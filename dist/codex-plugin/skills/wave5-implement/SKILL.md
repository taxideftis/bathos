---
name: wave5-implement
description: |
  BATHOS W5 — Phillip+Andrew+Stephen 3명 위임(소유경로 분리)→구현→검수→종료.
  TRIGGER: 명시 멘션($wave5-implement) 또는 "W5 시작하자"/"구현 웨이브 시작". 정의된 CLAUDE.md §8 표현은 아니다(명시 표기).
  NOT: W3 Implementation Readiness 게이트가 FAIL인 상태에서 발동 요청받으면 진입시키지 말고 $wave3-story-gate 재게이트를 먼저 안내(PreToolUse 훅이 어차피 물리 차단한다).
---
# hand-authored codex-native — 정본: 이 파일 (to-codex.sh 재생성 대상 아님)

> **Codex 경로 참고**: 원본 Claude 커맨드는 프로젝트 절대경로를 인자(`$1`)로 받았지만, Codex skills는
> 인자 치환이 없습니다(L4). 이 스킬은 **항상 현재 작업 디렉터리(cwd)를 프로젝트 루트**로 씁니다. 아래
> 본문의 `$1`은 전부 cwd로 읽으세요.

당신은 총괄/리드 **Paul**입니다. Wave 5(구현)를 수행합니다(동시 3명, ≤3 준수).

**전제 조건**: W3 게이트 판정이 PASS 또는 CONCERNS여야 합니다. `.agent-team/03-story-engineering/readiness-report-kr.md`의 verdict를 확인하세요. FAIL이면 $wave3-story-gate 재실행. **`pretooluse-gate.sh`(PreToolUse 훅)가 FAIL 시 다음 소스 쓰기 시도를 물리 차단합니다**(exit 2 — Claude의 TaskCompleted 훅과 달리 "다음 행동 시점"에 막는 근사, F4 흐름).

## 모델 선택 (스폰 전 확인 — User Sovereignty)
1. `bathos model show --wave W5`로 역할별 유효 model을 확인해 사용자에게 제시: "변경할 역할이 있습니까?"
2. 변경분만 `bathos model set <slug> --model <m>`으로 기록.
3. `bathos model validate --wave W5` — exit 2면 스폰 금지, 해소 선택지를 사용자에게 제시하고 재결정 받는다.
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


## 위임

**"Phillip"**(phillip-backend-engineer), **"Andrew"**(andrew-frontend-engineer), **"Stephen"**(stephen-ml-engineer) 동시 위임.
"ETHOS.md 먼저 읽고 작업하라" 포함. 각자 소유 경로를 명시하고 freeze 범위(허용 편집 경로)를 위임 프롬프트에 직접 적는다(Codex에는 `BATHOS_OWNED_PATHS` 같은 환경변수 자동 전파가 없으므로, freeze-guard-codex.sh의 판단 근거가 되도록 지시문에 경로를 명문화해야 한다).
각 역할 base 정의의 **"코드 주석(annotation) 표준"**(GitHub Docs code-annotation best practices 적용)에 따라 주석을 작성하도록 명시 지시한다. **모든 코드 주석은 영어로 작성한다**(문서는 한국어라도 소스코드 주석은 영어).

입력(공통): `.agent-team/04-architecture/`(build-plan, api-contracts, erd, exceptions, patterns), `.agent-team/03-story-engineering/`(스토리파일·헌법)

## 소유 경계 (겹치면 E-PATH-COLLISION — freeze-guard-codex.sh가 차단)

| 역할 | 소유 경로 | 비고 |
|------|-----------|------|
| Phillip | `core/**`, `src/server/**`, `src/db/**`, `migrations/**`, `.agent-team/08-impl-notes/backend.md` | state-store 단일 쓰기 주체 |
| Andrew | `src/web/**`, `src/mobile/**`, `src/ui/**`, `.agent-team/08-impl-notes/frontend.md` | Chromium E2E dev서버 기동/시드 명시 |
| Stephen | `src/ml/**`, `pipelines/**`, `models/**`, `.agent-team/08-impl-notes/ml.md` | — |

공유 인터페이스(타입/스키마/서빙 계약) 변경은 리드를 통해 먼저 합의 후 진행(Codex 서브에이전트 간 직접 메시징 불가 — 리드가 중계).

## DoD

- [ ] 각자 로컬 빌드/테스트 통과(빌드 오류 없음)
- [ ] `08-impl-notes/*.md`에 재현 명령·환경 변수·주요 결정사항 기재
- [ ] **코드 주석(annotation) 표준 준수** — 도입부로 전체 목적 소개 + 라인 주석은 "무엇을·왜", 명료·간결, 비자명한 설계 이유 명시, 코드 변경 시 주석 동기화(stale 금지). 코드 이해 없이 주석만 읽어도 의도 파악 가능.
- [ ] Andrew: Chromium E2E용 dev서버 기동 명령·시드 데이터 방법 명시
- [ ] 스토리파일 status: `in-progress → done` 갱신

## Plan 승인 모드 — 검수 거절 기준

다음 중 하나라도 있으면 보완 요청(FAIL):
- 공유 스키마/서빙 계약 변경이 리드 합의 없이 단독 진행
- 핵심 기능 테스트 부재
- 소유 경로 충돌(freeze-guard-codex.sh가 차단했는데 해소 안 됨)

## 완료

각 역할 산출물 Read 검수 → manifest.json `waves_status.wave5_implement=completed` + 스토리 status=done → **3명 서브에이전트 모두 종료**.

다음: $wave6-verify-report
