# CloudWatch GPU 지표 수집

## 1. 개요

AWS EC2 기본 CloudWatch 지표에는 GPU 정보가 포함되지 않으므로 커스텀 지표로 수집해야 함.
CloudWatch Agent + NVIDIA DCGM 조합이 공식 지원 방식이며, DCGM 없이 nvidia-smi 기반 스크립트로도 구성 가능.
GPU 지표를 CloudWatch에 수집하면 알람, 대시보드, Logs Insights를 통한 GPU 인스턴스 운영 가시성 확보 가능.

**핵심 요약**
- **사용 목적**: GPU 사용률/메모리/온도/Xid 에러를 CloudWatch에서 모니터링
- **주요 이점**: 기존 AWS 모니터링 체계에 통합, EC2 지표와 함께 대시보드 구성 가능
- **관련 도구**: CloudWatch Agent, DCGM, nvidia-smi, IAM Role
- **해당 인스턴스**: 모든 NVIDIA GPU 인스턴스

---

## 2. 설명

### 2.1 핵심 개념

```
[GPU] --> [nvidia-smi / DCGM] --> [CloudWatch Agent] --> [CloudWatch]
                                         |
                              (커스텀 지표 네임스페이스)
                                    CWAgent
```

| 수집 방식 | 특징 | 권장 상황 |
|----------|------|---------|
| CWAgent + DCGM (nvidia_gpu) | 공식 지원, 풍부한 지표 | 프로덕션 |
| nvidia-smi + put-metric-data | 간단, DCGM 불필요 | 소규모/테스트 |
| DCGM Exporter + Prometheus | K8s/Prometheus 환경 | EKS GPU 노드 |

### 2.2 CloudWatch Agent + DCGM 방식 (권장)

#### IAM Role 권한 확인

EC2 인스턴스에 연결된 IAM Role에 아래 권한 필요:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData",
        "ec2:DescribeVolumes",
        "ec2:DescribeTags",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams",
        "logs:DescribeLogGroups",
        "logs:CreateLogStream",
        "logs:CreateLogGroup"
      ],
      "Resource": "*"
    }
  ]
}
```

#### CloudWatch Agent 설치

```bash
# AL2023
sudo dnf install -y amazon-cloudwatch-agent
```

#### DCGM 설치 (CWAgent nvidia_gpu 플러그인 필요)

```bash
# NVIDIA DCGM 저장소 추가
sudo dnf config-manager --add-repo \
  https://developer.download.nvidia.com/compute/cuda/repos/amzn2023/x86_64/cuda-amzn2023.repo

sudo dnf install -y datacenter-gpu-manager

# nv-hostengine 서비스 시작
sudo systemctl enable nvidia-dcgm
sudo systemctl start nvidia-dcgm

# 정상 동작 확인
dcgmi discovery -l
# 출력 예시:
# 1 GPU found.
# +--------+--------------------------------------------------------------+
# | GPU ID | Device Information                                           |
# +--------+--------------------------------------------------------------+
# | 0      | Name: NVIDIA A10G                                            |
```

#### CloudWatch Agent 설정 파일 (/opt/aws/amazon-cloudwatch-agent/etc/nvidia-gpu.json)

```json
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "metrics": {
    "namespace": "CWAgent",
    "metrics_collected": {
      "nvidia_gpu": {
        "measurement": [
          "utilization_gpu",
          "utilization_memory",
          "memory_total",
          "memory_used",
          "memory_free",
          "temperature_gpu",
          "power_draw",
          "fan_speed"
        ],
        "metrics_collection_interval": 60
      }
    },
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}",
      "InstanceType": "${aws:InstanceType}"
    }
  }
}
```

#### CloudWatch Agent 시작

```bash
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/nvidia-gpu.json \
  -s

# 상태 확인
sudo systemctl status amazon-cloudwatch-agent

# 로그 확인
tail -50 /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log
```

#### 지표 수집 확인

```bash
# CloudWatch에서 지표 확인 (수집 시작 후 1~2분 대기)
aws cloudwatch list-metrics \
  --namespace CWAgent \
  --metric-name utilization_gpu \
  --region ap-northeast-2

# 최근 값 조회
aws cloudwatch get-metric-statistics \
  --namespace CWAgent \
  --metric-name utilization_gpu \
  --dimensions Name=InstanceId,Value=<INSTANCE_ID> \
  --statistics Average \
  --period 60 \
  --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --region ap-northeast-2
```

### 2.3 nvidia-smi 기반 직접 발행 (경량 방식)

DCGM 없이 nvidia-smi로 지표를 수집하여 CloudWatch에 직접 발행하는 방식.

```bash
#!/bin/bash
# /opt/scripts/gpu-metrics-to-cw.sh
# cron으로 5분마다 실행

set -euo pipefail

TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/region)
NAMESPACE="GPU/Custom"

GPU_COUNT=$(nvidia-smi --query-gpu=index --format=csv,noheader | wc -l)

for i in $(seq 0 $((GPU_COUNT - 1))); do
  IFS=',' read -r UTIL MEM_USED MEM_TOTAL TEMP POWER <<< \
    "$(nvidia-smi -i "$i" \
      --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw \
      --format=csv,noheader,nounits)"

  # 공백 제거
  UTIL=$(echo "$UTIL" | tr -d ' ')
  MEM_USED=$(echo "$MEM_USED" | tr -d ' ')
  MEM_TOTAL=$(echo "$MEM_TOTAL" | tr -d ' ')
  TEMP=$(echo "$TEMP" | tr -d ' ')
  POWER=$(echo "$POWER" | xargs printf "%.0f")  # 소수점 반올림

  aws cloudwatch put-metric-data \
    --namespace "$NAMESPACE" \
    --metric-data \
      "[
        {\"MetricName\":\"gpu_util\",\"Value\":$UTIL,\"Unit\":\"Percent\",
         \"Dimensions\":[{\"Name\":\"InstanceId\",\"Value\":\"$INSTANCE_ID\"},{\"Name\":\"GpuIndex\",\"Value\":\"$i\"}]},
        {\"MetricName\":\"gpu_mem_used\",\"Value\":$MEM_USED,\"Unit\":\"None\",
         \"Dimensions\":[{\"Name\":\"InstanceId\",\"Value\":\"$INSTANCE_ID\"},{\"Name\":\"GpuIndex\",\"Value\":\"$i\"}]},
        {\"MetricName\":\"gpu_temperature\",\"Value\":$TEMP,\"Unit\":\"None\",
         \"Dimensions\":[{\"Name\":\"InstanceId\",\"Value\":\"$INSTANCE_ID\"},{\"Name\":\"GpuIndex\",\"Value\":\"$i\"}]},
        {\"MetricName\":\"gpu_power_draw\",\"Value\":$POWER,\"Unit\":\"None\",
         \"Dimensions\":[{\"Name\":\"InstanceId\",\"Value\":\"$INSTANCE_ID\"},{\"Name\":\"GpuIndex\",\"Value\":\"$i\"}]}
      ]" \
    --region "$REGION"
done
```

```bash
# cron 등록 (5분 간격)
echo "*/5 * * * * root /opt/scripts/gpu-metrics-to-cw.sh >> /var/log/gpu-metrics.log 2>&1" \
  | sudo tee /etc/cron.d/gpu-metrics
```

### 2.4 Best Practice

- Multi-GPU 인스턴스에서는 `GpuIndex` Dimension 추가 — GPU별 독립 알람 설정 가능
- CloudWatch Agent 설정을 SSM Parameter Store에 저장하면 여러 인스턴스에 중앙 배포 가능
- 수집 간격 60초 기본값 — 온도/ECC 에러는 30초 간격 권장

---

## 3. 트러블슈팅

### 3.1 주요 이슈

#### GPU 지표가 CloudWatch에 나타나지 않음

**증상**
- `aws cloudwatch list-metrics --namespace CWAgent` 에 `nvidia_gpu` 관련 지표 없음

**원인**
- `nvidia-dcgm` 서비스가 중지됐거나 nv-hostengine이 실행되지 않음
- CWAgent 설정 파일 경로 오류

**해결 방법**
```bash
# DCGM 서비스 상태 확인
systemctl status nvidia-dcgm

# nv-hostengine 프로세스 확인
pgrep -a nv-hostengine

# CWAgent 로그에서 nvidia_gpu 플러그인 오류 확인
grep -i "nvidia\|gpu" /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log

# CWAgent 재시작
sudo systemctl restart amazon-cloudwatch-agent
```

---

#### IAM 권한 부족으로 put-metric-data 실패

**증상**
- CWAgent 로그에 `AccessDenied` 오류

**원인**
- EC2 인스턴스 프로파일에 `cloudwatch:PutMetricData` 권한 미포함

**해결 방법**
```bash
# 인스턴스 프로파일 확인
aws iam get-instance-profile \
  --instance-profile-name <PROFILE_NAME> \
  --region ap-northeast-2

# CloudWatchAgentServerPolicy 정책 연결
aws iam attach-role-policy \
  --role-name <ROLE_NAME> \
  --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
```

---

### 3.2 자주 발생하는 문제 (Q&A)

**Q: Multi-GPU 인스턴스(p4d)에서 GPU 0번 지표만 수집됨**
A: CWAgent nvidia_gpu 플러그인은 기본적으로 감지된 모든 GPU를 수집함. GPU 0만 나타난다면 DCGM이 일부 GPU를 인식하지 못한 것 — `dcgmi discovery -l`로 DCGM이 인식하는 GPU 개수 확인.

**Q: CloudWatch 비용이 과도하게 발생함**
A: GPU 지표를 1분 간격, 8 GPU, 10개 지표로 수집하면 하루 수천 건의 메트릭 데이터. 수집 간격을 5분으로 늘리거나 핵심 지표(util, memory, temperature)만 선택적으로 수집.

---

## 4. 모니터링 및 알람

### 핵심 지표 (CWAgent nvidia_gpu)

| 지표명 | 단위 | 의미 | 임계값 예시 |
|--------|------|------|------------|
| `utilization_gpu` | Percent | GPU 코어 사용률 | `> 95% (10분)` |
| `memory_used` | Megabytes | 사용 중 VRAM | `> 90% of memory_total` |
| `temperature_gpu` | None | GPU 온도 (°C) | `> 85` |
| `power_draw` | None | 소비 전력 (W) | `> TDP * 0.95` |

### CloudWatch 알람 세트

```bash
# GPU 온도 알람
aws cloudwatch put-metric-alarm \
  --alarm-name "gpu-high-temp-<INSTANCE_ID>" \
  --metric-name "temperature_gpu" \
  --namespace "CWAgent" \
  --dimensions Name=InstanceId,Value=<INSTANCE_ID> \
  --statistic Maximum \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 85 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions "arn:aws:sns:ap-northeast-2:<ACCOUNT_ID>:<SNS_TOPIC>" \
  --region ap-northeast-2

# GPU 메모리 사용률 알람 (Metric Math 활용)
aws cloudwatch put-metric-alarm \
  --alarm-name "gpu-mem-high-<INSTANCE_ID>" \
  --metrics \
    '[{"Id":"m1","MetricStat":{"Metric":{"Namespace":"CWAgent","MetricName":"memory_used","Dimensions":[{"Name":"InstanceId","Value":"<INSTANCE_ID>"}]},"Period":300,"Stat":"Average"}},
      {"Id":"m2","MetricStat":{"Metric":{"Namespace":"CWAgent","MetricName":"memory_total","Dimensions":[{"Name":"InstanceId","Value":"<INSTANCE_ID>"}]},"Period":300,"Stat":"Average"}},
      {"Id":"e1","Expression":"(m1/m2)*100","Label":"GPU Memory Util %"}]' \
  --comparison-operator GreaterThanThreshold \
  --threshold 90 \
  --evaluation-periods 2 \
  --alarm-actions "arn:aws:sns:ap-northeast-2:<ACCOUNT_ID>:<SNS_TOPIC>" \
  --region ap-northeast-2
```

---

## 5. TIP

- CloudWatch Agent 설정을 SSM Parameter Store에 저장:
  ```bash
  aws ssm put-parameter \
    --name "/cloudwatch-agent/gpu-config" \
    --value "$(cat /opt/aws/amazon-cloudwatch-agent/etc/nvidia-gpu.json)" \
    --type String \
    --region ap-northeast-2
  ```
- 여러 GPU 인스턴스에 동일 설정 배포: SSM Run Command로 CWAgent 설정 fetch + restart 일괄 수행
- Grafana 연동 시 CloudWatch 데이터소스로 GPU 대시보드 구성 가능 — `GpuIndex` Dimension으로 GPU별 패널 분리

**관련 문서**
- [CloudWatch Agent nvidia_gpu 설정](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Agent-NVIDIA-GPU.html)
- 연관 내부 문서: `docs/smi/nvidia-smi-query.md`, `docs/dcgm/dcgm-setup.md`
