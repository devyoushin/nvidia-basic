# nvidia-basic

AWS NVIDIA GPU 인스턴스 운영을 위한 드라이버, `nvidia-smi`, DCGM, CloudWatch 연동, 장애 대응 지식 베이스입니다.

## 어디서 시작할까

- 문서 지도: `docs/README.md`
- 운영/실습 자산: `ops/README.md`
- AI 작업 지침: `CLAUDE.md`, `AGENTS.md -> CLAUDE.md`

## 구조

| 경로 | 내용 |
|------|------|
| `docs/` | NVIDIA 드라이버, CUDA, DCGM, SMI, 모니터링, 트러블슈팅 문서 |
| `ops/` | GPU 헬스체크와 CloudWatch metric publish 스크립트 |
| `.claude/` | Claude Code 커맨드와 설정 |
| `CLAUDE.md` | Claude/Codex 공통 작업 지침 원본 |
| `AGENTS.md -> CLAUDE.md` | Codex/agent 작업 지침 링크 |

## 학습 흐름

1. `docs/driver/`에서 드라이버 설치와 버전 관리 학습
2. `docs/smi/`에서 `nvidia-smi` 조회, 모니터링, reset 절차 학습
3. `docs/dcgm/`, `docs/monitoring/`에서 DCGM과 Prometheus/CloudWatch 연동 학습
4. `docs/troubleshooting/`에서 Xid, driver crash, AWS host replacement 대응 확인
5. `ops/scripts/`에서 운영 자동화 스크립트 확인
