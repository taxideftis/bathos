# BATHOS — 특징 & 구동원리

> **βάθος**(그리스어) — *"깊이·심연."* 표층적 AI 보조와 의도적으로 대비되는, 압도적 깊이의 AI Workflow Agent 메서드.
>
> 사용 가이드와 짝을 이루는 "왜, 그리고 어떻게" 문서라고 생각하면 된다. **BATHOS가 무엇이고(특징), 내부에서 실제로 어떻게 동작하는지(구동원리)** 를 풀어 설명한다. 전부 **실제 v0.4.0 빌드 기준**으로 썼다. 아래 메커니즘은 하나같이 구현·검증된 것이고, 한계가 있는 대목은 감추지 않고 그대로 밝힌다.
>
> **함께 보기:** 이해보다 실행이 먼저라면 [사용 가이드](USAGE-kr.md)로 가면 된다. 운영 규칙은 [`../CLAUDE.md`](../CLAUDE.md), 그 바탕이 되는 원칙은 [`../ETHOS.md`](../ETHOS.md)에서 볼 수 있다. · English: [`FEATURES-en.md`](FEATURES-en.md) · Español: [`FEATURES-es.md`](FEATURES-es.md)

---

## 0. 모든 것의 바탕이 되는 한 가지 생각

긴 단일 LLM 대화는 **표류(drift)** 한다: "설계"와 "구현" 사이에서 컨텍스트가 유실되고, 품질 점검은 생략되며, *같은 모델*이 작업을 쓰고 또 스스로 승인한다. BATHOS의 명제는 한 문장이다:

> **생성 ≠ 검증.** 생성자는 자기 산출물의 사각(blind spot)을 보지 못한다.

그래서 BATHOS는 표류하는 한 대화를 **구조**로 대체한다: 분리된 전문 역할, 단계화된 파이프라인, *독립적인* 검증자, 그리고 핵심 불변식을 모델의 선의가 아니라 **코드로 강제**하는 작은 **결정적 엔진**.

이것은 비유가 아니라 BATHOS가 실제로 만들어진 방식 그 자체다. BATHOS는 자기 자신을 구현한 뒤, 자기 코드에 Wave 6 독립 검증을 직접 돌렸다. 기능 QA는 그린이었지만, 독립 코드 리뷰가 **저자가 놓친 차단성 불변식 결함**을 잡아냈다(Rust 엔진과 bash 훅이 같은 감사 체인에 *비호환* 형식으로 기록 → tamper-evidence가 조용히 무력화). 이를 보완·재게이트하고 백로그를 소진했다 — 명제의 실증이다.

---

## 1. 특징 (BATHOS를 차별화하는 것)

메커니즘으로 들어가기 전에 큰 그림부터 보자. 열두 가지 특징이 각각 실제로 무엇을 주는지 정리했다.

| # | 특징 | 무엇을 주는가 |
|---|------|---------------|
| 1 | **17 전문 역할 × 7 웨이브 파이프라인** | 단일 Claude Code 세션이 점점 비대해지는 한 대화가 아니라 절제된 제품 팀(디스커버리 → 설계 → 스토리 → 빌드 → 검증)처럼 동작한다. |
| 2 | **두 실행면: 마크다운 오케스트레이션 + Rust 엔진** | 사람이 보는 워크플로우는 편집 가능한 마크다운으로 두고, 핵심 불변식은 단일 정적 바이너리가 결정적으로 계산·*강제*한다. |
| 3 | **Scale-Adaptive 라우팅 (Lv0–4)** | 작업에 실제로 필요한 웨이브만 가동한다. 버그 수정을 풀 디스커버리에 욱여넣지 않고, 엔터프라이즈 빌드를 과소 스코핑하지 않는다. |
| 4 | **Zero-Context-Loss 스토리파일 (Wave 3)** | 모든 기술 세부에 `[Source: …]`를 붙인 자족 dev 스토리파일로 설계→구현 컨텍스트 갭을 정면 차단한다. |
| 5 | **하드 품질 게이트 (PASS / CONCERNS / FAIL)** | Readiness 게이트의 `FAIL`은 권고가 아니라 훅(exit code 2)으로 구현 진입을 *물리적으로 차단*한다. |
| 6 | **독립 검증 + tamper-evident 감사 체인** | 검증자는 저자와 분리되며, 모든 상태 변경은 append-only sha256 해시 체인에 기록된다. |
| 7 | **User Sovereignty(사용자 주권)** | AI는 제안하고 *사용자가* 결정한다. 사용자의 명시된 방향을 바꾸는 권고는 "추천 + 근거 + 놓친 맥락"으로 제시하며 절대 먼저 실행하지 않는다. |
| 8 | **안전 훅 (careful / freeze)** | 파괴적 명령을 차단하고, 편집을 소유 경로로 잠근다. fail-safe 설계(의심 시 차단). |
| 9 | **플러그 모듈 (슬림 코어, 도메인 opt-in)** | IP/특허·연구 팩은 플러그이며, 코어는 모듈을 모른다(역의존 금지). 새 도메인은 코어를 비대하게 만들지 않고 꽂힌다. |
| 10 | **3계층 역할 오버라이드** | 역할 정체성은 base 계층에 고정되고, 프로젝트·사용자가 소유 경로/언어/facilitation 수위를 포크 없이 덮어쓴다. |
| 11 | **한 단어 세션 저장/재개** | `/save`가 세션 전체를 스냅샷하고 `/resume`이 다음 세션에서 복원한다. 자연어("저장"/"이어서")로도 동작 → 여러 세션에 걸친 작업도 컨텍스트를 잃지 않는다. |
| 12 | **크로스-프로젝트 메모리** | 전역 레지스트리(`~/.bathos/registry/`)로 완전히 새 프로젝트도 이전 프로젝트들의 결정·패턴·교훈에서 warm-start — 통했던 것은 재사용하고, 아프게 배운 것은 다시 겪지 않는다. |

---

## 2. 구동원리 (실제로 어떻게 동작하는가)

### 2.1 두 실행면

가장 먼저 이해해야 할 핵심 메커니즘이다.

| 면 | 정체 | 책임 | 실행 주체 |
|----|------|------|-----------|
| **오케스트레이션** | `.claude/` 아래 마크다운 **슬래시 커맨드**·**역할 정의**·**bash 훅** | 웨이브 진행, 팀원 스폰·검수·종료, 사람과의 대화 | **리드(Paul)** — 메인 Claude Code 세션 |
| **엔진** | 단일 정적 Rust 바이너리 **`bathos`** (~5.6MB, 7 크레이트) | 상태·라우팅·웨이브 전이·게이트·스토리 신선도·플러그·감사 체인을 계산·*강제* | 훅/커맨드가 `bathos <subcommand>`로 호출(직접도 가능) |

사람은 슬래시 커맨드를 타이핑한다. `bathos` 바이너리는 그 밑에서 커맨드·훅이 부르는 결정적 코어다. 이 분리가 핵심이다: **신뢰·재현 가능해야 하는 것**(게이트가 정말 통과했나? 활성 역할이 ≤3인가? 감사 체인이 무결한가?)은 엔진에 두어 단위 테스트로 보장하며, 설득력 있는 모델이 "말로 우회"할 수 없게 한다.

### 2.2 상태 모델 — 단일 진실 원천 (`bathos-state`)

엔진이 신뢰 가능한 절반이라면, 그 신뢰가 닻을 내리는 곳이 바로 여기다. 전 프로젝트 상태가 단일 JSON 파일 `<state-dir>/manifest.json`(기본 `./_state`)에 인라인되고 JSON Schema로 검증된다. 주요 필드:

- `project_id`(`bathos-<uuid>`), `codename`, `current_level`(0–4), `status`(active|paused|done), `lang`, `created`
- 1:N 배열: `routing[]`(레벨 결정), `waves[]`, `roles[]`, `tasks[]`, `gates[]`, `risks[]`, `modules[]`, `artifacts[]`

상태를 신뢰 가능하게 만드는 두 불변식:

1. **원자적 쓰기** — manifest는 절반만 쓰인 상태로 남지 않는다.
2. **Tamper-evident 감사 체인**(`audit-log.jsonl`) — 모든 변경은 append-only **sha256 해시 체인**에 항목을 추가한다:
   - 각 항목은 `hash_prev`(이전 항목의 `hash_self`)와 `hash_self`(자신을 `hash_self` 빈 상태로 직렬화한 sha256 — 순환 해시 방지)를 저장한다.
   - 불변식: `seq` 단조 증가; `hash_prev[n] == hash_self[n-1]`; 첫 항목의 `hash_prev == "genesis"`.
   - 단일 writer(`bathos audit append`)가 모든 훅을 블로킹 파일락으로 직렬화하므로 동시 append가 체인을 오염시킬 수 없다. *(이것이 바로 dogfooding 리뷰가 잡아낸 그 불변식 — Rust와 bash가 비호환 형식으로 쓰던 것을 단일화했다.)*

체인 단절은 `E-AUDIT-TAMPER`, 스키마 위반은 `E-STATE-CORRUPT`로 검출된다.

### 2.3 Scale-Adaptive 라우터 (`bathos-router`)

라우터는 네 "stakes" 축을 추천 레벨로 변환한다. 점수 산정은 완전히 결정적이다:

| 축 | 입력 | 점수 |
|----|------|------|
| `scope` | bug/fix/hotfix/trivial/small | 0 |
| | feature/medium *(또는 불명확)* | 1 |
| | large/big/module/component | 2 |
| | enterprise/platform/product | 3 |
| `novelty` | true | +1 |
| `regulation_ip` | true | +2 *(강한 상향 신호)* |
| `team_size` | solo/single/small | 0 |
| | medium/mid | 1 |
| | large/big/enterprise | 2 |

합계 → 레벨 매핑: **0 → Lv0 · 1 → Lv1 · 2–3 → Lv2 · 4–5 → Lv3 · 6+ → Lv4.**

| Lv | 작업 유형 | 가동 웨이브 | #17 | W4 |
|----|----------|------------|:---:|:--:|
| 0 | 버그수정·사소 | W5 (+초경량 W6) | ✗ | ✗ |
| 1 | 소기능·국소 리팩터 | 경량 W2 + W3(축약) + W5 + 경량 W6 | ✓ | ✗ |
| 2 | 표준 기능/모듈 | W1 + W2 + W3 + W5 + W6 | ✓ | 선택 |
| 3 | 신규 제품·대형 | W0–W6 (W4 선택) | ✓ | 권장 |
| 4 | 엔터프라이즈·딥테크·규제 | W0–W6 전체 + W4 | ✓ | 필수 |

핵심은 **추천과 확정의 분리**(User Sovereignty): `route decide`는 추천만 하고(`requires_confirmation: true`), 사용자가 `--confirm <0–4>`를 줄 때만 레벨이 기록된다. 확정 레벨이 추천과 다르면 엔진은 `modify` verdict를 기록하고 웨이브/역할 세트를 재계산한다. 이후 레벨이 바뀌면 `E-LEVEL-DRIFT`로 잡아 사용자에게 다시 묻는다.

### 2.4 웨이브 엔진 (`bathos-wave-engine`)

파이프라인은 7웨이브 상태기계다: **W0 → W1 → W2 → W3 → W5 → W6**, **W4(IP·연구)** 는 W2 이후 언제든 실행 가능한 선택 플러그다.

```
(사전) 킥오프 → W0 분석 → W1 디스커버리 → W2 설계
        → W3 스토리 게이트 ★ → W5 구현 → W6 검증 → (사후) 확정
                                  ↑
                       W4 IP & 연구  (선택 플러그)
```

각 웨이브는 상태 전이를 거친다(예: `active → gated → …`). 두 하드 규칙:

- **동시성 ≤ 3.** `MAX_CONCURRENT_ROLES = 3`; `spawn_role()`은 한 웨이브에서 4번째 활성 역할을 `E-CONCURRENCY`로 거부한다. (토큰 비용은 활성 팀원 수에 선형 비례하므로, 웨이브는 필요한 인원만 가동한다.)
- **웨이브 종료 → 해당 팀원 shutdown → 다음 웨이브.** 인수인계는 전부 `.agent-team/` 디스크 산출물로만 이뤄지며, 팀원은 리드의 대화 히스토리를 물려받지 않는다.

### 2.5 게이트 엔진 (`bathos-gate-engine`)

모든 웨이브 게이트는 단일 용어와 단일 결정적 규칙을 쓴다:

| 판정 | 규칙 | 효과 |
|------|------|------|
| **PASS** | 이슈 없음 | 다음 웨이브 진입 |
| **CONCERNS** | 비차단 이슈만 존재 | `_state/`에 리스크 로그 후 진행 |
| **FAIL** | `issues_critical > 0` | 진입 차단; 보완 후 재게이트 |

이슈 레벨은 `critical | enhancement | optimization`이며, **`critical` 이슈가 하나라도 있으면 FAIL.** 게이트는 **FACILITATOR이지 generator가 아니다** — 판정의 `facilitator`(누가 결정했는지)는 비어 있을 수 없으므로 근거 없는 자동 PASS가 불가능하다. 엔진은 또한 게이트 이력에서 *연속* FAIL을 카운트(`take_while(Fail)`)해 재게이트 사이클을 추적한다. 최신 판정의 진실 원천은 `bathos gate show`.

### 2.6 스토리 엔진 — Zero-Context-Loss (`bathos-story-engine`)

Wave 3가 심장이다: 상류 설계(W2)를 **자족 dev 스토리파일**로 응축해 구현자가 스토리만 보고 착수하게 한다. 엔진은 세 차원을 강제한다:

- **D1 완전성** — 6개 필수 섹션이 존재해야 한다: `story_requirements`, `developer_context`, `architecture_compliance`, `library_framework_requirements`, `file_structure_requirements`, `testing_requirements`. 추가로 `developer_context`는 비어 있으면 안 된다. 누락·공백 섹션은 `E-CTX-LOSS`로 컴파일에 실패한다. *(마크다운 템플릿은 스토리·인수기준·작업·Dev Notes·Dev Agent Record 등 더 많은 섹션을 담지만, 이 6개가 기계가 강제하는 최소치다.)*
- **D2 추적성** — 기술 주장에 `[Source:` 마커를 붙여 각 세부를 상류 산출물로 연결한다.
- **D3 신선도(staleness)** — `story check-stale`이 저장된 sha256과 현재 상류 파일을 비교; 상류가 바뀌었으면 스토리는 `E-STALE`이며 재컴파일해야 한다. W2와 W5 사이의 조용한 설계 표류를 막는다.

### 2.7 플러그 매니저 (`bathos-plug`)

도메인 기능은 `modules/` 아래 opt-in 플러그이며, **코어는 모듈을 모른다**(불변식 A9 — 의존 그래프로 증명). 각 모듈은 `module.yaml`로 자기를 선언한다:

```yaml
module_id: ip                    # ip | research | game | security ...
name: IP Pack
wave: W4
trigger: "Lv>=3 OR domain=ip"    # 자동 트리거 조건
enabled_default: false
provides:
  workflows: [patent-spec-draft]
  templates: [patent-spec]
outputs: ".agent-team/05-ip/"
evidence_trace: true
```

트리거 DSL은 `Lv>=N`/`Lv>N`/`Lv<=N`/`Lv<N`/`Lv=N`(N=0–4)과 `domain=X`를 ` OR `로 결합하며, 해석 불가 토큰은 보수적으로 `false`로 처리한다. 토글(`plug enable`/`disable`)은 `manifest.modules[]`에 영속된다. 없는 모듈은 `E-PLUG-NOTFOUND`. 기본 동봉: **ip-pack**(특허 출원명세) · **research-pack**(학술 Abstract/Introduction).

### 2.8 안전 훅 — 강제가 Claude Code와 만나는 지점 (`.claude/settings.json`)

6종의 결정적·fail-safe 훅이 Claude Code 이벤트에 바인딩된다. 엔진의 보장이 실제 세션에서 *효력*을 갖는 지점이다:

| 훅 | 이벤트 | 역할 | 차단(exit 2) 조건 |
|----|--------|------|-------------------|
| `careful-guard.sh` | PreToolUse(Bash) | 파괴적 명령 차단 | `rm -rf`, `DROP TABLE`, `git push --force`, WHERE 없는 `DELETE`, `TRUNCATE` |
| `freeze-guard.sh` | PreToolUse(Write/Edit) | 편집을 소유 경로로 잠금 | `BATHOS_OWNED_PATHS` 밖 편집 |
| `audit-log.sh` | PostToolUse | 모든 도구 사용을 감사 체인에 append | (비차단) |
| `artifact-verify.sh` | TaskCompleted / SubagentStop | 산출물·스토리파일 완전성 검증 | QA/W3 태스크 산출물 누락; #15 종료 시 불완전 스토리파일 |
| `gate-enforce.sh` | TaskCompleted | **W3 판정 FAIL 시 W5 진입 차단** | W5 진입 태스크 + 최신 Implementation 판정 = FAIL |
| `next-action.sh` | TeammateIdle | 다음 액션 안내 | (비차단) |

`gate-enforce` 흐름: W5 진입 태스크 감지 → `bathos gate show`로 최신 Implementation 판정 조회 → `FAIL` ⇒ exit 2(차단); `PASS`/`CONCERNS` ⇒ exit 0(허용). 바이너리·게이트 부재 시 fail-safe(경고 후 통과). `artifact-verify` 훅은 #17(Matthew) 역할을 다중 페이로드 필드명(`.role // .agent_type // .subagent_type // .agentType` + grep 폴백)으로 탐지해, 런타임 필드명이 바뀌어도 스토리파일 검증이 조용히 누락되지 않게 한다.

> 운영 주의: `settings.json`의 `hooks` 블록에는 **유효한 훅 이벤트명만** — 주석 키를 넣으면 서브에이전트 시작 시 무한 대기가 발생한다.

### 2.9 CLI 표면 & 종료 코드 규약

바이너리를 손으로 직접 부를 일은 드물다 — 훅과 커맨드가 대신 부른다 — 하지만 필요할 때를 위해 CLI 표면 전체를 여기에 정리해 둔다.

전역 옵션: `-s, --state-dir <PATH>`(기본 `./_state`), `--modules-dir <PATH>`(기본 `./modules`), `-h/--help`, `-V/--version`.
**종료 코드:** `0` 성공 · `1` 오류 · **`2` 게이트 FAIL**(훅이 차단에 사용).

| 커맨드 | 서브커맨드 | 목적 |
|--------|-----------|------|
| `state` | `validate`, `show` | manifest.json 스키마 검증·조회 |
| `route` | `decide`, `show` | Scale-Adaptive 레벨 추천/확정 |
| `wave` | `init`, `activate`, `show` | 7웨이브 전이(동시성 ≤ 3) |
| `gate` | `verdict`, `show` | 게이트 판정 기록/조회(FAIL → exit 2) |
| `story` | `compile`, `check-stale` | 완전성(D1)·출처추적(D2)·신선도(D3) |
| `plug` | `list`, `enable`, `disable` | 플러그 모듈 토글 |
| `audit` | `append`, `verify` | tamper-evident 감사 체인에 append / **검증**(`verify` → 변조 시 `E-AUDIT-TAMPER`, exit 1) |
| `doctor` | — | 설치·배선 프리플라이트 진단(§2.12 참조) |

### 2.10 오류 분류 (E-codes)

엔진은 실패 모드에 이름을 붙여 훅과 사람이 결정적으로 반응하게 한다: `E-LEVEL-DRIFT`(레벨 중도 변경), `E-CONCURRENCY`(활성 역할 >3), `E-CTX-LOSS`(불완전 스토리파일), `E-STALE`(상류 대비 스토리 구식), `E-STATE-CORRUPT`(manifest 스키마 위반), `E-AUDIT-TAMPER`(감사 체인 단절), `E-PLUG-NOTFOUND`(없는 모듈).

### 2.11 세션 저장/재개

실제 빌드는 여러 Claude Code 세션에 걸치며, 팀원은 리드의 대화 히스토리를 **물려받지 않는다** — 그래서 BATHOS는 한 단어짜리 두 커맨드로 인계를 명시적·무손실로 만든다:

- **`/save`** — 세션 *전체*를 단일 권위 스냅샷 `_state/SESSION-SNAPSHOT.md`(+ 날짜 사본)에 담는다. 엔진 상태(`bathos state/wave/gate/route show`)·제품 코드 git 상태·확정 결정(User Sovereignty 선택 포함)·진행 중 웨이브와 활성 역할·남은 작업, 그리고 **다음에 실행할 정확한 커맨드**를 자동 집계한다. 인자 없이 동작하며(현재 프로젝트의 `_state`가 기본값), 되묻지 않는다.
- **`/resume`** — 그 스냅샷을 읽어(`manifest.json`·`wave-log.md`와 교차 확인) *어디까지 했고 다음에 뭘 할지*를 복원한다(읽기 전용). in-process 팀원은 되살릴 수 없으므로 해당 `/waveN-…` 커맨드로 재스폰하라고 안내한다 — 디스크 산출물 덕에 무손실이다.

둘 다 **자연어 친화적**: 리드는 "저장/체크포인트" 같은 표현을 `/save`로, "이어서/재개"를 `/resume`으로 간주한다(`CLAUDE.md` 규칙). 이 둘은 더 긴 gstack `/context-save`·`/context-restore`의 BATHOS-native 심플 별칭으로, 동일한 `_state`·동일한 단일 진실 원천을 공유한다.

### 2.12 프리플라이트 진단 & 무결성 검증

두 커맨드가, 문서로만 경고하던 함정 점검과 tamper-evidence 약속을 *실제로 실행 가능한 검증*으로 만든다:

- **`bathos audit verify`** — 감사 해시체인을 처음부터 끝까지 검증한다(`hash_prev[n] == hash_self[n-1]`, genesis 앵커, 단조 `seq`). 무결 → exit 0; 단절/변조 → 문제 `seq`와 함께 `E-AUDIT-TAMPER` 출력 후 exit 1. "tamper-evident"를 주장이 아니라 *증명 가능*하게 만든다.
- **`bathos doctor`** — 채택자가 흔히 걸려 넘어지는 바로 그 지점들을 한 번에 점검하는 설치·배선 프리플라이트: `BATHOS_BIN` 설정, `jq` 존재, Agent Teams 플래그, **`settings.json` `hooks` 블록의 주석키**(`_note` 하나가 서브에이전트 시작을 무한 대기에 빠뜨림 — 이제 결정적으로 탐지), 훅 파일 존재+실행권한, `assets/`·`modules/` 존재, `manifest.json` 스키마 유효성, 감사 체인 무결성. ✓//✗ 체크리스트를 출력하고 하드 오류가 있으면 exit 1. `install.sh` 직후 실행 권장.

### 2.13 크로스-프로젝트 메모리 & 핸드오프

세션 저장/복원은 *프로젝트 내부*에 한정된다. 하지만 간직할 가치가 있는 지식 — 아키텍처 결정, 디자인 토큰 시스템, 값비싸게 얻은 운영 교훈 — 은 프로젝트 *사이*의 경계를 넘어야 한다. BATHOS는 이를 **전역 레지스트리** `~/.bathos/registry/`에 축적한다:

- `INDEX.md` — 작업한 프로젝트 1줄 인덱스.
- `<slug>.md` — 각 프로젝트를 증류한 **프로젝트 카드**: 도메인, USP 프레이밍, 핵심 아키텍처 결정/ADR, 디자인 시스템 하이라이트, 재사용 패턴, 교훈 & 인시던트, 현재 상태, 그리고 그 프로젝트 `.agent-team/`로의 포인터.

**적용 방식.** `/project-handoff`가 현 프로젝트를 카드로 증류하고, `/save-session`이 이 upsert를 **자동으로** 수행한다 — 저장할 때마다 추가 노력 없이 레지스트리가 쌓인다. *다른* 프로젝트, *다른* 세션에서 `/recall`(그리고 레지스트리를 함께 참조하는 `/cold-start`)이 관련 이전 카드를 끌어온다.

**장점.** 완전히 새 프로젝트가 cold가 아니라 *warm*으로 시작한다: 이미 통한 결정·패턴을 재사용하고, 이미 배운 교훈(예: "팀원 hang = quota" 운영 교훈, `settings.json` 주석키 함정)은 미리 경고받는다 — 같은 함정을 다시 발견할 필요가 없다. 회상은 제안이다(User Sovereignty): 재사용 컨텍스트를 제시할 뿐, 이 프로젝트의 방향은 사용자가 결정한다.

---

## 3. End-to-end 실행 흐름

이 모두를 합치면, 한 번의 풀 실행은 위에서 아래로 이렇게 읽힌다 — 각 화살표는 리드 세션에서 당신이 직접 실행하는 커맨드다:

```
/team-kickoff        → .agent-team/ 골격 + charter + manifest 초기화 (SSOT 생성)
/route <abs-path>    → stakes → 추천 Lv0–4 → 사용자 확정 → current_level 기록
/wave1-discovery     → John ∥ Caleb            → USP Readiness 게이트
/wave2-design        → Joshua → (James, Jonnathan) → Plan Readiness 게이트
/wave3-story-gate ★  → Matthew가 스토리파일 응축; Thomas·Matthias 독립 리뷰
                       → Implementation Readiness 게이트 (PASS/CONCERNS/FAIL)
                       → FAIL은 gate-enforce 훅으로 W5를 물리 차단
/wave5-implement     → Phillip, Andrew, Stephen (동시 ≤3, 소유경로 격리)
/wave6-verify-report → (Thomas, Timothy, Matthias) → Michael → Hananiah → Martin → Release Readiness 게이트
/team-confirm        → 최종 사인오프 + cleanup
```

전 과정에서 역할은 입력 경로만 읽고 소유 경로만 편집하며, 인수인계는 디스크로만 이뤄지고, 엔진이 모든 전이·판정을 기록하며, 감사 체인이 모든 도구 사용을 포착한다.

---

## 4. 설계 원칙 (ETHOS)

BATHOS는 Garry Tan의 **gstack** ETHOS를 차용·강화했다. 세 원칙이 모든 역할을 지배한다:

1. **User Sovereignty(최상위)** — AI는 제안, *사용자가* 결정. 사용자의 명시된 방향을 바꾸는 권고는 "추천 + 근거 + 놓친 맥락"으로 제시하고 *물어본다*; 절대 먼저 실행하지 않는다.
2. **Boil the Ocean** — 완전한 구현이 몇 분 더 들 뿐이라면 완전한 쪽을 택하고, 테스트·엣지케이스를 미루지 않는다.
3. **Search Before Building** — 익숙지 않은 영역은 먼저 검색해 지형을 파악한 뒤 제1원리로 통념에 도전한다.

이는 장식이 아니다: 게이트의 "facilitator이지 generator 아님" 규칙과 독립 검증자 분리는 User Sovereignty와 "생성 ≠ 검증"을 강제된 메커니즘으로 표현한 것이다.

---

## 5. 프로젝트 상태 & 정직한 한계 (v0.4.0)

**Early but functional — 오늘 end-to-end로 빌드·동작한다.**

- BATHOS는 **Claude Code v2.1.32+ 위에서 도는 메서드 패키지**이며 독립 실행 앱이 아니고, **실험 기능 Agent Teams**에 의존한다.
- **엔진은 검증됨:** **Rust 테스트 628 + 훅 결정성 86, 전부 그린**; `cargo clippy -D warnings` 클린; release 재현 빌드.
- **완전 독립 인증(dogfooding):** BATHOS는 자기 자신에 Wave 6를 적용했다. **ThomasCert(독립 코드 리뷰, PASS) + MatthiasCert(독립 QA/E2E, PASS)** ⇒ **Release Readiness = PASS**. 알려진 Blocking/High/Medium 결함: **0 open**. 검증 trail: `.agent-team/`(`10-review/`·`11-qa/`·`12-report/w6-final-certification.html`·`_state/signoff.md`).
- 일부 웨이브 커맨드는 리드가 Claude Code에서 돌리는 **오케스트레이션 프롬프트**(팀원 스폰·검수)이며 완전 자동 엔진 플로우가 아니다.
- **아직 production-hardened 아님** — 1.0 전까지 API·스키마·커맨드명 변경 가능.

---

## 6. 라이선스 & 고지

**MIT License**로 배포한다. BATHOS는 독립적으로 구현된 저작물로, [BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD)(MIT © 2025 BMad Code, LLC)를 정밀 역분석한 뒤 제1원리에서 재구현했다 — BATHOS가 더 깊이 파고들고자 한 지형을 앞서 그려낸 선행 작업에 진심 어린 경의를 표한다. "BMAD", "BMad Method" 등 상표를 제품명·마케팅에 **사용하지 않는다.** 전문: [`../README.md`](../README.md).

---

<div align="center">

**BATHOS** · βάθος — 표층이 아닌 깊이
[`FEATURES-en.md`](FEATURES-en.md) · [`FEATURES-es.md`](FEATURES-es.md)

</div>
