# nvidia-smi 기본 사용법

## 1. 개요

nvidia-smi (NVIDIA System Management Interface)는 NVIDIA GPU의 상태를 조회하고 관리하는 CLI 도구.
드라이버 설치 시 자동으로 포함되며, GPU 사용률, 메모리, 온도, 실행 중인 프로세스를 실시간으로 확인 가능.
AWS GPU 인스턴스(p3, p4d, p5, g4dn, g5 등)에서 GPU 이상 여부 1차 진단의 시작점.

**핵심 요약**
- **사용 목적**: GPU 상태 모니터링, 프로세스 확인, 드라이버/CUDA 버전 조회
- **주요 이점**: 별도 설치 없이 드라이버와 함께 제공, 스크립트 파싱에 적합한 CSV 출력 지원
- **관련 도구**: DCGM, CloudWatch Agent, dmesg
- **해당 인스턴스**: p3, p4d, p4de, p5, g4dn, g5, g6, g6e

---

## 2. 설명

### 2.1 핵심 개념

nvidia-smi는 NVML (NVIDIA Management Library) 위에서 동작하는 래퍼(wrapper) 도구.
드라이버 커널 모듈(`nvidia.ko`)이 로드된 상태에서만 정상 동작함.

```
[사용자] --> [nvidia-smi CLI]
                    |
              [NVML 라이브러리]
                    |
            [nvidia 커널 모듈]
                    |
              [GPU 하드웨어]
```

| 정보 유형 | 설명 |
|----------|------|
| Driver Version | 설치된 NVIDIA 드라이버 버전 |
| CUDA Version | 드라이버가 지원하는 최대 CUDA 버전 (런타임 CUDA와 다를 수 있음) |
| GPU Name | GPU 모델 (예: Tesla T4, NVIDIA A100-SXM4-80GB) |
| Persistence-M | Persistence Mode — 활성화 시 드라이버가 GPU 초기화 상태를 유지 |
| Bus-Id | PCIe 버스 주소 |
| Disp.A | Display Active 여부 (GPU 인스턴스는 Off) |

### 2.2 실무 적용 명령어

#### 기본 출력 (전체 요약)

```bash
nvidia-smi
```

**출력 예시 (g5.xlarge — A10G 1개)**:
```
+-----------------------------------------------------------------------------+
| NVIDIA-SMI 535.154.05   Driver Version: 535.154.05   CUDA Version: 12.2    |
|-------------------------------+----------------------+----------------------+
| GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
| Fan  Temp  Perf  Pwr:Usage/Cap|         Memory-Usage | GPU-Util  Compute M. |
|                               |                      |               MIG M. |
|===============================+======================+======================|
|   0  NVIDIA A10G         Off  | 00000000:00:1E.0 Off |                    0 |
|  0%   28C    P8    15W / 300W |      0MiB / 23028MiB |      0%      Default |
|                               |                      |                  N/A |
+-----------------------------------------------------------------------------+
+-----------------------------------------------------------------------------+
| Processes:                                                                  |
|  GPU   GI   CI        PID   Type   Process name                  GPU Memory |
|        ID   ID                                                   Usage      |
|=============================================================================|
|  No running processes found                                                 |
+-----------------------------------------------------------------------------+
```

#### GPU 수 확인

```bash
nvidia-smi --query-gpu=index --format=csv,noheader | wc -l
```

#### 드라이버 및 CUDA 버전만 출력

```bash
# 드라이버 버전
nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1

# CUDA 버전 (드라이버 지원 최대값)
nvidia-smi | grep "CUDA Version" | awk '{print $NF}'
```

#### GPU별 핵심 지표 한 줄 출력

```bash
nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw \
  --format=csv,noheader,nounits
```

**출력 예시**:
```
0, NVIDIA A10G, 0, 0, 23028, 28, 15.31
```

#### 실행 중인 프로세스 확인

```bash
nvidia-smi --query-compute-apps=pid,used_memory,process_name \
  --format=csv,noheader,nounits
```

**출력 예시** (프로세스 있을 때):
```
12345, 8192, python3
```

#### Persistence Mode 활성화

```bash
# 활성화 (재부팅 후에도 GPU 초기화 상태 유지 → 첫 로드 레이턴시 감소)
sudo nvidia-smi -pm 1

# 확인
nvidia-smi --query-gpu=persistence_mode --format=csv,noheader
```

> **권장**: ML 학습/추론 서버에서는 Persistence Mode On 설정 권장

### 2.3 Best Practice

- `--format=csv,noheader,nounits` 조합으로 파싱 친화적 출력 사용
- 스크립트에서 GPU 수를 하드코딩하지 말고 동적으로 확인
- p4d/p5처럼 GPU 8개 이상인 인스턴스에서는 `-i <GPU_INDEX>` 플래그로 특정 GPU 지정
- `nvidia-smi -q` (상세 전체 출력)는 정보가 방대하므로 `-d` 플래그로 섹션 지정 권장

```bash
# 특정 섹션만 조회
nvidia-smi -q -d MEMORY      # 메모리 정보만
nvidia-smi -q -d UTILIZATION # 사용률만
nvidia-smi -q -d ECC         # ECC 에러만
nvidia-smi -q -d TEMPERATURE # 온도만
nvidia-smi -q -d POWER       # 전력만
```

---

## 3. 트러블슈팅

### 3.1 주요 이슈

#### nvidia-smi: command not found

**증상**
- `nvidia-smi` 실행 시 `command not found` 또는 `No such file or directory`

**원인**
- NVIDIA 드라이버가 설치되지 않았거나, PATH에 `/usr/bin` 미포함

**해결 방법**
```bash
# 드라이버 설치 여부 확인
rpm -qa | grep nvidia    # AL2023/RHEL 계열
dpkg -l | grep nvidia    # Ubuntu 계열

# PATH 확인
which nvidia-smi
ls -la /usr/bin/nvidia-smi
```

> **예방책**: EC2 Launch Template의 UserData에 드라이버 설치 스크립트 포함

---

#### NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA driver

**증상**
- `NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA driver. Make sure that the latest NVIDIA driver is installed and running.`

**원인**
- 커널 업그레이드 후 DKMS 재빌드 미완료로 커널 모듈 로드 실패
- 드라이버 설치 후 재부팅 미수행

**해결 방법**
```bash
# 커널 모듈 로드 상태 확인
lsmod | grep nvidia

# DKMS 상태 확인
dkms status

# 현재 커널 버전과 DKMS 빌드된 버전 비교
uname -r
dkms status | grep nvidia

# 모듈 수동 로드 시도
sudo modprobe nvidia
dmesg | tail -20    # 로드 실패 원인 확인
```

> **예방책**: `yum-cron` 또는 `dnf-automatic`으로 커널 자동 업데이트 시 DKMS 연동 확인

---

#### GPU is lost (p4d/p5 NVSwitch 환경)

**증상**
- `nvidia-smi` 출력에서 일부 GPU가 `[N/A]` 또는 누락됨
- `dmesg -T | grep NVRM` 에 Xid 79 에러 포함

**원인**
- PCIe 링크 오류로 GPU가 버스에서 분리됨 (AWS 물리 호스트 하드웨어 문제)

**해결 방법**
```bash
# Xid 에러 확인
dmesg -T | grep "NVRM: Xid"

# GPU 개수 확인 (정상: p4d = 8, g5 = 1)
nvidia-smi --query-gpu=index --format=csv,noheader | wc -l
```

→ Xid 79 확인 시: **인스턴스 Stop&Start 수행** (물리 호스트 교체)

> **예방책**: CloudWatch에 GPU 개수 모니터링 알람 설정 (정상 개수 미달 시 알림)

---

### 3.2 자주 발생하는 문제 (Q&A)

**Q: `CUDA Version: N/A` 로 표시됨**
A: 드라이버는 설치됐으나 CUDA Toolkit이 미설치인 경우. nvidia-smi의 CUDA Version은 드라이버가 지원하는 최대 버전을 표시하므로, NVCC가 없어도 보통 버전이 표시됨. `N/A`가 나오면 드라이버 버전이 너무 낮거나 커널 모듈 로드 오류 의심.

**Q: Persistence Mode가 재부팅 후 Off로 초기화됨**
A: `systemd` 서비스로 영구 설정 필요. `/etc/rc.local` 또는 별도 서비스 파일 작성:
```bash
# /etc/systemd/system/nvidia-persistenced.service 이미 존재 시
sudo systemctl enable nvidia-persistenced
sudo systemctl start nvidia-persistenced
```

**Q: p4d 인스턴스에서 GPU 8개 중 일부만 조회됨**
A: Fabric Manager 서비스 상태 확인. Fabric Manager가 비정상이면 NVSwitch 연결 GPU 중 일부가 누락될 수 있음:
```bash
systemctl status nvidia-fabricmanager
journalctl -u nvidia-fabricmanager --since "10 minutes ago"
```

---

## 4. 모니터링 및 알람

### 핵심 지표

| 지표 | 수집 방법 | 의미 | 임계값 예시 |
|------|----------|------|------------|
| `gpu_util` | nvidia-smi / DCGM | GPU 코어 사용률 | `< 5% (1시간 지속)` → idle 의심 |
| `gpu_mem_used` | nvidia-smi / DCGM | 사용 중인 VRAM (MiB) | `> 95% of total` |
| `gpu_temperature` | nvidia-smi / DCGM | GPU 온도 | `> 85°C` |
| `gpu_power_draw` | nvidia-smi / DCGM | 소비 전력 (W) | `> TDP * 0.95` |

### CloudWatch 알람 설정 (GPU 온도 예시)

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "gpu-high-temperature" \
  --alarm-description "GPU 온도 85도 초과" \
  --metric-name "gpu_temperature" \
  --namespace "CWAgent" \
  --dimensions Name=InstanceId,Value=<INSTANCE_ID> \
  --statistic Maximum \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 85 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions "arn:aws:sns:ap-northeast-2:<ACCOUNT_ID>:<SNS_TOPIC>" \
  --region ap-northeast-2
```

---

## 5. TIP

- `watch -n 1 nvidia-smi` 로 1초 간격 실시간 모니터링 (터미널에서 빠른 확인용)
- `nvidia-smi dmon` 은 `watch`보다 가볍고 CSV 파일로 리디렉션 가능: `nvidia-smi dmon -s u -d 5 >> /var/log/gpu-util.log`
- AWS EC2 인스턴스 메타데이터로 인스턴스 타입 확인 후 GPU 수 기대값 검증 가능:
  ```bash
  TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
  curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type
  ```

**관련 문서**
- [NVIDIA SMI Documentation](https://developer.nvidia.com/nvidia-system-management-interface)
- 연관 내부 문서: `docs/smi/nvidia-smi-query.md`, `docs/troubleshooting/xid-error-codes.md`
