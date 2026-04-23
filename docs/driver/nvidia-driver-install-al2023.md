# AL2023 GPU 인스턴스 NVIDIA 드라이버 설치

## 1. 개요

Amazon Linux 2023 (AL2023) 기반 GPU 인스턴스에 NVIDIA 드라이버를 설치하는 절차.
AL2 대비 AL2023은 패키지 관리자가 `yum` → `dnf`로 변경, SELinux 기본 활성화, DKMS 패키지 경로 등 차이점이 있음.
잘못된 드라이버 설치는 커널 패닉 또는 `nvidia-smi` 동작 불가로 이어지므로 절차 준수 필요.

**핵심 요약**
- **사용 목적**: 신규 GPU 인스턴스 환경 구축, AMI 생성 전 드라이버 설치
- **주요 이점**: DKMS 사용 시 커널 업그레이드 후 자동 모듈 재빌드
- **관련 도구**: dnf, DKMS, nvidia-smi, dkms
- **해당 인스턴스**: p3, p4d, p4de, p5, g4dn, g5, g6 (AL2023 기반)

---

## 2. 설명

### 2.1 핵심 개념

NVIDIA 드라이버는 커널 모듈(`nvidia.ko`, `nvidia-uvm.ko` 등)로 동작. 커널 버전과 1:1 매핑이므로 커널 업그레이드 시 모듈 재빌드 필요.
DKMS (Dynamic Kernel Module Support)를 사용하면 커널 업그레이드 시 자동으로 모듈을 재빌드하여 `nvidia-smi` 사용 불가 상황 방지.

```
[NVIDIA 드라이버 패키지]
        |
   [DKMS 빌드]   ←→   [현재 커널 헤더]
        |
  [nvidia.ko 로드]
        |
 [nvidia-smi 동작]
```

| 설치 방법 | 특징 | 권장 상황 |
|----------|------|---------|
| DKMS 방식 (runfile) | 커널 업그레이드 시 자동 재빌드 | 장기 운영 인스턴스 |
| RPM 패키지 (CUDA repo) | 간편하나 커널 버전 고정 위험 | 단기 테스트 |
| AWS DLAMI | 드라이버 사전 설치 AMI | 빠른 시작 필요 시 |

### 2.2 DKMS 방식 드라이버 설치 (권장)

#### 사전 준비

```bash
# 커널 헤더 및 개발 도구 설치
sudo dnf install -y \
  kernel-devel-$(uname -r) \
  kernel-headers-$(uname -r) \
  gcc \
  make \
  dkms \
  elfutils-libelf-devel \
  libglvnd-devel

# 현재 커널 버전 확인
uname -r
```

#### nouveau 드라이버 비활성화 (AL2023)

```bash
# nouveau(오픈소스 NVIDIA 대체 드라이버) 블랙리스트 등록
sudo tee /etc/modprobe.d/blacklist-nouveau.conf <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF

# initramfs 재생성
sudo dracut --force

# 재부팅
sudo reboot
```

#### NVIDIA 드라이버 runfile 다운로드 및 설치

```bash
# NVIDIA 드라이버 버전 선택 (Production Branch 권장)
# 최신 버전 확인: https://www.nvidia.com/en-us/drivers/

DRIVER_VERSION="550.90.12"  # 예시 — 실제 사용할 버전으로 교체

# runfile 다운로드
wget "https://us.download.nvidia.com/tesla/${DRIVER_VERSION}/NVIDIA-Linux-x86_64-${DRIVER_VERSION}.run" \
  -O /tmp/nvidia-driver.run

# DKMS 포함 설치 (--dkms 플래그 필수)
sudo sh /tmp/nvidia-driver.run \
  --dkms \
  --silent \
  --no-opengl-files \   # GPU 인스턴스에서 OpenGL 불필요
  --no-x-check          # X 서버 없는 환경
```

#### 설치 확인

```bash
# 드라이버 버전 확인
cat /proc/driver/nvidia/version

# 커널 모듈 로드 확인
lsmod | grep nvidia

# nvidia-smi 동작 확인
nvidia-smi

# DKMS 등록 확인
dkms status
# 출력 예시: nvidia/550.90.12, 6.1.91-99.172.amzn2023.x86_64, x86_64: installed
```

#### Persistence Mode 영구 활성화

```bash
# nvidia-persistenced 서비스 활성화
sudo systemctl enable nvidia-persistenced
sudo systemctl start nvidia-persistenced

# 확인
systemctl status nvidia-persistenced
nvidia-smi --query-gpu=persistence_mode --format=csv,noheader
# 출력: Enabled
```

### 2.3 RPM 패키지 방식 (간편 설치)

```bash
# CUDA 저장소 추가 (AL2023)
sudo dnf config-manager --add-repo \
  https://developer.download.nvidia.com/compute/cuda/repos/amzn2023/x86_64/cuda-amzn2023.repo

sudo dnf clean all

# 드라이버 설치 (최신 버전 자동 선택)
sudo dnf install -y nvidia-driver-latest-dkms

# 또는 특정 버전
# sudo dnf install -y cuda-drivers-550

# 재부팅
sudo reboot
```

### 2.4 Best Practice

- **DKMS 방식 권장**: `dnf update`로 커널 업그레이드 시 드라이버 재설치 없이 자동 재빌드됨
- 드라이버 설치 후 반드시 `dkms status`로 빌드 성공 확인
- Golden AMI 생성 시: 드라이버 설치 → AMI 생성 → AMI 기반 인스턴스에서 `nvidia-smi` 재확인
- `--no-opengl-files` 플래그: GPU 인스턴스는 디스플레이 출력 불필요 → OpenGL 파일 설치 스킵으로 불필요한 의존성 방지

---

## 3. 트러블슈팅

### 3.1 주요 이슈

#### DKMS 빌드 실패 (커널 헤더 불일치)

**증상**
- `dkms status` 출력: `nvidia/XXX.XX.XX: broken`
- `dmesg | grep nvidia` 에 모듈 로드 실패 메시지

**원인**
- 커널 헤더가 현재 실행 중인 커널 버전과 다른 버전으로 설치됨

**해결 방법**
```bash
# 현재 커널 버전 확인
uname -r

# 설치된 커널 헤더 확인
rpm -qa | grep kernel-devel

# 정확한 버전의 헤더 재설치
sudo dnf install -y kernel-devel-$(uname -r)

# DKMS 재빌드
sudo dkms remove nvidia/<DRIVER_VERSION> --all
sudo dkms install nvidia/<DRIVER_VERSION>

# 확인
dkms status
```

> **예방책**: UserData 스크립트에서 `kernel-devel-$(uname -r)` 형식으로 현재 커널 버전 명시

---

#### nouveau 드라이버와 충돌

**증상**
- 드라이버 설치 후 `nvidia-smi` 동작 안 함
- `dmesg | grep nouveau` 에 nouveau 모듈 로드 로그

**원인**
- `/etc/modprobe.d/blacklist-nouveau.conf` 설정 후 `dracut --force` 미수행 또는 재부팅 전

**해결 방법**
```bash
# nouveau 로드 여부 확인
lsmod | grep nouveau

# 블랙리스트 파일 확인
cat /etc/modprobe.d/blacklist-nouveau.conf

# dracut 재생성 후 재부팅
sudo dracut --force
sudo reboot
```

---

#### 커널 업그레이드 후 nvidia-smi 동작 안 함

**증상**
- `dnf update` 후 재부팅 시 `nvidia-smi` 에러
- `lsmod | grep nvidia` 출력 없음

**원인**
- DKMS가 새 커널 버전에 맞춰 자동 재빌드해야 하지만, 새 커널 헤더 패키지 미설치로 빌드 실패

**해결 방법**
```bash
# 새 커널 버전 확인
uname -r

# 새 커널 헤더 설치
sudo dnf install -y kernel-devel-$(uname -r)

# DKMS 재빌드
DRIVER_VERSION=$(dkms status | grep nvidia | head -1 | awk -F'/' '{print $2}' | awk '{print $1}' | tr -d ',')
sudo dkms autoinstall -k $(uname -r)

# 모듈 로드
sudo modprobe nvidia

# 확인
nvidia-smi
```

> **예방책**: `/etc/dnf/automatic.conf` 에서 `upgrade_type = security` 설정으로 커널 자동 업그레이드 제한 또는 업그레이드 후 DKMS 확인 스크립트 자동 실행

---

### 3.2 자주 발생하는 문제 (Q&A)

**Q: p4d 인스턴스는 드라이버만 설치하면 되는가?**
A: 아님. p4d/p4de/p5는 NVSwitch를 통한 GPU 간 통신을 위해 **Fabric Manager**도 설치해야 함. Fabric Manager 없이는 GPU 8개가 각각 독립적으로만 동작:
```bash
sudo dnf install -y nvidia-fabricmanager-<VERSION>
sudo systemctl enable nvidia-fabricmanager
sudo systemctl start nvidia-fabricmanager
```

**Q: AL2 → AL2023 마이그레이션 시 드라이버 재설치 필요한가?**
A: 필요함. 커널 버전과 패키지 시스템이 완전히 다르므로 AL2023 인스턴스에서 처음부터 드라이버 설치 절차 수행 필요.

---

## 4. 모니터링 및 알람

### 핵심 지표

| 지표 | 수집 방법 | 의미 | 임계값 예시 |
|------|----------|------|------------|
| `gpu_util` | nvidia-smi | GPU 사용률 (드라이버 정상 동작 확인) | `== 0 (장시간)` → 드라이버 이상 의심 |
| EC2 StatusCheckFailed_System | CloudWatch | 물리 호스트 이상 | `>= 1` |

### CloudWatch 알람 (GPU 드라이버 미응답 감지)

```bash
# GPU 사용률 수집 불가 시 알람 (CWAgent 연동 필요)
aws cloudwatch put-metric-alarm \
  --alarm-name "gpu-driver-not-reporting" \
  --alarm-description "GPU 지표 수집 중단 — 드라이버 이상 가능성" \
  --metric-name "gpu_util" \
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

- AMI 기반 배포 시 드라이버 설치 완료 후 AMI 생성 — 매번 설치 절차 불필요
- `nvidia-smi -q | grep "Driver Version"` 을 헬스체크 스크립트에 포함하면 인스턴스 시작 후 드라이버 정상 동작 자동 확인 가능
- AL2023에서 `amazon-linux-extras` 없어짐 — CUDA는 CUDA 공식 repo 또는 AWS DLAMI 사용

**관련 문서**
- [NVIDIA Driver Installation Guide Linux](https://docs.nvidia.com/datacenter/tesla/tesla-installation-notes/index.html)
- [AWS GPU 인스턴스 드라이버 설치](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/install-nvidia-driver.html)
- 연관 내부 문서: `docs/driver/nvidia-driver-version-management.md`, `docs/driver/nvidia-fabric-manager.md`
