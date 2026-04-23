# NVIDIA 코드 작성 규칙 (NVIDIA Conventions)

nvidia-smi, DCGM, 드라이버 관련 코드/명령어 작성 시 따라야 할 규칙입니다.

---

## 1. nvidia-smi 명령어 작성 규칙

### 기본 형식
```bash
# 단순 조회
nvidia-smi

# 구조화 쿼리 (반드시 --format=csv,noheader,nounits 조합 사용)
nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total,temperature.gpu \
  --format=csv,noheader,nounits

# 루프 모니터링 (간격 초 단위)
nvidia-smi dmon -s u -d 5
```

### query-gpu 주요 필드 목록

| 필드 | 설명 | 단위 |
|------|------|------|
| `index` | GPU 인덱스 (0부터 시작) | — |
| `name` | GPU 모델명 | — |
| `utilization.gpu` | GPU 코어 사용률 | % |
| `utilization.memory` | 메모리 대역폭 사용률 | % |
| `memory.used` | 사용 중인 VRAM | MiB |
| `memory.total` | 전체 VRAM | MiB |
| `temperature.gpu` | GPU 다이 온도 | °C |
| `power.draw` | 현재 소비 전력 | W |
| `power.limit` | TDP 한도 | W |
| `clocks.current.graphics` | 현재 그래픽 클럭 | MHz |
| `ecc.errors.corrected.volatile.total` | 수정된 ECC 에러 (휘발성) | — |
| `ecc.errors.uncorrected.volatile.total` | 수정 불가 ECC 에러 (휘발성) | — |

### 규칙
- `--format=csv` 사용 시 항상 `noheader,nounits` 추가 (파싱 편의)
- 스크립트에서 GPU 수 동적 확인: `nvidia-smi --query-gpu=index --format=csv,noheader | wc -l`
- 루프 종료는 `Ctrl+C` 또는 `-c <횟수>` 플래그로 명시

---

## 2. DCGM 명령어 작성 규칙

```bash
# dcgmi 기본 형식
dcgmi <subcommand> [options]

# 헬스 체크
dcgmi health -g <GROUP_ID> -c

# 필드 값 조회
dcgmi dmon -e <FIELD_ID1>,<FIELD_ID2> -d <interval_ms>
```

### 자주 쓰는 DCGM 필드 ID

| 필드 ID | 이름 | 설명 |
|---------|------|------|
| 1001 | DCGM_FI_DEV_GPU_UTIL | GPU 사용률 (%) |
| 1002 | DCGM_FI_DEV_MEM_COPY_UTIL | 메모리 복사 사용률 (%) |
| 1003 | DCGM_FI_DEV_ENC_UTIL | 인코더 사용률 (%) |
| 1004 | DCGM_FI_DEV_DEC_UTIL | 디코더 사용률 (%) |
| 1005 | DCGM_FI_DEV_SM_CLOCK | SM 클럭 (MHz) |
| 1006 | DCGM_FI_DEV_MEM_CLOCK | 메모리 클럭 (MHz) |
| 1007 | DCGM_FI_DEV_GPU_TEMP | GPU 온도 (°C) |
| 1008 | DCGM_FI_DEV_POWER_USAGE | 소비 전력 (W) |
| 1009 | DCGM_FI_DEV_FB_FREE | 남은 Frame Buffer (MiB) |
| 1010 | DCGM_FI_DEV_FB_USED | 사용 중인 Frame Buffer (MiB) |
| 1012 | DCGM_FI_DEV_NVLINK_BANDWIDTH_TOTAL | NVLink 총 대역폭 |
| 230 | DCGM_FI_DEV_XID_ERRORS | Xid 에러 코드 |

---

## 3. AWS GPU 인스턴스 패밀리 표기

| 인스턴스 패밀리 | GPU 모델 | NVSwitch/NVLink | 비고 |
|----------------|----------|-----------------|------|
| `p3` | Tesla V100 | NVLink (일부) | 구세대, CUDA 7.0 |
| `p4d` | A100 (8x) | NVSwitch + NVLink | Fabric Manager 필수 |
| `p4de` | A100 80GB (8x) | NVSwitch + NVLink | Fabric Manager 필수 |
| `p5` | H100 (8x) | NVSwitch + NVLink | Fabric Manager 필수 |
| `g4dn` | T4 | — | 추론/그래픽 |
| `g5` | A10G | — | 추론/그래픽 |
| `g6` | L4 | — | 추론/그래픽 |
| `g6e` | L40S | — | 고성능 추론 |

- 코드 예시는 특정 인스턴스 타입에 의존하지 않도록 작성
- `p4d`/`p5`처럼 Fabric Manager 필요 여부는 반드시 문서에 명시

---

## 4. 드라이버 버전 표기

```
형식: {MAJOR}.{MINOR}.{PATCH}
예시: 535.154.05, 550.90.12, 570.00.00
```

- **Production Branch**: 안정 운영 권장 (짝수 MAJOR: 535, 550, 570)
- **New Feature Branch**: 최신 기능 포함, 안정성 검증 필요 (홀수 MAJOR: 545, 560)
- AWS 공식 지원 버전은 DLAMI 릴리스 노트에서 확인

---

## 5. 커널 모듈 명령어 규칙

```bash
# 모듈 상태 확인
lsmod | grep nvidia

# 모듈 언로드 (프로세스 없을 때만)
sudo rmmod nvidia_uvm nvidia_drm nvidia_modeset nvidia

# 모듈 로드
sudo modprobe nvidia

# 드라이버 바인딩 확인
cat /proc/driver/nvidia/version
```

- 커널 모듈 언로드 전 반드시 GPU 사용 프로세스 종료 확인: `nvidia-smi` 출력의 Processes 섹션
- DKMS 사용 시 커널 업그레이드 후 모듈 자동 재빌드 여부 확인: `dkms status`

---

## 6. CloudWatch 커스텀 지표 네임스페이스

```
네임스페이스: CWAgent (CWAgent 경유) 또는 GPU/Custom (직접 발행)
지표명 형식: gpu_{metric_name}  (소문자, 언더스코어)
```

| 지표명 | 단위 | 설명 |
|--------|------|------|
| `gpu_util` | Percent | GPU 코어 사용률 |
| `gpu_mem_util` | Percent | VRAM 사용률 |
| `gpu_mem_used` | Megabytes | 사용 중인 VRAM |
| `gpu_temperature` | None | GPU 온도 (°C) |
| `gpu_power_draw` | None | 소비 전력 (W) |
| `gpu_xid_errors` | Count | Xid 에러 누적 횟수 |
