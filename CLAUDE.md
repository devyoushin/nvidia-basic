# CLAUDE.md — nvidia-practice 지식 베이스

AWS 환경에서 NVIDIA GPU 인스턴스를 운영하며 쌓은 경험 기반의 개인 지식 베이스입니다.
nvidia-smi, DCGM, 드라이버 관리, CloudWatch 연동 등 실무 내용 위주로 정리합니다.

---

## 프로젝트 구조

```
nvidia-practice/
├── docs/                              # 지식 문서 (카테고리별 분류)
│   ├── driver/        (3개)           # 드라이버 설치, 버전 관리, Fabric Manager
│   ├── smi/           (4개)           # nvidia-smi 기본/쿼리/모니터링/프로세스
│   ├── dcgm/          (2개)           # DCGM 설치, 지표 수집
│   ├── monitoring/    (2개)           # CloudWatch GPU 지표, DCGM Exporter
│   ├── cuda/          (2개)           # CUDA/드라이버 호환성, 컨테이너 런타임
│   └── troubleshooting/ (3개)        # Xid 에러, 드라이버 크래시, AWS 호스트 교체
│
├── scripts/                           # nvidia-smi 자동화 스크립트 (8개)
│
├── templates/                         # 재사용 문서 템플릿
│   ├── gpu-doc.md                     # GPU 서비스 문서 스캐폴딩
│   └── runbook.md                     # 운영 Runbook
│
├── rules/                             # Claude 작성 규칙
│   ├── doc-writing.md                 # 문서 스타일 가이드
│   └── nvidia-conventions.md         # nvidia-smi/DCGM 코드 작성 규칙
│
├── agents/                            # Claude 전문 에이전트
│   ├── gpu-doc-writer.md              # GPU 문서 작성 에이전트
│   └── driver-troubleshooter.md      # 드라이버 장애 분석 에이전트
│
└── .claude/
    ├── settings.json                  # 프로젝트 공유 설정
    └── commands/                      # 커스텀 슬래시 커맨드
        ├── new-doc.md                 # /new-doc
        ├── new-runbook.md             # /new-runbook
        ├── add-troubleshooting.md     # /add-troubleshooting
        └── search-kb.md               # /search-kb
```

---

## 커스텀 슬래시 커맨드

| 커맨드 | 사용법 | 설명 |
|--------|--------|------|
| `/new-doc` | `/new-doc smi query-options` | 신규 문서 스캐폴딩 |
| `/new-runbook` | `/new-runbook driver upgrade` | 운영 Runbook 생성 |
| `/add-troubleshooting` | `/add-troubleshooting docs/smi/nvidia-smi-basics.md <증상>` | 트러블슈팅 추가 |
| `/search-kb` | `/search-kb Xid 에러` | 지식 베이스 키워드 검색 |

---

## 파일 네이밍 규칙

```
docs/{카테고리}/{서비스}-{주제}.md
```

- 카테고리: `driver`, `smi`, `dcgm`, `monitoring`, `cuda`, `troubleshooting`
- 서비스 약어: `nvidia`, `dcgm`, `cuda`, `cw` (CloudWatch)
- 예시: `docs/driver/nvidia-driver-install-al2023.md`, `docs/smi/nvidia-smi-query.md`

---

## 문서 작성 원칙

1. **실제 경험 기반** — AWS GPU 인스턴스 운영 중 실제 발생한 이슈 위주
2. **재현 가능한 명령어** — nvidia-smi 명령어는 복붙 즉시 실행 가능 수준
3. **원인 중심 트러블슈팅** — Xid 에러 등 증상만 나열하지 말고 근본 원인 설명
4. **한국어 기술 문서** — 주요 개념은 영어 원문 병기
5. **모니터링 필수** — 모든 문서에 CloudWatch 지표/알람 포함 (GPU 인스턴스 기준)

세부 규칙은 `rules/` 디렉토리를 참조합니다.

---

## 카테고리별 문서 목록

### docs/driver/
| 파일 | 주제 |
|------|------|
| `nvidia-driver-install-al2023.md` | AL2023 GPU 인스턴스 NVIDIA 드라이버 설치 (DKMS, 커널 모듈) |
| `nvidia-driver-version-management.md` | 드라이버 버전 관리 (업그레이드, 롤백, Branch 선택) |
| `nvidia-fabric-manager.md` | Fabric Manager 설치/운영 (NVSwitch 연결 p4d/p5 필수) |

### docs/smi/
| 파일 | 주제 |
|------|------|
| `nvidia-smi-basics.md` | nvidia-smi 기본 사용법 (GPU 상태 조회, 프로세스 확인) |
| `nvidia-smi-query.md` | --query-gpu/--query-compute-apps 옵션 활용 |
| `nvidia-smi-monitoring.md` | dmon/pmon 루프 모니터링, 로그 수집 자동화 |
| `nvidia-smi-gpu-reset.md` | GPU 리셋 (-r), MIG 모드 전환, drain 처리 |

### docs/dcgm/
| 파일 | 주제 |
|------|------|
| `dcgm-setup.md` | DCGM 설치 및 nv-hostengine 구성 |
| `dcgm-field-groups.md` | DCGM 필드 그룹, dcgmi 명령어, 헬스 체크 |

### docs/monitoring/
| 파일 | 주제 |
|------|------|
| `cw-gpu-metrics.md` | CloudWatch 커스텀 GPU 지표 수집 (CWAgent + DCGM) |
| `dcgm-exporter-prometheus.md` | DCGM Exporter Prometheus 연동, Grafana 대시보드 |

### docs/cuda/
| 파일 | 주제 |
|------|------|
| `cuda-driver-compatibility.md` | CUDA Toolkit ↔ 드라이버 버전 호환성 매트릭스 |
| `nvidia-container-toolkit.md` | NVIDIA Container Toolkit 설치, EKS GPU 노드 설정 |

### docs/troubleshooting/
| 파일 | 주제 |
|------|------|
| `xid-error-codes.md` | Xid 에러 코드 분류, dmesg 진단, AWS 호스트 교체 판단 |
| `driver-crash-recovery.md` | 드라이버 크래시 복구 (nvidia-smi -r, 재설치, 커널 모듈 재로드) |
| `aws-host-replacement.md` | AWS 물리 호스트 교체 절차 (Stop&Start), Scheduled Event 대응 |

---

## 추가 예정 주제 (백로그)

- `docs/driver/nvidia-driver-efa.md` — EFA + GPU 인스턴스 (p4d, p5) 드라이버 구성
- `docs/smi/nvidia-smi-mig.md` — MIG (Multi-Instance GPU) 파티셔닝 (A100, H100)
- `docs/monitoring/gpu-alarm-patterns.md` — GPU 지표 알람 패턴 (온도, 메모리, ECC)
- `docs/cuda/cuda-multi-version.md` — CUDA 다중 버전 공존 (update-alternatives 활용)
