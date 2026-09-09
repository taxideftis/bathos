---
description: "BATHOS W5 — Phillip+Andrew+Stephen 3명 스폰(소유경로 분리)→구현→검수→shutdown"
argument-hint: "[대상 프로젝트 절대경로]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task
model: sonnet
---
당신은 총괄/리드 **Paul** 입니다. Wave 5(구현)를 수행합니다(동시 3명, ≤3 준수).

**전제 조건**: W3 게이트 판정이 PASS 또는 CONCERNS여야 합니다. `$1/.agent-team/03-story-engineering/readiness-report-kr.md`의 verdict를 확인하세요. FAIL이면 `/wave3-story-gate $1` 재실행. `TaskCompleted gate-enforce.sh` 훅이 FAIL 시 물리 차단합니다.

---

## 모델 선택 (스폰 전 필수 — User Sovereignty)

1. `./core/target/release/bathos -s $1/.agent-team/_state model detect` 실행(session_backend 기록).
2. `bathos model show --wave W5`로 역할별 유효 runtime/model 표를 사용자에게 제시하고 묻는다:
   "이번 웨이브 역할별 모델입니다. 변경할 역할이 있습니까? (풀: Claude fable5·sonnet5·haiku / env 스왑: GLM·Kimi·DeepSeek·Qwen / Codex: GPT 경로 — 기본값 유지 가능. 웨이브 단위 지정·전환 절차는 `/model-config`)"
3. 변경분만 `bathos model set <slug> --runtime <r> [--model <m>]`으로 기록.
4. `bathos model validate --wave W5` — exit 2면 스폰 금지: 출력된 해소 선택지를
   사용자에게 제시하고 재결정 받는다(자동 우회 금지).
5. 스폰 분기: runtime=claude → 팀원 스폰 시 resolve된 model 지정 ·
   runtime=codex → 해당 역할은 팀원으로 스폰하지 않고 `codex-adapter/run-role.sh` 위임 ·
   runtime=glm → validate가 PASS를 준 경우에만(=전 배치 GLM 세션) 통상 스폰.

## 스폰

**"Phillip"**(phillip-backend-engineer), **"Andrew"**(andrew-frontend-engineer), **"Stephen"**(stephen-ml-engineer) 동시 스폰.
"ETHOS.md 먼저 읽고 작업하라" 지시. 각자 소유 경로를 명시하고 `BATHOS_OWNED_PATHS` 설정.
각 역할 base 정의의 **"코드 주석(annotation) 표준"**(GitHub Docs code-annotation best practices 적용)에 따라 주석을 작성하도록 명시 지시한다. **모든 코드 주석은 영어로 작성한다**(문서는 한국어라도 소스코드 주석은 영어).

### 구현 규율 주입 (사다리 — 필수)

스폰 프롬프트에 다음 두 가지를 **반드시** 포함한다:

1. **규율 문서 경로** — `.claude/agents/_preamble/ponytail-inject-kr.md`(정본)를 먼저 읽고 그 규율에
   따라 구현하라고 지시. 팀원 언어 설정에 따라 `-en`/`-ja`/`-es` 보조 번역본을 대신 지정할 수 있다.
2. **현재 intensity 값** — 스폰 전에 읽어서 프롬프트에 명시한다:
   ```bash
   jq -r '.intensity // "full"' "$1/.agent-team/_state/session-flags.json" 2>/dev/null || echo full
   ```
   변경이 필요하면 사용자에게 묻고 `/bathos intensity <lite|full|ultra|off>`로 조정한다(자동 변경 금지).

> **축 분리(필수 이해):** 사다리는 **무엇을 만들지**(스코프·추상화·의존성)를, ETHOS "Boil the Ocean"은
> **정한 범위를 얼마나 완전히**(에러 경로·엣지·테스트)를 지배한다. 사다리를 근거로 검증·에러 처리·
> 보안·테스트를 잘라내는 것은 **규율 위반**이다. 상세: 규율 문서 §0.

> 🖥️ **패널 관측**: 별도 터미널에서 `bathos panes`(tmux/TUI 중 선택) — 패널 입력은
> `_state/panes/inbox/`로 들어오며 게이트 체크포인트에서 반영된다(자동 기동 안 함 —
> Paul은 자기 TTY를 점유 중이므로 패널은 사람의 두 번째 터미널이다).

입력(공통): `$1/.agent-team/04-architecture/`(build-plan, api-contracts, erd, exceptions, patterns), `$1/.agent-team/03-story-engineering/`(스토리파일·헌법)

---

## 소유 경계 (겹치면 E-PATH-COLLISION — freeze 훅이 차단)

| 역할 | 소유 경로 | 비고 |
|------|-----------|------|
| Phillip | `$1/core/**`, `$1/src/server/**`, `$1/src/db/**`, `$1/migrations/**`, `.agent-team/08-impl-notes/backend.md` | state-store 단일 쓰기 주체 |
| Andrew | `$1/src/web/**`, `$1/src/mobile/**`, `$1/src/ui/**`, `.agent-team/08-impl-notes/frontend.md` | Chromium E2E dev서버 기동/시드 명시 |
| Stephen | `$1/src/ml/**`, `$1/pipelines/**`, `$1/models/**`, `.agent-team/08-impl-notes/ml.md` | — |

공유 인터페이스(타입/스키마/서빙 계약) 변경은 메시지로 먼저 합의 후 진행.

---

## DoD

- [ ] 각자 로컬 빌드/테스트 통과(빌드 오류 없음)
- [ ] `08-impl-notes/*.md`에 재현 명령·환경 변수·주요 결정사항 기재
- [ ] **코드 주석(annotation) 표준 준수** — 도입부로 전체 목적 소개 + 라인 주석은 "무엇을·왜", 명료·간결, 비자명한 설계 이유 명시, 코드 변경 시 주석 동기화(stale 금지). 코드 이해 없이 주석만 읽어도 의도 파악 가능. (근거: 각 역할 base 정의의 "코드 주석 표준")
- [ ] Andrew: Chromium E2E용 dev서버 기동 명령·시드 데이터 방법 명시
- [ ] 스토리파일 status: `in-progress → done` 갱신
- [ ] **구현 규율(사다리) 준수** — 요청받지 않은 추상화·"나중을 위한" 스캐폴딩 없음. 새 의존성을
      추가했다면 `08-impl-notes/`에 사다리 5단을 못 넘은 이유를 한 줄로 남겼는가.
- [ ] **의도적 단순화에 `ponytail:` 마커** — 알려진 천장이 있는 단순화마다
      `ponytail: <ceiling>, <upgrade path>`(영어)를 남겼는가. 업그레이드 트리거가 없는 마커는
      `/bathos-debt`에서 `no-trigger`로 잡히므로 트리거를 반드시 포함.
- [ ] **비자명 로직에 실행 가능한 검증 1개** — 분기·루프·파서·금액/보안 경로에 `assert` 자체검증이나
      작은 테스트 하나. (자명한 한 줄은 면제 — YAGNI는 테스트에도 적용)

---

## Plan 승인 모드 — 검수 거절 기준

다음 중 하나라도 있으면 보완 요청(FAIL):
- 공유 스키마/서빙 계약 변경이 메시지 합의 없이 단독 진행
- 핵심 기능 테스트 부재
- 소유 경로 충돌(freeze 훅이 차단했는데 해소 안 됨)
- **요청받지 않은 추상화** — 구현체가 하나뿐인 인터페이스, 산출물이 하나뿐인 팩토리, 아무도 바꾸지
  않는 값을 위한 설정. (규율 §3)
- **사다리를 근거로 잘라낸 검증·에러 처리·보안·접근성** — 축 오용이므로 무조건 FAIL. (규율 §0·§4)
- **천장 있는 단순화에 `ponytail:` 마커 누락** 또는 업그레이드 트리거 없는 마커 방치. (규율 §5)

---

## 완료

각 역할 산출물 Read 검수 → manifest.json `waves_status.wave5_implement=completed` + 스토리 status=done → **3명 모두 shutdown**.

> 🔧 **bathos CLI**: `bathos wave transition --from W5 --to W6` (B2 구현 예정).

다음: `/wave6-verify-report $1`
