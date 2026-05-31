# AGENTS.md — nvidia-basic Codex 작업 지침

이 저장소는 NVIDIA GPU 인스턴스 운영 지식 베이스입니다. Codex 작업 시 `CLAUDE.md`와 `docs/rules/`의 규칙을 동일하게 따릅니다.

## 공통 원칙

- 설명 문서는 `docs/` 아래에 둡니다.
- GPU 헬스체크, CloudWatch 발행 등 실행 스크립트는 `ops/` 아래에 둡니다.
- 명령 예시는 `nvidia-smi`, DCGM, driver, CUDA 버전 호환성을 명확히 구분합니다.
- 장애 대응 문서는 Xid, driver crash, host replacement 판단 기준을 포함합니다.

## Claude와의 싱크

- Claude용 상세 지침은 `CLAUDE.md`를 참고합니다.
- Codex도 공통 문서/운영 규칙은 `docs/rules/`를 따릅니다.
- 로컬 도구 설정은 Git에 올리지 않습니다.

## 작업 체크리스트

- 기존 변경 확인
- shell script는 `bash -n` 검사
- 링크 검사와 `git diff --check` 수행
