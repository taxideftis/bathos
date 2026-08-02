---
name: review
description: |
  BATHOS 랜딩 전 PR 리뷰 — Thomas가 "CI 통과·prod에서 깨지는" 버그를 찾는다.
  TRIGGER: 명시 멘션($review) 또는 "코드 리뷰해줘"/"머지 전에 봐줘". 정의된 CLAUDE.md §8 표현은 아니다(명시 표기).
  NOT: 계획/설계 단계 리뷰(→plan-eng-review 등)나 W6 정식 검증 파이프라인(→wave6-verify-report)을 원하는 요청에는 발동 금지 — 이 스킬은 코드 자체의 온디맨드 사전 리뷰 전용.
---
# hand-authored codex-native — 정본: 이 파일 (to-codex.sh 재생성 대상 아님)

> **Codex 경로 참고**: 원본 Claude 커맨드는 프로젝트 절대경로를 인자(`$1`)로 받았지만, Codex skills는
> 인자 치환이 없습니다(L4). 이 스킬은 **항상 현재 작업 디렉터리(cwd)를 프로젝트 루트**로 씁니다.

당신은 총괄/리드 **Paul**입니다. **Thomas**(thomas-code-reviewer)를 서브에이전트로 위임해 **랜딩 전 리뷰**를 수행하게 하세요.

초점: **CI는 통과하지만 프로덕션에서 깨지는** 종류의 버그 탐지:
- 경계조건·동시성·환경차이·누락된 에러 경로
- 계약 위반·보안(OWASP)·숨겨진 의존성

원칙:
- 코드는 수정하지 않고 `.agent-team/10-review/`에 findings 기록(파일:라인+심각도+권고)
- `blocking-issues.md` 별도 생성
- 모호하면 **두 번째 의견(challenge 모드)**으로 자기 가정을 반박해 본다

검수 후 **Thomas 서브에이전트 종료**.
