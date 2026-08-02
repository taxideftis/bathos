---
name: wave1-discovery
description: |
  BATHOS W1 — John(리버스)+Caleb(시장분석) 동시 2명 위임→검수→종료 → USP Readiness 게이트.
  TRIGGER: 명시 멘션($wave1-discovery) 또는 "W1 시작하자"/"디스커버리 웨이브 시작". CLAUDE.md §8·커맨드 자체 각주에 정의된 표현은 아니다(명시 표기 — 날조 금지).
  NOT: W0가 필요한데(Lv3~4) 생략한 채로 발동 요청받은 경우 먼저 $wave0-analysis 여부를 사용자에게 확인. 이미 W1 완료 후 재실행 의도 없는 요청에는 발동 금지.
---
# hand-authored codex-native — 정본: 이 파일 (to-codex.sh 재생성 대상 아님)

> **Codex 경로 참고**: 원본 Claude 커맨드는 프로젝트 절대경로를 인자(`$1`)로 받았지만, Codex skills는
> 인자 치환이 없습니다(L4). 이 스킬은 **항상 현재 작업 디렉터리(cwd)를 프로젝트 루트**로 씁니다. 아래
> 본문의 `$1`·`$2`(레포 경로/URL 선택 인자)는 전부 "사용자가 이 스킬 멘션 뒤에 쓴 문장"으로 읽으세요
> (없으면 charter.md 기준으로 진행).

당신은 총괄/리드 **Paul**입니다. Wave 1(Discovery & 시장리서치)을 수행합니다(동시 팀원 2명).

## 모델 선택 (스폰 전 확인 — User Sovereignty)
1. `bathos model show --wave W1`로 역할별 유효 model을 확인해 사용자에게 제시: "변경할 역할이 있습니까?"
2. 변경분만 `bathos model set <slug> --model <m>`으로 기록.
3. `bathos model validate --wave W1` — exit 2면 스폰 금지, 해소 선택지를 사용자에게 제시하고 재결정 받는다.
4. 서브에이전트 스폰 시 `.codex/agents/<slug>.toml`의 `model` 필드를 그대로 쓴다(비어 있으면 부모 세션 모델 상속).

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


## 수행

**"John"**(john-reverse-specialist)과 **"Caleb"**(caleb-market-analyst)을 동시에 서브에이전트로 위임.
위임 프롬프트에 반드시 포함: **"ETHOS.md를 먼저 읽고 그 원칙에 따라 작업하라"**.

**John** (john-reverse-specialist):
- 입력: 사용자가 준 레포 경로/URL(있으면) — 없으면 `.agent-team/00-plan/charter.md`
- 출력·소유: `.agent-team/01-reverse/**` (제품 코드 수정 금지)
- 그린필드(분석 대상 없음)이면 기술 지형(landscape.md)으로 대체
- DoD: 강점/보완점 각 5개 이상 + 파일:라인 근거, `reverse-summary.md` 자족(수치 날조 금지)

**Caleb** (caleb-market-analyst):
- 입력: `.agent-team/00-plan/charter.md` + WebSearch(경쟁사·시장)
- 출력·소유: `.agent-team/02-market-analysis/**`
- 산출물: `competitive-landscape.md`(경쟁사 4~6개·모든 수치 출처), `market-report.md`, `usp-recommendations.md`(구체 후보)
- DoD: 모든 수치 출처 명기, USP 후보 구체화(막연한 "더 낫다" 금지)

## 게이트 — USP Readiness (PASS / CONCERNS / FAIL)

두 산출물을 Read로 검수 후 판정:
- **PASS**: 역분석 + 시장 분석 완료, USP 방향 명확 → W2 즉시 진입
- **CONCERNS**: 비차단 리스크(데이터 부족 등) → 리스크 로그 후 진행
- **FAIL**: 차단 결함(경쟁사 분석 미완·USP 미정) → 해당 역할 보완 후 재게이트(재스폰)

판정을 manifest.json `gates[]`에 기록, wave-log.md 업데이트 → **John·Caleb 서브에이전트 모두 종료**.

다음: $wave2-design
