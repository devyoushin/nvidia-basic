#!/bin/bash
# gpu-metrics-to-cw.sh
# nvidia-smi 지표를 CloudWatch 커스텀 네임스페이스에 발행
# 사용법: bash gpu-metrics-to-cw.sh
# cron 예시: */5 * * * * root /opt/scripts/gpu-metrics-to-cw.sh >> /var/log/gpu-metrics.log 2>&1

set -euo pipefail

NAMESPACE="GPU/Custom"
REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"

# IMDSv2로 인스턴스 ID 조회
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null)
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null)

if [ -z "$INSTANCE_ID" ]; then
  echo "ERROR: 인스턴스 ID를 가져올 수 없습니다" >&2
  exit 1
fi

GPU_COUNT=$(nvidia-smi --query-gpu=index --format=csv,noheader | wc -l)

for i in $(seq 0 $((GPU_COUNT - 1))); do
  IFS=',' read -r UTIL MEM_UTIL MEM_USED MEM_TOTAL TEMP POWER ECC_CORR ECC_UNCORR <<< \
    "$(nvidia-smi -i "$i" \
      --query-gpu=utilization.gpu,utilization.memory,memory.used,memory.total,temperature.gpu,power.draw,ecc.errors.corrected.volatile.total,ecc.errors.uncorrected.volatile.total \
      --format=csv,noheader,nounits)"

  # 공백 제거 및 N/A 처리
  UTIL=$(echo "$UTIL" | tr -d ' ')
  MEM_UTIL=$(echo "$MEM_UTIL" | tr -d ' ')
  MEM_USED=$(echo "$MEM_USED" | tr -d ' ')
  MEM_TOTAL=$(echo "$MEM_TOTAL" | tr -d ' ')
  TEMP=$(echo "$TEMP" | tr -d ' ')
  POWER=$(echo "$POWER" | tr -d ' ' | xargs printf "%.2f")
  ECC_CORR=$(echo "$ECC_CORR" | tr -d ' ')
  ECC_UNCORR=$(echo "$ECC_UNCORR" | tr -d ' ')

  # ECC N/A 처리 (ECC 미지원 GPU)
  [ "$ECC_CORR" = "N/A" ] && ECC_CORR=0
  [ "$ECC_UNCORR" = "N/A" ] && ECC_UNCORR=0

  DIMS="[{\"Name\":\"InstanceId\",\"Value\":\"$INSTANCE_ID\"},{\"Name\":\"GpuIndex\",\"Value\":\"$i\"}]"

  aws cloudwatch put-metric-data \
    --namespace "$NAMESPACE" \
    --metric-data \
      "[
        {\"MetricName\":\"gpu_util\",\"Value\":$UTIL,\"Unit\":\"Percent\",\"Dimensions\":$DIMS},
        {\"MetricName\":\"gpu_mem_util\",\"Value\":$MEM_UTIL,\"Unit\":\"Percent\",\"Dimensions\":$DIMS},
        {\"MetricName\":\"gpu_mem_used\",\"Value\":$MEM_USED,\"Unit\":\"None\",\"Dimensions\":$DIMS},
        {\"MetricName\":\"gpu_temperature\",\"Value\":$TEMP,\"Unit\":\"None\",\"Dimensions\":$DIMS},
        {\"MetricName\":\"gpu_power_draw\",\"Value\":$POWER,\"Unit\":\"None\",\"Dimensions\":$DIMS},
        {\"MetricName\":\"gpu_ecc_corrected\",\"Value\":$ECC_CORR,\"Unit\":\"Count\",\"Dimensions\":$DIMS},
        {\"MetricName\":\"gpu_ecc_uncorrected\",\"Value\":$ECC_UNCORR,\"Unit\":\"Count\",\"Dimensions\":$DIMS}
      ]" \
    --region "$REGION"

  echo "$(date '+%Y-%m-%dT%H:%M:%S') GPU[$i] util=${UTIL}% mem=${MEM_USED}/${MEM_TOTAL}MiB temp=${TEMP}C power=${POWER}W ecc_uncorr=${ECC_UNCORR}"
done
