# NVIDIA 드라이버 버전 관리

## 1. 개요

NVIDIA 드라이버는 Production Branch와 New Feature Branch로 나뉘며, 운영 환경에서는 안정성이 검증된 Production Branch 사용 권장.
드라이버 버전은 CUDA 호환성 및 AWS 지원 여부와 직결되므로, 업그레이드 전 호환성 확인 필수.
잘못된 버전 업그레이드 시 `nvidia-smi` 동작 불가 또는 학습 코드 실행 실패가 발생하므로 롤백 절차를 미리 준비해야 함.

**핵심 요약**
- **사용 목적**: 드라이버 버전 선택 기준 정립, 안전한 업그레이드/롤백 절차
- **주요 이점**: Production Branch 고정으로 운영 중 예기치 않은 변경 방지
- **관련 도구**: dkms, nvidia-smi, dnf, AWS AMI
- **해당 인스턴스**: 모든 NVIDIA GPU 인스턴스

---

## 2. 설명

### 2.1 핵심 개념

#### 드라이버 Branch 종류

| Branch 유형 | MAJOR 번호 | 특징 | 권장 상황 |
|------------|-----------|------|---------|
| Production Branch (짝수) | 470, 510, 525, 535, 550, 570 | 장기 지원(LTS), 안정성 검증 | **운영 환경 필수** |
| New Feature Branch (홀수) | 545, 560 | 최신 기능, 안정성 미검증 | 테스트 환경만 |

#### 버전 표기 및 의미

```
535 . 154 . 05
 │     │     └── Patch (보안 패치, 버그 수정)
 │     └──────── Minor (기능 추가)
 └────────────── Major (Branch 번호)
```

#### 드라이버-CUDA 지원 관계

드라이버가 지원하는 CUDA 최대 버전(Forward Compatibility):

| 드라이버 Branch | 지원 최대 CUDA |
|---------------|--------------|
| 535.x | CUDA 12.2 |
| 550.x | CUDA 12.4 |
| 570.x | CUDA 12.8 |

> `nvidia-smi`의 `CUDA Version` 표시는 드라이버가 **지원하는 최대** CUDA 버전. 실제 설치된 CUDA Toolkit 버전(`nvcc --version`)과 다를 수 있음.

### 2.2 현재 버전 확인 및 업그레이드 절차

#### 현재 버전 확인

```bash
# 드라이버 버전 확인
cat /proc/driver/nvidia/version
# 출력 예시: NVRM version: NVIDIA UNIX x86_64 Kernel Module  535.154.05  ...

# nvidia-smi로 확인
nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1

# DKMS 빌드 이력 확인
dkms status
# 출력: nvidia/535.154.05, 6.1.91-99.172.amzn2023.x86_64: installed
```

#### 목표 버전 선택

```bash
# NVIDIA 공식 드라이버 목록 확인 (웹)
# https://www.nvidia.com/en-us/drivers/ → Data Center/Tesla 카테고리

# AWS DLAMI 릴리스 노트에서 검증된 버전 확인
# https://docs.aws.amazon.com/dlami/latest/devguide/appendix-ami-release-notes.html
```

#### 드라이버 업그레이드 (DKMS runfile 방식)

```bash
export CURRENT_VERSION="535.154.05"
export TARGET_VERSION="550.90.12"

# 1. 현재 상태 백업
nvidia-smi -q > /tmp/nvidia-before-upgrade.txt
dkms status > /tmp/dkms-before.txt

# 2. GPU 사용 프로세스 종료 확인
nvidia-smi --query-compute-apps=pid,process_name --format=csv,noheader

# 3. 커널 헤더 최신화
sudo dnf install -y kernel-devel-$(uname -r)

# 4. 새 드라이버 다운로드
wget "https://us.download.nvidia.com/tesla/${TARGET_VERSION}/NVIDIA-Linux-x86_64-${TARGET_VERSION}.run" \
  -O /tmp/nvidia-driver-new.run

# 5. 기존 드라이버 제거 후 새 버전 설치
sudo sh /tmp/nvidia-driver-new.run \
  --uninstall --silent                   # 기존 제거

sudo sh /tmp/nvidia-driver-new.run \
  --dkms --silent --no-opengl-files --no-x-check  # 신규 설치

# 6. 재부팅
sudo reboot
```

#### 업그레이드 후 확인

```bash
# 버전 확인
nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1

# DKMS 빌드 성공 확인
dkms status | grep nvidia

# Xid 에러 없는지 확인
dmesg -T | grep "NVRM: Xid"

# CUDA 호환성 확인 (CUDA 코드 실행 가능한지)
python3 -c "import torch; print(torch.cuda.is_available(), torch.version.cuda)"
```

### 2.3 드라이버 롤백

```bash
export ROLLBACK_VERSION="535.154.05"

# 1. 현재 드라이버 제거
sudo sh /tmp/nvidia-driver-new.run --uninstall --silent

# 2. 이전 버전 재설치 (runfile이 보존된 경우)
sudo sh /tmp/nvidia-driver-old.run \
  --dkms --silent --no-opengl-files --no-x-check

# 3. 재부팅
sudo reboot
```

> **권장**: 업그레이드 전 AMI 스냅샷 생성 → 롤백 시 AMI에서 새 인스턴스 시작 (가장 안전)

### 2.4 Best Practice

- 운영 인스턴스 업그레이드 전 **개발/스테이징 인스턴스에서 동일 절차 먼저 검증**
- AMI 기반 배포: 업그레이드된 드라이버로 Golden AMI 새로 생성 후 롤링 교체
- 드라이버 버전을 코드로 관리 (Packer HCL 또는 ansible playbook)
- `dkms status` 출력을 CloudWatch Custom Metric이나 인스턴스 초기화 헬스체크에 포함

---

## 3. 트러블슈팅

### 3.1 주요 이슈

#### 업그레이드 후 CUDA 코드 실행 실패

**증상**
- `torch.cuda.is_available()` → `False`
- `RuntimeError: CUDA error: no kernel image is available for execution on the device`

**원인**
- CUDA Toolkit 버전이 새 드라이버가 요구하는 최소 드라이버 버전보다 낮음
- 반대로, CUDA Toolkit이 현재 드라이버보다 너무 높은 경우

**해결 방법**
```bash
# CUDA Toolkit 버전 확인
nvcc --version

# 드라이버가 지원하는 CUDA 버전 확인
nvidia-smi | grep "CUDA Version"

# CUDA Toolkit과 드라이버 호환성 표 대조
# docs/cuda/cuda-driver-compatibility.md 참조
```

> **예방책**: 업그레이드 전 `docs/cuda/cuda-driver-compatibility.md` 호환성 매트릭스 확인

---

#### 업그레이드 후 특정 GPU만 `nvidia-smi`에서 누락

**증상**
- p4d 인스턴스에서 8개 GPU 중 일부만 표시

**원인**
- Fabric Manager 버전이 새 드라이버와 불일치 (p4d/p5 전용 이슈)

**해결 방법**
```bash
# Fabric Manager 버전 확인
systemctl status nvidia-fabricmanager | grep version

# 드라이버와 동일 버전 Fabric Manager 설치
sudo dnf install -y nvidia-fabricmanager-550  # 드라이버 버전에 맞춰 변경

sudo systemctl restart nvidia-fabricmanager
nvidia-smi  # GPU 전체 표시 확인
```

---

### 3.2 자주 발생하는 문제 (Q&A)

**Q: Production Branch인지 확인하는 방법은?**
A: Major 버전 번호가 짝수(470, 510, 525, 535, 550, 570)이면 Production Branch. `nvidia-smi | grep "Driver Version"` 에서 확인.

**Q: AWS DLAMI 사용 시 드라이버를 직접 업그레이드해도 되는가?**
A: 가능하나, DLAMI는 특정 드라이버 버전에 맞춰 CUDA Toolkit, cuDNN 등이 사전 구성됨. 드라이버만 업그레이드하면 기존 CUDA 환경이 깨질 수 있음. DLAMI 신규 버전 AMI로 교체하는 방식 권장.

---

## 4. 모니터링 및 알람

### 핵심 지표

| 지표 | 수집 방법 | 의미 | 임계값 예시 |
|------|----------|------|------------|
| `gpu_util` | nvidia-smi | 드라이버 로드 및 동작 여부 간접 확인 | 수집 중단 시 알람 |

### CloudWatch 알람

```bash
# 드라이버 버전 변경 감지 (Systems Manager Inventory 활용)
# AWS Systems Manager → Inventory → Software에서 nvidia-smi 버전 추적 가능
aws ssm put-inventory \
  --instance-id <INSTANCE_ID> \
  --items '[{"TypeName":"Custom:NvidiaDriver","SchemaVersion":"1.0","CaptureTime":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","Content":[{"DriverVersion":"'$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)'"}]}]'
```

---

## 5. TIP

- NVIDIA Security Bulletins 구독으로 취약점 패치 버전 출시 시 알림 수신 가능
- `dkms status` 출력 자동화 모니터링: `/usr/local/bin/check-dkms.sh` 스크립트를 cron으로 실행 후 이상 시 CloudWatch Alarm 발행
- 드라이버 runfile은 `/tmp`에 보관하지 말고 S3에 저장 — 재설치/롤백 시 재다운로드 불필요

**관련 문서**
- [NVIDIA Driver Branches](https://docs.nvidia.com/datacenter/tesla/drivers/index.html)
- 연관 내부 문서: `docs/driver/nvidia-driver-install-al2023.md`, `docs/cuda/cuda-driver-compatibility.md`
