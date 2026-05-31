#!/bin/bash
# gpu-health-check.sh
# GPU 인스턴스 전반적인 상태를 한 번에 점검하는 스크립트
# 사용법: sudo bash gpu-health-check.sh

set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo "========================================"
echo "  NVIDIA GPU Health Check"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"

# 1. 드라이버 상태
echo ""
echo "[1] 드라이버 정보"
if cat /proc/driver/nvidia/version 2>/dev/null; then
  echo -e "${GREEN}  ✅ 드라이버 로드됨${NC}"
else
  echo -e "${RED}  ❌ 드라이버 미로드 — lsmod | grep nvidia 확인 필요${NC}"
  exit 1
fi

# 2. GPU 개수 및 기본 상태
echo ""
echo "[2] GPU 상태"
nvidia-smi --query-gpu=index,name,persistence_mode,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw \
  --format=csv,noheader,nounits | while IFS=',' read -r idx name pmode util mem_used mem_total temp power; do
  name=$(echo "$name" | xargs)
  util=$(echo "$util" | xargs)
  mem_used=$(echo "$mem_used" | xargs)
  mem_total=$(echo "$mem_total" | xargs)
  temp=$(echo "$temp" | xargs)
  power=$(echo "$power" | xargs | printf "%.0f")
  pmode=$(echo "$pmode" | xargs)

  MEM_PCT=$(awk "BEGIN {printf \"%.0f\", ($mem_used/$mem_total)*100}")

  echo "  GPU $idx: $name"
  echo "    Persistence: $pmode | Util: ${util}% | Mem: ${mem_used}/${mem_total} MiB (${MEM_PCT}%) | Temp: ${temp}°C | Power: ${power}W"

  # 경고 임계값 체크
  if [ "$temp" -gt 85 ]; then
    echo -e "    ${RED}⚠️  온도 경고: ${temp}°C > 85°C${NC}"
  fi
  if [ "$MEM_PCT" -gt 90 ]; then
    echo -e "    ${YELLOW}⚠️  메모리 사용률 높음: ${MEM_PCT}%${NC}"
  fi
done

# 3. ECC 에러 확인
echo ""
echo "[3] ECC 에러 상태"
nvidia-smi --query-gpu=index,ecc.errors.corrected.volatile.total,ecc.errors.uncorrected.volatile.total \
  --format=csv,noheader,nounits | while IFS=',' read -r idx corrected uncorrected; do
  corrected=$(echo "$corrected" | xargs)
  uncorrected=$(echo "$uncorrected" | xargs)
  if [ "$uncorrected" != "N/A" ] && [ "$uncorrected" -gt 0 ]; then
    echo -e "  GPU $idx: ${RED}❌ Uncorrected ECC 에러 발생: ${uncorrected}건 — 즉시 조치 필요${NC}"
  elif [ "$corrected" != "N/A" ] && [ "$corrected" -gt 0 ]; then
    echo -e "  GPU $idx: ${YELLOW}⚠️  Corrected ECC 에러: ${corrected}건 (모니터링 필요)${NC}"
  else
    echo -e "  GPU $idx: ${GREEN}✅ ECC 에러 없음${NC}"
  fi
done

# 4. Xid 에러 확인 (최근 1시간)
echo ""
echo "[4] 최근 Xid 에러 (최근 1시간)"
XID_ERRORS=$(dmesg -T | grep "NVRM: Xid" | tail -10)
if [ -z "$XID_ERRORS" ]; then
  echo -e "  ${GREEN}✅ Xid 에러 없음${NC}"
else
  echo -e "  ${RED}❌ Xid 에러 감지:${NC}"
  echo "$XID_ERRORS" | while read -r line; do
    echo "    $line"
  done
fi

# 5. 실행 중인 GPU 프로세스
echo ""
echo "[5] GPU 프로세스"
PROCS=$(nvidia-smi --query-compute-apps=gpu_uuid,pid,used_gpu_memory,process_name \
  --format=csv,noheader,nounits 2>/dev/null)
if [ -z "$PROCS" ]; then
  echo "  실행 중인 GPU 프로세스 없음"
else
  echo "  PID     VRAM(MiB)  Process"
  echo "$PROCS" | while IFS=',' read -r uuid pid mem name; do
    pid=$(echo "$pid" | xargs)
    mem=$(echo "$mem" | xargs)
    name=$(echo "$name" | xargs | sed 's|.*/||')
    echo "  $pid      $mem       $name"
  done
fi

# 6. DKMS 상태
echo ""
echo "[6] DKMS 상태"
if command -v dkms &>/dev/null; then
  DKMS_STATUS=$(dkms status | grep nvidia)
  if echo "$DKMS_STATUS" | grep -q "installed"; then
    echo -e "  ${GREEN}✅ $DKMS_STATUS${NC}"
  else
    echo -e "  ${RED}❌ DKMS 빌드 이상: $DKMS_STATUS${NC}"
  fi
else
  echo "  DKMS 미설치"
fi

# 7. Fabric Manager 상태 (p4d/p5 해당 시)
if systemctl list-units --type=service | grep -q "nvidia-fabricmanager"; then
  echo ""
  echo "[7] Fabric Manager (NVSwitch 인스턴스)"
  if systemctl is-active --quiet nvidia-fabricmanager; then
    echo -e "  ${GREEN}✅ nvidia-fabricmanager 실행 중${NC}"
    # NVLink 링크 수 확인
    LINK_COUNT=$(nvidia-smi nvlink -s 2>/dev/null | grep -c "GB/s" || echo "0")
    echo "  활성 NVLink 수: $LINK_COUNT"
  else
    echo -e "  ${RED}❌ nvidia-fabricmanager 중지됨 — systemctl start nvidia-fabricmanager${NC}"
  fi
fi

echo ""
echo "========================================"
echo "  Health Check 완료"
echo "========================================"
