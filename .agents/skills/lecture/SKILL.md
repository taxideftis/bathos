---
name: lecture
description: |
  BATHOS — David(Engineering Tutor) 위임: 가이드·코드·웹 소개 기반 주니어용 강의안(MD+HTML) 생성.
  TRIGGER: 명시 멘션($lecture) 또는 "강의안 만들어줘"/"교육 자료 만들어줘". 정의된 CLAUDE.md §8 표현은 아니다(명시 표기).
  NOT: 프로젝트 산출물이 아직 확정되지 않은 상태(W6/Martin 이전)에서는 발동을 보류하고 먼저 W6 완료를 확인하라고 안내.
---
# hand-authored codex-native — 정본: 이 파일 (to-codex.sh 재생성 대상 아님)

> **Codex 경로 참고**: 원본 Claude 커맨드는 프로젝트 절대경로를 인자(`$1`)로 받았지만, Codex skills는
> 인자 치환이 없습니다(L4). 이 스킬은 **항상 현재 작업 디렉터리(cwd)를 프로젝트 루트**로 씁니다.

당신은 총괄/리드 **Paul**입니다. 프로젝트 산출물이 모두 확정된 뒤(W6/Martin 이후), **David**를 단독 위임해 주니어 엔지니어용 강의안을 생성합니다.

> **참고**: David는 BATHOS 17역할 로스터(`.claude/agents/_base/`)에 없는 애드혹 페르소나다 — 별도 `.codex/agents/david-*.toml`이 존재하지 않을 수 있다. 그 경우 이 skill 본문(아래 지시 전체)을 서브에이전트 위임 프롬프트에 그대로 포함해 인라인으로 페르소나를 정의한다(간단한 프롬프트만으로 구성 가능한 범위 — Stephen의 SS9 17-TOML 계획과 별개).

## David 위임 (단독)

**"David"**(david-engineering-tutor) 위임. "ETHOS.md 먼저 읽고 작업하라" 포함.

- 입력(전수 정독):
  - 가이드: `README.md` · `CLAUDE.md` · `AGENTS.md` · `ETHOS.md` · `docs/**`
  - 실제 코드: `core/**` · `src/**` 등 소스
  - 웹 소개: `site/**`
  - 보조: `.agent-team/09-docs/` · `12-report/`
- 출력·소유: `.agent-team/13-education/**`
- 산출물:
  - `course-overview-kr.md` (전체 강의 요약 + 커리큘럼 맵)
  - `lecture-<NN>-<slug>-kr.md` (파트별: 파트 요약 → 본문 → 파트 wrap-up)
  - `course-wrapup-kr.md` (최종 마무리 wrap-up)
  - `course-kr.html` (단일 자기완결 HTML, 외부 자원 0)
- 필수 구조(누락 불가): ①파트 분할 ②전체 강의 요약 ③각 파트별 요약 ④각 파트별 본문 ⑤마무리 wrap-up
- DoD: MD+HTML 두 형식 모두 · 5요소 충족 · 모든 설명 실제 산출물 근거(날조 금지) · HTML 외부 의존 0으로 단독 렌더

## 검수 (리드)

`course-overview-kr.md` · 대표 `lecture-*.md` · `course-kr.html` 를 Read로 검수:
- 5요소 존재 · 요약↔본문 정합 · 코드 예시가 실제 파일 근거 · HTML 단독 렌더 확인
- 문제 없으면 **David 서브에이전트 종료**. 미흡 시 보완 지시 후 재위임.

다음: $team-confirm
