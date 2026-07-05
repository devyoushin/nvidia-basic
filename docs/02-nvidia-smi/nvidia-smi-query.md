# nvidia-smi 쿼리 옵션 활용

## 1. 개요

`nvidia-smi --query-gpu` 및 `--query-compute-apps`는 GPU 지표를 CSV 형식으로 구조화 출력하는 기능.
쉘 스크립트·Python 파싱에 최적화된 형태로 지표를 수집할 수 있어, CloudWatch 커스텀 지표 발행 자동화의 기반이 됨.
단순 `nvidia-smi` 출력 파싱보다 버전 간 호환성이 높음.

**핵심 요약**
- **사용 목적**: 특정 지표만 선택적으로 수집, 스크립트 자동화, CloudWatch 발행
- **주요 이점**: `--format=csv,noheader,nounits` 조합으로 파싱 코드 최소화
- **관련 도구**: CloudWatch Agent, Python boto3, bash cron
- **해당 인스턴스**: 모든 NVIDIA GPU 인스턴스

---

## 2. 설명

### 2.1 핵심 개념

```
nvidia-smi --query-{대상} <필드 목록> --format=csv[,noheader][,nounits]
```

| 쿼리 대상 | 설명 |
|----------|------|
| `--query-gpu` | GPU 자체 지표 (사용률, 메모리, 온도, ECC 등) |
| `--query-compute-apps` | GPU를 점유 중인 프로세스 정보 |
| `--query-accounted-apps` | 종료된 프로세스의 자원 사용 이력 (Accounting Mode 필요) |

### 2.2 실무 적용 명령어

#### query-gpu 주요 필드 조합

```bash
# 운영 모니터링용 핵심 지표
nvidia-smi --query-gpu=\
index,\
name,\
utilization.gpu,\
utilization.memory,\
memory.used,\
memory.total,\
temperature.gpu,\
power.draw,\
power.limit \
  --format=csv,noheader,nounits

# 출력 예시 (A10G)
# 0, NVIDIA A10G, 42, 35, 9845, 23028, 52, 187.23, 300.00
```

```bash
# ECC 에러 모니터링 (프로덕션 필수)
nvidia-smi --query-gpu=\
index,\
ecc.errors.corrected.volatile.total,\
ecc.errors.uncorrected.volatile.total,\
ecc.errors.corrected.aggregate.total,\
ecc.errors.uncorrected.aggregate.total \
  --format=csv,noheader,nounits

# 출력 예시
# 0, 0, 0, 12, 0
```

```bash
# 클럭 속도 (성능 저하 의심 시)
nvidia-smi --query-gpu=\
index,\
clocks.current.graphics,\
clocks.current.sm,\
clocks.current.memory,\
clocks.max.graphics,\
clocks.max.sm \
  --format=csv,noheader,nounits

# 출력 예시 (정상: 현재 ≈ 최대)
# 0, 1410, 1410, 2000, 1410, 1410
```

```bash
# Throttle 원인 확인 (클럭이 낮을 때)
nvidia-smi --query-gpu=index,clocks_throttle_reasons.active \
  --format=csv,noheader,nounits
```

#### query-compute-apps: 프로세스별 VRAM 사용량

```bash
nvidia-smi --query-compute-apps=\
gpu_uuid,\
pid,\
used_gpu_memory,\
process_name \
  --format=csv,noheader,nounits

# 출력 예시
# GPU-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx, 12345, 8192, python3
```

#### GPU별 반복 처리 스크립트

```bash
#!/bin/bash
# GPU별 지표를 개별 행으로 출력

GPU_COUNT=$(nvidia-smi --query-gpu=index --format=csv,noheader | wc -l)

echo "Timestamp,GPU_Index,Util(%),Mem_Used(MiB),Mem_Total(MiB),Temp(C),Power(W)"

for i in $(seq 0 $((GPU_COUNT - 1))); do
  METRICS=$(nvidia-smi -i "$i" \
    --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw \
    --format=csv,noheader,nounits)
  echo "$(date '+%Y-%m-%dT%H:%M:%S'),$i,$METRICS"
done
```

#### CloudWatch 커스텀 지표 발행 (bash)

```bash
#!/bin/bash
# GPU 지표를 CloudWatch에 발행

INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $(curl -s -X PUT \
  http://169.254.169.254/latest/api/token \
  -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600')" \
  http://169.254.169.254/latest/meta-data/instance-id)
REGION="ap-northeast-2"

GPU_COUNT=$(nvidia-smi --query-gpu=index --format=csv,noheader | wc -l)

for i in $(seq 0 $((GPU_COUNT - 1))); do
  read -r UTIL MEM_USED MEM_TOTAL TEMP POWER <<< $(nvidia-smi -i "$i" \
    --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw \
    --format=csv,noheader,nounits | tr ',' ' ')

  aws cloudwatch put-metric-data \
    --namespace "GPU/Custom" \
    --metric-data \
      "[
        {\"MetricName\":\"gpu_util\",\"Value\":$UTIL,\"Unit\":\"Percent\",\"Dimensions\":[{\"Name\":\"InstanceId\",\"Value\":\"$INSTANCE_ID\"},{\"Name\":\"GpuIndex\",\"Value\":\"$i\"}]},
        {\"MetricName\":\"gpu_mem_used\",\"Value\":$MEM_USED,\"Unit\":\"None\",\"Dimensions\":[{\"Name\":\"InstanceId\",\"Value\":\"$INSTANCE_ID\"},{\"Name\":\"GpuIndex\",\"Value\":\"$i\"}]},
        {\"MetricName\":\"gpu_temperature\",\"Value\":$TEMP,\"Unit\":\"None\",\"Dimensions\":[{\"Name\":\"InstanceId\",\"Value\":\"$INSTANCE_ID\"},{\"Name\":\"GpuIndex\",\"Value\":\"$i\"}]}
      ]" \
    --region "$REGION"
done
```

### 2.3 Best Practice

- `noheader`와 `nounits`는 항상 함께 사용 (단위 문자열이 파싱을 방해함)
- ECC Uncorrected Volatile 값이 0이 아니면 즉시 알람 — 데이터 손상 가능성
- `power.draw`는 소수점 포함 부동소수 반환 → bash 산술 연산 시 `bc` 사용
- 쿼리 필드 목록은 공백 없이 쉼표로 구분 (`utilization.gpu,memory.used`)

---

## 3. 트러블슈팅

### 3.1 주요 이슈

#### 특정 필드가 [N/A]로 출력됨

**증상**
- `nvidia-smi --query-gpu=power.draw --format=csv,noheader` 출력: `[N/A]`

**원인**
- 해당 GPU 모델이 특정 필드를 지원하지 않음 (예: 일부 소비자용 GPU에서 power.draw 미지원)
- AWS GPU 인스턴스에서는 보통 발생하지 않으나, T4 (g4dn) 에서 일부 필드 제한 있음

**해결 방법**
```bash
# 지원 필드 목록 확인
nvidia-smi --help-query-gpu | grep -A2 "power.draw"
```

---

#### query-compute-apps 결과가 비어 있음 (프로세스 실행 중임에도)

**증상**
- GPU가 사용 중임에도 (`utilization.gpu > 0`) `--query-compute-apps` 결과 없음

**원인**
- MIG 모드 활성화 시 GPU 인스턴스 단위로 쿼리해야 함
- 일부 그래픽 워크로드는 Compute Apps가 아닌 Graphics Apps로 분류됨

**해결 방법**
```bash
# Graphics Apps 포함 조회
nvidia-smi --query-accounted-apps=pid,gpu_util,mem_util --format=csv,noheader,nounits

# MIG 환경에서 인스턴스별 조회
nvidia-smi mig -lgip    # GPU 인스턴스 목록
```

---

### 3.2 자주 발생하는 문제 (Q&A)

**Q: `clocks_throttle_reasons.active`가 `Not Active`가 아닌 다른 값을 반환함**
A: 쓰로틀 원인이 활성화됐다는 의미. 주요 원인:
- `HW Slowdown`: 온도 초과 또는 전력 한도 초과
- `SW Power Cap`: 소프트웨어 전력 제한 설정
- `HW Power Brakes`: PSU 전력 제한 신호

온도가 정상이면 `nvidia-smi -q -d POWER`로 전력 한도 확인.

**Q: ECC Aggregate 카운터가 계속 증가함**
A: Volatile은 재부팅 시 초기화, Aggregate는 누적값. Aggregate Uncorrected가 증가하면 해당 GPU 메모리 불량 가능성 — AWS Support에 Xid 에러 로그와 함께 보고 권장.

---

## 4. 모니터링 및 알람

### 핵심 지표

| 지표 | 수집 방법 | 의미 | 임계값 예시 |
|------|----------|------|------------|
| `ecc.errors.uncorrected.volatile.total` | nvidia-smi query | 수정 불가 ECC 에러 | `> 0` 즉시 알람 |
| `utilization.gpu` | nvidia-smi query | GPU 코어 사용률 | `> 95% (10분)` |
| `clocks_throttle_reasons.active` | nvidia-smi query | 쓰로틀 여부 | Not Active 이탈 시 |

### CloudWatch 알람 (ECC Uncorrected 에러)

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "gpu-ecc-uncorrected-error" \
  --alarm-description "GPU ECC Uncorrected 에러 발생" \
  --metric-name "gpu_ecc_uncorrected" \
  --namespace "GPU/Custom" \
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

- 전체 쿼리 가능 필드 목록: `nvidia-smi --help-query-gpu`
- 프로세스 쿼리 가능 필드 목록: `nvidia-smi --help-query-compute-apps`
- cron으로 5분 간격 수집: `*/5 * * * * /opt/scripts/gpu-metrics.sh >> /var/log/gpu-metrics.log 2>&1`

**관련 문서**
- [nvidia-smi Query Fields](https://developer.download.nvidia.com/compute/DCGM/docs/nvidia-smi-367.38.pdf)
- 연관 내부 문서: `docs/02-nvidia-smi/nvidia-smi-basics.md`, `docs/05-monitoring/cw-gpu-metrics.md`
