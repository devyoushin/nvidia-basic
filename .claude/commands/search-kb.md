---
description: 지식 베이스에서 키워드를 검색합니다. 사용법: /search-kb <키워드>
---

`$ARGUMENTS`에 포함된 키워드로 nvidia-practice 지식 베이스 전체를 검색합니다.

## 검색 범위

- `docs/**/*.md` — 모든 지식 문서
- `scripts/*.sh` — 자동화 스크립트
- `CLAUDE.md` — 문서 목록 인덱스

## 검색 결과 출력 형식

```
## 검색 결과: "{키워드}"

### 문서 매칭
| 파일 | 섹션 | 관련 내용 요약 |
|------|------|--------------|
| docs/troubleshooting/xid-error-codes.md | 3.1 | Xid 48 Double Bit ECC... |

### 스크립트 매칭
| 파일 | 관련 내용 요약 |
|------|--------------|

### 추천 문서
{가장 관련성 높은 문서 1~3개 링크}
```

## 검색 팁

- Xid 에러 검색: `/search-kb Xid 48`
- 명령어 검색: `/search-kb nvidia-smi dmon`
- 인스턴스 패밀리 검색: `/search-kb p4d Fabric Manager`
