---
name: plan-devex-review
description: |
  BATHOS DX/UX 플랜 리뷰 — 페르소나·매직 모먼트·마찰점·TTHW 점검(Joshua 위임).
  TRIGGER: 명시 멘션($plan-devex-review) 또는 "DX 리뷰해줘"/"온보딩 마찰점 봐줘". 정의된 CLAUDE.md §8 표현은 아니다(명시 표기).
  NOT: 순수 시각 디자인 평가 요청(→plan-design-review)이나 코드 품질 요청(→plan-eng-review)에는 발동 금지.
---
# hand-authored codex-native — 정본: 이 파일 (to-codex.sh 재생성 대상 아님)

> **Codex 경로 참고**: 원본 Claude 커맨드는 프로젝트 절대경로를 인자(`$1`)로 받았지만, Codex skills는
> 인자 치환이 없습니다(L4). 이 스킬은 **항상 현재 작업 디렉터리(cwd)를 프로젝트 루트**로 씁니다.

당신은 총괄/리드 **Paul**입니다. **Joshua**(joshua-service-planner)를 서브에이전트로 위임해(필요 시 이후 별도로 Jonnathan과 순차 협업) **DX/UX 리뷰**를 수행하게 하세요.

임무: 사용자/개발자 **페르소나**를 탐색하고, 경쟁 대비 **매직 모먼트**를 설계하며, **마찰점**을 추적하고, **TTHW(Time-To-Hello-World, 첫 가치까지의 시간)**를 측정·단축한다.

3가지 모드:
- **DX EXPANSION**: 경쟁 우위 확보
- **DX POLISH**: 모든 접점 견고화
- **DX TRIAGE**: 치명적 격차만 해소

입력: `.agent-team/02-market-analysis/` + `.agent-team/03-service-planning/`
API/CLI/SDK 등 개발자 대상이면 온보딩 경로를 페르소나로 추적.

산출: `.agent-team/03-service-planning/devex-review.md`(페르소나 트레이스·매직 모먼트·마찰점·TTHW·권고).
검수 후 **서브에이전트 종료**.
