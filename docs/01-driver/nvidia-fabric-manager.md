# Fabric Manager 설치 및 운영

## 1. 개요

Fabric Manager (패브릭 매니저)는 NVSwitch 기반 멀티-GPU 인스턴스(p4d, p4de, p5)에서 GPU 간 NVLink 연결을 관리하는 서비스.
Fabric Manager 없이 p4d/p5를 시작하면 GPU가 독립적으로만 동작 — NVLink를 통한 GPU 간 직접 통신 불가.
드라이버와 동일 버전의 Fabric Manager를 설치해야 하며, 버전 불일치 시 NVSwitch 연결 GPU 누락 현상 발생.

**핵심 요약**
- **사용 목적**: p4d/p4de/p5에서 NVSwitch를 통한 8 GPU 간 NVLink 통신 활성화
- **주요 이점**: NVLink로 GPU 간 고대역폭 직접 통신 — PCIe 대비 최대 600 GB/s
- **관련 도구**: nvidia-smi nvlink, systemctl, journalctl
- **해당 인스턴스**: p4d.24xlarge, p4de.24xlarge, p5.48xlarge (NVSwitch 탑재 인스턴스만 해당)

---

## 2. 설명

### 2.1 핵심 개념

```
[p4d 인스턴스 — GPU 8개]
 GPU0 ─┐
 GPU1 ─┤
 GPU2 ─┤  [NVSwitch]  ←→  [Fabric Manager]
 GPU3 ─┤       |
 GPU4 ─┤  All-to-All NVLink
 GPU5 ─┤  (600 GB/s)
 GPU6 ─┤
 GPU7 ─┘
```

| 항목 | 설명 |
|------|------|
| NVSwitch | GPU 간 NVLink 연결을 중계하는 하드웨어 스위치 |
| NVLink | GPU-to-GPU 고속 인터커넥트 (PCIe보다 10배 이상 대역폭) |
| Fabric Manager | NVSwitch 라우팅 테이블을 설정하고 관리하는 데몬 |

Fabric Manager가 실행되지 않으면:
- `nvidia-smi nvlink -s` 에서 링크 상태가 `Inactive`
- PyTorch/TensorFlow의 NCCL 멀티-GPU 학습 성능이 PCIe 수준으로 저하

### 2.2 설치 및 구성

#### 드라이버 버전 확인

```bash
# 현재 드라이버 버전 확인
nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1
# 출력 예시: 535.154.05
```

#### Fabric Manager 설치 (드라이버와 동일 버전)

```bash
DRIVER_MAJOR=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1 | cut -d'.' -f1)
# DRIVER_MAJOR = 535 (예시)

# CUDA 저장소 추가 (미설치 시)
sudo dnf config-manager --add-repo \
  https://developer.download.nvidia.com/compute/03-cuda/repos/amzn2023/x86_64/cuda-amzn2023.repo

# Fabric Manager 설치 (Major 버전 일치)
sudo dnf install -y nvidia-fabricmanager-${DRIVER_MAJOR}

# 서비스 활성화
sudo systemctl enable nvidia-fabricmanager
sudo systemctl start nvidia-fabricmanager
```

#### 설치 확인

```bash
# 서비스 상태 확인
systemctl status nvidia-fabricmanager

# 정상 출력 예시:
# ● nvidia-fabricmanager.service - NVIDIA Fabric Manager service
#    Loaded: loaded (/usr/lib/systemd/system/nvidia-fabricmanager.service; enabled)
#    Active: active (running)

# NVLink 활성화 확인
nvidia-smi nvlink -s
# 정상 출력 예시 (GPU 0의 NVLink):
# GPU 00000000:10:1C.0
#         Link 0: 25.781 GB/s
#         Link 1: 25.781 GB/s
#         ...

# 모든 GPU 표시 확인 (p4d: 8개)
nvidia-smi --query-gpu=index,name --format=csv,noheader | wc -l
```

### 2.3 Best Practice

- 드라이버 업그레이드 시 Fabric Manager도 동시에 동일 버전으로 업그레이드
- `nvidia-fabricmanager` 서비스 재시작은 학습 작업 중에는 금지 — NVLink 연결 초기화로 NCCL 크래시 유발
- 서비스 이상 감지 자동화: systemd FailureAction 또는 CloudWatch 알람으로 서비스 다운 시 알림

---

## 3. 트러블슈팅

### 3.1 주요 이슈

#### Fabric Manager 버전 불일치 (드라이버 업그레이드 후)

**증상**
- `systemctl status nvidia-fabricmanager` → `failed` 또는 `inactive`
- `journalctl -u nvidia-fabricmanager` 에 버전 불일치 오류
- `nvidia-smi` 에서 8개 GPU 중 일부 누락

**원인**
- 드라이버는 새 버전으로 업그레이드됐으나 Fabric Manager는 구 버전 유지

**해결 방법**
```bash
# 드라이버 버전 확인
DRIVER_MAJOR=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1 | cut -d'.' -f1)

# 현재 Fabric Manager 버전 확인
rpm -qa | grep nvidia-fabricmanager

# 새 버전으로 교체
sudo dnf remove -y nvidia-fabricmanager-<OLD_VERSION>
sudo dnf install -y nvidia-fabricmanager-${DRIVER_MAJOR}

sudo systemctl restart nvidia-fabricmanager
systemctl status nvidia-fabricmanager
```

---

#### Fabric Manager 시작 후에도 NVLink Inactive

**증상**
- `nvidia-smi nvlink -s` 에서 모든 링크 `Inactive`
- `journalctl -u nvidia-fabricmanager` 에 `NvSwitch initialization failed`

**원인**
- 인스턴스 스타트업 순서 문제: nvidia 드라이버가 Fabric Manager보다 늦게 로드됨
- Xid 74 (NVLink Error) 선행 발생

**해결 방법**
```bash
# 드라이버 로드 확인
lsmod | grep nvidia

# 서비스 재시작 (드라이버 로드 완료 후)
sudo systemctl restart nvidia-fabricmanager

# Xid 에러 확인
dmesg -T | grep "NVRM: Xid"
# Xid 74 있으면 → Stop&Start 후 재시도
```

---

### 3.2 자주 발생하는 문제 (Q&A)

**Q: g5 인스턴스에도 Fabric Manager가 필요한가?**
A: 불필요. g5는 A10G GPU 1~8개이지만 NVSwitch가 없음 (PCIe 연결). Fabric Manager는 NVSwitch가 탑재된 p4d, p4de, p5에서만 필요.

**Q: Fabric Manager 실행 중 `nvidia-smi nvlink -s` 출력이 없음**
A: GPU에 NVLink가 없거나 링크가 비활성화된 상태. `nvidia-smi -q` 에서 NVLink 섹션 확인. p4d에서 모든 링크가 비활성이면 Fabric Manager 재시작 필요.

---

## 4. 모니터링 및 알람

### 핵심 지표

| 지표 | 수집 방법 | 의미 | 임계값 예시 |
|------|----------|------|------------|
| `nvlink_bandwidth` | DCGM 필드 1012 | NVLink 총 대역폭 | 갑작스러운 0으로 감소 |
| Fabric Manager 서비스 상태 | systemd / CloudWatch | 서비스 정상 동작 여부 | Inactive 시 즉시 알람 |

### CloudWatch 알람 (Fabric Manager 서비스 모니터링)

```bash
# SSM Run Command + EventBridge로 Fabric Manager 상태 주기적 확인
# 또는 CWAgent procstat 플러그인으로 nv-fabricmanager 프로세스 모니터링

# procstat 설정 추가 (nvidia-gpu.json 에 추가)
# "procstat": [
#   {
#     "process_name": "nv-fabricmanager",
#     "measurement": ["pid_count"]
#   }
# ]

# pid_count = 0 이면 프로세스 없음 → 알람
aws cloudwatch put-metric-alarm \
  --alarm-name "fabric-manager-down-<INSTANCE_ID>" \
  --alarm-description "Fabric Manager 프로세스 비정상" \
  --metric-name "procstat_lookup_pid_count" \
  --namespace "CWAgent" \
  --dimensions \
    Name=InstanceId,Value=<INSTANCE_ID> \
    Name=process_name,Value=nv-fabricmanager \
  --statistic Minimum \
  --period 60 \
  --evaluation-periods 2 \
  --threshold 1 \
  --comparison-operator LessThanThreshold \
  --alarm-actions "arn:aws:sns:ap-northeast-2:<ACCOUNT_ID>:<SNS_TOPIC>" \
  --region ap-northeast-2
```

---

## 5. TIP

- 드라이버 + Fabric Manager 버전을 항상 함께 관리 — UserData 스크립트에서 같은 변수(`DRIVER_MAJOR`)로 두 패키지 버전 통일
- `nvidia-smi nvlink -e` 로 NVLink 에러 카운터 주기적 확인 — 카운터 증가 시 Xid 74 선행 발생 가능성
- p4d/p5에서 ML 학습 전 항상 `systemctl is-active nvidia-fabricmanager` 확인을 학습 시작 스크립트에 포함

**관련 문서**
- [NVIDIA Fabric Manager Documentation](https://docs.nvidia.com/datacenter/tesla/fabric-manager-user-guide/)
- 연관 내부 문서: `docs/06-troubleshooting/xid-error-codes.md`, `docs/01-driver/nvidia-driver-version-management.md`
