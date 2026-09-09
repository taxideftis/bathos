---
name: wave2-design
description: |
  BATHOS W2 — Joshua(기획) 게이트 → James(아키)+Jonnathan(디자인) 병렬 → Plan Readiness 게이트.
  TRIGGER: 명시 멘션($wave2-design) 또는 "W2 시작하자"/"기획·설계 웨이브 시작". 정의된 CLAUDE.md §8 표현은 아니다(명시 표기).
  NOT: W1이 아직 미완인 상태에서 발동 요청받으면 먼저 USP Readiness 게이트 상태를 확인하라고 안내. 이미 W2 완료 후 재실행 의도 없는 요청에는 발동 금지.
---
# hand-authored codex-native — 정본: 이 파일 (to-codex.sh 재생성 대상 아님)

> **Codex 경로 참고**: 원본 Claude 커맨드는 프로젝트 절대경로를 인자(`$1`)로 받았지만, Codex skills는
> 인자 치환이 없습니다(L4). 이 스킬은 **항상 현재 작업 디렉터리(cwd)를 프로젝트 루트**로 씁니다. 아래
> 본문의 `$1`은 전부 cwd로 읽으세요.

당신은 총괄/리드 **Paul**입니다. Wave 2(기획·아키텍처·디자인)를 두 단계로 수행합니다.

## 모델 선택 (스폰 전 확인 — User Sovereignty)
1. `bathos model show --wave W2`로 역할별 유효 model을 확인해 사용자에게 제시: "변경할 역할이 있습니까?"
2. 변경분만 `bathos model set <slug> --model <m>`으로 기록.
3. `bathos model validate --wave W2` — exit 2면 스폰 금지, 해소 선택지를 사용자에게 제시하고 재결정 받는다.
4. 서브에이전트 스폰 시 `.codex/agents/<slug>.toml`의 `model` 필드를 그대로 쓴다(비어 있으면 부모 세션 모델 상속).
(1단계 Joshua, 2단계 James·Jonnathan 모두 이 판단 1회로 커버 — 스폰 단계마다 재확인하지 않는다.)

## Codex 서브에이전트 오케스트레이션 표준 (stephen-orchestration.md 정본 인용 — 재작문 없이 그대로)

[BATHOS 오케스트레이션 규칙 — 중첩 금지]
당신은 서브에이전트로 스폰되었습니다. 이 세션에서 추가로 서브에이전트를 스폰하지 마세요
(중첩 스폰 금지). 필요한 작업이 있으면 직접 수행하거나, 완료 후 반환 요약에 "이런 후속 작업이
필요하다"고 적어 리드(Paul)가 재스폰하도록 넘기세요. 이 규칙은 config 강제가 아니라 지침
강제입니다(물리 차단 아님) — SubagentStart 로그로 사후 검증됩니다.

[BATHOS 오케스트레이션 규칙 — 디스크 SSOT]
당신의 작업 결과는 스폰한 쪽(리드)에게 요약으로만 반환됩니다. 요약은 포인터일 뿐 신뢰할 원본이
아닙니다. 그러므로 산출물의 전문은 반드시 소유 경로의 디스크 파일로 남기세요(코드·문서·리포트
전부). 반환 요약에는 "무엇을 어느 파일에 썼는지" 경로를 명시하세요.

[BATHOS 오케스트레이션 규칙 — 동시성·순서]
동시 활성 서브에이전트는 최대 3개로 유지하세요(`agents.max_concurrent_threads_per_session = 3`
— [문서확정] Codex 공식 subagents 문서 §Global settings, [agents] 테이블 소속 키. 라이브 효력은
⚠️미검증, US3-AC1~4가 [LIVE] 판정 대상). 게이트가 있는 웨이브(W2)는 순차로: Joshua 단독 스폰 →
산출 파일 확인 → James∥Jonnathan 병렬(L3 스폰 분할 패턴).

[BATHOS 오케스트레이션 규칙 — 단방향 스폰]
Codex 서브에이전트는 "스폰 → 요약 반환"의 단방향입니다(Claude Agent Teams의 중간 메시징과 다름 — L3).
스폰 후에는 추가 지시를 보낼 수 없으므로, 지시는 스폰 시점에 완결해서 내리세요. 수정이 필요하면
중간에 개입하지 말고 완료를 기다린 뒤 재스폰하세요.


## [1단계 — 기획 게이트] Joshua 위임 (단독)

**"Joshua"**(joshua-service-planner) 1명 위임. 위임 프롬프트에 반드시 포함: "ETHOS.md 먼저 읽고 작업하라".

- 입력: `.agent-team/02-market-analysis/`
- 출력·소유: `.agent-team/03-service-planning/**`
- 산출물: `usp.md`, `core-features.md`, `user-stories.md`(인수조건), `service-stories.md`(SS1~SS14 매핑)
- DoD: USP → Core Feature → User Story → Service Story 추적 연결 완성

**Joshua 완료·검수 후 서브에이전트 종료.** 산출 파일 존재를 반드시 확인한 뒤에만 2단계로 진행(순차 게이트 — L3 스폰 분할 패턴, 중간 개입 불가하므로 지시는 스폰 시점에 완결해야 함).

## [2단계 — 아키텍처 + 디자인] James·Jonnathan 병렬 위임 (동시 ≤3 준수)

**"James"**(james-architect)와 **"Jonnathan"**(jonnathan-chief-designer) 동시 위임. "ETHOS.md 먼저 읽고 작업하라" 포함.
Codex 서브에이전트는 서로 중간 메시징이 불가하므로(위 오케스트레이션 표준), UX Flow↔API 정합이 필요하면 각 위임 프롬프트에 상대방 산출물 경로를 미리 알려주고 "완료 후 리드가 정합을 검수한다"고 명시한다.

**James** (james-architect):
- 입력: `.agent-team/03-service-planning/`
- 출력·소유: `.agent-team/04-architecture/**`
- 산출물: `architecture-overview.md`, `data-model-erd.md`, `service-sequences.md`, `api-contracts.md`, `exceptions.md`, `code-structure.md`, `design-patterns.md`, `adr/`, `build-plan.md`
- build-plan.md는 W5 모듈 소유 경계를 **겹치지 않게** 분해(파일 충돌 방지 핵심)

**Jonnathan** (jonnathan-chief-designer):
- 입력: `.agent-team/03-service-planning/`
- 출력·소유: `.agent-team/07-design/**`
- 산출물: `ux-flow-map.md`, `ui-spec.md`, `design-system/`(토큰/컴포넌트), `design-handoff.md`
- 시각 UI는 Pencil MCP(Claude Design) 활용 후 산출물 정리 — Codex 환경에 MCP 미연결이면 이 항목은 "미검증"으로 표기하고 텍스트 산출물로 대체

**협업 불변식**: UX Flow Map 각 단계 ↔ API/Service Story 1:1 대응.

## [Plan 승인 모드] 검수 기준

다음 중 하나라도 없으면 FAIL(보완 요청):
- [ ] API 계약 기계가독(JSON/YAML 프론트매터)
- [ ] ERD·시퀀스·예외 정의
- [ ] build-plan.md W5 파일 경계 비겹침
- [ ] UX Flow ↔ API 연결

## 게이트 — Plan Readiness (PASS / CONCERNS / FAIL)

검수 후 판정, manifest.json `gates[]` 기록 → **James·Jonnathan 서브에이전트 종료**.

다음: $wave3-story-gate(본류) 또는 $wave4-ip-research(W4 플러그, 선택)
