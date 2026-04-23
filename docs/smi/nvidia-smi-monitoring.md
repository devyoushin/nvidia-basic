# nvidia-smi dmon/pmon 루프 모니터링

## 1. 개요

`nvidia-smi dmon`과 `pmon`은 GPU 지표를 일정 간격으로 반복 출력하는 모니터링 서브커맨드.
`watch -n 1 nvidia-smi`보다 가볍고 CSV 리디렉션이 가능하여 로그 수집 자동화에 적합.
단기 부하 테스트, 학습 중 실시간 확인, 로그 파일 기반 사후 분석에 주로 활용됨.

**핵심 요약**
- **사용 목적**: GPU 지표 실시간 루프 출력, 파일 리디렉션 기반 로그 수집
- **주요 이점**: 경량 데몬, 별도 설치 불필요, `dmon`은 GPU 단위 / `pmon`은 프로세스 단위 출력
- **관련 도구**: nvidia-smi, cron, CloudWatch Agent
- **해당 인스턴스**: 모든 NVIDIA GPU 인스턴스

---

## 2. 설명

### 2.1 핵심 개념

| 서브커맨드 | 단위 | 주요 용도 |
|-----------|------|---------|
| `dmon` | GPU 단위 | 사용률, 메모리, 온도, 전력 등 하드웨어 지표 |
| `pmon` | 프로세스 단위 | GPU를 점유 중인 프로세스별 사용률, VRAM |

### 2.2 실무 적용 명령어

#### dmon — GPU 단위 모니터링

```bash
# 5초 간격, 사용률(u) + 메모리(m) + 전력(p) + 온도(t) 출력
nvidia-smi dmon -s umpt -d 5

# 출력 예시
# # gpu   pwr  gtemp  mtemp    sm   mem   enc   dec   jpg   ofa
# # Idx     W      C      C     %     %     %     %     %     %
#     0    15     28      -     0     0     0     0     0     0
#     0    18     29      -    42    35     0     0     0     0
```

**-s 플래그 옵션**

| 플래그 | 수집 지표 |
|--------|---------|
| `u` | 사용률 (SM, 메모리 대역폭, 인코더, 디코더) |
| `m` | Frame Buffer 메모리 (used/free) |
| `p` | 전력 소비 |
| `t` | 온도 |
| `c` | SM 클럭, 메모리 클럭 |
| `e` | ECC 에러 (single-bit, double-bit) |
| `v` | P-State, Throttle Reason |

```bash
# 특정 GPU만 모니터링 (-i)
nvidia-smi dmon -i 0,1 -s umt -d 3

# 횟수 제한 (-c): 100회 수집 후 종료
nvidia-smi dmon -s u -d 5 -c 100

# 파일로 저장 (타임스탬프 없음 — 별도 추가 필요)
nvidia-smi dmon -s umpt -d 10 >> /var/log/gpu-dmon.log
```

#### 타임스탬프 포함 dmon 로그 수집

```bash
#!/bin/bash
# /opt/scripts/gpu-dmon-log.sh
# dmon 출력에 타임스탬프를 추가하여 로그 저장

LOG_FILE="/var/log/gpu-dmon-$(date +%Y%m%d).log"
INTERVAL=10  # 초

while true; do
  TIMESTAMP=$(date '+%Y-%m-%dT%H:%M:%S')
  nvidia-smi --query-gpu=index,utilization.gpu,utilization.memory,memory.used,temperature.gpu,power.draw \
    --format=csv,noheader,nounits | while IFS=',' read -r idx util mem_util mem_used temp power; do
    echo "${TIMESTAMP},${idx},${util},${mem_util},${mem_used},${temp},${power}"
  done >> "$LOG_FILE"
  sleep "$INTERVAL"
done
```

```bash
# 서비스로 등록 (systemd)
cat > /etc/systemd/system/gpu-dmon-log.service <<'EOF'
[Unit]
Description=GPU dmon logging
After=nvidia-persistenced.service

[Service]
Type=simple
ExecStart=/opt/scripts/gpu-dmon-log.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable gpu-dmon-log
sudo systemctl start gpu-dmon-log
```

#### pmon — 프로세스 단위 모니터링

```bash
# 5초 간격, 프로세스별 GPU 사용률 출력
nvidia-smi pmon -d 5

# 출력 예시
# # gpu        pid  type    sm   mem   enc   dec   jpg   ofa        command
# # Idx          #   C/G     %     %     %     %     %     %        name
#     0      12345    C    42    35     0     0     0     0        python3
#     0      12346    C     8     5     0     0     0     0        python3
```

```bash
# 특정 GPU + 횟수 제한
nvidia-smi pmon -i 0 -d 3 -c 20
```

### 2.3 로그 분석

```bash
# 로그에서 GPU 사용률 평균 계산 (GPU 0, awk)
awk -F',' 'NR>1 && $2==0 {sum+=$3; cnt++} END {printf "GPU 0 평균 사용률: %.1f%%\n", sum/cnt}' \
  /var/log/gpu-dmon-$(date +%Y%m%d).log

# 온도 최대값 확인
awk -F',' 'NR>1 {if($6>max) max=$6} END {print "최대 온도:", max"°C"}' \
  /var/log/gpu-dmon-$(date +%Y%m%d).log

# 특정 시간대 필터링 (14:00~15:00)
awk -F'[,T]' '$2>="14:00:00" && $2<="15:00:00"' \
  /var/log/gpu-dmon-$(date +%Y%m%d).log
```

### 2.4 Best Practice

- `dmon`은 CSV 로그에, CloudWatch 발행은 `scripts/gpu-metrics-to-cw.sh` 별도 운영 — 역할 분리
- 일별 로그 파일 분리 (`$(date +%Y%m%d)`) + logrotate 설정으로 디스크 관리
- 학습 시작/종료 시점을 로그에 마커로 삽입하면 사후 분석 용이

---

## 3. 트러블슈팅

### 3.1 주요 이슈

#### dmon 출력에서 특정 컬럼이 `-` 로 표시

**증상**
- `mtemp` (메모리 온도) 컬럼이 `-` 출력

**원인**
- 해당 GPU 모델이 메모리 온도 센서를 지원하지 않음 (T4, A10G 등 일부 모델)

**해결 방법**
- `-` 출력은 정상. 지원 센서 목록은 `nvidia-smi -q -d TEMPERATURE`로 확인:
```bash
nvidia-smi -q -d TEMPERATURE | grep -i temp
```

---

#### dmon 프로세스가 갑자기 종료됨

**증상**
- 백그라운드로 실행한 dmon 스크립트가 종료됨
- `systemctl status gpu-dmon-log` → `failed`

**원인**
- nvidia 드라이버 재시작 또는 GPU 리셋 시 NVML 연결 끊김
- `/var/log` 파티션 디스크 가득 참

**해결 방법**
```bash
# 디스크 사용량 확인
df -h /var/log

# systemd Restart=always 로 자동 재시작 설정 (위 서비스 파일 참조)
# 로그 로테이션 설정
cat > /etc/logrotate.d/gpu-dmon <<'EOF'
/var/log/gpu-dmon-*.log {
    daily
    rotate 30
    compress
    missingok
    notifempty
}
EOF
```

---

### 3.2 자주 발생하는 문제 (Q&A)

**Q: `dmon`과 `--query-gpu` 루프 중 어느 것이 더 적합한가?**
A: 실시간 터미널 확인은 `dmon`, 스크립트 파싱/CloudWatch 발행은 `--query-gpu`가 적합. `dmon`은 출력 형식이 드라이버 버전에 따라 컬럼이 추가될 수 있어 파싱이 불안정.

**Q: 여러 GPU에서 dmon을 동시에 수집하면 출력이 섞이는가?**
A: `dmon`은 GPU 인덱스를 첫 번째 컬럼으로 출력하므로 구분 가능. 단일 `dmon` 실행으로 모든 GPU 동시 수집됨.

---

## 4. 모니터링 및 알람

### 핵심 지표

| 지표 | 수집 방법 | 의미 | 임계값 예시 |
|------|----------|------|------------|
| `utilization.gpu` | dmon / query | GPU 코어 사용률 | `> 95% (지속)` |
| `memory.used` | dmon / query | VRAM 사용량 | `> 90% of total` |

### CloudWatch 알람

```bash
# GPU 사용률 지속 포화 알람
aws cloudwatch put-metric-alarm \
  --alarm-name "gpu-util-saturated" \
  --metric-name "gpu_util" \
  --namespace "GPU/Custom" \
  --dimensions Name=InstanceId,Value=<INSTANCE_ID> \
  --statistic Average \
  --period 300 \
  --evaluation-periods 3 \
  --threshold 95 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions "arn:aws:sns:ap-northeast-2:<ACCOUNT_ID>:<SNS_TOPIC>" \
  --region ap-northeast-2
```

---

## 5. TIP

- 학습 job 시작 시 타임스탬프 마커 삽입: `echo "$(date '+%Y-%m-%dT%H:%M:%S'),JOB_START,-,-,-,-,-" >> /var/log/gpu-dmon-$(date +%Y%m%d).log`
- `dmon -s e` 로 ECC 에러를 실시간으로 감시하다가 값이 오르면 즉시 학습 중단 판단에 활용 가능

**관련 문서**
- 연관 내부 문서: `docs/smi/nvidia-smi-query.md`, `docs/monitoring/cw-gpu-metrics.md`
