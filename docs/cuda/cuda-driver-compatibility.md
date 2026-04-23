# CUDA Toolkit ↔ 드라이버 버전 호환성

## 1. 개요

CUDA 코드는 실행 시 드라이버가 지원하는 CUDA 버전 이하에서만 동작하는 **Forward Compatibility** 규칙을 따름.
`nvidia-smi`에 표시된 `CUDA Version`은 드라이버가 지원하는 최대 CUDA 버전이며, 실제 설치된 CUDA Toolkit 버전(`nvcc --version`)과 다를 수 있음.
드라이버를 업그레이드하지 않고도 상위 CUDA Toolkit 사용 가능한 경우가 있으므로, 드라이버 업그레이드 전 호환성 확인이 중요.

**핵심 요약**
- **사용 목적**: 드라이버 업그레이드 없이 새 CUDA 기능 사용 가능 여부 판단
- **주요 이점**: 불필요한 드라이버 업그레이드 방지로 운영 안정성 유지
- **관련 도구**: nvcc, nvidia-smi, python, torch/tensorflow
- **해당 인스턴스**: 모든 NVIDIA GPU 인스턴스

---

## 2. 설명

### 2.1 핵심 개념

#### CUDA 버전 체계

```
CUDA Toolkit 버전   ←→   드라이버 최소 요구 버전
(nvcc --version)         (nvidia-smi CUDA Version ≥ Toolkit 버전)
```

| CUDA Toolkit | 필요 최소 드라이버 (Linux) | 권장 드라이버 Branch |
|-------------|--------------------------|-------------------|
| CUDA 12.0 | 525.60.13 | 525.x |
| CUDA 12.1 | 530.30.02 | 535.x |
| CUDA 12.2 | 535.54.03 | 535.x |
| CUDA 12.3 | 545.23.06 | 545.x |
| CUDA 12.4 | 550.54.14 | 550.x |
| CUDA 12.5 | 555.42.02 | — |
| CUDA 12.6 | 560.28.03 | — |
| CUDA 12.8 | 570.86.10 | 570.x |

> **Forward Compatibility**: 드라이버 버전이 높으면 더 낮은 CUDA Toolkit도 사용 가능.
> 예: 드라이버 550.x → CUDA 12.4 이하 모든 버전 사용 가능.

#### 버전 확인 방법

```bash
# 드라이버 지원 최대 CUDA 버전 (nvidia-smi)
nvidia-smi | grep "CUDA Version"
# CUDA Version: 12.4

# 설치된 CUDA Toolkit 버전 (nvcc)
nvcc --version
# nvcc: NVIDIA (R) Cuda compiler driver
# Cuda compilation tools, release 12.2, V12.2.140

# PyTorch에서 인식하는 CUDA 버전
python3 -c "import torch; print('PyTorch CUDA:', torch.version.cuda)"

# 드라이버 버전
nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1
```

#### 버전 불일치 시나리오

```
시나리오 1 (정상): 드라이버 550.x (CUDA 12.4 지원) + CUDA Toolkit 12.2
  → 드라이버가 CUDA 12.2 이상 지원 → 실행 가능 ✅

시나리오 2 (오류): 드라이버 535.x (CUDA 12.2 지원) + CUDA Toolkit 12.4
  → 드라이버가 CUDA 12.4 미지원 → 실행 불가 ❌
  → RuntimeError: CUDA error: no kernel image is available for execution on the device

시나리오 3 (AWS DLAMI): 드라이버 535.x + PyTorch 2.1 (CUDA 12.1 빌드)
  → 드라이버가 CUDA 12.1 지원 → 실행 가능 ✅
```

### 2.2 호환성 확인 스크립트

```bash
#!/bin/bash
# CUDA-드라이버 호환성 빠른 확인

echo "=== 버전 정보 ==="
echo "드라이버 버전: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)"
echo "드라이버 지원 최대 CUDA: $(nvidia-smi | grep 'CUDA Version' | awk '{print $NF}')"

if command -v nvcc &>/dev/null; then
  echo "CUDA Toolkit 버전: $(nvcc --version | grep 'release' | awk '{print $6}' | tr -d ',')"
else
  echo "CUDA Toolkit: 미설치"
fi

if python3 -c "import torch" 2>/dev/null; then
  echo "PyTorch 버전: $(python3 -c 'import torch; print(torch.__version__)')"
  echo "PyTorch CUDA 버전: $(python3 -c 'import torch; print(torch.version.cuda)')"
  echo "GPU 사용 가능: $(python3 -c 'import torch; print(torch.cuda.is_available())')"
fi

echo ""
echo "=== 호환성 판단 ==="
DRIVER_CUDA=$(nvidia-smi | grep 'CUDA Version' | awk '{print $NF}')
if command -v nvcc &>/dev/null; then
  TOOLKIT_CUDA=$(nvcc --version | grep 'release' | awk '{print $6}' | tr -d ',')
  # 간단 비교 (Major.Minor)
  DRIVER_MAJOR=$(echo $DRIVER_CUDA | cut -d'.' -f1)
  TOOLKIT_MAJOR=$(echo $TOOLKIT_CUDA | cut -d'.' -f1)
  DRIVER_MINOR=$(echo $DRIVER_CUDA | cut -d'.' -f2)
  TOOLKIT_MINOR=$(echo $TOOLKIT_CUDA | cut -d'.' -f2)

  if [ "$DRIVER_MAJOR" -gt "$TOOLKIT_MAJOR" ] || \
     ([ "$DRIVER_MAJOR" -eq "$TOOLKIT_MAJOR" ] && [ "$DRIVER_MINOR" -ge "$TOOLKIT_MINOR" ]); then
    echo "✅ 호환 가능: 드라이버(CUDA $DRIVER_CUDA) >= Toolkit($TOOLKIT_CUDA)"
  else
    echo "❌ 호환 불가: 드라이버(CUDA $DRIVER_CUDA) < Toolkit($TOOLKIT_CUDA)"
    echo "   → 드라이버 업그레이드 필요"
  fi
fi
```

### 2.3 CUDA Toolkit 설치

```bash
# CUDA 12.2 설치 예시 (AL2023)
CUDA_VERSION="12-2"

sudo dnf config-manager --add-repo \
  https://developer.download.nvidia.com/compute/cuda/repos/amzn2023/x86_64/cuda-amzn2023.repo

sudo dnf install -y cuda-toolkit-${CUDA_VERSION}

# 환경 변수 설정
cat >> ~/.bashrc <<'EOF'
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
EOF
source ~/.bashrc

# 설치 확인
nvcc --version
```

### 2.4 Best Practice

- CUDA Toolkit 버전은 프레임워크(PyTorch/TensorFlow) 빌드 버전에 맞춰 선택 — 프레임워크가 지원하는 CUDA 버전이 실제 필요한 버전
- 드라이버 버전 고정(`pinning`)으로 `dnf update` 시 자동 업그레이드 방지:
  ```bash
  echo "exclude=nvidia-driver* cuda-drivers*" | sudo tee -a /etc/dnf/dnf.conf
  ```
- 컨테이너 환경에서는 호스트 드라이버 버전만 고정하고, CUDA Toolkit은 컨테이너 이미지에 포함

---

## 3. 트러블슈팅

### 3.1 주요 이슈

#### PyTorch `torch.cuda.is_available()` → False

**증상**
- GPU가 `nvidia-smi`에서 정상 표시되지만 PyTorch에서 GPU 인식 못 함

**원인**
- PyTorch 빌드에 포함된 CUDA 버전이 설치된 드라이버보다 높음
- 또는 CUDA 관련 공유 라이브러리(`.so`)가 `LD_LIBRARY_PATH`에 없음

**해결 방법**
```bash
# PyTorch CUDA 버전과 드라이버 지원 버전 비교
python3 -c "import torch; print(torch.version.cuda)"   # PyTorch 빌드 CUDA
nvidia-smi | grep "CUDA Version"                         # 드라이버 지원 최대 CUDA

# CUDA 라이브러리 경로 확인
ldconfig -p | grep libcuda
python3 -c "import ctypes; ctypes.CDLL('libcuda.so.1')"

# PyTorch 재설치 (드라이버 CUDA 버전에 맞는 빌드)
# 예: 드라이버가 CUDA 12.2 지원 → cu122 빌드 사용
pip3 install torch --index-url https://download.pytorch.org/whl/cu122
```

---

#### nvcc 없음 에러 (`command not found`)

**증상**
- `nvcc --version` → `command not found`

**원인**
- CUDA Toolkit 미설치 또는 PATH 미설정
- CUDA Toolkit과 드라이버가 분리 설치됨 (드라이버만 있고 Toolkit 없음)

**해결 방법**
```bash
# CUDA Toolkit 설치 여부 확인
rpm -qa | grep cuda-toolkit

# PATH 확인
echo $PATH | tr ':' '\n' | grep cuda

# 경로 추가
export PATH=/usr/local/cuda/bin:$PATH
```

---

### 3.2 자주 발생하는 문제 (Q&A)

**Q: `nvidia-smi`의 CUDA Version과 `nvcc --version`의 버전이 다른 이유는?**
A: 정상. `nvidia-smi`의 CUDA Version은 드라이버가 지원하는 **최대** CUDA API 버전. `nvcc --version`은 실제 설치된 CUDA Toolkit 버전. 두 값이 다르더라도 Toolkit 버전 ≤ 드라이버 지원 버전이면 정상 동작.

**Q: 동일 서버에서 CUDA 11과 CUDA 12를 동시에 사용할 수 있는가?**
A: 가능. `/usr/local/cuda-11.8`, `/usr/local/cuda-12.2` 처럼 별도 경로에 설치 후 `update-alternatives` 또는 환경 변수로 전환:
```bash
# 사용할 CUDA 버전 전환
export PATH=/usr/local/cuda-12.2/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda-12.2/lib64:$LD_LIBRARY_PATH
```

---

## 4. 모니터링 및 알람

### 핵심 지표

| 지표 | 수집 방법 | 의미 | 임계값 예시 |
|------|----------|------|------------|
| CUDA 사용 가능 여부 | 초기화 스크립트 | 드라이버-CUDA 호환성 확인 | False 시 즉시 알람 |

### 인스턴스 시작 시 CUDA 호환성 자동 확인

```bash
#!/bin/bash
# /opt/scripts/check-cuda-compat.sh — 인스턴스 시작 시 실행

RESULT=$(python3 -c "import torch; print(torch.cuda.is_available())" 2>/dev/null)
if [ "$RESULT" != "True" ]; then
  # CloudWatch에 이상 지표 발행
  INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $(curl -s -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600')" http://169.254.169.254/latest/meta-data/instance-id)
  aws cloudwatch put-metric-data \
    --namespace "GPU/Health" \
    --metric-name "cuda_available" \
    --value 0 \
    --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
    --region ap-northeast-2
fi
```

---

## 5. TIP

- AWS DLAMI 사용 시 해당 AMI의 CUDA/드라이버 버전 조합이 검증됨 — DLAMI 릴리스 노트에서 버전 확인 후 프레임워크 설치
- 컨테이너에서 CUDA 사용 시 `nvidia/cuda` 공식 이미지의 태그(`12.2.0-cudnn8-runtime-ubuntu20.04` 등)에 CUDA 버전이 명시됨
- `torch.cuda.get_device_capability()` 로 GPU의 Compute Capability 확인 가능 — A100: `(8, 0)`, H100: `(9, 0)`

**관련 문서**
- [CUDA Compatibility](https://docs.nvidia.com/deploy/cuda-compatibility/index.html)
- [CUDA Toolkit Archive](https://developer.nvidia.com/cuda-toolkit-archive)
- 연관 내부 문서: `docs/driver/nvidia-driver-version-management.md`
