# DCGM Exporter Prometheus 연동

## 1. 개요

DCGM Exporter는 DCGM 지표를 Prometheus 형식으로 노출하는 컨테이너.
EKS GPU 노드에서 GPU 지표를 Prometheus/Grafana로 수집하는 표준 방식이며, NVIDIA 공식 지원.
DaemonSet으로 배포하여 각 GPU 노드에서 `:9400/metrics` 엔드포인트로 지표를 제공함.

**핵심 요약**
- **사용 목적**: EKS GPU 노드 GPU 지표의 Prometheus 수집 및 Grafana 대시보드 연동
- **주요 이점**: Kubernetes 표준 메트릭 파이프라인에 GPU 지표 통합
- **관련 도구**: DCGM, Prometheus, Grafana, Helm, kubectl
- **해당 인스턴스**: EKS GPU 노드 (p4d, g5 등) — DaemonSet으로 배포

---

## 2. 설명

### 2.1 핵심 개념

```
[GPU 노드]
  nvidia-driver
       |
  nv-hostengine (DCGM)
       |
  dcgm-exporter 컨테이너 (:9400/metrics)
       |
  Prometheus (scrape)
       |
  Grafana (대시보드)
```

| 구성 요소 | 역할 |
|----------|------|
| `dcgm-exporter` | DCGM → Prometheus 변환 컨테이너 |
| `ServiceMonitor` | Prometheus Operator가 스크레이프 설정을 자동 생성 |
| `default-counters.csv` | 수집할 DCGM 필드 목록 정의 파일 |

### 2.2 Helm으로 DCGM Exporter 배포

```bash
# NVIDIA GPU Helm 저장소 추가
helm repo add gpu-helm-charts https://nvidia.github.io/dcgm-exporter/helm-charts
helm repo update

# GPU 노드에만 배포되도록 nodeSelector 지정
helm install dcgm-exporter gpu-helm-charts/dcgm-exporter \
  --namespace monitoring \
  --create-namespace \
  --set nodeSelector."node\.kubernetes\.io/instance-type"=g5.xlarge \
  --set serviceMonitor.enabled=true \
  --set serviceMonitor.interval=30s
```

#### values.yaml 주요 설정

```yaml
# values.yaml
image:
  repository: nvcr.io/nvidia/k8s/dcgm-exporter
  tag: "3.3.5-3.4.0-ubuntu22.04"   # 드라이버 버전에 맞는 태그 선택

# GPU 노드에만 배포
nodeSelector:
  nvidia.com/gpu: "true"

tolerations:
  - key: nvidia.com/gpu
    operator: Exists
    effect: NoSchedule

# Prometheus Operator ServiceMonitor
serviceMonitor:
  enabled: true
  interval: 30s
  honorLabels: true

# 수집 필드 커스터마이징 (기본값 사용 시 생략)
# extraConfigMapMounts:
#   - name: exporter-metrics-config
#     mountPath: /etc/dcgm-exporter/
#     configMapName: dcgm-exporter-metrics

resources:
  limits:
    nvidia.com/gpu: 0   # GPU 리소스 자체는 소비하지 않음
  requests:
    cpu: 100m
    memory: 128Mi
```

#### 배포 확인

```bash
# DaemonSet 상태 확인
kubectl get daemonset -n monitoring dcgm-exporter

# Pod 상태 확인
kubectl get pods -n monitoring -l app.kubernetes.io/name=dcgm-exporter -o wide

# 지표 엔드포인트 직접 확인
kubectl port-forward -n monitoring svc/dcgm-exporter 9400:9400 &
curl -s http://localhost:9400/metrics | grep DCGM_FI_DEV_GPU_UTIL
```

### 2.3 수집 필드 커스터마이징

기본 수집 필드는 컨테이너 내 `/etc/dcgm-exporter/default-counters.csv` 에 정의됨.

```bash
# 기본 필드 목록 확인
kubectl exec -n monitoring \
  $(kubectl get pods -n monitoring -l app.kubernetes.io/name=dcgm-exporter -o jsonpath='{.items[0].metadata.name}') \
  -- cat /etc/dcgm-exporter/default-counters.csv
```

#### 커스텀 필드 ConfigMap (Xid, NVLink 필드 추가)

```yaml
# dcgm-exporter-metrics-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: dcgm-exporter-metrics
  namespace: monitoring
data:
  default-counters.csv: |
    # Format: FieldId, FieldName, PromType
    1001, DCGM_FI_DEV_GPU_UTIL,          gauge
    1002, DCGM_FI_DEV_MEM_COPY_UTIL,     gauge
    1007, DCGM_FI_DEV_GPU_TEMP,          gauge
    1008, DCGM_FI_DEV_POWER_USAGE,       gauge
    1009, DCGM_FI_DEV_FB_FREE,           gauge
    1010, DCGM_FI_DEV_FB_USED,           gauge
    1500, DCGM_FI_DEV_ECC_SBE_VOL_TOTAL, counter
    1501, DCGM_FI_DEV_ECC_DBE_VOL_TOTAL, counter
    230,  DCGM_FI_DEV_XID_ERRORS,        gauge
    1012, DCGM_FI_DEV_NVLINK_BANDWIDTH_TOTAL, gauge
```

```bash
kubectl apply -f dcgm-exporter-metrics-configmap.yaml

# Helm upgrade로 ConfigMap 마운트 적용
helm upgrade dcgm-exporter gpu-helm-charts/dcgm-exporter \
  --namespace monitoring \
  --set extraConfigMapMounts[0].name=exporter-metrics-config \
  --set extraConfigMapMounts[0].mountPath=/etc/dcgm-exporter/ \
  --set extraConfigMapMounts[0].configMapName=dcgm-exporter-metrics
```

### 2.4 Prometheus 쿼리 예시

```promql
# GPU 사용률 평균 (클러스터 전체)
avg(DCGM_FI_DEV_GPU_UTIL) by (kubernetes_node)

# VRAM 사용률 (%)
(DCGM_FI_DEV_FB_USED / (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE)) * 100

# Xid 에러 발생 GPU (0이 아닌 값)
DCGM_FI_DEV_XID_ERRORS != 0

# GPU 온도 최대값
max(DCGM_FI_DEV_GPU_TEMP) by (kubernetes_node, gpu)

# ECC DBE 에러 누적 증가율
rate(DCGM_FI_DEV_ECC_DBE_VOL_TOTAL[5m])
```

### 2.5 Grafana 대시보드

NVIDIA 공식 대시보드를 Grafana에 임포트하여 빠르게 시각화 가능.

```bash
# NVIDIA DCGM Exporter 대시보드 ID: 12239
# Grafana UI → Dashboards → Import → ID 12239 입력
```

주요 패널 구성:
- GPU 사용률 히트맵 (노드별, GPU별)
- VRAM 사용량 시계열
- GPU 온도 게이지
- 전력 소비 시계열
- ECC 에러 카운터

### 2.6 Best Practice

- `serviceMonitor.interval`은 30s 권장 — 1분 미만으로 수집해야 빠른 이상 탐지 가능
- GPU 노드 레이블(`nvidia.com/gpu: "true"`)로 DaemonSet nodeSelector 지정 필수
- Xid 에러 필드(230)는 반드시 수집 — Grafana Alert과 연동하여 0이 아닐 때 즉시 알림

---

## 3. 트러블슈팅

### 3.1 주요 이슈

#### dcgm-exporter Pod가 CrashLoopBackOff

**증상**
- `kubectl get pods -n monitoring` 에서 dcgm-exporter Pod `CrashLoopBackOff`

**원인**
- 노드의 NVIDIA 드라이버가 로드되지 않음
- dcgm-exporter 이미지 버전과 드라이버 버전 불일치
- DCGM hostengine 소켓에 접근 권한 없음

**해결 방법**
```bash
# Pod 로그 확인
kubectl logs -n monitoring \
  $(kubectl get pods -n monitoring -l app.kubernetes.io/name=dcgm-exporter -o jsonpath='{.items[0].metadata.name}') \
  --previous

# 노드에서 nvidia-smi 동작 확인
kubectl debug node/<NODE_NAME> -it --image=ubuntu -- nvidia-smi

# 드라이버 버전에 맞는 이미지 태그 재선택
# nvcr.io/nvidia/k8s/dcgm-exporter:3.3.5-3.4.0-ubuntu22.04
# ↑ 첫 번째 버전은 DCGM, 두 번째는 드라이버 요구 최소 버전
```

---

#### `/metrics` 엔드포인트에서 특정 지표 누락

**증상**
- `curl http://localhost:9400/metrics | grep DCGM_FI_DEV_XID_ERRORS` 결과 없음

**원인**
- `default-counters.csv`에 해당 필드가 미포함

**해결 방법**
```bash
# 현재 수집 중인 필드 확인
kubectl exec -n monitoring <POD_NAME> -- cat /etc/dcgm-exporter/default-counters.csv

# ConfigMap으로 필드 추가 후 Pod 재시작
kubectl rollout restart daemonset/dcgm-exporter -n monitoring
```

---

### 3.2 자주 발생하는 문제 (Q&A)

**Q: MIG 모드 활성화된 GPU에서 DCGM Exporter가 지표를 수집하는가?**
A: 수집됨. MIG 모드에서는 각 MIG 인스턴스별로 지표가 분리되어 노출되며, `gpu_i_id` 레이블로 인스턴스 구분 가능.

**Q: Prometheus 없이 CloudWatch만 사용하는 환경에서 dcgm-exporter가 필요한가?**
A: 불필요. CloudWatch 환경에서는 `docs/05-monitoring/cw-gpu-metrics.md`의 CWAgent + DCGM 방식 사용.

---

## 4. 모니터링 및 알람

### Prometheus Alert 규칙 예시

```yaml
# gpu-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: gpu-alerts
  namespace: monitoring
spec:
  groups:
    - name: gpu.rules
      rules:
        - alert: GPUXidError
          expr: DCGM_FI_DEV_XID_ERRORS != 0
          for: 0m
          labels:
            severity: critical
          annotations:
            summary: "GPU Xid 에러 발생 ({{ $labels.kubernetes_node }}, GPU {{ $labels.gpu }})"
            description: "Xid 코드: {{ $value }} — docs/06-troubleshooting/xid-error-codes.md 참조"

        - alert: GPUHighTemperature
          expr: DCGM_FI_DEV_GPU_TEMP > 85
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "GPU 온도 경고 ({{ $labels.kubernetes_node }}, GPU {{ $labels.gpu }})"
            description: "현재 온도: {{ $value }}°C"

        - alert: GPUMemoryHigh
          expr: (DCGM_FI_DEV_FB_USED / (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE)) * 100 > 90
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "GPU VRAM 사용률 높음 ({{ $labels.kubernetes_node }})"
            description: "VRAM 사용률: {{ $value | humanize }}%"

        - alert: GPUECCError
          expr: rate(DCGM_FI_DEV_ECC_DBE_VOL_TOTAL[5m]) > 0
          for: 0m
          labels:
            severity: critical
          annotations:
            summary: "GPU ECC Double Bit 에러 발생"
            description: "즉시 Stop&Start 검토 필요"
```

---

## 5. TIP

- NVIDIA GPU Operator를 사용하면 드라이버, DCGM Exporter, Container Toolkit을 한 번에 관리 가능
- Grafana 대시보드 ID 12239는 DCGM Exporter 공식 대시보드 — 즉시 임포트하여 사용 가능
- EKS GPU 노드의 라벨 확인: `kubectl get nodes -l nvidia.com/gpu=true --show-labels`

**관련 문서**
- [DCGM Exporter GitHub](https://github.com/NVIDIA/dcgm-exporter)
- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/index.html)
- 연관 내부 문서: `docs/04-dcgm/dcgm-setup.md`, `docs/03-cuda/nvidia-container-toolkit.md`
