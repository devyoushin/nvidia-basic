# Xid 에러 코드 분류 및 대응

## 1. 개요

Xid (eXtended IDentifier) 에러는 NVIDIA 드라이버가 커널 로그(`dmesg`)에 기록하는 GPU 하드웨어/소프트웨어 이벤트 코드.
에러 코드별로 원인(하드웨어 불량, 애플리케이션 오류, 메모리 오류 등)이 다르므로 코드를 정확히 파악해야 적절한 조치 가능.
AWS GPU 인스턴스에서는 특정 Xid 코드가 물리 호스트 교체(Stop&Start)의 트리거가 됨.

**핵심 요약**
- **사용 목적**: GPU 이상 현상의 근본 원인 분류, AWS 호스트 교체 vs. 애플리케이션 재시작 판단
- **주요 이점**: 코드만 알면 조치 방향 즉시 결정 가능
- **관련 도구**: dmesg, nvidia-smi, CloudWatch Logs, DCGM
- **해당 인스턴스**: 모든 NVIDIA GPU 인스턴스 (p3, p4d, p5, g4dn, g5 등)

---

## 2. 설명

### 2.1 Xid 에러 확인 방법

```bash
# 실시간 확인
dmesg -T | grep "NVRM: Xid"

# 최근 1시간 이내 로그
journalctl -k --since "1 hour ago" | grep -i "xid\|NVRM"

# DCGM으로 확인 (DCGM 설치 시)
dcgmi dmon -e 230   # DCGM_FI_DEV_XID_ERRORS 필드
```

**dmesg 출력 예시**:
```
[Thu Apr 23 14:23:11 2026] NVRM: Xid (PCI:0000:00:1e.0): 48, pid='<unknown>', name=<unknown>, Ch 00000008
[Thu Apr 23 14:23:11 2026] NVRM: Xid (PCI:0000:00:1e.0): 63, pid=12345, name=python3, Row Remapping: bank=3, row=15
```

### 2.2 Xid 에러 코드 분류표

#### AWS 운영 관점에서 중요한 코드

| Xid | 이름 | 설명 | AWS 권고 조치 |
|-----|------|------|--------------|
| **13** | Graphics Engine Exception | 애플리케이션의 잘못된 명령어 또는 메모리 접근 | `CUDA_LAUNCH_BLOCKING=1`로 재실행하여 드라이버/앱 문제 판별 |
| **31** | GPU memory page fault | 잘못된 메모리 주소 접근 | `CUDA_LAUNCH_BLOCKING=1`로 재실행, 애플리케이션 코드 확인 |
| **32** | Invalid or corrupted push buffer stream | PCIe 데이터 전송 오류 | 재시작 후 재발 시 Stop&Start |
| **43** | GPU stopped processing | GPU가 응답 없음 (hang) | `nvidia-smi -r`로 GPU 리셋 시도, 실패 시 Stop&Start |
| **45** | Preemptive cleanup | 드라이버가 강제로 프로세스 정리 | 프로세스 비정상 종료 여부 확인, 재발 시 드라이버 업그레이드 검토 |
| **48** | Double Bit ECC Error | 하드웨어 메모리 2비트 오류 (수정 불가) | **즉시 Stop&Start** → AWS Support 연락 |
| **61** | Internal micro-controller breakpoint/exception | 드라이버 내부 오류 | 드라이버 재설치, 재발 시 Stop&Start |
| **63** | GPU Row Remapping Event | Ampere 이상 아키텍처 — 메모리 행 리매핑 대기 | GPU 프로세스 종료 후 `nvidia-smi -r`, 리매핑 완료 확인 |
| **74** | GPU NVLink Error | NVLink 패브릭 오류 | `nvidia-smi nvlink -e`로 링크 확인, Stop&Start |
| **79** | GPU has fallen off the bus | GPU가 PCIe 버스에서 완전히 분리됨 | **즉시 Stop&Start** (물리 호스트 교체 필요) |
| **92** | High single-bit ECC error rate | 단일 비트 ECC 오류 누적 (비율 높음) | 재부팅 후 ECC 카운터 초기화, 재발 시 AWS Support |
| **119** | GSP RPC timeout | GPU System Processor RPC 타임아웃 | `nvidia-smi -r` 시도, 실패 시 Stop&Start |

#### Xid 심각도 분류

```
[즉시 Stop&Start 필요]
  Xid 48 — Double Bit ECC (하드웨어 불량)
  Xid 79 — GPU fell off the bus (PCIe 분리)

[GPU 리셋 시도 → 재발 시 Stop&Start]
  Xid 43 — GPU hang
  Xid 63 — Row Remapping (Ampere)
  Xid 74 — NVLink Error
  Xid 119 — GSP RPC timeout

[애플리케이션 레벨 오류]
  Xid 13 — Graphics Engine Exception
  Xid 31 — GPU memory page fault
  Xid 45 — Preemptive cleanup
```

### 2.3 조치별 명령어

#### GPU 리셋 (Xid 43, 63)

```bash
# GPU 사용 프로세스 모두 종료 확인
nvidia-smi --query-compute-apps=pid --format=csv,noheader

# GPU 리셋 (특정 GPU)
sudo nvidia-smi -r -i 0

# 리셋 후 상태 확인
nvidia-smi
dmesg -T | grep "NVRM" | tail -10
```

#### Row Remapping 완료 확인 (Xid 63, Ampere 전용)

```bash
# 리매핑 대기 행 수 확인
nvidia-smi --query-remapped-rows=gpu_uuid,remapped_rows.pending,remapped_rows.failure \
  --format=csv,noheader

# 정상: remapped_rows.pending = 0
# GPU 리셋 후 pending이 0이 되면 완료
```

#### NVLink 오류 확인 (Xid 74, p4d/p5 전용)

```bash
# NVLink 상태 요약
nvidia-smi nvlink -s

# NVLink 오류 카운터 (오류 링크 식별)
nvidia-smi nvlink -e

# 출력 예시 (오류 있을 때)
# Link 0: <OK>
# Link 1: <ERROR> Replay errors: 5
```

#### AWS 인스턴스 Stop&Start

```bash
# AWS CLI로 인스턴스 중지 (물리 호스트 교체됨)
aws ec2 stop-instances --instance-ids <INSTANCE_ID> --region ap-northeast-2

# 완전히 중지될 때까지 대기
aws ec2 wait instance-stopped --instance-ids <INSTANCE_ID> --region ap-northeast-2

# 인스턴스 시작
aws ec2 start-instances --instance-ids <INSTANCE_ID> --region ap-northeast-2

# 시작 완료 대기
aws ec2 wait instance-running --instance-ids <INSTANCE_ID> --region ap-northeast-2
```

> **주의**: Reboot(재부팅)은 동일 물리 호스트에서 재시작됨 — 하드웨어 교체 효과 없음. 반드시 **Stop&Start** 사용.

---

## 3. 트러블슈팅

### 3.1 주요 이슈

#### 동일 Xid가 반복 발생

**증상**
- 24시간 내 동일 Xid 코드가 3회 이상 발생
- `nvidia-smi -r` 후 일시적으로 해소됐다가 재발

**원인**
- GPU 하드웨어 점진적 열화
- 특정 워크로드에서의 메모리 패턴이 하드웨어 취약점 노출

**해결 방법**
```bash
# 반복 횟수 확인
dmesg -T | grep "NVRM: Xid" | awk '{print $NF}' | sort | uniq -c | sort -rn

# Stop&Start 수행 후 재발 여부 모니터링
# 재발 시 AWS Support에 아래 정보와 함께 케이스 오픈:
# - Instance ID
# - Xid 에러 코드 및 타임스탬프
# - nvidia-smi -q 전체 출력
```

---

#### Xid 에러가 없는데 GPU 성능 저하

**증상**
- `dmesg`에 Xid 없음
- `nvidia-smi` 온도/전력 정상
- 하지만 학습 처리량(throughput)이 이전 대비 30%+ 감소

**원인**
- 클럭 쓰로틀링 (Throttle Reason 확인 필요)
- SM 클럭이 최대값 미달

**해결 방법**
```bash
# 쓰로틀 원인 확인
nvidia-smi --query-gpu=index,clocks_throttle_reasons.active,clocks.current.sm,clocks.max.sm \
  --format=csv,noheader,nounits

# 현재 클럭이 최대 클럭과 크게 차이나면 쓰로틀 중
# HW Thermal 쓰로틀 시: 냉각 확인 (인스턴스 타입 변경 검토)
# SW Power Cap 쓰로틀 시: power limit 설정 확인
nvidia-smi -q -d POWER
```

---

### 3.2 자주 발생하는 문제 (Q&A)

**Q: Xid 에러 발생 시 항상 Stop&Start 해야 하는가?**
A: 아님. Xid 13, 31, 45처럼 애플리케이션 레벨 오류는 애플리케이션 재실행으로 해결. Xid 48, 79처럼 하드웨어 문제가 명확한 경우에만 Stop&Start 필요. Xid 코드 분류표의 심각도를 기준으로 판단.

**Q: `dmesg -T`에서 `NVRM: Xid`가 아닌 `NVRM: GPU-*`로 시작하는 로그는?**
A: 드라이버 일반 정보 로그 또는 GPU 초기화 메시지. 에러가 아닌 경우 많음. 핵심은 `Xid` 키워드가 포함된 라인.

**Q: p5 인스턴스에서 Xid 74 발생 시 NVSwitch 교체가 필요한가?**
A: NVSwitch는 물리 호스트에 포함된 하드웨어. Stop&Start로 물리 호스트가 교체되므로 사용자가 직접 교체 불필요. Stop&Start 후 재발 시 AWS Support에 Xid 로그와 함께 케이스 오픈.

---

## 4. 모니터링 및 알람

### 핵심 지표

| 지표 | 수집 방법 | 의미 | 임계값 예시 |
|------|----------|------|------------|
| `gpu_xid_errors` | DCGM 필드 230 | Xid 에러 누적 횟수 | `>= 1` 즉시 알람 |
| `ecc.errors.uncorrected.volatile.total` | nvidia-smi query | 수정 불가 ECC 에러 | `>= 1` 즉시 알람 |

### CloudWatch 알람 (Xid 에러 발생 시 — DCGM 연동)

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "gpu-xid-error-detected" \
  --alarm-description "GPU Xid 에러 발생 — 즉시 확인 필요" \
  --metric-name "DCGM_FI_DEV_XID_ERRORS" \
  --namespace "DCGM" \
  --dimensions Name=InstanceId,Value=<INSTANCE_ID> \
  --statistic Maximum \
  --period 60 \
  --evaluation-periods 1 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --treat-missing-data notBreaching \
  --alarm-actions "arn:aws:sns:ap-northeast-2:<ACCOUNT_ID>:<SNS_TOPIC>" \
  --region ap-northeast-2
```

---

## 5. TIP

- `dmesg -T | grep "NVRM: Xid" | awk '{print $NF}' | sort | uniq -c` 로 코드별 발생 빈도 빠르게 파악
- GPU 인스턴스 시작 직후 `dmesg -T | grep NVRM` 한 번 확인하는 습관 — 이전 호스트의 잔존 에러 여부 확인
- CloudWatch Logs Insights 쿼리로 EC2 시스템 로그에서 Xid 이력 검색 가능 (CloudWatch Agent syslog 수집 시)
- AWS EC2 Scheduled Events (`aws ec2 describe-instance-status`)에서 `instance-stop` 이벤트 발생 전 Xid 패턴 확인

**관련 문서**
- [NVIDIA Xid Errors](https://docs.nvidia.com/deploy/xid-errors/index.html)
- [AWS GPU Telemetry](https://aws.amazon.com/ko/blogs/compute/capturing-gpu-telemetry-on-the-amazon-ec2-accelerated-computing-instances/)
- 연관 내부 문서: `docs/troubleshooting/aws-host-replacement.md`, `docs/smi/nvidia-smi-gpu-reset.md`
