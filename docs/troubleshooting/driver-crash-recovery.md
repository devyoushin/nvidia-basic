# 드라이버 크래시 복구

## 1. 개요

NVIDIA 드라이버 크래시는 커널 모듈(`nvidia.ko`)이 비정상 종료되어 `nvidia-smi`가 동작하지 않는 상태.
원인은 하드웨어 결함, 커널 버전 불일치, 잘못된 드라이버 설치, 메모리 오류 등 다양함.
GPU 리셋(`nvidia-smi -r`) → 커널 모듈 재로드 → 드라이버 재설치 순서로 단계적 복구 시도.

**핵심 요약**
- **사용 목적**: 드라이버 크래시 상황에서 인스턴스 재부팅 없이 복구 시도
- **주요 이점**: 빠른 복구로 GPU 워크로드 다운타임 최소화
- **관련 도구**: nvidia-smi, modprobe, rmmod, dkms, dmesg
- **해당 인스턴스**: 모든 NVIDIA GPU 인스턴스

---

## 2. 설명

### 2.1 드라이버 크래시 단계별 진단 흐름

```
nvidia-smi 동작 안 함
        |
  ┌─────┴──────┐
  │            │
lsmod에        lsmod에
nvidia 있음    nvidia 없음
  │            │
  │      → 커널 모듈 로드 실패
  │            │
  │       dmesg 확인
  │       (Xid, DKMS 오류)
  │
nvidia-smi -r 시도
  │
 성공? ──→ 복구 완료
  │ 실패
  ↓
커널 모듈 언로드 후 재로드
  │
 성공? ──→ 복구 완료
  │ 실패
  ↓
드라이버 재설치
  │
 성공? ──→ 복구 완료
  │ 실패
  ↓
인스턴스 재부팅 또는 Stop&Start
```

### 2.2 단계별 복구 명령어

#### Step 1. 상태 확인

```bash
# nvidia-smi 오류 메시지 확인
nvidia-smi 2>&1

# 커널 모듈 로드 여부
lsmod | grep nvidia

# 드라이버 오류 로그
dmesg -T | grep -E "nvidia|NVRM|Xid" | tail -30

# 드라이버 버전 파일 존재 여부
cat /proc/driver/nvidia/version 2>&1
```

#### Step 2. GPU 리셋 시도

```bash
# GPU 점유 프로세스 확인 및 종료
nvidia-smi --query-compute-apps=pid --format=csv,noheader 2>/dev/null | \
  xargs -I{} kill -9 {} 2>/dev/null; sleep 2

# GPU 리셋
sudo nvidia-smi -r

# 확인
nvidia-smi
```

#### Step 3. 커널 모듈 재로드

GPU 리셋 실패 시 모듈 언로드 → 재로드 시도.

```bash
# 1. GPU 프로세스 전부 종료
GPU_PIDS=$(nvidia-smi --query-compute-apps=pid --format=csv,noheader 2>/dev/null | tr -d ' ')
[ -n "$GPU_PIDS" ] && echo "$GPU_PIDS" | xargs kill -9 2>/dev/null
sleep 3

# 2. 관련 모듈 의존성 순서대로 언로드
sudo rmmod nvidia_uvm 2>/dev/null
sudo rmmod nvidia_drm 2>/dev/null
sudo rmmod nvidia_modeset 2>/dev/null
sudo rmmod nvidia 2>/dev/null

# 언로드 확인
lsmod | grep nvidia   # 아무것도 안 나와야 정상

# 3. 재로드
sudo modprobe nvidia
sudo modprobe nvidia_uvm
sudo modprobe nvidia_modeset
sudo modprobe nvidia_drm

# 확인
lsmod | grep nvidia
nvidia-smi
```

> **주의**: `rmmod nvidia`가 `Module is in use` 오류 반환 시, GPU를 사용 중인 프로세스가 남아있는 것 — 모든 CUDA 프로세스 종료 후 재시도

#### Step 4. 드라이버 재설치

커널 모듈 재로드도 실패 시 드라이버 재설치.

```bash
# 현재 드라이버 버전 확인 (DKMS에서)
DRIVER_VERSION=$(dkms status | grep nvidia | head -1 | awk -F'[/,]' '{print $2}' | tr -d ' ')
echo "설치된 드라이버 버전: $DRIVER_VERSION"

# DKMS 빌드 상태 확인 (broken이면 재빌드)
dkms status

# DKMS 재빌드 시도
sudo dkms remove "nvidia/$DRIVER_VERSION" --all
sudo dkms install "nvidia/$DRIVER_VERSION"

# 성공 시 모듈 로드
sudo modprobe nvidia
nvidia-smi
```

```bash
# DKMS 재빌드도 실패 시 runfile로 재설치
# (runfile은 S3 또는 /opt에 보관해두는 것 권장)
DRIVER_RUNFILE="/opt/nvidia-drivers/NVIDIA-Linux-x86_64-${DRIVER_VERSION}.run"

if [ -f "$DRIVER_RUNFILE" ]; then
  sudo sh "$DRIVER_RUNFILE" --dkms --silent --no-opengl-files --no-x-check
  sudo reboot
else
  echo "runfile 없음 — S3에서 다운로드 필요"
  # aws s3 cp s3://<BUCKET>/nvidia-drivers/NVIDIA-Linux-x86_64-${DRIVER_VERSION}.run /tmp/
fi
```

#### Step 5. 인스턴스 재부팅 / Stop&Start

위 단계 모두 실패 시:

```bash
# 재부팅 (동일 물리 호스트)
sudo reboot

# 또는 Stop&Start (새 물리 호스트) — Xid 48/79 있으면 Stop&Start 필수
# docs/troubleshooting/aws-host-replacement.md 참조
```

### 2.3 크래시 원인별 대응

| 증상 (dmesg) | 원인 | 조치 |
|-------------|------|------|
| `NVRM: Xid 48` | 하드웨어 ECC 불량 | Stop&Start |
| `NVRM: Xid 79` | GPU PCIe 연결 분리 | Stop&Start |
| `Module nvidia not found` | 커널 업그레이드 후 DKMS 재빌드 실패 | `kernel-devel` 재설치 후 DKMS 재빌드 |
| `Failed to initialize NVML: Driver/library version mismatch` | 드라이버 업그레이드 후 구 프로세스가 구 libcuda 사용 | 해당 프로세스 종료 또는 재부팅 |
| `rmmod: ERROR: Module nvidia is in use` | GPU 점유 프로세스 존재 | 모든 CUDA 프로세스 종료 후 재시도 |

### 2.4 Best Practice

- `/opt/nvidia-drivers/` 에 현재 사용 중인 runfile 보관 (재설치 시 S3 재다운로드 없이 즉시 사용)
- 드라이버 재설치 절차를 Runbook으로 문서화하여 야간 장애 시 빠르게 실행 가능하게 준비
- 크래시 발생 시 `dmesg -T | grep -E "NVRM|nvidia" > /tmp/dmesg-crash-$(date +%Y%m%d-%H%M%S).log` 로 로그 보존

---

## 3. 트러블슈팅

### 3.1 주요 이슈

#### `Failed to initialize NVML: Driver/library version mismatch`

**증상**
- `nvidia-smi` 실행 시 `Failed to initialize NVML: Driver/library version mismatch`

**원인**
- 드라이버 업그레이드 후 구 `libcuda.so`를 로드한 프로세스가 여전히 실행 중
- 커널 모듈(새 버전)과 유저스페이스 라이브러리(구 버전) 불일치

**해결 방법**
```bash
# 구 libcuda를 사용 중인 프로세스 확인
lsof | grep libcuda

# 해당 프로세스 종료
lsof | grep libcuda | awk '{print $2}' | sort -u | xargs kill -9 2>/dev/null

# 또는 재부팅 (가장 확실한 방법)
sudo reboot
```

---

#### `rmmod: ERROR: Module nvidia is in use by: nvidia_uvm nvidia_drm`

**증상**
- `sudo rmmod nvidia` 실행 시 `Module nvidia is in use`

**원인**
- `nvidia_uvm`, `nvidia_drm`, `nvidia_modeset` 모듈이 nvidia에 의존하므로 먼저 언로드해야 함

**해결 방법**
```bash
# 의존성 역순으로 언로드
sudo rmmod nvidia_uvm    # 먼저
sudo rmmod nvidia_drm
sudo rmmod nvidia_modeset
sudo rmmod nvidia        # 마지막
```

---

### 3.2 자주 발생하는 문제 (Q&A)

**Q: 모듈 언로드 중 `Resource temporarily unavailable` 오류가 남**
A: GPU를 사용 중인 프로세스가 완전히 종료되지 않은 상태. `fuser /dev/nvidia*` 로 디바이스를 점유한 프로세스 확인 후 종료:
```bash
sudo fuser /dev/nvidia*
sudo fuser -k /dev/nvidia*   # 강제 종료
```

**Q: 재설치 후 reboot 없이 바로 `nvidia-smi` 동작시킬 수 있나?**
A: 가능 (재부팅 없이 모듈 재로드). runfile 재설치 후 `--no-kernel-module` 플래그 없이 설치했다면 자동으로 모듈 로드됨. 이후 `nvidia-smi` 동작 확인.

---

## 4. 모니터링 및 알람

### 핵심 지표

| 지표 | 수집 방법 | 의미 | 임계값 예시 |
|------|----------|------|------------|
| `gpu_util` 수집 여부 | CWAgent | 드라이버 정상 동작 간접 확인 | 데이터 없음 (breaching) |
| EC2 StatusCheckFailed_System | CloudWatch | 물리 호스트 이상 | `>= 1` |

### CloudWatch 알람 (GPU 지표 수집 중단 감지)

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "gpu-metrics-missing-<INSTANCE_ID>" \
  --alarm-description "GPU 지표 수집 중단 — 드라이버 크래시 가능성" \
  --metric-name "utilization_gpu" \
  --namespace "CWAgent" \
  --dimensions Name=InstanceId,Value=<INSTANCE_ID> \
  --statistic SampleCount \
  --period 300 \
  --evaluation-periods 3 \
  --threshold 1 \
  --comparison-operator LessThanThreshold \
  --treat-missing-data breaching \
  --alarm-actions "arn:aws:sns:ap-northeast-2:<ACCOUNT_ID>:<SNS_TOPIC>" \
  --region ap-northeast-2
```

---

## 5. TIP

- 드라이버 크래시 발생 시 로그 자동 보존 스크립트를 cron 또는 systemd path unit으로 구성: `/proc/driver/nvidia/version` 파일 사라지면 자동 dmesg 저장
- S3에 드라이버 runfile 보관 버킷 생성: `s3://<BUCKET>/nvidia-drivers/NVIDIA-Linux-x86_64-<VERSION>.run`
- 복구 후 반드시 `scripts/gpu-health-check.sh` 실행으로 전체 상태 재확인

**관련 문서**
- 연관 내부 문서: `docs/troubleshooting/xid-error-codes.md`, `docs/troubleshooting/aws-host-replacement.md`, `docs/driver/nvidia-driver-install-al2023.md`
