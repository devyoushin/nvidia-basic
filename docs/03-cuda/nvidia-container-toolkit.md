# NVIDIA Container Toolkit 설치 및 EKS GPU 노드 설정

## 1. 개요

NVIDIA Container Toolkit (구 nvidia-docker2)은 Docker/containerd 컨테이너가 호스트의 NVIDIA GPU에 접근할 수 있도록 하는 런타임 레이어.
EKS GPU 노드에서 컨테이너 기반 ML 워크로드를 실행하려면 드라이버 외에 Container Toolkit 설치가 필수.
AWS DLAMI 기반 AMI나 NVIDIA GPU Operator를 사용하면 자동 구성되지만, 커스텀 AMI 사용 시 수동 설치 필요.

**핵심 요약**
- **사용 목적**: 컨테이너에서 GPU 사용 가능하게 하는 런타임 설정
- **주요 이점**: 호스트 드라이버 설치만으로 컨테이너에서 CUDA 사용 가능 (CUDA Toolkit 컨테이너 내 포함)
- **관련 도구**: nvidia-ctk, containerd, docker, EKS
- **해당 인스턴스**: EKS GPU 노드 (g5, p4d, p5 등) 또는 GPU 인스턴스에서 Docker 사용 시

---

## 2. 설명

### 2.1 핵심 개념

```
[컨테이너 내 CUDA 코드]
          |
  [NVIDIA Container Runtime]  ← Container Toolkit이 제공
          |
  [호스트 NVIDIA 드라이버]
          |
       [GPU 하드웨어]
```

| 구성 요소 | 역할 |
|----------|------|
| `nvidia-container-toolkit` | 핵심 패키지 — nvidia-ctk CLI 포함 |
| `nvidia-container-runtime` | containerd/docker 런타임 훅 |
| `libnvidia-container` | GPU 디바이스 마운트 라이브러리 |
| `nvidia-ctk` | 런타임 설정 CLI (containerd/docker 설정 자동화) |

### 2.2 설치 (AL2023)

```bash
# NVIDIA Container Toolkit 저장소 추가
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | \
  sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo

# 설치
sudo dnf install -y nvidia-container-toolkit

# 버전 확인
nvidia-ctk --version
```

### 2.3 containerd 설정 (EKS 기본 런타임)

```bash
# containerd 런타임 설정 자동 생성
sudo nvidia-ctk runtime configure --runtime=containerd

# 설정 확인 (/etc/containerd/config.toml 수정 내용)
grep -A 10 'nvidia' /etc/containerd/config.toml

# containerd 재시작
sudo systemctl restart containerd

# 정상 동작 확인 (GPU 컨테이너 실행 테스트)
sudo ctr image pull nvcr.io/nvidia/cuda:12.2.0-base-ubuntu20.04
sudo ctr run --rm --gpus all \
  nvcr.io/nvidia/cuda:12.2.0-base-ubuntu20.04 \
  gpu-test nvidia-smi
```

### 2.4 Docker 설정 (EC2에서 Docker 사용 시)

```bash
# Docker 런타임 설정
sudo nvidia-ctk runtime configure --runtime=docker

# Docker 재시작
sudo systemctl restart docker

# 설정 확인
cat /etc/docker/daemon.json
# 출력 예시:
# {
#   "runtimes": {
#     "nvidia": {
#       "path": "nvidia-container-runtime",
#       "runtimeArgs": []
#     }
#   },
#   "default-runtime": "nvidia"
# }

# GPU 컨테이너 실행 테스트
docker run --rm --gpus all \
  nvcr.io/nvidia/cuda:12.2.0-base-ubuntu20.04 \
  nvidia-smi
```

### 2.5 EKS GPU 노드 DevicePlugin 설정

EKS에서 GPU 리소스(`nvidia.com/gpu`)를 Pod에 할당하려면 NVIDIA Device Plugin이 필요.

```bash
# NVIDIA Device Plugin DaemonSet 배포 (EKS에서 권장 방식)
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.5/nvidia-device-plugin.yml

# Pod 상태 확인
kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds

# GPU 노드에서 할당 가능한 GPU 수 확인
kubectl get nodes -o json | jq '.items[] | .metadata.name, .status.allocatable["nvidia.com/gpu"]'
```

#### GPU Pod 리소스 요청 예시

```yaml
# gpu-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test
spec:
  restartPolicy: Never
  containers:
    - name: cuda-container
      image: nvcr.io/nvidia/cuda:12.2.0-base-ubuntu20.04
      command: ["nvidia-smi"]
      resources:
        limits:
          nvidia.com/gpu: 1    # GPU 1개 요청
        requests:
          nvidia.com/gpu: 1
  nodeSelector:
    nvidia.com/gpu: "true"     # GPU 노드에만 스케줄링
  tolerations:
    - key: nvidia.com/gpu
      operator: Exists
      effect: NoSchedule
```

```bash
kubectl apply -f gpu-pod.yaml
kubectl logs gpu-test
```

### 2.6 MIG 모드 EKS 설정

A100/H100 MIG 인스턴스에서 EKS 사용 시 MIG 리소스 타입 별도 설정 필요.

```bash
# MIG 전략 설정 (Device Plugin)
# values.yaml에서 migStrategy 변경
helm upgrade nvidia-device-plugin nvdp/nvidia-device-plugin \
  --set migStrategy=single   # single: 모든 MIG 인스턴스를 동일 타입으로 노출
  # 또는 mixed: 각 MIG 프로파일을 별도 리소스로 노출

# MIG 리소스 확인
kubectl get nodes -o json | jq '.items[].status.allocatable | with_entries(select(.key | startswith("nvidia")))'
# 출력 예시 (1g.10gb 7개 생성 시):
# { "nvidia.com/mig-1g.10gb": "7" }
```

### 2.7 Best Practice

- EKS Managed Node Group에서 NVIDIA DLAMI 기반 AMI 사용 시 Container Toolkit 사전 포함됨 — 별도 설치 불필요
- 커스텀 AMI 생성 시 Container Toolkit 설치 후 `nvidia-ctk runtime configure` 실행을 반드시 포함
- `--gpus all` 플래그는 Docker/containerd 단에서 GPU 전부 노출 — EKS에서는 리소스 제한(`nvidia.com/gpu: N`)으로 제어

---

## 3. 트러블슈팅

### 3.1 주요 이슈

#### 컨테이너에서 nvidia-smi: command not found

**증상**
- GPU 컨테이너 실행 시 `nvidia-smi: command not found`

**원인**
- Container Toolkit이 설치되지 않았거나 containerd 재시작 미수행
- `--gpus all` 플래그 미사용

**해결 방법**
```bash
# Container Toolkit 설치 여부 확인
rpm -qa | grep nvidia-container

# containerd 설정 확인
grep -A 5 'nvidia' /etc/containerd/config.toml

# containerd 재시작
sudo systemctl restart containerd

# GPU 플래그 포함하여 재실행
docker run --rm --gpus all ubuntu nvidia-smi
```

---

#### EKS Pod에서 GPU 리소스 할당 실패

**증상**
- Pod이 `Pending` 상태로 유지
- `kubectl describe pod <POD>` 에 `Insufficient nvidia.com/gpu`

**원인**
- NVIDIA Device Plugin DaemonSet이 실행되지 않음
- GPU 노드의 모든 GPU가 이미 다른 Pod에 할당됨

**해결 방법**
```bash
# Device Plugin 상태 확인
kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds

# 각 노드의 할당 가능 GPU 수 확인
kubectl describe nodes | grep -A 5 "Allocatable"

# GPU 노드 레이블 확인
kubectl get nodes --show-labels | grep nvidia
```

---

### 3.2 자주 발생하는 문제 (Q&A)

**Q: `--gpus all` 과 `--gpus '"device=0,1"'` 의 차이는?**
A: `all`은 모든 GPU 노출, `device=0,1`은 특정 인덱스 GPU만 노출. EKS에서는 리소스 요청(`nvidia.com/gpu: N`)으로 제어하므로 `device=` 형태는 직접 사용하지 않음.

**Q: `nvidia-ctk runtime configure` 실행 후 기존 컨테이너가 영향받는가?**
A: 실행 중인 컨테이너는 영향 없음. containerd/docker 재시작 후 신규 생성되는 컨테이너부터 적용됨.

---

## 4. 모니터링 및 알람

### 핵심 지표

| 지표 | 수집 방법 | 의미 | 임계값 예시 |
|------|----------|------|------------|
| `nvidia.com/gpu` allocatable | kubectl / kube-state-metrics | 사용 가능한 GPU 수 | 0 알람 |
| Container Toolkit 프로세스 | CWAgent procstat | 정상 동작 여부 | 없으면 알람 |

### GPU 할당 현황 확인 (운영 중)

```bash
# 클러스터 전체 GPU 할당 현황
kubectl get pods -A -o json | jq '
  .items[] |
  select(.spec.containers[].resources.limits["nvidia.com/gpu"] != null) |
  {
    namespace: .metadata.namespace,
    pod: .metadata.name,
    node: .spec.nodeName,
    gpus: .spec.containers[].resources.limits["nvidia.com/gpu"]
  }'
```

---

## 5. TIP

- NVIDIA GPU Operator는 드라이버, Container Toolkit, Device Plugin, DCGM Exporter를 모두 Kubernetes Operator로 관리 — 대규모 클러스터에서 유지보수 편의성 향상
- AWS EKS Optimized Accelerated AMI는 Container Toolkit + Device Plugin이 사전 구성된 AMI — 커스텀 AMI 없이 GPU 워크로드 빠르게 시작 가능
- `nvidia-ctk cdi generate` 로 CDI(Container Device Interface) 설정 생성 — containerd 1.7+ 에서 권장 방식

**관련 문서**
- [NVIDIA Container Toolkit Installation Guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
- [EKS GPU 노드 최적화 AMI](https://docs.aws.amazon.com/eks/latest/userguide/eks-optimized-ami.html)
- 연관 내부 문서: `docs/03-cuda/cuda-driver-compatibility.md`, `docs/05-monitoring/dcgm-exporter-prometheus.md`
