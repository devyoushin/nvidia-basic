# AWS 물리 호스트 교체 절차 (Stop&Start)

## 1. 개요

AWS EC2 GPU 인스턴스에서 하드웨어 결함(Xid 48, Xid 79 등)이 발생하면 물리 호스트 교체가 필요함.
Reboot(재부팅)은 동일 물리 호스트에서 OS만 재시작되므로 하드웨어 문제 해결 불가 — **반드시 Stop&Start** 사용.
Stop&Start 시 인스턴스는 새로운 물리 호스트에 배치되며, 인스턴스 스토어(NVMe SSD) 데이터는 소실됨.

**핵심 요약**
- **사용 목적**: GPU 하드웨어 결함 해소, AWS Scheduled Event 대응
- **주요 이점**: EIP/ENI/EBS는 Stop&Start 후에도 유지됨
- **관련 도구**: AWS CLI, EC2 콘솔, nvidia-smi, dmesg
- **해당 인스턴스**: 모든 GPU 인스턴스 (p3, p4d, p5, g4dn, g5 등)

---

## 2. 설명

### 2.1 핵심 개념

```
[Stop 수행]
  EC2 인스턴스 → Stopping → Stopped
  (물리 호스트 A에서 분리)
        |
[Start 수행]
  EC2 인스턴스 → Pending → Running
  (물리 호스트 B에 새로 배치)
```

| 항목 | Stop&Start 후 유지 여부 |
|------|----------------------|
| EBS 루트 볼륨 | ✅ 유지 |
| EBS 데이터 볼륨 | ✅ 유지 (자동 재연결) |
| ENI (프라이빗 IP) | ✅ 유지 |
| EIP (탄력적 IP) | ✅ 유지 (연결된 경우) |
| 인스턴스 스토어 | ❌ **초기화됨** |
| 퍼블릭 IP (EIP 아닌 경우) | ❌ 변경됨 |
| 인스턴스 ID | ✅ 유지 |

> **주의**: p4d, p5, g5 같은 NVMe 인스턴스 스토어 탑재 인스턴스는 Stop 시 스토어 데이터 소실. 모델 가중치 등 중요 데이터는 EBS에 저장 필요.

### 2.2 Stop&Start 수행 절차

#### 사전 준비

```bash
export INSTANCE_ID="<INSTANCE_ID>"
export REGION="ap-northeast-2"

# 1. 현재 Xid 에러 및 드라이버 상태 기록
nvidia-smi -q > /tmp/nvidia-smi-before.txt
dmesg -T | grep NVRM > /tmp/dmesg-before.txt

# 2. GPU 사용 프로세스 종료 여부 확인 (학습/추론 작업 중지 필요)
nvidia-smi --query-compute-apps=pid,process_name --format=csv,noheader

# 3. 인스턴스 스토어 데이터 백업 (있는 경우 — 필요시)
# df -h | grep nvme    # 인스턴스 스토어 마운트 위치 확인
# rsync -av /mnt/instance-store/ s3://<BUCKET>/backup/
```

#### Stop 수행

```bash
# 인스턴스 중지
aws ec2 stop-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION"

# Stopped 상태까지 대기
aws ec2 wait instance-stopped \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION"

echo "인스턴스가 완전히 중지됐습니다. 물리 호스트에서 분리됩니다."
```

#### Start 수행

```bash
# 인스턴스 시작 (새 물리 호스트에 배치)
aws ec2 start-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION"

# Running 상태까지 대기
aws ec2 wait instance-running \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION"

echo "인스턴스가 새 물리 호스트에서 시작됐습니다."
```

#### 사후 확인

```bash
# GPU 정상 동작 확인
nvidia-smi

# Xid 에러 없는지 확인
dmesg -T | grep "NVRM: Xid"

# 이전 에러와 비교 (새 Xid 없어야 정상)
diff /tmp/dmesg-before.txt <(dmesg -T | grep NVRM)

# ECC 에러 카운터 초기화 확인 (Stop&Start 후 Volatile 카운터 리셋됨)
nvidia-smi --query-gpu=index,ecc.errors.uncorrected.volatile.total \
  --format=csv,noheader,nounits
```

### 2.3 AWS Scheduled Event 대응

AWS가 인스턴스에 하드웨어 점검 예정을 통보하는 경우 Scheduled Event 발생.

```bash
# Scheduled Event 확인
aws ec2 describe-instance-status \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query 'InstanceStatuses[*].Events'

# 출력 예시 (이벤트 있을 때)
# [
#   {
#     "Code": "instance-stop",
#     "Description": "The instance is running on degraded hardware",
#     "NotBefore": "2026-04-25T00:00:00.000Z",
#     "NotAfter": "2026-05-02T00:00:00.000Z"
#   }
# ]
```

`instance-stop` 이벤트는 `NotBefore` 시점 전에 사용자가 직접 Stop&Start 수행하면 AWS 강제 중지 방지 가능.

### 2.4 Best Practice

- p4d/p5처럼 Multi-GPU 인스턴스에서 일부 GPU만 Xid 발생해도 **전체 인스턴스** Stop&Start 필요
- ASG(Auto Scaling Group) 내 인스턴스면 직접 Stop&Start 전에 Standby 상태로 전환 권장
- Stop&Start 후 새 물리 호스트의 물리 호스트 ID 확인으로 교체 여부 검증 가능

```bash
# 물리 호스트 ID 확인 (교체 전후 비교)
aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query 'Reservations[*].Instances[*].Placement.HostId'
# (전용 호스트가 아닌 경우 null 반환 — 일반 인스턴스는 호스트 ID 미제공)

# 대안: 인스턴스 메타데이터로 물리 호스트 변경 간접 확인
# (퍼블릭 IP 변경 여부, 새 호스트에서 dmesg Xid 없음 확인)
```

---

## 3. 트러블슈팅

### 3.1 주요 이슈

#### Stop&Start 후에도 동일 Xid 재발

**증상**
- Stop&Start 완료 후 1~24시간 내 동일 Xid 코드 재발생
- `dmesg -T | grep "NVRM: Xid"` 에 동일 코드 등장

**원인**
- 새 물리 호스트에도 동일 계열 하드웨어 결함 가능성 (낮음)
- 애플리케이션 코드 또는 워크로드 자체의 문제 (Xid 13, 31의 경우)
- 드라이버 버전 버그

**해결 방법**
```bash
# Xid 코드 재확인 — 새 코드인지 기존 코드인지 구분
dmesg -T | grep "NVRM: Xid" | awk '{print $NF}' | sort -u

# 애플리케이션 문제 의심 시 (Xid 13, 31)
CUDA_LAUNCH_BLOCKING=1 python3 your_script.py

# 드라이버 문제 의심 시
cat /proc/01-driver/nvidia/version
# → Production Branch 최신 버전으로 업그레이드 검토
```

→ Stop&Start 후 재발 시: AWS Support Case 오픈 (Instance ID + Xid 로그 첨부)

---

#### ASG 내 인스턴스 Stop&Start 후 교체됨

**증상**
- ASG 정책에 의해 Stop&Start 수행한 인스턴스가 Terminated 처리되고 새 인스턴스 생성됨

**원인**
- ASG의 Health Check가 Stop 상태를 Unhealthy로 판단

**해결 방법**
```bash
# Stop 전에 ASG Standby 상태로 전환
aws autoscaling enter-standby \
  --instance-ids "$INSTANCE_ID" \
  --auto-scaling-group-name "<ASG_NAME>" \
  --should-decrement-desired-capacity \
  --region "$REGION"

# Stop&Start 수행
aws ec2 stop-instances --instance-ids "$INSTANCE_ID" --region "$REGION"
aws ec2 wait instance-stopped --instance-ids "$INSTANCE_ID" --region "$REGION"
aws ec2 start-instances --instance-ids "$INSTANCE_ID" --region "$REGION"
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"

# GPU 확인 후 Standby 해제
nvidia-smi  # 정상 확인 후
aws autoscaling exit-standby \
  --instance-ids "$INSTANCE_ID" \
  --auto-scaling-group-name "<ASG_NAME>" \
  --region "$REGION"
```

---

### 3.2 자주 발생하는 문제 (Q&A)

**Q: Stop 후 EBS 볼륨이 재연결되지 않음**
A: EBS 볼륨의 `DeleteOnTermination` 속성이 True이거나, 볼륨이 `available` 상태로 분리된 경우. `aws ec2 describe-volumes --volume-ids <VOL_ID>`로 상태 확인 후 필요 시 수동 attach.

**Q: Placement Group (Cluster)에 속한 인스턴스도 Stop&Start 가능한가?**
A: 가능하나, Stop 시 용량 확보가 보장되지 않아 Start 시 동일 Cluster Placement Group에 다시 배치가 실패할 수 있음. p5 인스턴스처럼 용량 예약과 함께 사용하는 경우 용량 예약 확인 후 진행.

---

## 4. 모니터링 및 알람

### 핵심 지표

| 지표 | 수집 방법 | 의미 | 임계값 예시 |
|------|----------|------|------------|
| EC2 StatusCheckFailed_System | CloudWatch 기본 | 물리 호스트 문제 감지 | `>= 1` |
| EC2 StatusCheckFailed_Instance | CloudWatch 기본 | OS/드라이버 문제 감지 | `>= 1` |

### CloudWatch 알람 (시스템 상태 체크 실패)

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "ec2-system-status-check-failed" \
  --alarm-description "EC2 시스템 상태 체크 실패 — GPU 물리 호스트 문제 가능성" \
  --metric-name "StatusCheckFailed_System" \
  --namespace "AWS/EC2" \
  --dimensions Name=InstanceId,Value=<INSTANCE_ID> \
  --statistic Maximum \
  --period 60 \
  --evaluation-periods 2 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --alarm-actions "arn:aws:sns:ap-northeast-2:<ACCOUNT_ID>:<SNS_TOPIC>" \
  --region ap-northeast-2
```

---

## 5. TIP

- EIP 사용 시 Stop&Start 후 별도 재연결 불필요 — EIP는 자동으로 재연결됨
- Placement Group 없는 일반 인스턴스는 Stop&Start 후 다른 AZ 배치 가능 → Target Group 등록 IP 변경 없는지 확인 (프라이빗 IP는 동일 서브넷 내 유지)
- 야간 PM 작업 형태로 정기 Stop&Start를 스케줄링하면 하드웨어 누적 오류를 예방적으로 해소 가능

**관련 문서**
- [AWS EC2 인스턴스 중지 및 시작](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Stop_Start.html)
- [AWS EC2 Scheduled Events](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/monitoring-instances-status-check_sched.html)
- 연관 내부 문서: `docs/06-troubleshooting/xid-error-codes.md`, `docs/02-nvidia-smi/nvidia-smi-gpu-reset.md`
