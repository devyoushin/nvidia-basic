# GPU 리셋 및 MIG 모드 전환

## 1. 개요

`nvidia-smi -r`은 GPU를 소프트웨어적으로 리셋하여 Xid 에러 43(GPU hang), 63(Row Remapping) 등에서 복구하는 명령어.
MIG (Multi-Instance GPU) 모드는 A100, H100 같은 Ampere/Hopper GPU를 여러 독립 인스턴스로 분할하는 기능.
두 작업 모두 GPU 점유 프로세스가 없는 상태에서만 수행 가능하므로, 작업 순서가 중요함.

**핵심 요약**
- **사용 목적**: Xid 에러 복구용 GPU 리셋, 추론 워크로드 격리를 위한 MIG 파티셔닝
- **주요 이점**: 인스턴스 재부팅 없이 GPU 상태 초기화 가능
- **관련 도구**: nvidia-smi, dmesg
- **해당 인스턴스**: GPU 리셋 — 모든 인스턴스 / MIG — p4d(A100), p5(H100)

---

## 2. 설명

### 2.1 GPU 리셋 (nvidia-smi -r)

GPU 리셋은 NVML을 통해 드라이버가 GPU 컨텍스트를 재초기화하는 작업.
ECC 카운터(Volatile), 클럭 상태, 메모리 컨텍스트가 초기화됨.

```bash
# 1. 리셋 전 GPU 상태 확인
nvidia-smi

# 2. GPU 점유 프로세스 확인 (없어야 리셋 가능)
nvidia-smi --query-compute-apps=pid,process_name --format=csv,noheader

# 3. GPU 전체 리셋
sudo nvidia-smi -r

# 4. 특정 GPU만 리셋 (-i 플래그)
sudo nvidia-smi -r -i 0

# 5. 리셋 후 상태 확인
nvidia-smi
dmesg -T | grep "NVRM" | tail -10
```

**리셋 후 확인 항목**

```bash
# ECC Volatile 카운터 초기화 확인 (0으로 리셋되어야 정상)
nvidia-smi --query-gpu=index,ecc.errors.corrected.volatile.total,ecc.errors.uncorrected.volatile.total \
  --format=csv,noheader,nounits

# Row Remapping 완료 확인 (Xid 63 복구 시)
nvidia-smi --query-remapped-rows=gpu_uuid,remapped_rows.pending,remapped_rows.failure \
  --format=csv,noheader
# pending = 0 이면 리매핑 완료
```

> **주의**: GPU 리셋은 하드웨어 결함(Xid 48, 79)을 해결하지 않음. 이 경우 Stop&Start 필요.

### 2.2 프로세스 강제 종료 후 리셋

```bash
# GPU 점유 프로세스 PID 확인
GPU_PIDS=$(nvidia-smi --query-compute-apps=pid --format=csv,noheader | tr -d ' ')

if [ -n "$GPU_PIDS" ]; then
  echo "종료할 프로세스:"
  echo "$GPU_PIDS" | xargs -I{} ps -p {} -o pid,cmd --no-headers

  # SIGTERM 먼저 시도 (정상 종료)
  echo "$GPU_PIDS" | xargs kill -TERM 2>/dev/null
  sleep 5

  # 여전히 실행 중이면 SIGKILL
  REMAINING=$(nvidia-smi --query-compute-apps=pid --format=csv,noheader | tr -d ' ')
  if [ -n "$REMAINING" ]; then
    echo "SIGKILL로 강제 종료: $REMAINING"
    echo "$REMAINING" | xargs kill -KILL 2>/dev/null
    sleep 2
  fi
fi

# 프로세스 없음 확인 후 리셋
sudo nvidia-smi -r
```

### 2.3 MIG 모드 전환

MIG (Multi-Instance GPU)는 A100/H100을 최대 7개의 독립 GPU 인스턴스로 분할하는 기능.
각 MIG 인스턴스는 독립된 SM, 메모리, 캐시를 가짐.

#### MIG 모드 활성화

```bash
# MIG 지원 여부 확인
nvidia-smi --query-gpu=index,name,mig.mode.current --format=csv,noheader

# MIG 모드 활성화 (GPU 0)
sudo nvidia-smi -i 0 -mig 1

# 재부팅 없이 적용됨 (드라이버가 GPU 리셋 수행)
nvidia-smi --query-gpu=index,mig.mode.current --format=csv,noheader
# 출력: 0, Enabled
```

#### MIG 인스턴스 프로파일 목록 확인

```bash
nvidia-smi mig -lgip

# 출력 예시 (A100 80GB)
# +-----------------------------------------------------------------------------+
# | GPU instance profiles:                                                      |
# | GPU   Name             ID    Instances   Memory     P2P    SM    DEC   ENC  |
# |       (MIG)                  Free/Total   GiB              CE    JPEG  OFA  |
# |=============================================================================|
# |   0  MIG 1g.10gb       19     7/7        9.75       No     14    0     0    |
# |   0  MIG 2g.20gb       14     3/3        19.62      No     28    1     0    |
# |   0  MIG 3g.40gb        9     2/2        39.25      No     42    2     0    |
# |   0  MIG 4g.40gb        5     1/1        39.25      No     56    2     0    |
# |   0  MIG 7g.80gb        0     1/1        79.12      No     98    5     0    |
```

#### GPU 인스턴스 생성

```bash
# 7g.80gb 프로파일 1개 생성 (A100 전체 사용)
sudo nvidia-smi mig -cgi 0 -C

# 1g.10gb 프로파일 7개 생성 (최대 분할)
for i in {1..7}; do
  sudo nvidia-smi mig -cgi 19 -C
done

# 생성된 인스턴스 확인
nvidia-smi mig -lgi   # GPU 인스턴스
nvidia-smi mig -lci   # Compute 인스턴스
nvidia-smi -L          # 전체 GPU + MIG 인스턴스 목록
```

#### MIG 인스턴스 삭제 및 모드 해제

```bash
# 모든 Compute 인스턴스 삭제
sudo nvidia-smi mig -dci

# 모든 GPU 인스턴스 삭제
sudo nvidia-smi mig -dgi

# MIG 모드 비활성화
sudo nvidia-smi -i 0 -mig 0
```

### 2.4 Best Practice

- GPU 리셋 전 애플리케이션 담당자에게 사전 공지 — 리셋 시 점유 중인 모든 CUDA 컨텍스트 강제 종료됨
- MIG 활성화/비활성화는 해당 GPU의 모든 작업을 중단시키므로 점검 시간 확보 후 수행
- EKS GPU 노드에서 MIG 사용 시 `nvidia.com/mig-1g.10gb` 같은 MIG 전용 리소스 요청 필요 — `nvidia-container-toolkit` 설정 필요

---

## 3. 트러블슈팅

### 3.1 주요 이슈

#### nvidia-smi -r 실패: "Unable to reset GPU"

**증상**
- `sudo nvidia-smi -r` 실행 시 `Unable to reset the GPU at index 0: In use by another client`

**원인**
- 리셋 시도 시 GPU를 점유 중인 프로세스 존재

**해결 방법**
```bash
# 점유 프로세스 확인 및 종료
nvidia-smi --query-compute-apps=pid,process_name --format=csv,noheader

# 프로세스 종료 후 재시도
kill -9 <PID>
sleep 2
sudo nvidia-smi -r
```

---

#### MIG 모드 활성화 후 nvidia-smi에서 GPU가 사라짐

**증상**
- MIG 활성화 후 `nvidia-smi`의 GPU 목록에 해당 GPU가 표시되지 않음

**원인**
- MIG 모드에서는 GPU 자체가 아닌 MIG 인스턴스 단위로 표시됨

**해결 방법**
```bash
# MIG 모드에서 GPU + 인스턴스 전체 표시
nvidia-smi -L
# 출력 예시:
# GPU 0: NVIDIA A100-SXM4-80GB (UUID: GPU-xxx)
#   MIG 1g.10gb      Device  0: (UUID: MIG-xxx)
#   MIG 1g.10gb      Device  1: (UUID: MIG-xxx)

# MIG 인스턴스 상태 확인
nvidia-smi mig -lgi
```

---

### 3.2 자주 발생하는 문제 (Q&A)

**Q: GPU 리셋 후에도 Xid 에러가 재발하면?**
A: 소프트웨어 리셋으로 해결 안 되는 하드웨어 결함. `docs/troubleshooting/aws-host-replacement.md` 참조하여 Stop&Start 수행.

**Q: MIG 인스턴스에서 nvidia-smi 쿼리 시 GPU UUID 지정 방법은?**
A: `-i` 플래그에 MIG UUID 사용:
```bash
nvidia-smi -i MIG-<UUID> --query-gpu=utilization.gpu --format=csv,noheader
```

---

## 4. 모니터링 및 알람

### 핵심 지표

| 지표 | 수집 방법 | 의미 | 임계값 예시 |
|------|----------|------|------------|
| `remapped_rows.pending` | nvidia-smi query | Row Remapping 대기 행 수 | `> 0` → 리셋 필요 |
| `ecc.errors.uncorrected.volatile.total` | nvidia-smi query | 수정 불가 ECC (리셋 후 0으로 초기화) | `> 0` 즉시 알람 |

### CloudWatch 알람

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "gpu-row-remapping-pending" \
  --alarm-description "GPU Row Remapping 대기 — nvidia-smi -r 필요" \
  --metric-name "gpu_row_remapping_pending" \
  --namespace "GPU/Custom" \
  --dimensions Name=InstanceId,Value=<INSTANCE_ID> \
  --statistic Maximum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --alarm-actions "arn:aws:sns:ap-northeast-2:<ACCOUNT_ID>:<SNS_TOPIC>" \
  --region ap-northeast-2
```

---

## 5. TIP

- Xid 63 (Row Remapping) 발생 후 리셋 전 `--query-remapped-rows` 출력을 저장해두면 사후 분석에 유용
- `nvidia-smi drain` 명령으로 특정 GPU를 신규 작업 배정에서 제외 가능 (Kubernetes GPU 노드에서 유용)
- MIG 프로파일 선택 기준: 동시 실행 job 수 > 분할 수, 각 job의 VRAM 요구량 ≤ 프로파일 메모리

**관련 문서**
- [NVIDIA MIG User Guide](https://docs.nvidia.com/datacenter/tesla/mig-user-guide/)
- 연관 내부 문서: `docs/troubleshooting/xid-error-codes.md`, `docs/troubleshooting/aws-host-replacement.md`
