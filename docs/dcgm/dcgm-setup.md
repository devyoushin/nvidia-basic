# DCGM 설치 및 nv-hostengine 구성

## 1. 개요

DCGM (Data Center GPU Manager)은 NVIDIA가 제공하는 데이터센터 GPU 관리 및 진단 프레임워크.
nvidia-smi보다 풍부한 지표 수집, 헬스 체크, 정책 기반 관리 기능을 제공하며 CloudWatch Agent의 GPU 지표 수집 백엔드로 사용됨.
`nv-hostengine` 데몬이 GPU 지표를 수집하고, `dcgmi` CLI와 CloudWatch Agent가 이를 조회하는 구조.

**핵심 요약**
- **사용 목적**: 상세 GPU 지표 수집, 헬스 체크 자동화, CloudWatch Agent 연동
- **주요 이점**: 필드 그룹 기반 선택적 수집, 그룹/엔티티 단위 헬스 체크
- **관련 도구**: dcgmi, nv-hostengine, CloudWatch Agent
- **해당 인스턴스**: 모든 NVIDIA GPU 인스턴스 (데이터센터급 GPU 권장)

---

## 2. 설명

### 2.1 핵심 개념

```
[GPU 하드웨어]
      |
[nv-hostengine]  ← DCGM 수집 데몬 (백그라운드 실행)
      |
  ┌───┴───────────┐
[dcgmi CLI]   [CloudWatch Agent]
              (nvidia_gpu 플러그인)
```

| 구성 요소 | 역할 |
|----------|------|
| `nv-hostengine` | GPU 지표 수집 데몬 (DCGM 코어) |
| `dcgmi` | DCGM CLI — 지표 조회, 그룹 관리, 헬스 체크 |
| `libdcgm.so` | DCGM 라이브러리 — CWAgent 연동에 필요 |
| `nvidia-dcgm` | systemd 서비스 단위 |

### 2.2 설치

```bash
# CUDA 저장소 추가 (미설치 시)
sudo dnf config-manager --add-repo \
  https://developer.download.nvidia.com/compute/cuda/repos/amzn2023/x86_64/cuda-amzn2023.repo

sudo dnf clean all

# DCGM 설치
sudo dnf install -y datacenter-gpu-manager

# 설치 확인
dcgmi --version
```

### 2.3 서비스 시작 및 확인

```bash
# systemd 서비스로 시작 (권장)
sudo systemctl enable nvidia-dcgm
sudo systemctl start nvidia-dcgm

# 상태 확인
systemctl status nvidia-dcgm

# GPU 인식 확인
dcgmi discovery -l

# 출력 예시 (g5.xlarge — A10G 1개)
# 1 GPU found.
# +--------+--------------------------------------------------------------+
# | GPU ID | Device Information                                           |
# +--------+--------------------------------------------------------------+
# | 0      | Name: NVIDIA A10G                                            |
# |        | PCI Bus ID: 00000000:00:1E.0                                 |
# |        | Device UUID: GPU-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx        |
# +--------+--------------------------------------------------------------+
```

### 2.4 nv-hostengine 수동 시작 (systemd 없는 환경)

```bash
# 포그라운드 테스트 (디버깅용)
nv-hostengine --term

# 백그라운드 데몬으로 시작
nv-hostengine

# 프로세스 확인
pgrep -a nv-hostengine

# 중지
nv-hostengine --term
```

### 2.5 기본 지표 수집 확인

```bash
# 모든 GPU 기본 지표 조회 (dmon 형태)
dcgmi dmon -e 1001,1007,1008,1009,1010 -d 5000
# 필드: GPU 사용률, 온도, 전력, FB Free, FB Used

# 출력 예시
# #Entity   DCGM_FI_DEV_GPU_UTIL  DCGM_FI_DEV_GPU_TEMP  DCGM_FI_DEV_POWER_USAGE  DCGM_FI_DEV_FB_FREE  DCGM_FI_DEV_FB_USED
# GPU 0                        0                    28                    15.198                22943                  85
```

### 2.6 그룹 생성 및 관리

```bash
# 전체 GPU로 그룹 생성
dcgmi group -c "all-gpus" -a 0
# 또는 모든 GPU 자동 포함
dcgmi group -c "all-gpus"

# 그룹 목록 확인
dcgmi group -l

# 출력 예시
# +----------------------------+
# | DCGM Groups                |
# +---------+------------------+
# | Group ID | Group Name      |
# +---------+------------------+
# | 1        | all-gpus        |
# +---------+------------------+

# 그룹에 GPU 추가
dcgmi group -g <GROUP_ID> -a <GPU_ID>
```

### 2.7 Best Practice

- `nvidia-dcgm` systemd 서비스 사용 권장 — 인스턴스 재시작 후 자동으로 nv-hostengine 재시작됨
- CloudWatch Agent와 함께 사용 시 CWAgent가 로컬 DCGM 소켓에 연결하므로 `nv-hostengine`이 먼저 실행되어야 함
- DCGM 버전과 드라이버 버전 호환성 확인 — DCGM 3.x는 드라이버 450 이상 필요

---

## 3. 트러블슈팅

### 3.1 주요 이슈

#### dcgmi discovery -l 에서 GPU 0개 인식

**증상**
- `dcgmi discovery -l` 출력: `0 GPUs found`

**원인**
- `nv-hostengine`이 실행되지 않았거나 nvidia 드라이버가 로드되지 않음

**해결 방법**
```bash
# nv-hostengine 프로세스 확인
pgrep -a nv-hostengine

# nvidia 커널 모듈 확인
lsmod | grep nvidia

# DCGM 서비스 재시작
sudo systemctl restart nvidia-dcgm
sleep 3
dcgmi discovery -l
```

---

#### CloudWatch Agent에서 nvidia_gpu 지표 미수집

**증상**
- CWAgent 로그에 `failed to get GPU metrics` 또는 `DCGM connection failed`

**원인**
- `libdcgm.so` 라이브러리 경로가 CWAgent에서 찾지 못하는 위치에 있음

**해결 방법**
```bash
# libdcgm.so 위치 확인
find /usr -name "libdcgm.so*" 2>/dev/null
ldconfig -p | grep libdcgm

# 심볼릭 링크 생성 (경로 불일치 시)
sudo ln -sf /usr/lib/x86_64-linux-gnu/libdcgm.so.3 /usr/lib/libdcgm.so

# ldconfig 업데이트
sudo ldconfig

# CWAgent 재시작
sudo systemctl restart amazon-cloudwatch-agent
```

---

### 3.2 자주 발생하는 문제 (Q&A)

**Q: DCGM 없이 CWAgent만으로 GPU 지표 수집 가능한가?**
A: 불가. CWAgent의 `nvidia_gpu` 플러그인은 내부적으로 DCGM 라이브러리(`libdcgm.so`)를 사용. DCGM 없이는 `scripts/gpu-metrics-to-cw.sh` 방식(nvidia-smi 직접 발행)을 사용해야 함.

**Q: dcgmi dmon -e 플래그에 사용하는 필드 ID는 어떻게 찾는가?**
A: `docs/dcgm/dcgm-field-groups.md` 또는 `dcgmi dmon --list` 명령으로 지원 필드 목록 확인.

---

## 4. 모니터링 및 알람

### 핵심 지표

| 지표 | 수집 방법 | 의미 | 임계값 예시 |
|------|----------|------|------------|
| nv-hostengine 프로세스 | CWAgent procstat | DCGM 데몬 정상 동작 | `pid_count < 1` 즉시 알람 |

### CloudWatch 알람 (procstat 연동)

```bash
# CWAgent 설정에 procstat 추가 후:
aws cloudwatch put-metric-alarm \
  --alarm-name "dcgm-hostengine-down" \
  --alarm-description "nv-hostengine 프로세스 비정상" \
  --metric-name "procstat_lookup_pid_count" \
  --namespace "CWAgent" \
  --dimensions \
    Name=InstanceId,Value=<INSTANCE_ID> \
    Name=process_name,Value=nv-hostengine \
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

- DCGM health watch로 GPU 헬스 상태를 지속 감시 가능: `dcgmi health -g <GROUP_ID> -w 30000` (30초 간격)
- DCGM은 ECC 에러, PCIe 에러, NVLink 에러 등을 통합 헬스 체크로 제공 — `dcgmi health -g <GROUP_ID> -c` 로 즉시 진단
- EKS GPU 노드에서는 DCGM Exporter 컨테이너로 배포하는 것이 표준 패턴 (`docs/monitoring/dcgm-exporter-prometheus.md` 참조)

**관련 문서**
- [NVIDIA DCGM Documentation](https://docs.nvidia.com/datacenter/dcgm/latest/user-guide/index.html)
- 연관 내부 문서: `docs/dcgm/dcgm-field-groups.md`, `docs/monitoring/cw-gpu-metrics.md`
