# DCGM 필드 그룹 및 dcgmi 명령어

## 1. 개요

DCGM 필드(Field)는 GPU에서 수집 가능한 지표의 단위이며, 필드 그룹(Field Group)으로 묶어 일괄 수집 및 관리 가능.
`dcgmi` CLI로 지표 실시간 조회, 헬스 체크, 그룹 관리, 진단 테스트를 수행할 수 있음.
CloudWatch Agent와 연동 시 어떤 필드를 수집할지 DCGM 측에서 미리 파악해두면 CWAgent 설정 최적화에 도움.

**핵심 요약**
- **사용 목적**: 수집 지표 선택, 헬스 체크 자동화, 필드 그룹 기반 모니터링
- **주요 이점**: nvidia-smi보다 세분화된 지표 (NVLink 대역폭, PCIe 에러, 클럭 이벤트 등)
- **관련 도구**: dcgmi, nv-hostengine
- **해당 인스턴스**: 모든 NVIDIA GPU 인스턴스 (DCGM 설치 필요)

---

## 2. 설명

### 2.1 주요 필드 ID 목록

#### 사용률 및 메모리

| 필드 ID | 필드명 | 설명 | 단위 |
|---------|--------|------|------|
| 1001 | DCGM_FI_DEV_GPU_UTIL | GPU 코어 사용률 | % |
| 1002 | DCGM_FI_DEV_MEM_COPY_UTIL | 메모리 대역폭 사용률 | % |
| 1003 | DCGM_FI_DEV_ENC_UTIL | 인코더 사용률 | % |
| 1004 | DCGM_FI_DEV_DEC_UTIL | 디코더 사용률 | % |
| 1009 | DCGM_FI_DEV_FB_FREE | Frame Buffer 여유 공간 | MiB |
| 1010 | DCGM_FI_DEV_FB_USED | Frame Buffer 사용량 | MiB |
| 1011 | DCGM_FI_DEV_FB_TOTAL | Frame Buffer 전체 크기 | MiB |

#### 클럭

| 필드 ID | 필드명 | 설명 | 단위 |
|---------|--------|------|------|
| 1005 | DCGM_FI_DEV_SM_CLOCK | SM 클럭 | MHz |
| 1006 | DCGM_FI_DEV_MEM_CLOCK | 메모리 클럭 | MHz |
| 1100 | DCGM_FI_DEV_APP_SM_CLOCK | 애플리케이션 SM 클럭 | MHz |
| 1101 | DCGM_FI_DEV_APP_MEM_CLOCK | 애플리케이션 메모리 클럭 | MHz |

#### 전력 및 온도

| 필드 ID | 필드명 | 설명 | 단위 |
|---------|--------|------|------|
| 1007 | DCGM_FI_DEV_GPU_TEMP | GPU 다이 온도 | °C |
| 1008 | DCGM_FI_DEV_POWER_USAGE | 현재 소비 전력 | W |
| 1021 | DCGM_FI_DEV_POWER_MGMT_LIMIT | 전력 한도 | W |

#### ECC 에러

| 필드 ID | 필드명 | 설명 | 단위 |
|---------|--------|------|------|
| 1500 | DCGM_FI_DEV_ECC_SBE_VOL_TOTAL | 단일 비트 ECC (휘발성) | Count |
| 1501 | DCGM_FI_DEV_ECC_DBE_VOL_TOTAL | 이중 비트 ECC (휘발성) | Count |
| 1502 | DCGM_FI_DEV_ECC_SBE_AGG_TOTAL | 단일 비트 ECC (누적) | Count |
| 1503 | DCGM_FI_DEV_ECC_DBE_AGG_TOTAL | 이중 비트 ECC (누적) | Count |

#### NVLink (p4d/p5 전용)

| 필드 ID | 필드명 | 설명 | 단위 |
|---------|--------|------|------|
| 1012 | DCGM_FI_DEV_NVLINK_BANDWIDTH_TOTAL | NVLink 총 대역폭 | KB/s |
| 1044 | DCGM_FI_DEV_NVLINK_CRC_FLIT_ERROR_COUNT_TOTAL | NVLink CRC 에러 (FLIT) | Count |
| 1045 | DCGM_FI_DEV_NVLINK_CRC_DATA_ERROR_COUNT_TOTAL | NVLink CRC 에러 (Data) | Count |
| 1046 | DCGM_FI_DEV_NVLINK_REPLAY_ERROR_COUNT_TOTAL | NVLink Replay 에러 | Count |
| 1047 | DCGM_FI_DEV_NVLINK_RECOVERY_ERROR_COUNT_TOTAL | NVLink Recovery 에러 | Count |

#### Xid 에러 및 기타

| 필드 ID | 필드명 | 설명 | 단위 |
|---------|--------|------|------|
| 230 | DCGM_FI_DEV_XID_ERRORS | 마지막 Xid 에러 코드 | Code |
| 1603 | DCGM_FI_DEV_RETIRED_DBE | DBE로 인해 리타이어된 페이지 | Count |
| 1013 | DCGM_FI_DEV_PCIE_TX_THROUGHPUT | PCIe TX 처리량 | KB/s |
| 1014 | DCGM_FI_DEV_PCIE_RX_THROUGHPUT | PCIe RX 처리량 | KB/s |

### 2.2 dcgmi 명령어 활용

#### 실시간 지표 모니터링 (dmon)

```bash
# 핵심 지표 5초 간격 수집
dcgmi dmon \
  -e 1001,1002,1009,1010,1007,1008 \
  -d 5000

# 출력 예시
# #Entity   DCGM_FI_DEV_GPU_UTIL  DCGM_FI_DEV_MEM_COPY_UTIL  DCGM_FI_DEV_FB_FREE  DCGM_FI_DEV_FB_USED  DCGM_FI_DEV_GPU_TEMP  DCGM_FI_DEV_POWER_USAGE
# GPU 0                       42                         35                22104                  924                    52                   187.198

# ECC 에러 모니터링
dcgmi dmon -e 1500,1501,230 -d 10000

# NVLink 대역폭 (p4d/p5 전용)
dcgmi dmon -e 1012 -d 1000
```

#### 헬스 체크

```bash
# GPU 그룹 헬스 체크 (1회)
dcgmi health -g <GROUP_ID> -c

# 출력 예시 (정상)
# +---------------------------+-------+
# | Overall Health            |       |
# +===========================+=======+
# | Healthy                   |       |
# +---------------------------+-------+
# | GPU ID 0                  |       |
# +---------------------------+-------+
# | Memory                    | OK    |
# | PCIe                      | OK    |
# | SM                        | OK    |
# | MC                        | OK    |
# | NVLink                    | OK    |
# +---------------------------+-------+

# 헬스 감시 모드 (30초 간격)
dcgmi health -g <GROUP_ID> -w 30000
```

#### 필드 그룹 생성 및 관리

```bash
# 커스텀 필드 그룹 생성 (운영 모니터링용)
dcgmi fieldgroup -c "ops-metrics" \
  -f 1001,1002,1009,1010,1007,1008,1500,1501,230

# 필드 그룹 목록 확인
dcgmi fieldgroup -l

# 필드 그룹으로 dmon 실행
FIELD_GROUP_ID=$(dcgmi fieldgroup -l | grep "ops-metrics" | awk '{print $1}')
dcgmi dmon -g <GROUP_ID> -r "$FIELD_GROUP_ID" -d 5000

# 필드 그룹 삭제
dcgmi fieldgroup -d "$FIELD_GROUP_ID"
```

#### 진단 테스트 (Diag)

```bash
# 빠른 진단 (1~2분)
dcgmi diag -g <GROUP_ID> -r 1

# 표준 진단 (수 분, 실제 연산 포함)
dcgmi diag -g <GROUP_ID> -r 2

# 상세 진단 (긴 시간, 스트레스 테스트 포함)
# ⚠️ 학습 작업 없을 때만 수행 — GPU 최대 부하
dcgmi diag -g <GROUP_ID> -r 3

# 출력 예시 (정상)
# +---------------------------+------------------------------------------------+
# | Diagnostic                | Result                                         |
# +===========================+================================================+
# | Deployment                | Pass                                           |
# | PCIe                      | Pass                                           |
# | SM Stress                 | Pass                                           |
# | Targeted Stress           | Pass                                           |
# | Memory Bandwidth          | Pass                                           |
# +---------------------------+------------------------------------------------+
```

### 2.3 Best Practice

- 운영 필드 그룹은 `ops-metrics` (사용률+메모리+온도+전력+ECC), NVLink 인스턴스는 NVLink 필드 추가
- `dcgmi diag -r 1` 을 드라이버 업그레이드 후 기본 검증 단계로 루틴에 포함
- `DCGM_FI_DEV_XID_ERRORS` (필드 230)는 마지막으로 발생한 Xid 코드를 반환 — 0이 아니면 최근 에러 발생

---

## 3. 트러블슈팅

### 3.1 주요 이슈

#### dcgmi dmon에서 특정 필드가 N/A

**증상**
- `dcgmi dmon -e 1012` 출력에서 `N/A` 반환

**원인**
- 해당 GPU 모델이 해당 필드를 지원하지 않음 (예: NVLink 필드는 NVLink 탑재 GPU에서만)
- `nv-hostengine` 버전이 낮아 해당 필드가 미지원

**해결 방법**
```bash
# 지원 필드 확인
dcgmi dmon --list | grep <FIELD_ID>

# DCGM 버전 확인
dcgmi --version

# 최신 버전으로 업그레이드 검토
sudo dnf update -y datacenter-gpu-manager
```

---

#### dcgmi health 에서 Memory Warn

**증상**
- `dcgmi health -g <GROUP_ID> -c` 에서 `Memory: Warn`

**원인**
- ECC DBE(이중 비트 에러) 임계값 초과 또는 Retired Pages 증가

**해결 방법**
```bash
# 상세 원인 확인
dcgmi health -g <GROUP_ID> -c -v   # verbose

# ECC 에러 카운터 확인
dcgmi dmon -e 1501,1503 -d 1000 -c 1

# Retired Pages 확인
nvidia-smi --query-gpu=retired_pages.sbe,retired_pages.dbe --format=csv,noheader
```

---

### 3.2 자주 발생하는 문제 (Q&A)

**Q: DCGM 필드 ID를 코드로 관리하고 싶음**
A: DCGM 헤더 파일(`dcgm_fields.h`)에 모든 필드 ID 상수가 정의됨. Python DCGM 바인딩 사용 시 `pydcgm` 패키지에서 `dcgm_fields.DCGM_FI_DEV_GPU_UTIL` 형태로 참조 가능.

**Q: dcgmi diag 진단 중 GPU 사용 중이면 어떻게 되나?**
A: 진단이 실패하거나 오탐(false negative)이 발생할 수 있음. 반드시 GPU 점유 프로세스 없는 상태에서 실행.

---

## 4. 모니터링 및 알람

### 핵심 지표

| 지표 | 수집 방법 | 의미 | 임계값 예시 |
|------|----------|------|------------|
| DCGM_FI_DEV_XID_ERRORS (230) | dcgmi dmon | Xid 에러 발생 | `!= 0` 즉시 알람 |
| DCGM_FI_DEV_ECC_DBE_VOL_TOTAL (1501) | dcgmi dmon | 이중 비트 ECC 에러 | `> 0` 즉시 알람 |
| DCGM_FI_DEV_FB_FREE (1009) | dcgmi dmon | VRAM 여유 공간 | `< 10% of total` |

### CloudWatch 알람 (DCGM Exporter 또는 CWAgent 연동)

```bash
# Xid 에러 감지
aws cloudwatch put-metric-alarm \
  --alarm-name "dcgm-xid-error" \
  --alarm-description "DCGM Xid 에러 감지" \
  --metric-name "DCGM_FI_DEV_XID_ERRORS" \
  --namespace "DCGM" \
  --dimensions Name=InstanceId,Value=<INSTANCE_ID> \
  --statistic Maximum \
  --period 60 \
  --evaluation-periods 1 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --alarm-actions "arn:aws:sns:ap-northeast-2:<ACCOUNT_ID>:<SNS_TOPIC>" \
  --region ap-northeast-2
```

---

## 5. TIP

- `dcgmi dmon --list` 로 현재 DCGM 버전에서 지원하는 전체 필드 목록 확인 가능
- 운영 환경 기준 필수 수집 필드: `1001,1002,1009,1010,1007,1008,1500,1501,230` (사용률+메모리+온도+전력+ECC+Xid)
- p4d/p5에서 NVLink 문제 의심 시 `1044,1045,1046,1047` (NVLink 에러 카운터) 추가 수집

**관련 문서**
- [DCGM Field Identifiers](https://docs.nvidia.com/datacenter/04-dcgm/latest/user-guide/feature-overview.html#field-identifiers)
- 연관 내부 문서: `docs/04-dcgm/dcgm-setup.md`, `docs/05-monitoring/dcgm-exporter-prometheus.md`
