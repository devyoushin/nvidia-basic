---
description: GPU 운영 Runbook을 생성합니다. 사용법: /new-runbook <카테고리> <작업명>
---

`$ARGUMENTS`를 파싱하여 GPU 운영 Runbook을 생성합니다.
- 첫 번째 인자: 대상 카테고리 (driver, smi, dcgm, cuda 등)
- 나머지 인자: 작업명

## 파일 생성 규칙

1. 파일명: `runbook-{카테고리}-{작업명}.md`
2. 저장 위치: `docs/{해당 카테고리}/`
3. `templates/runbook.md` 템플릿 기반으로 작성

## 작성 시 필수 포함 사항

- **사전 체크리스트**: 최소 4개 항목 (GPU 프로세스 확인 반드시 포함)
- **환경 변수 설정**: `export` 형식으로 명시 (INSTANCE_ID, REGION 기본 포함)
- **단계별 명령어**: 복붙 즉시 실행 가능
- **확인 명령어**: 각 스텝 완료 후 `nvidia-smi` 또는 `dmesg` 기반 검증
- **롤백 절차**: 드라이버 다운그레이드 또는 이전 AMI 복구 등 구체적으로
- **모니터링 포인트**: 작업 후 Xid 에러 / CloudWatch GPU 지표 감시 항목

## 작업 특성별 추가 요소

| 작업 유형 | 추가 항목 |
|----------|---------|
| 드라이버 업그레이드 | 이전/이후 버전 기록, DKMS 재빌드 확인, CUDA 호환성 체크 |
| GPU 리셋 | 실행 중인 프로세스 종료 절차, Xid 에러 확인 |
| 호스트 교체 (Stop&Start) | EIP/ENI 유지 확인, Scheduled Event 확인 명령어 |
| MIG 파티셔닝 | 현재 GPU 점유 프로세스 정리, MIG 모드 전환 순서 |
