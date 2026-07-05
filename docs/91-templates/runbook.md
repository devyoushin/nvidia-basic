# Runbook — {작업명}

> **작성일**: {YYYY-MM-DD} | **대상 인스턴스**: {p4d/p5/g5 등} | **예상 소요**: {시간}

---

## 개요

| 항목 | 내용 |
|------|------|
| 목적 | {이 작업을 수행하는 이유} |
| 영향 범위 | {GPU 프로세스 중단 여부, 서비스 다운타임 여부} |
| 롤백 가능 여부 | {가능/불가능 및 이유} |
| 승인 필요 여부 | {예: 프로덕션 변경 시 팀장 승인 필요} |

---

## 사전 체크리스트

- [ ] GPU 프로세스 확인 (`nvidia-smi` Processes 섹션 빈 상태)
- [ ] 현재 드라이버 버전 기록 (`cat /proc/01-driver/nvidia/version`)
- [ ] CloudWatch 알람 억제 (작업 시간대 알람 발생 방지)
- [ ] 스냅샷/AMI 백업 완료 (루트 볼륨)
- [ ] {추가 체크 항목}

---

## 환경 변수

```bash
export INSTANCE_ID="<INSTANCE_ID>"
export REGION="ap-northeast-2"
export DRIVER_VERSION="<TARGET_DRIVER_VERSION>"  # 예: 550.90.12
export SNS_TOPIC_ARN="arn:aws:sns:${REGION}:<ACCOUNT_ID>:<TOPIC_NAME>"
```

---

## 작업 단계

### Step 1. 현재 상태 확인

```bash
# GPU 상태 및 드라이버 버전 확인
nvidia-smi

# 커널 모듈 로드 상태
lsmod | grep nvidia

# DKMS 상태 (드라이버 업그레이드 작업 시)
dkms status
```

**확인 기준**: {어떤 출력이 나오면 다음 단계로 진행하는지}

---

### Step 2. {작업 내용}

```bash
# {명령어 설명}
{명령어}
```

**확인 명령어**:
```bash
{검증 명령어}
```

**예상 출력**:
```
{정상 출력 예시}
```

---

### Step N. 작업 완료 확인

```bash
# GPU 정상 동작 확인
nvidia-smi

# 드라이버 버전 확인
cat /proc/01-driver/nvidia/version

# Xid 에러 없는지 확인
dmesg -T | grep -i "xid\|NVRM" | tail -20
```

---

## 롤백 절차

```bash
# {롤백 방법 설명}
{롤백 명령어}
```

> **주의**: {롤백 시 유의사항}

---

## 모니터링 포인트

작업 완료 후 아래 지표를 최소 **15분간** 감시:

| 지표 | 확인 방법 | 정상 기준 |
|------|---------|---------|
| GPU 사용률 | `nvidia-smi dmon -s u -d 5` | 이전 수준 유지 |
| Xid 에러 | `dmesg -T \| grep NVRM` | 새 에러 없음 |
| CloudWatch GPU 지표 | CW 콘솔 → CWAgent 네임스페이스 | 수집 재개 확인 |

---

## 비고

- {참고 사항}
- 연관 문서: `docs/{category}/{file}.md`
