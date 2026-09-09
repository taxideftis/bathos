# BATHOS 사용 가이드 (v0.1.0)

> **BATHOS** — βάθος, 그리스어로 '깊이·심연'을 뜻한다. 표면을 훑는 지식의 정반대편에 서는 **압도적 깊이의 AI Workflow Agent 메서드 패키지**를 지향한다는 의미를 담았다.
> Claude Code라는 단일 런타임 위에서 **17역할 × 7웨이브 × Scale-Adaptive Lv0~4** 구조로 제품 개발의 전 과정을 오케스트레이션한다.
> 이 문서는 개념이 아니라 **실제로 빌드된 산출물(B1~B4)**을 기준으로 쓰였다. 아직 구현되지 않았거나 스텁 상태인 항목은 감추지 않고 그대로 밝힌다.
>
> **함께 보기:** 처음이라면 [활용 사례(새 서비스 만들기)](USECASE-kr.md)로 감을 잡고 → [특징·구동원리](FEATURES-kr.md)로 원리를 이해한 뒤 → (본 문서) 사용 가이드로 넘어오길 권한다. · English: [USECASE-en](USECASE-en.md) · [FEATURES-en](FEATURES-en.md) · Español: [`USAGE-es.md`](USAGE-es.md)

---

## Codex CLI 포팅 상태

이 문서는 아직 Claude Code 사용법을 정본으로 설명한다. Codex CLI 포팅은 별도
어댑터 레이어로 진행 중이며, 저장소에는 다음 자산이 추가됐다:

- `.agents/skills/**` — Codex skills 정본(`$route`, `$wave*`, `$save-session` 등).
- `.codex/agents/*.toml` — 17역할 Codex subagent 정의(Paul 제외).
- `.codex/hooks.json` + `codex-adapter/hooks/*.sh` — Codex project hooks
  (게이트, 저장, careful/freeze, resume 안내).
- `dist/codex-plugin/**` — Codex plugin 번들 후보.
- `bathos runtime` + `dist/lib/host-detect.sh` — 현재 호스트 런타임 감지.

현재 기준선은 **Codex CLI v0.145.0+**다. 단, 인증된 Codex 세션에서의 live
walkthrough(`story-20`)는 아직 릴리스 게이트로 남아 있다. 특히 hook wiring,
skills 호출, subagent model/agent_type 동작, plugin 활성화, `SessionEnd` 실제
발화 여부는 `codex-adapter/probe.sh`와 W6 검증에서 증명해야 한다. 상세는
[`docs/codex-adapter-kr.md`](codex-adapter-kr.md)를 본다.

---

## 0. 핵심 개념 — 두 개의 실행면을 구분하라

BATHOS를 제대로 쓰기 위해 먼저 짚어야 할 것은 딱 하나다. BATHOS는 성격이 전혀 다른 **두 개의 층**에서 동시에 돌아간다. 이 둘을 구분하는 순간, 나머지 사용법은 대부분 자연스럽게 풀린다.

| 층 | 정체 | 무엇을 하나 | 실행 주체 |
|----|------|------|-----------|
| **오케스트레이션 면** | Claude Code 슬래시 커맨드(`.claude/commands/*.md`) + 역할(`.claude/agents/`) + 훅(`.claude/hooks/`) | 웨이브를 진행시키고, 팀원을 스폰·검수·종료한다 | **리드(Paul) = 메인 Claude Code 세션** |
| **엔진 면** | `bathos` 단일 정적 바이너리(Rust) | 상태(SSOT)·게이트·웨이브 전이·라우팅·스토리·플러그를 **결정적으로** 계산하고 강제한다 | 훅/커맨드가 내부에서 `bathos <subcommand>`를 호출 |

> 정리하면, 당신이 손으로 입력하는 것은 대개 **슬래시 커맨드**(`/wave1-discovery` 같은)다. `bathos` 바이너리는 그 아래에서 **훅과 커맨드가 알아서 호출**하는 하부 엔진이다. 물론 필요하면 둘 다 직접 다룰 수 있다.

---

## 1. 요구사항 · 설치 · 타겟 프로젝트 연동

### 1.1 전제
- **Claude Code v2.1.32 이상**
- **Agent Teams 실험 기능 활성** — `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (패키지의 `bathos/.claude/settings.json`에 이미 설정돼 있다).
- **Rust 툴체인**(엔진 빌드용) — cargo 1.92.0에서 검증했다.

### 1.2 엔진 빌드
```bash
cd bathos/core
cargo build --release        # → target/release/bathos (단일 정적 바이너리, ~5.7MB)
cargo test                   # 전체 검증 (18 테스트 그룹)
cargo clippy --all-targets -- -D warnings   # 린트 (경고 0)
```
빌드 결과물 `bathos/core/target/release/bathos`를 PATH에 올려두거나, 훅이 참조할 수 있도록 `BATHOS_BIN` 환경변수로 경로를 지정한다(지정하지 않으면 기본 탐색 경로는 `core/target/debug/bathos`다).

### 1.3 타겟 프로젝트 연동 (설치·채택)

> **핵심:** BATHOS는 하나로 통째 돌아가는 앱이 아니라 **Claude Code 위에서 도는 메서드 패키지**다(§0의 두 실행면 참조). 그래서 여기서 "연동"이란 **① 엔진 바이너리를 미리 빌드해 두고, ② 오케스트레이션 자산(`.claude/`·`assets/`·`modules/`)을 대상 프로젝트에 심는 것**, 이 두 가지를 뜻한다.

#### 1.3.1 `install.sh` — 엔진 빌드 + `.claude/` 주입
`install.sh`가 하는 일은 두 가지다. 그리고 **아무것도 삭제하지 않는다.** 기존 `.claude/`가 이미 있으면 `--force` 없이는 덮어쓰기를 거부한다.

```bash
# A) 엔진만 빌드 (+ 다음 단계 안내 출력)
./install.sh

# B) 엔진 빌드 + 메서드 패키지를 타겟 프로젝트로 복사
./install.sh --into /abs/path/to/your-project
#   → your-project/ 안으로 .claude/  assets/  modules/  를 cp -R
```

이때 타겟 프로젝트로 복사되는 세 가지가 바로 프로젝트에 심기는 **"연동 자산"**이다:
- **`.claude/`** — 슬래시 커맨드 32종 + 역할 17개 base + 안전 훅 6종 + `settings.json`(Agent Teams 플래그 포함)
- **`assets/`** — W3 스토리엔진·플러그가 참조하는 템플릿/워크플로우/체크리스트
- **`modules/`** — 플러그 모듈(`ip-pack`, `research-pack`)

#### 1.3.2 엔진을 훅이 찾게 하기 (필수 환경변수)
복사된 훅들은 `bathos` 바이너리를 호출한다. 따라서 바이너리가 어디에 있는지 알려줘야 한다:

```bash
export BATHOS_BIN="/abs/path/to/bathos/core/target/release/bathos"
#   (지정하지 않으면 core/target/debug/bathos로 fallback — release를 권장)
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1   # settings.json에도 이미 설정돼 있음
```

#### 1.3.3 두 가지 채택 방식
| | 방식 A — BATHOS 레포를 작업 디렉터리로 | 방식 B — 내 프로젝트에 채택 |
|---|---|---|
| **동작** | `bathos/`에서 곧바로 Claude Code를 연다(`.claude/`가 이미 배선돼 있다) | `install.sh --into`로 `.claude/`·`assets/`·`modules/`를 복사한다 |
| **적합** | BATHOS 자체를 손보거나 빠르게 시험해 볼 때 | 실제 자기 제품 프로젝트에 적용할 때 |

### 1.4 타겟 프로젝트에 생기는 두 디렉터리 (중요)

연동을 마치면 타겟 프로젝트에는 **성격이 다른 두 경로**가 나란히 생긴다. 이 둘은 서로 섞이지 않는다:

```
your-project/
├── .claude/          ← (연동 자산) 커맨드·역할·훅·settings   ※install로 주입
├── .agent-team/      ← (런타임 산출) 팀 작업·산출 메타        ※/team-kickoff가 생성
│   ├── 00-plan/ ... 12-report/
│   └── _state/manifest.json   ← SSOT (전 상태 단일 JSON, 스키마 검증 + 감사 해시체인)
└── src/ ...          ← 당신의 실제 제품 소스코드 (통상 경로 그대로)
```

- **`.agent-team/`** 은 BATHOS가 만들어 내는 작업 산출물이다(기획·설계·스토리·리뷰·QA·리포트·상태).
- 반면 **실제 제품 코드는 `src/` 같은 평소 경로에 그대로** 쌓인다. BATHOS는 그 위에 얹히는 **"공정(工程)"**이라고 보면 된다.

> **한 줄 요약:** `install.sh --into <타겟>`으로 `.claude/`·`assets/`·`modules/`를 심고 → `BATHOS_BIN`과 Agent Teams 플래그를 설정한 뒤 → 타겟에서 Claude Code를 열어 `/team-kickoff` → `/route` → 웨이브 커맨드를 절대경로 인자와 함께 순서대로 실행한다. **산출물은 `.agent-team/`에, 실제 코드는 `src/`에 쌓이고, 핵심 불변식은 `bathos` Rust 엔진이 강제한다.**

### 1.5 패키지 구조
```
bathos/
├── core/                      # Rust 워크스페이스 (엔진)
│   ├── Cargo.toml             # 7 크레이트 워크스페이스
│   └── crates/
│       ├── bathos-state/      # M1 상태 SSOT (manifest.json·audit 체인)
│       ├── bathos-router/     # M2 Scale-Adaptive 라우터 (Lv0~4)
│       ├── bathos-wave-engine/# M3 7웨이브 전이 (동시≤3)
│       ├── bathos-gate-engine/# M4 게이트 판정 (PASS/CONCERNS/FAIL)
│       ├── bathos-story-engine/#M5 스토리 컴파일·staleness
│       ├── bathos-plug/       # M12 플러그 모듈 매니저
│       └── bathos-cli/        # bin: bathos
├── .claude/
│   ├── agents/_base/          # M8 17역할 base 정의 (00-paul ~ 17-matthew)
│   ├── commands/              # M7 슬래시 커맨드 32종
│   ├── hooks/                 # M6 안전·이벤트 훅 6종 + 테스트 하네스
│   └── settings.json          # 훅 바인딩 + Agent Teams 활성
├── assets/                    # M9 템플릿·워크플로우·체크리스트·용어집
├── modules/                   # 플러그 모듈 (W4)
│   ├── ip-pack/               # M10 특허 출원명세 모듈
│   └── research-pack/         # M11 논문 Abstract/Introduction 모듈
├── CLAUDE.md  ETHOS.md  README.md  VERSION
└── docs/USAGE-kr.md           # (본 문서)
```

---

## 2. 빠른 시작 (Quick Start)

대상 프로젝트 루트에서 Claude Code 세션(= 리드 Paul)을 연 다음, 슬래시 커맨드로 웨이브를 하나씩 진행하면 된다.

```
# 1) 킥오프 — .agent-team 골격 + charter + manifest 초기화
/team-kickoff

# 2) 작업 규모 라우팅 — stakes로 Lv0~4 추천받고 사용자가 확정
/route /절대/경로/프로젝트

# 3) 추천 레벨의 웨이브를 순서대로 진행 (예: Lv2~3)
/wave1-discovery   /절대/경로
/wave2-design      /절대/경로
/wave3-story-gate  /절대/경로     # ← 심장: Readiness Gate (PASS여야 W5 진입)
/wave5-implement   /절대/경로
/wave6-verify-report /절대/경로

# 4) (선택·비본류) IP/논문 플러그
/wave4-ip-research /절대/경로

# 5) 진행 점검 / 최종 확정
/team-status
/team-confirm
```

> **본류 의존성:** W0 → W1 → W2 → **W3** → W5 → W6. **W4(IP&연구)는 선택 플러그**이며 W2 이후라면 언제든 끼워 넣을 수 있다.
> 각 웨이브는 끝날 때 해당 팀원을 shutdown하고 다음 웨이브로 넘어간다(동시 활성 팀원은 3명 이하로 유지하기를 권장한다).

---

## 3. 7 웨이브 워크플로우

| 커맨드 | 웨이브 | 팀원(동시) | 게이트 |
|--------|--------|-----------|--------|
| `/team-kickoff` | (사전) | 리드 단독 | — |
| `/wave0-analysis` | **W0** Analysis(선택) | Caleb(Analyst 겸임) | Brief Readiness |
| `/wave1-discovery` | **W1** 디스커버리·시장 | John ∥ Caleb | USP Readiness |
| `/wave2-design` | **W2** 기획·아키텍처·디자인 | Joshua → (James, Jonnathan) | Plan Readiness |
| `/wave3-story-gate` | **W3** 스토리엔지니어링·게이트 ★ | Matthew(#17) + Thomas·Matthias(독립리뷰) + Timothy | **Implementation Readiness(이중)** |
| `/wave4-ip-research` | **W4** IP·연구(플러그) | Mark ∥ Nathanael | 없음 |
| `/wave5-implement` | **W5** 구현 | Phillip, Andrew, Stephen | 스토리 단위 완료 |
| `/wave6-verify-report` | **W6** 검증·문서·리포트 | (Thomas, Timothy, Matthias) → Michael → Hananiah → Martin | Release Readiness |
| `/team-confirm` | (사후) | 리드 단독 | — |

슬래시 커맨드는 저마다 **대상 프로젝트의 절대경로**(`$1`)를 인자로 받는다. 커맨드가 리드 세션에서 팀원을 스폰하고, 산출물을 검수하고, 게이트를 판정한 뒤 팀원을 종료하는 식이다. 팀원 사이의 인수인계는 오직 **디스크 파일**(`.agent-team/...`)로만 이뤄진다 — 대화 히스토리에 기대지 않는다.

### W3가 심장인 이유
설계(W2)와 구현(W5) 사이에는 늘 **컨텍스트가 새어 나가는 틈**이 있다. W3는 바로 이 틈을 정면에서 막는다. #17 Matthew가 W2의 산출을 그 자체로 완결된 **자족 dev 스토리파일**(9섹션, 모든 기술 세부에 `[Source:...]` 근거를 단다)로 응축하고, Thomas와 Matthias가 이를 독립적으로 검토한다. 판정이 **FAIL로 나오면 `gate-enforce` 훅이 W5 진입 자체를 물리적으로 차단한다**(§7).

---

## 4. Scale-Adaptive 라우팅 (Lv0~4)

작업의 규모에 맞춰 **가동할 웨이브와 역할을 명시적으로 조절한다**. 언제나 전부를 풀가동하지는 않는다는 뜻이다. `/route`에 stakes를 넣으면 추천 레벨이 나오고, **최종 결정은 사용자의 몫**이다(User Sovereignty). 현재 레벨은 `_state/manifest.json`의 `current_level`에 기록된다.

| Lv | 작업 유형 | 가동 웨이브 | #17 Matthew | W4 |
|----|----------|------------|:----:|:--:|
| **Lv0** | 버그수정·사소 변경 | W5만 (+초경량 W6) | ✗ | ✗ |
| **Lv1** | 소기능·국소 리팩터 | 경량 W2 + W3(축약) + W5 + 경량 W6 | ✓(축약) | ✗ |
| **Lv2** | 표준 기능/모듈 | W1 + W2 + W3 + W5 + W6 | ✓ | 선택 |
| **Lv3** | 신규 제품·대형 | W0~W6 (W4 선택) | ✓ | 선택(권장) |
| **Lv4** | 엔터프라이즈·딥테크·규제 | W0~W6 전체 + W4 풀 | ✓ | ✓ 필수 |

stakes를 레벨로 옮기는 추천 규칙은 `bathos-router`가 계산한다. stakes는 네 축으로 이뤄진다 — `scope`, `novelty`, `regulation_ip`, `team_size`. (매핑표는 `route.md` 커맨드 참조.)

---

## 5. 게이트 시스템 (PASS / CONCERNS / FAIL)

모든 웨이브 게이트는 **하나의 용어 체계**를 공유한다.

| 판정 | 의미 | 동작 |
|------|------|------|
| **PASS** | 기준 충족, 블로커 없음 | 다음 웨이브로 즉시 진입 |
| **CONCERNS** | 조건부 통과(차단성은 아닌 리스크) | `_state/`에 리스크를 로그하고 진행 |
| **FAIL** | 차단 결함 | 진입 차단, 보완 후 **재게이트** |

원칙은 분명하다. 게이트는 **판정을 돕는 FACILITATOR이지, 판정을 만들어 내는 generator가 아니다** — 근거 없는 자동 PASS는 허용하지 않는다. W3의 핵심 게이트는 훅으로 하드강제되며, 게이트 판정 주체(`facilitator`)는 결코 비어 있을 수 없다(불변식).

---

## 6. CLI 레퍼런스 (`bathos` 바이너리)

전역 옵션(모든 서브커맨드 공통):
- `-s, --state-dir <PATH>` — 상태 디렉터리 (기본 `./_state`)
- `--modules-dir <PATH>` — 플러그 모듈 디렉터리 (기본 `./modules`)
- `-h, --help` · `-V, --version`

**종료 코드 규약:** `0`=성공 · `1`=일반 오류 · `2`=게이트 FAIL(훅이 진입 차단에 사용).

### 6.1 `bathos state` — 상태 SSOT (B1)
```bash
bathos --state-dir .agent-team/_state state init \
       --codename MYPROJECT                            # 스키마 유효 manifest.json seed 생성
bathos --state-dir .agent-team/_state state validate   # manifest.json JSON Schema 검증 (VALID/위반목록)
bathos --state-dir .agent-team/_state state show        # 현재 상태 JSON 출력
```

`state init`은 기본 `level=0`, `lang=ko`, 자동 `project_id=bathos-<uuid>`로
최소 유효 상태를 만든다. 기존 manifest는 `--force` 없이는 덮어쓰지 않는다.
`/team-kickoff`가 이 명령을 호출하므로 일반 사용자는 직접 실행할 필요가 없다.

### 6.2 `bathos gate` — 게이트 판정 (B3)
```bash
# 판정 기록 — GATE_TYPE: Brief|Usp|Plan|Implementation|Release / VERDICT: PASS|CONCERNS|FAIL
bathos -s _state gate verdict Implementation PASS Matthew
bathos -s _state gate verdict Implementation FAIL Matthew \
       --issues-json '[{"level":"critical","description":"...","source":"..."}]'
#   → FAIL 기록 시 종료코드 2

# 최신 Implementation 게이트 조회 (gate-enforce.sh가 호출하는 SSOT)
bathos -s _state gate show
#   → {"gate_type":"Implementation","verdict":"PASS","issues_total":0,"issues_critical":0,...}
#   게이트 없음 → 빈 출력(exit 0)
```
- 옵션: `--report <경로>`, `--story-key <키>`, `--issues-json <JSON배열>`
- **이슈 level enum:** `critical` | `enhancement` | `optimization` (`critical`이 하나라도 있으면 FAIL).

### 6.3 `bathos story` — 스토리 검증 (B3)
```bash
# D1 완전성 + D2 출처추적 검증 (stdin 또는 --file)
bathos story compile 1-2-payment-auth --file story-1-2-kr.md
#   → {"is_valid":true,"missing_sections":[],...}  / 실패 시 exit 1 (E-CTX-LOSS)

# D3 신선도(staleness) — 저장된 hash vs 현재 상류파일
bathos story check-stale 1-2-payment-auth \
       --stored-hash <sha256> --upstream archi.md --upstream design.md
#   → fresh: "FRESH" exit 0 / stale: E-STALE exit 1
```

### 6.4 `bathos wave` / `bathos route` (B2)
```bash
bathos -s _state wave activate W2     # 웨이브를 active로 전이 (동시 활성 ≤3 강제, 초과 시 E-CONCURRENCY)
bathos -s _state wave show            # 모든 웨이브 상태 JSON
bathos -s _state route show           # 레벨 결정 이력

# stakes(JSON)로 레벨 추천 — stdin 또는 --stakes-json. 기본은 추천만(커밋 X).
echo '{"scope":"feature","novelty":true,"regulation_ip":false,"team_size":"medium"}' \
  | bathos -s _state route decide
#   → {"recommended_level":2,"wave_set":[...],"role_set":[...],"requires_confirmation":true}

# --confirm <0-4>: 사용자가 명시 확정 → manifest routing[] 기록 + current_level 갱신
bathos -s _state route decide \
  --stakes-json '{"scope":"product","novelty":true,"regulation_ip":true,"team_size":"large"}' --confirm 4
```
- `route decide`는 **추천과 확정을 일부러 분리한다**(User Sovereignty). 인자가 없으면 추천만 내놓고, `--confirm <레벨>`을 붙였을 때만 실제로 기록한다.
- stakes 4축: `scope`(bug|feature|module|product…) · `novelty`(bool) · `regulation_ip`(bool) · `team_size`(solo|medium|large).

### 6.5 `bathos plug` — 플러그 모듈 (B4)
```bash
bathos --modules-dir modules plug list              # 모듈 목록 + 활성 상태(JSON)
bathos -s _state --modules-dir modules plug enable ip      # 모듈 활성화(영속)
bathos -s _state --modules-dir modules plug disable ip     # 모듈 비활성화
#   존재하지 않는 모듈 → exit 1 (E-PLUG-NOTFOUND)
```

### 6.6 `bathos audit` — 감사 로그 (B-1)
```bash
# append: 단일 Rust writer 경유(bash 훅과 형식 통일). 항상 exit 0(훅 차단 방지).
bathos -s _state audit append --actor hook --action tool.write --target manifest.json

# verify: 감사 해시체인 무결성 검증 (tamper-evident 약속을 직접 확인)
bathos -s _state audit verify
#   → 무결: "OK — 감사 해시체인 무결 (N entries ...)" exit 0
#   → 변조/단절: "[E-AUDIT-TAMPER] ... seq=N hash_prev 불일치 ..." exit 1
```

### 6.7 `bathos doctor` — 설치·배선 프리플라이트 진단
```bash
bathos -s .agent-team/_state doctor --root .
#   점검: BATHOS_BIN · jq · Agent Teams 플래그 · settings.json hooks 주석키 함정 ·
#         훅 존재/실행권한 · assets·modules · manifest 스키마 · 감사 체인
#   → ✓//✗ 체크리스트 출력. 오류 0건이면 exit 0, 하나라도 있으면 exit 1.
```
- `install.sh` 직후 가장 먼저 한 번 돌려 보길 권한다. 특히 **settings.json의 `hooks` 블록에 주석키(`_note` 등)가 섞여 무한 대기를 일으키는 함정**을 결정적으로 잡아낸다(§13 트러블슈팅).
- `--root`는 `.claude/`·`assets/`·`modules/`를 찾는 기준 경로이고(기본은 현재 디렉터리), `-s`는 manifest와 감사 체인의 위치를 가리킨다.

---

## 7. 훅 / 안전계층 (M6)

`bathos/.claude/settings.json`이 Claude Code의 각 이벤트에 훅을 바인딩한다. 차단성을 가진 훅은 모두 **결정적이며 fail-safe**하게 설계돼 있다 — 애매하면 막는 쪽으로 기운다.

| 훅 | 이벤트 | 역할 | 차단(exit 2) 조건 |
|----|--------|------|-------------------|
| `careful-guard.sh` | PreToolUse(Bash) | 파괴적 명령 차단 | `rm -rf`·`DROP TABLE`·`git push --force` 등 |
| `freeze-guard.sh` | PreToolUse(Write/Edit/MultiEdit) | 편집 범위 잠금 | `BATHOS_OWNED_PATHS` 밖 편집 |
| `audit-log.sh` | PostToolUse | 감사 로그 append | (비차단) `_state/audit-log.jsonl` |
| `artifact-verify.sh` | TaskCompleted | 산출물 존재 검증 | QA/W3 태스크에 산출물 누락 시 |
| `gate-enforce.sh` | TaskCompleted | **W3 FAIL → W5 진입 물리 차단** | W5 진입 태스크 + W3 verdict=FAIL |
| `next-action.sh` | TeammateIdle | 다음 액션 안내 | (비차단) |

**`gate-enforce`가 도는 순서:** W5 진입 태스크를 감지하면 → `bathos gate show`로 최신 Implementation verdict를 조회하고 → 그 값이 `FAIL`이면 exit 2로 차단, `PASS`나 `CONCERNS`면 exit 0으로 통과시킨다. 바이너리나 게이트가 없을 때는 fail-safe 원칙에 따라 경고만 남기고 통과한다.

> **운영 주의:** `settings.json`의 `hooks` 블록에는 **유효한 훅 이벤트명만** 넣어야 한다. 주석 키(`_note` 등)를 섞으면 서브에이전트가 시작할 때 무한 대기에 빠진다.

훅 자체를 검증하려면: `bash .claude/hooks/_test-hooks.sh` (46개 결정성 테스트, 전건 PASS).

---

## 8. 17 역할 (M8)

base 정의는 `bathos/.claude/agents/_base/`에 있다. 오버라이드는 3계층(base→team→user)으로 이뤄지며, 스칼라 값은 덮어쓰고 배열은 append한다.

| # | 이름 | 역할 | 모델 | 웨이브 |
|---|------|------|------|--------|
| 0 | Paul | 총괄/리드/최종 confirm | Opus 4.8 | 전 웨이브(메인 세션) |
| 1 | John | Reverse Specialist | Opus 4.8 | W1 (+W0) |
| 2 | Caleb | 시장분석/USP (+W0 Analyst) | Opus 4.8 | W1 (+W0) |
| 3 | Joshua | 서비스 기획 | Opus 4.8 | W2(게이트) |
| 4 | James | SW·클라우드 아키텍트 | Opus 4.8 | W2 |
| 5 | Mark | IP Specialist(특허) | Opus 4.8 | W4(플러그) |
| 6 | Nathanael | 논문 Abstract/Intro | Sonnet 5 | W4(플러그) |
| 7 | Jonnathan | 수석 디자이너(UX/UI) | Opus 4.8 | W2 |
| 8 | Phillip | 백엔드·데이터 수석 | Sonnet 5 | W5 |
| 9 | Andrew | 프론트·모바일 수석 | Sonnet 5 | W5 |
| 10 | Stephen | AI/ML 수석 | Sonnet 5 | W5 |
| 11 | Timothy | 개발 정의 문서화 | Sonnet 5 | W6 (+W3) |
| 12 | Thomas | 코드 리뷰어 | Sonnet 5 | W6 (+W3 독립리뷰) |
| 13 | Michael | 보안 감사·하드닝(방어적 웹·사이버) | Sonnet 5 | W6 (Thomas 이후) |
| 14 | Hananiah | 리팩토링(동작보존) | Sonnet 5 | W6 (Michael 이후) |
| 15 | Matthias | QA/검증(E2E) | Sonnet 5 | W6 (+W3 독립리뷰) |
| 16 | Martin | 모니터링/HTML 리포트 | Sonnet 5 | W6(취합) |
| **17** | **Matthew** | **Scrum Master/Story Engineer** | Opus 4.8 | **W3 전용(평시 비가동)** |

> Paul은 팀원으로 스폰되지 않는 **메인 세션**이다. #17 Matthew는 **W3가 활성일 때만** 스폰되므로 평소에는 토큰을 전혀 쓰지 않는다. agent type 슬러그는 `matthew-story-engineer`.

---

## 9. 플러그 모듈 (W4 확장)

코어는 슬림하게 두고, 도메인 기능은 **플러그 모듈로 켜고 끈다.** 코어는 모듈의 존재를 알지 못한다 — 역방향 의존을 금지하기 때문이다(A9). 각 모듈은 `modules/<id>/module.yaml`로 자기 자신을 선언한다.

### 9.1 module.yaml 계약
```yaml
module_id: ip                      # ip | research | game | security ...
name: IP Pack
wave: W4
trigger: "Lv>=3 OR domain=ip"      # 자동 트리거 조건 (Lv 비교 + domain= , OR 결합)
enabled_default: false
provides:
  workflows: [patent-spec-draft]
  templates: [patent-spec]
outputs: ".agent-team/05-ip/"
evidence_trace: true               # 주장→[Source:] 근거 추적
```

### 9.2 기본 동봉 모듈
| 모듈 | id | 산출 | 워크플로우 |
|------|----|------|-----------|
| IP팩 (Mark) | `ip` | `.agent-team/05-ip/` | `patent-spec-draft` (특허청 포맷 출원명세) |
| 연구팩 (Nathanael) | `research` | `.agent-team/06-research/` | `abstract-introduction` (학술 Abstract+Intro) |

### 9.3 트리거 문법 (`bathos-plug`)
- `Lv>=N` `Lv>N` `Lv<=N` `Lv<N` `Lv=N` (N=0~4) · `domain=X` / `domain:X`
- ` OR `로 이으면 하나라도 참일 때 트리거된다. 해석할 수 없는 토큰은 `false`로 처리한다(보수적으로).

---

## 10. 자산 (M9, `assets/`)

W3 스토리엔진과 플러그가 참조하는, 한글로 일관되게 정리된 자산 모음이다.
- `templates/` — `story-template.md`, `project-context-template.md`, `readiness-report-template.md`, `session-snapshot-template.md`, `design-system-template.md`(디자인 토큰·컴포넌트 계약)
- `workflows/` — `create-story.md`(스토리 컴파일 절차), `check-implementation-readiness.md`(게이트 절차), `design-excellence.md`(탑티어 UI/UX 10단계)
- `checklists/` — `story-context-quality.md`(8대 치명실수 적대적 재검증), `design-quality.md`(디자인 품질 11차원 0~10 루브릭)
- `_index.md`, `_glossary-kr.md`(용어집)

---

## 11. 상태 모델 & 디렉터리 규약

### 11.1 SSOT — `_state/manifest.json`
프로젝트의 모든 상태가 단 하나의 JSON 안에 인라인된다(JSON Schema로 검증한다). 주요 필드는 다음과 같다:
`project_id`(`bathos-<uuid>`), `codename`, `current_level`(0~4), `status`(active|paused|done), `lang`, `created`, 그리고 1:N 배열들 — `routing[]`(LevelDecision), `waves[]`, `roles[]`, `tasks[]`, `gates[]`(GateVerdict), `risks[]`, `modules[]`(PlugModule), `artifacts[]`.
모든 쓰기는 **원자적 쓰기 + 감사 해시 체인**(`audit-log.jsonl`)으로 기록된다.

### 11.2 산출물 디렉터리 `.agent-team/`
```
00-plan/  00-analysis/  01-reverse/  02-market-analysis/  03-service-planning/
03-story-engineering/   04-architecture/  05-ip/  06-research/  07-design/
08-impl-notes/  09-docs/  10-review/  11-qa/  12-report/  _state/
```
**실제 제품 소스 코드**는 프로젝트 루트의 통상 경로(`src/` 등)에 그대로 두고, `.agent-team/`에는 팀의 작업·산출 메타만 쌓인다.

---

## 12. 운영 커맨드 & gstack 보강

- **팀:** `/team-kickoff` · `/team-status` · `/team-confirm` · `/team-cleanup`(긴급 정리)
- **세션 저장/복원:** `/save-session`(완전 저장) · `/cold-start`(새 세션 완전 복원). 짧은 별칭 `/save`·`/resume`, gstack 별칭 `/context-save`·`/context-restore`. §12.1 참조.
- **크로스-프로젝트 메모리:** `/project-handoff`(현 프로젝트를 `~/.bathos/registry/`에 증류) · `/recall`(관련된 이전 프로젝트의 컨텍스트를 새 프로젝트에서 회상). §12.1 참조.
- **안전:** `/guard`(careful+freeze 활성) · `/unfreeze`
- **plan 리뷰 게이트(W2 보강):** `/plan-ceo-review` · `/plan-design-review` · `/plan-eng-review` · `/plan-devex-review` · `/autoplan`(넷을 순차 실행)
- **기타:** `/review`(PR 리뷰) · `/investigate`(근본원인 디버깅) · `/cso`(OWASP+STRIDE 보안감사) · `/retro` · `/health` · `/context-save`·`/context-restore`

### 12.1 세션 저장 & 콜드스타트 (완전·무손실 인계)

실제 빌드는 여러 Claude Code 세션에 걸쳐 이어진다. 그런데 팀원들은 **리드의 대화 히스토리를 물려받지 않는다.** 그래서 BATHOS는 모든 것을 디스크에 영속시켜, 문맥이 전혀 없는 새 세션도 컨텍스트를 완전히 복원할 수 있게 한다. 정식 커맨드는 다음 둘이다(인자가 필요 없다 — 현재 프로젝트의 `.agent-team/_state`를 기본으로 쓴다):

**`/save-session` — 세션의 *모든* 정보를 저장한다.** 작업을 멈추기 전에 실행한다. 두 개의 산출물(+ 날짜별 아카이브)을 남긴다:

| 산출물 | 담는 것 |
|--------|---------|
| `_state/session-state.json` | 완전한 머신 SSOT — manifest 전체(`routing`·`waves`·`roles`·`tasks`·`gates`·`risks`·`modules`·`artifacts`)를 `bathos state show`로 덤프한 것. |
| `_state/SESSION-SNAPSHOT.md` | 사람이 읽는 서술 — 그중 **"★ 현재 상태"** 단락이 콜드스타트의 진입점이다(한 단락 요약 + 다음에 실행할 커맨드). |

여기에 더해 감사 체인 검증(`bathos audit verify`), 제품 코드의 git 상태, `.agent-team/` 인벤토리, 그리고 이번 세션의 결정 사항·진행 중이던 웨이브·재스폰 대상 팀원·남은 작업·다음 커맨드까지 함께 담는다.

**`/cold-start` — 새 세션에서 모든 것을 복원한다.** 문맥이 0인 새 세션에서 실행한다. `SESSION-SNAPSHOT.md` → `session-state.json` → `manifest.json` → `wave-log.md`/`signoff.md` 순으로 읽고, 세 상태원을 교차 확인해 드리프트가 없는지 살핀 뒤, 감사 무결성을 검증하고 나서 완전한 브리핑을 내놓는다: 프로젝트 정체성, 현재 레벨, 웨이브 상태와 게이트 판정, 이미 끝난 것, 진행 중이던 것, **다시 스폰해야 할 팀원**(해당 `/waveN-…` 커맨드로 — 산출물이 디스크에 남아 있어 손실이 없다), 남은 리스크, 그리고 **▶ 다음에 실행할 커맨드**. 이 과정은 읽기 전용이며, 다음 단계를 사용자 대신 자동으로 진행하지 않는다(User Sovereignty).

```text
# 세션 종료 시:
/save-session            # (또는 /save — 동일)

# 다음 세션 시작 시, 같은 프로젝트 디렉터리에서:
/cold-start              # (또는 /resume — 동일)
```

> **별칭 & 트리거.** `/save`=`/save-session`, `/resume`=`/cold-start`이며, `/context-save`·`/context-restore`는 gstack 별칭이다. 모두 같은 `_state`/SSOT를 공유한다. 자연어로도 동작한다: "세션 저장/저장/체크포인트" → 저장, "콜드스타트/이어서/재개/불러와" → 복원.
> **사용량 한도 노트.** 팀원이 갑자기 조용해지면 대개 크래시가 아니라 quota 한도에 걸린 것이다 — `/save-session`으로 저장하고 리셋을 기다린 뒤, `/cold-start`로 복원하고 웨이브를 다시 실행하면 된다. [`QUOTA-kr.md`](QUOTA-kr.md) 참조.

**크로스-프로젝트 메모리 (프로젝트를 가로지르는 warm cold-start).** 위 두 커맨드는 한 프로젝트 안에 한정된다. 프로젝트 *사이*를 넘어가야 하는 컨텍스트 — 재사용할 결정, 반복되는 패턴, 값비싸게 배운 교훈 — 은 전역 레지스트리 `~/.bathos/registry/`(`INDEX.md` + 프로젝트별 `<slug>.md` 카드)에 쌓인다:
- **`/project-handoff`** — 현 프로젝트를 레지스트리 카드로 증류한다. `/save-session`이 이 upsert를 자동으로 수행하므로, 저장할 때마다 메모리가 자연스럽게 쌓인다.
- **`/recall`** — 새 프로젝트에서 관련 있는 이전 프로젝트 카드(재사용할 결정·패턴 + 피해야 할 교훈)를 끌어와 **warm-start**한다. `/cold-start`도 레지스트리를 함께 참조한다.

즉 **다른 프로젝트, 다른 세션이더라도** 이전 프로젝트에서 배운 것을 깊이 있게 재사용한다. 다만 회상은 어디까지나 제안이다(User Sovereignty) — 이 프로젝트의 방향은 사용자가 정한다.

### gstack 3원칙 (ETHOS.md)
1. **User Sovereignty(최상위):** AI는 제안하고, **결정은 사용자가 한다.** 방향을 바꾸는 권고는 "추천 + 근거 + 놓친 맥락"의 형태로 묻는다.
2. **Boil the Ocean:** 완전한 구현이 몇 분 더 드는 정도라면, 완전한 쪽을 택한다. 테스트와 엣지케이스를 나중으로 미루지 않는다.
3. **Search Before Building:** 익숙하지 않은 영역은 먼저 검색해 지형부터 파악한다.

---

## 13. 트러블슈팅 (실전 교훈)

| 증상 | 원인 | 해결 |
|------|------|------|
| 서브에이전트 시작 시 무한 대기 | `settings.json` `hooks` 블록에 주석 키가 섞임 | 유효한 이벤트명만 남긴다 · **`bathos doctor`로 탐지**(§6.7) |
| 팀원이 아무 출력 없이 멈춘 듯 | Claude 계정 **사용량(session) 한도** — 코드 버그가 아니다 | 리셋을 기다린 뒤 재스폰(산출물은 디스크에 남아 무손실). 상세: [`QUOTA-kr.md`](QUOTA-kr.md) |
| 설치·배선이 맞는지 확신이 서지 않음 | — | **`bathos doctor`** 실행(§6.7) |
| `state validate`가 정상 manifest를 거부 | 구 스키마(운영용)와 bathos-product 스키마를 혼동 | bathos manifest 스키마(§11.1)를 사용 |
| `gate verdict ... noncritical` 파싱 실패 | 이슈 level enum 오류 | `critical`/`enhancement`/`optimization`을 사용 |
| 다중 프로젝트를 동시에 운영할 때 역할명 충돌 | 같은 agent type/name이 swarm 레지스트리에서 충돌 | 프로젝트별 고유 접미사를 붙이거나 단독으로 운영 |
| 팀원 shutdown에 응답이 없음 | TeammateIdle 훅이 재기동 | `tmux -L claude-swarm-<pid> kill-pane -t <id>`(작업물은 디스크에 보존됨) |
| `gate-enforce`가 차단하지 않음 | 훅 입력 필드 불일치(`.title`/`.description`) 또는 게이트 미기록 | 입력 형태와 `bathos gate show` 출력을 확인 |

---

## 14. 현재 구현 상태 & 한계 (정직성 고지)

**v0.1.0 — 이른 단계지만, 실제로 동작한다.** BATHOS는 오늘 end-to-end로 빌드되고 돌아간다. 채택을 고민하는 이들에게 정직하게 밝혀 둔다:

- 이것은 **독립 실행 앱이 아니라 Claude Code v2.1.32+ 위에서 도는 메서드 패키지**이며, **실험 기능인 Agent Teams**에 의존한다.
- **엔진은 검증됐다:** **Rust 테스트 257개 + 훅 결정성 46개가 전부 그린**, `clippy -D warnings` 클린, `cargo build --release` 재현 성공, 게이트 하드강제와 플러그 통합을 end-to-end로 확인했고, 코어의 모듈 비의존(A9)도 증명했다.
- **완전 독립 인증을 마쳤다(dogfooding):** BATHOS는 W6 독립 검증을 자기 자신의 코드에 그대로 적용했다. **ThomasCert(독립 코드 리뷰, PASS)와 MatthiasCert(독립 QA/E2E, PASS)** 두 인증이 모두 통과해 **Release Readiness = PASS(완전 독립 인증)**에 도달했다. 흥미로운 대목은, 기능 QA는 그린이었는데도 독립 코드리뷰가 **저자 스스로는 놓쳤던 차단성 불변식 결함**을 잡아냈다는 점이다 — Rust 엔진과 bash 훅이 같은 감사 체인에 서로 호환되지 않는 형식으로 기록해 tamper-evidence를 무력화하는 문제였다. 이는 보완·재게이트·백로그 소진을 거쳐 전건 해소됐다. 검증 trail: `.agent-team/`(`10-review/`·`11-qa/`·`12-report/w6-final-certification.html`·`_state/signoff.md`).
- 일부 웨이브 커맨드는 완전 자동화된 엔진 플로우가 아니라, **리드가 직접 돌리는 오케스트레이션 프롬프트**(팀원 스폰·검수)다.
- **아직 production-hardened 단계는 아니다** — 1.0 이전까지 API·스키마·커맨드명이 바뀔 수 있다.

> **방법론이 말하는 명제:** 위 dogfooding이 증명한 핵심은 **"생성 ≠ 검증"**이다. 같은 모델이 쓰고 스스로 승인하면 반드시 사각이 남는다. 그래서 BATHOS는 저자와 검증자를 분리하고, 게이트를 FACILITATOR로 세우며, 핵심 불변식을 Rust 엔진으로 못 박는다.

---

## 15. 라이선스

BATHOS는 BMAD-METHOD(MIT © 2025 BMad Code, LLC)를 정밀 역분석한 뒤 제1원리에서 독립 구현한 패키지로, 그 근간이 된 선행 작업에 경의를 표하며 **MIT License**로 배포한다. "BMAD"/"BMad Method" 등 원저작사의 상표는 제품명이나 마케팅에 사용하지 않는다. (전문은 `README.md` 참조.)

---

*문서 버전: v0.1.0 · 작성: 리드 Paul · 기준: 실제 빌드 산출물(B1~B4).*
[USAGE-en](USAGE-en.md) · [USAGE-es](USAGE-es.md)
