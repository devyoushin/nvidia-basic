# {기술명} — {주제명}

> **파일명 규칙**: `{카테고리}-{주제}.md` | **카테고리**: `docs/{카테고리}/`

---

## 1. 개요

{이 기술/기능이 무엇인지 1~3문장 설명}
{왜 알아야 하는지 — GPU 운영 상 의미, 장애 사례 연관성}

**핵심 요약**
- **사용 목적**: {언제 사용하는가}
- **주요 이점**: {왜 쓰는가}
- **관련 도구**: {함께 사용되는 도구 — nvidia-smi, DCGM, CloudWatch 등}
- **해당 인스턴스**: {p4d, p5, g5 등 적용 대상 인스턴스 패밀리}

---

## 2. 설명

### 2.1 핵심 개념

{동작 원리, 주요 차이점, 구성 다이어그램 (ASCII)}

```
[컴포넌트 A] --> [컴포넌트 B] --> [컴포넌트 C]
```

| 항목 | 설명 |
|------|------|
| {개념 1} | {설명} |
| {개념 2} | {설명} |

### 2.2 실무 적용 명령어

#### 기본 확인

```bash
# {동작 설명}
nvidia-smi {options}
```

#### 구조화 쿼리

```bash
nvidia-smi --query-gpu=<FIELDS> \
  --format=csv,noheader,nounits
```

#### 자동화 스크립트

```bash
#!/bin/bash
# {스크립트 목적}

GPU_COUNT=$(nvidia-smi --query-gpu=index --format=csv,noheader | wc -l)

for i in $(seq 0 $((GPU_COUNT - 1))); do
  # GPU별 처리
  nvidia-smi -i "$i" --query-gpu=<FIELDS> --format=csv,noheader,nounits
done
```

### 2.3 Best Practice

- {실무 팁 1}
- {실무 팁 2}
- {주의사항}

---

## 3. 트러블슈팅

### 3.1 주요 이슈

#### {이슈명}

**증상**
- {증상 설명}
- 오류 메시지: `{에러 텍스트}`
- `dmesg -T | grep NVRM` 출력: `{출력 예시}`

**원인**
- {근본 원인}

**해결 방법**
```bash
# 진단
nvidia-smi -q | grep -i error

# 해결
{해결 명령어}
```

> **예방책**: {재발 방지 방법}

---

### 3.2 자주 발생하는 문제 (Q&A)

**Q: {질문}**
A: {답변}

**Q: {질문}**
A: {답변}

---

## 4. 모니터링 및 알람

### 핵심 지표

| 지표 | 수집 방법 | 의미 | 임계값 예시 |
|------|----------|------|------------|
| `gpu_util` | nvidia-smi / DCGM | GPU 코어 사용률 | `> 95% (5분 지속)` |
| `gpu_temperature` | nvidia-smi / DCGM | GPU 온도 | `> 85°C` |
| `{MetricName}` | {수집 방법} | {설명} | `{임계값}` |

### CloudWatch 알람 설정

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "gpu-{condition}-alarm" \
  --alarm-description "{설명}" \
  --metric-name "{MetricName}" \
  --namespace "CWAgent" \
  --dimensions Name=InstanceId,Value=<INSTANCE_ID> \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold {value} \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions "arn:aws:sns:ap-northeast-2:<ACCOUNT_ID>:<SNS_TOPIC>" \
  --region ap-northeast-2
```

---

## 5. TIP

- {현장 유용 팁 1}
- {현장 유용 팁 2}

**관련 문서**
- [NVIDIA 공식 문서]({URL})
- 연관 내부 문서: `docs/{category}/{related-file}.md`
