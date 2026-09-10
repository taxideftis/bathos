<p align="center">
  <!-- BATHOS_LANDING_URL — replace href="#" with the landing-page URL once the landing page is live (same marker in all language READMEs) -->
  <a href="#"><img src=".github/assets/bathos-lockup-transparent.png" alt="BATHOS" width="480"></a>
</p>

# BATHOS

[English](README.md) · **한국어** · [Español](README-es.md) · [Deutsch](README-de.md) · [日本語](README-ja.md)

> **βάθος** (그리스어) — *"깊이, 심연."* 표층적인 AI 지원과는 의도적으로 대비되는, 압도적인 깊이를 지닌 AI Workflow Agent 메서드.

![version](https://img.shields.io/badge/version-0.4.0-0e9aa1)
![license](https://img.shields.io/badge/license-MIT-blue)
![engine](https://img.shields.io/badge/engine-Rust-d2691e)
![runtime](https://img.shields.io/badge/runtime-Claude%20Code%20v2.1.32%2B-7b61ff)
![status](https://img.shields.io/badge/status-v0.4.0%20early%20%C2%B7%20dogfood--verified-c8841a)

BATHOS는 **단일 Claude Code 세션을 규율 잡힌 제품 팀으로** 바꿉니다 — 17개 전문 역할, 7웨이브 딜리버리 파이프라인, Scale-Adaptive 라우팅, 그리고 강력한 품질 게이트를 갖추고, 핵심 불변식을 감(感)이 아니라 결정론적으로 만들어 주는 작은 **Rust 엔진**이 이를 뒷받침합니다.

> **한국어:** BATHOS는 Claude Code 위에서 **17역할 × 7웨이브 × Scale-Adaptive Lv0~4**로 제품 개발을 오케스트레이션하는 메서드 패키지입니다. 처음이라면 **[활용 사례(새 서비스 만들기)](docs/USECASE-kr.md)** → **[특징·구동원리](docs/FEATURES-kr.md)** → **[사용 가이드](docs/USAGE-kr.md)** 순서를 권장합니다. (운영 규칙: [`CLAUDE.md`](CLAUDE.md) · 원칙: [`ETHOS.md`](ETHOS.md))

---

## 목차

- [문서](#문서)
- [BATHOS를 쓰는 이유](#bathos를-쓰는-이유)
- [작동 방식: 두 개의 평면](#작동-방식-두-개의-평면)
- [요구 사항](#요구-사항)
- [빠른 시작](#빠른-시작)
- [7웨이브 파이프라인](#7웨이브-파이프라인)
- [Scale-Adaptive 라우팅 (Lv0–4)](#scale-adaptive-라우팅-lv04)
- [품질 게이트](#품질-게이트)
- [CLI 레퍼런스 (`bathos` 엔진)](#cli-레퍼런스-bathos-엔진)
- [슬래시 커맨드](#슬래시-커맨드)
- [17개 역할](#17개-역할)
- [플러그인 모듈](#플러그인-모듈)
- [안전 훅](#안전-훅)
- [저장소 구조](#저장소-구조)
- [설정](#설정)
- [프로젝트 상태](#프로젝트-상태)
- [BATHOS는 어떻게 만들어졌나 (도그푸딩)](#bathos는-어떻게-만들어졌나-도그푸딩)
- [기여하기](#기여하기)
- [라이선스 및 출처 고지](#라이선스-및-출처-고지)

---

## 문서

| 문서 | English | 한국어 | Español | 용도 |
|-----|:----------:|:---------:|:---------:|---------------|
| **활용 사례** — 새 서비스를 단계별로 만들기 | [`docs/USECASE-en.md`](docs/USECASE-en.md) | [`docs/USECASE-kr.md`](docs/USECASE-kr.md) | [`docs/USECASE-es.md`](docs/USECASE-es.md) | 여기서 시작: 직접 따라 하는 실습 (자기 프로젝트에 도입, "ReadShelf"를 처음부터 끝까지 구축) |
| **특징·운영 원칙** | [`docs/FEATURES-en.md`](docs/FEATURES-en.md) | [`docs/FEATURES-kr.md`](docs/FEATURES-kr.md) | [`docs/FEATURES-es.md`](docs/FEATURES-es.md) | BATHOS를 차별화하는 요소와 엔진이 내부에서 작동하는 방식 |
| **사용 가이드** | [`docs/USAGE-en.md`](docs/USAGE-en.md) | [`docs/USAGE-kr.md`](docs/USAGE-kr.md) | [`docs/USAGE-es.md`](docs/USAGE-es.md) | 레퍼런스: 설치, CLI, 웨이브, 게이트, 훅, 트러블슈팅 |
| **토큰·쿼터 관리** | [`docs/QUOTA-en.md`](docs/QUOTA-en.md) | [`docs/QUOTA-kr.md`](docs/QUOTA-kr.md) | [`docs/QUOTA-es.md`](docs/QUOTA-es.md) | 비용 통제, 웨이브 순서 조정, 사용 한도에서 복구하기 |
| **커스텀 모듈 작성** | [`docs/MODULE-GUIDE-en.md`](docs/MODULE-GUIDE-en.md) | [`docs/MODULE-GUIDE-kr.md`](docs/MODULE-GUIDE-kr.md) | [`docs/MODULE-GUIDE-es.md`](docs/MODULE-GUIDE-es.md) | 코어를 건드리지 않고 나만의 플러그인 작성 (module.yaml, 트리거 DSL, W4) |
| **역할 커스터마이즈** | [`docs/ROLE-GUIDE-en.md`](docs/ROLE-GUIDE-en.md) | [`docs/ROLE-GUIDE-kr.md`](docs/ROLE-GUIDE-kr.md) | [`docs/ROLE-GUIDE-es.md`](docs/ROLE-GUIDE-es.md) | 3계층 오버라이드(base → team → user)로 17개 역할 조정 |
| **아키텍처** (기여자용) | [`docs/ARCHITECTURE-en.md`](docs/ARCHITECTURE-en.md) | [`docs/ARCHITECTURE-kr.md`](docs/ARCHITECTURE-kr.md) | [`docs/ARCHITECTURE-es.md`](docs/ARCHITECTURE-es.md) | 크레이트 맵, 불변식(A9, 게이트, 감사), exit/error 코드, 기여 방법 |
| **FAQ** | [`docs/FAQ-en.md`](docs/FAQ-en.md) | [`docs/FAQ-kr.md`](docs/FAQ-kr.md) | [`docs/FAQ-es.md`](docs/FAQ-es.md) | 자주 묻는 질문 및 트러블슈팅 |
| **운영 규칙 / 원칙** | [`CLAUDE.md`](CLAUDE.md) · [`ETHOS.md`](ETHOS.md) | | | 팀 운영 규칙과 gstack에서 유래한 ETHOS |

> **처음이신가요?** **활용 사례** → **특징** → **사용 가이드** 순으로 읽으세요.

---

## BATHOS를 쓰는 이유

하나의 긴 LLM 대화는 표류합니다. "설계"와 "구축" 사이에서 컨텍스트가 유실되고, 품질 점검이 건너뛰어지며, 같은 모델이 자기 작업을 작성하면서 동시에 승인합니다. BATHOS는 이를 구조로 대체합니다.

| 일반 LLM 채팅 | BATHOS |
|---|---|
| 하나의 대화, 점점 커지는 컨텍스트 표류 | **7웨이브** 파이프라인 전반의 **17개 전문 역할** |
| 설계 ↔ 구현 사이에서 유실되는 컨텍스트 | **Zero-Context-Loss** 자족(自足) 스토리 파일 (Wave 3) |
| 암묵적이고 획일적인 노력 투입 | **Scale-Adaptive 라우터** — 명시적 Lv0–4 |
| 아무 때나 시작되는 구현 | **강제 readiness 게이트**가 `FAIL` 시 구축을 물리적으로 차단 |
| 작성자가 "검증"까지 겸함 | **독립 리뷰어** + 변조 탐지 가능한 감사 체인 |
| 슬그머니 사용자를 뒤엎는 조언 | **User Sovereignty** — AI는 제안하고 *당신이* 결정 |

그 결과: 한 사람이 AI 팀을 이끌고 디스커버리 → 설계 → 구현 → 검증을 관통하며, 매 단계마다 추적성과 게이트를 확보합니다.

---

## 작동 방식: 두 개의 평면

이것이 가장 중요한 단 하나의 개념입니다. BATHOS는 **두 개의 레이어** 위에서 동작합니다.

| 평면 | 무엇인가 | 무슨 일을 하는가 | 누가 구동하는가 |
|---|---|---|---|
| **오케스트레이션** | `.claude/` 아래의 마크다운 **슬래시 커맨드**, **역할**, **훅** | 웨이브 실행; 팀원 스폰 / 리뷰 / 종료 | **리드(Paul)** — 당신의 메인 Claude Code 세션 |
| **엔진** | 단일 정적 Rust 바이너리, **`bathos`** | 상태·게이트·웨이브 전이·라우팅·스토리 신선도·플러그인을 계산하고 *강제* | 훅과 커맨드가 자동 호출 (`bathos <subcommand>`) |

당신은 대부분 **슬래시 커맨드**(예: `/wave1-discovery`)를 입력합니다. `bathos` 바이너리는 그 커맨드와 훅이 그 밑에서 호출하는 결정론적 코어이며, 직접 실행할 수도 있습니다.

---

## 요구 사항

- **[Claude Code](https://claude.com/claude-code) v2.1.32+** — **Agent Teams** 실험 기능 활성화 필요
  (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`; 동봉된 `.claude/settings.json`에 이미 설정돼 있음)
- **Rust 툴체인** (cargo 1.92+ 검증됨) — 엔진 빌드용
- **`jq`** — 안전 훅이 JSON 파싱에 사용
- POSIX 셸 환경(macOS/Linux); 훅은 bash

---

## 빠른 시작

### 1. 코드 받기 & 엔진 빌드

```bash
git clone <your-fork-url> bathos && cd bathos

# Build the single static engine binary (~5.9 MB)
cd core
cargo build --release          # → core/target/release/bathos
cargo test                     # 510 tests, all green (optional sanity check)
cd ..

# Make the engine discoverable by hooks/commands:
export BATHOS_BIN="$(pwd)/core/target/release/bathos"
#   …or add core/target/release to your PATH
```

### 2. 프로젝트에서 BATHOS 사용하기

**옵션 A — 이 저장소를 작업 디렉터리로 사용.** `.claude/` 디렉터리(커맨드, 에이전트, 훅, 설정)가 이미 연결돼 있으니, 여기서 Claude Code를 열기만 하면 됩니다.

**옵션 B — 자기 프로젝트에 도입.** `.claude/`(커맨드, 에이전트, 훅, `settings.json`), `assets/`, `modules/`를 프로젝트 루트에 복사한 다음, 위와 같이 `BATHOS_BIN`을 설정하세요.

### 3. 파이프라인 구동 (Claude Code 안에서 슬래시 커맨드로)

```text
/team-kickoff                       # scaffold .agent-team/ + charter + manifest
/route        /abs/path/to/project  # analyze "stakes" → recommend Lv0–4 (you confirm)
/wave1-discovery   /abs/path        # discovery + market research
/wave2-design      /abs/path        # planning · architecture · design
/wave3-story-gate  /abs/path        # ★ condense to story files + readiness gate
/wave5-implement   /abs/path        # implementation
/wave6-verify-report /abs/path      # verification · docs · report
/team-confirm                       # final sign-off + cleanup
```

### 엔진 직접 써 보기

```bash
# Recommend a Scale-Adaptive level from "stakes" (recommend only; does not commit)
echo '{"scope":"feature","novelty":true,"regulation_ip":false,"team_size":"medium"}' \
  | bathos --state-dir .agent-team/_state route decide
#   → {"recommended_level":2,"wave_set":[...],"role_set":[...],"requires_confirmation":true}
```

---

## 7웨이브 파이프라인

```
(pre) kickoff → W0 Analysis → W1 Discovery → W2 Design
        → W3 Story Gate ★ → W5 Implementation → W6 Verify → (post) Confirm
                                  ↑
                       W4 IP & Research  (optional plug-in, off the critical path)
```

본류 의존성: **W0 → W1 → W2 → W3 → W5 → W6**. W4(IP & 연구)는 W2 이후 언제든 실행 가능한 선택적 플러그인입니다.

| 커맨드 | 웨이브 | 팀(병렬) | 게이트 |
|---|---|---|---|
| `/team-kickoff` | (사전) | 리드 단독 | — |
| `/wave0-analysis` | **W0** Analysis (선택) | Caleb | Brief Readiness |
| `/wave1-discovery` | **W1** Discovery & 시장 | John ∥ Caleb | USP Readiness |
| `/wave2-design` | **W2** 기획 · 아키텍처 · 디자인 | Joshua → (James, Jonnathan) | Plan Readiness |
| `/wave3-story-gate` | **W3** 스토리 엔지니어링 ★ | Matthew + Thomas · Matthias + Timothy | **Implementation Readiness** |
| `/wave4-ip-research` | **W4** IP & 연구 (플러그인) | Mark ∥ Nathanael | — |
| `/wave5-implement` | **W5** 구현 | Phillip, Andrew, Stephen | 스토리 단위 완료 |
| `/wave6-verify-report` | **W6** 검증 · 문서 · 리포트 | (Thomas, Timothy, Matthias) → Michael → Hananiah → Martin | Release Readiness |
| `/team-confirm` | (사후) | 리드 단독 | — |

**W3가 심장인 이유.** Wave 3은 설계→구축 컨텍스트 간극을 메웁니다. 역할 #17 **Matthew**가 상류 작업을 **자족 dev 스토리 파일**(9개 섹션, 모든 기술적 주장에 `[Source: …]` 태그)로 응축하고, Thomas와 Matthias가 이를 독립적으로 리뷰하며, 판정이 `FAIL`이면 `gate-enforce` 훅이 W5 진입을 **물리적으로 차단**합니다.

**W5는 어떻게 만드는가 — 구현 규율.** Wave 5는 *무엇을 만들지*를 결정하는 명시적 **사다리** 위에서 돕니다. 코드를 쓰기 전, 구현자는 버티는 첫 단에서 멈춥니다: ① 애초에 존재해야 하는가 → ② 이 코드베이스에 이미 있는가 → ③ 표준 라이브러리가 하는가 → ④ 플랫폼 네이티브 기능이 덮는가 → ⑤ 이미 설치된 의존성이 푸는가 → ⑥ 한 줄로 되는가 → ⑦ 그제서야, 동작하는 최소한의 코드.

사다리는 **스코프**를 지배하고, ETHOS *Boil the Ocean*은 정한 범위의 **완전성**을 지배합니다. 두 축은 서로를 자르지 않습니다 — 입력 검증·에러 처리·보안·접근성, 그리고 비자명한 로직 뒤에 남기는 실행 가능한 검증 하나는 사다리의 사정거리 밖입니다.

실제 코너를 자른 단순화에는 그 천장과 탈출 경로를 명시하는 마커를 남깁니다:

```rust
// ponytail: single global lock, split into per-wave locks if profiling shows contention
```

`/bathos-debt`는 소스코드의 `ponytail:` 마커를 문서의 `CONCERNS:` 앵커와 함께 수집하고, 업그레이드 트리거가 없는 마커를 `no-trigger`로 표시합니다 — "나중에"가 조용히 "영영"이 되지 않도록. 강도는 세션 단위 토글입니다: `/bathos intensity <lite|full|ultra|off>`(기본 `full`).

규율 정본: [`.claude/agents/_preamble/ponytail-inject-kr.md`](.claude/agents/_preamble/ponytail-inject-kr.md) — 한국어가 정본이며 `-en` / `-ja` / `-es` 판을 함께 둡니다.

---

## Scale-Adaptive 라우팅 (Lv0–4)

BATHOS는 태스크가 실제로 필요로 하는 웨이브만 활성화합니다. 레벨은 당신이 확정하며(User Sovereignty), `manifest.json`에 기록됩니다.

| Lv | 작업 유형 | 활성 웨이브 | #17 Matthew | W4 |
|----|-----------|--------------|:---:|:--:|
| **0** | 버그 수정 / 사소 | W5 (+ 최소 W6) | ✗ | ✗ |
| **1** | 소기능 / 국소 리팩터 | 경량 W2 + W3(축약) + W5 + 경량 W6 | ✓ (축약) | ✗ |
| **2** | 표준 기능 / 모듈 | W1 + W2 + W3 + W5 + W6 | ✓ | 선택 |
| **3** | 신규 제품 / 대형 | W0–W6 (W4 선택) | ✓ | 권장 |
| **4** | 엔터프라이즈 / 딥테크 / 규제 | W0–W6 전체 + W4 | ✓ | 필수 |

추천값은 네 개의 stakes 축(`scope`, `novelty`, `regulation_ip`, `team_size`)으로부터 라우터가 계산합니다.

---

## 품질 게이트

모든 웨이브 게이트는 하나의 어휘를 씁니다.

| 판정 | 의미 | 효과 |
|---|---|---|
| **PASS** | 기준 충족, 블로커 없음 | 다음 웨이브로 진행 |
| **CONCERNS** | 조건부 통과(비차단 리스크) | `_state/`에 리스크 기록 후 진행 |
| **FAIL** | 차단 결함 | 진입 차단; 보완 후 재게이트 |

게이트는 **FACILITATOR이지 generator가 아닙니다** — 근거 없는 자동 PASS 금지. W3 게이트는 훅으로 강제됩니다(exit code `2`가 W5를 차단). 판정의 진실 원천은 엔진입니다: `bathos gate show`.

---

## CLI 레퍼런스 (`bathos` 엔진)

전역 옵션: `-s, --state-dir <PATH>` (기본 `./_state`), `--modules-dir <PATH>` (기본 `./modules`), `-h/--help`, `-V/--version`.
Exit 코드: `0` 성공 · `1` 오류 · `2` 게이트 FAIL (훅이 차단에 사용).

| 커맨드 | 서브커맨드 | 목적 |
|---|---|---|
| `state` | `init`, `validate`, `show` | 단일 진실 원천 `manifest.json` 생성·스키마 검증·검사 |
| `route` | `decide`, `show` | Scale-Adaptive 레벨 추천 (stdin/`--stakes-json`; `--confirm <0-4>`로 기록) |
| `wave` | `init`, `activate`, `show` | 7웨이브 상태 전이 (동시성 ≤ 3 강제) |
| `gate` | `verdict`, `show` | 게이트 판정 기록 / 조회 (PASS/CONCERNS/FAIL; FAIL → exit 2) |
| `story` | `compile`, `check-stale` | 스토리 파일 완결성(D1), 소스 추적(D2), 신선도(D3) |
| `plug` | `list`, `enable`, `disable` | 플러그인 모듈 토글 (IP 팩, 연구 팩, …) |
| `audit` | `append`, `verify` | 변조 탐지 감사 해시 체인에 추가 / **검증** (`verify` → `E-AUDIT-TAMPER` 시 exit 1) |
| `doctor` | — | **설치/연결 프리플라이트** — `BATHOS_BIN`, `jq`, Agent Teams 플래그, `settings.json` hooks 블록(주석 키 무한대기), 훅 실행 비트, manifest 스키마, 감사 체인 |

```bash
bathos -s _state state init --codename MYPROJECT       # 스키마 유효 manifest seed 생성
bathos -s _state state validate                       # validate manifest.json
bathos -s _state gate verdict Implementation PASS Matthew
bathos -s _state gate show                            # latest Implementation gate (JSON)
bathos --modules-dir modules plug list                # modules + enabled state
bathos -s _state audit append --actor hook --action tool.write --target manifest.json
```

예제를 포함한 전체 레퍼런스: **[`docs/USAGE-kr.md`](docs/USAGE-kr.md)** (한국어).

---

## 슬래시 커맨드

`.claude/commands/` 아래에 34개 커맨드가 함께 제공됩니다.

- **웨이브:** `wave0-analysis`, `wave1-discovery`, `wave2-design`, `wave3-story-gate`, `wave4-ip-research`, `wave5-implement`, `wave6-verify-report`
- **라우팅:** `route`
- **팀:** `team-kickoff`, `team-status`, `team-confirm`, `team-cleanup`
- **플랜 리뷰 (W2 보강):** `autoplan`, `plan-ceo-review`, `plan-design-review`, `plan-eng-review`, `plan-devex-review`
- **세션 저장/복원:** `save-session`, `cold-start` (정본 — 완전 저장 & 완전 콜드스타트 복원); `save` / `resume` (짧은 별칭); `context-save` / `context-restore` (gstack 별칭)
- **크로스-프로젝트 메모리:** `project-handoff` (현 프로젝트를 `~/.bathos/registry/`로 증류), `recall` (관련 이전 프로젝트 컨텍스트를 새 프로젝트로 끌어오기)
- **엔지니어링 운영:** `review`, `investigate`, `cso` (OWASP + STRIDE), `retro`, `health`, `guard`, `unfreeze`, `context-save`, `context-restore`

---

## 17개 역할

리드(#0 Paul)는 당신의 메인 세션이며 결코 스폰되지 않습니다. 역할 #1–#17은 웨이브별로 스폰되며, 동시성은 3으로 제한됩니다.

| # | 이름 | 역할 | 모델 | 웨이브 |
|---|------|------|-------|------|
| 0 | Paul | 리드 / 최종 confirm | Opus 4.8 | 전체 (메인 세션) |
| 1 | John | 리버스 스페셜리스트 | Opus 4.8 | W1 (+W0) |
| 2 | Caleb | 시장 분석 / USP (+W0 애널리스트) | Opus 4.8 | W1 (+W0) |
| 3 | Joshua | 서비스 기획 | Opus 4.8 | W2 (게이트) |
| 4 | James | SW / 클라우드 아키텍트 | Opus 4.8 | W2 |
| 5 | Mark | IP 스페셜리스트 (특허) | Opus 4.8 | W4 |
| 6 | Nathanael | 논문 작성 (abstract/intro) | Sonnet 5 | W4 |
| 7 | Jonnathan | 수석 디자이너 (UX/UI) | Opus 4.8 | W2 |
| 8 | Phillip | 백엔드 & 데이터 리드 | Sonnet 5 | W5 |
| 9 | Andrew | 프론트엔드 & 모바일 리드 | Sonnet 5 | W5 |
| 10 | Stephen | AI/ML 리드 | Sonnet 5 | W5 |
| 11 | Timothy | 개발 정의 문서화 | Sonnet 5 | W6 (+W3) |
| 12 | Thomas | 코드 리뷰어 | Sonnet 5 | W6 (+W3) |
| 13 | Michael | 보안 스페셜리스트 (방어적 웹/사이버 감사 & 하드닝) | Sonnet 5 | W6 (Thomas 이후) |
| 14 | Hananiah | 리팩토링 스페셜리스트 (동작 보존) | Sonnet 5 | W6 (Michael 이후) |
| 15 | Matthias | QA / 검증 (E2E) | Sonnet 5 | W6 (+W3) |
| 16 | Martin | 모니터링 / HTML 리포트 | Sonnet 5 | W6 |
| **17** | **Matthew** | **스크럼 마스터 / 스토리 엔지니어** | Opus 4.8 | **W3 전용 (그 외 비가동)** |

역할 정의는 `.claude/agents/_base/`에 있으며 3계층 오버라이드(base → team → user)를 지원합니다.

---

## 플러그인 모듈

코어는 슬림하게 유지됩니다. 도메인 역량은 `modules/` 아래 opt-in 플러그인입니다(코어는 결코 모듈에 의존하지 않음 — A9). 각 모듈은 `module.yaml`에서 자신을 선언합니다.

```yaml
module_id: ip                    # ip | research | game | security ...
name: IP Pack
wave: W4
trigger: "Lv>=3 OR domain=ip"    # auto-enable condition
enabled_default: false
provides:
  workflows: [patent-spec-draft]
  templates: [patent-spec]
outputs: ".agent-team/05-ip/"
evidence_trace: true
```

기본 제공: **`ip-pack`**(특허 명세 초안 작성)과 **`research-pack`**(학술 abstract/introduction). `bathos plug enable <id>` / `disable <id>`로 토글합니다.

---

## 안전 훅

`.claude/settings.json`은 6개의 결정론적·fail-safe 훅을 Claude Code 이벤트(`PreToolUse`, `PostToolUse`, `TaskCompleted`, `SubagentStop`, `TeammateIdle`)에 바인딩합니다.

| 훅 | 이벤트 | 목적 |
|---|---|---|
| `careful-guard.sh` | PreToolUse(Bash) | 파괴적 명령 차단 (`rm -rf`, `DROP TABLE`, `git push --force`, `WHERE` 없는 `DELETE`, `TRUNCATE`) |
| `freeze-guard.sh` | PreToolUse(Write/Edit) | 소유 경로로 편집 잠금 |
| `audit-log.sh` | PostToolUse | 모든 도구 사용을 감사 체인에 추가 |
| `artifact-verify.sh` | TaskCompleted / SubagentStop | 필수 산출물 / 스토리 파일 완결성 검증 |
| `gate-enforce.sh` | TaskCompleted | **W3 판정이 FAIL일 때 W5 진입 차단** |
| `next-action.sh` | TeammateIdle | 다음 액션 제안 |

> `settings.json`의 `hooks` 블록 안에는 **유효한 훅 이벤트명만** 두세요 — 엉뚱한 주석 키 하나가 서브에이전트 시작을 무한 대기시킵니다.

---

## 저장소 구조

```
bathos/
├── core/                       # Rust workspace (the engine, 7 crates, ~9,200 LOC)
│   ├── Cargo.toml
│   └── crates/
│       ├── bathos-state/       # state SSOT: manifest.json + tamper-evident audit chain
│       ├── bathos-router/      # scale-adaptive Lv0–4 router
│       ├── bathos-wave-engine/ # 7-wave transitions, concurrency ≤ 3
│       ├── bathos-gate-engine/ # PASS/CONCERNS/FAIL verdicts
│       ├── bathos-story-engine/# story compilation, staleness (zero-context-loss)
│       ├── bathos-plug/        # plugin module manager
│       └── bathos-cli/         # the `bathos` binary
├── .claude/
│   ├── agents/_base/           # 17 role definitions (00-paul … 17-matthew-story-engineer)
│   ├── commands/               # 34 slash commands
│   ├── hooks/                  # 6 safety/event hooks + test harness
│   └── settings.json           # hook bindings + Agent Teams flag
├── assets/                     # templates, workflows, checklists, glossary
├── modules/                    # plugin modules: ip-pack, research-pack
├── docs/USAGE-kr.md            # detailed usage guide (Korean)
├── CLAUDE.md  ETHOS.md  VERSION  README.md
```

한 번의 실행이 산출하는 팀 산출물은 `.agent-team/` 아래에 놓입니다(plan, discovery, architecture, story engineering, reviews, QA, reports, 그리고 `_state/`). 실제 제품 소스 코드는 프로젝트의 통상 경로(`src/`, …)에 그대로 둡니다.

---

## 설정

- **엔진 상태 디렉터리** — `--state-dir` (기본 `./_state`); SSOT는 `<state-dir>/manifest.json` (JSON-Schema 검증, 원자적 쓰기, 감사 해시 체인).
- **모듈 디렉터리** — `--modules-dir` (기본 `./modules`).
- **훅용 엔진 경로** — `BATHOS_BIN` 환경 변수 (fallback은 `core/target/debug/bathos`).
- **역할 오버라이드** — 3계층 병합: `base`(고정 정체성/모델) → `team`(프로젝트 소유 경로) → `user`(언어/facilitation). 스칼라는 덮어쓰고, 배열은 append.

---

## 프로젝트 상태

**v0.4.0 — 초기이지만 작동함.** BATHOS는 오늘 처음부터 끝까지 빌드되고 실행됩니다. 도입자를 위한 정직한 유의 사항:

- 이것은 **Claude Code 위에서 동작하는 메서드 패키지**이지 독립 실행 앱이 아니며, **실험적 Agent Teams** 기능에 의존합니다.
- 엔진은 검증됐습니다: **510개 Rust 테스트 + 86개 훅 결정론 점검, 모두 green**; `cargo clippy -D warnings` 클린; 릴리스 빌드 재현 가능.
- **아직 프로덕션 하드닝은 되지 않았습니다**; API, 스키마, 커맨드명은 1.0 이전에 바뀔 수 있습니다.
- 일부 웨이브 커맨드는 리드가 Claude Code에서 실행하는 **오케스트레이션 프롬프트**(팀원을 스폰/리뷰)이며, 완전 자율 엔진 플로우가 아닙니다.

검증 이력은 `_state/signoff.md`와 `12-report/`를 참고하세요.

---

## BATHOS는 어떻게 만들어졌나 (도그푸딩)

BATHOS는 스스로를 구현한 뒤 **자신의 코드에 대해 자체 Wave 6 독립 검증을 실행**했습니다. 그 패스는 의도적으로 *작성자*와 *리뷰어*를 분리했습니다. 기능 QA는 green으로 보였지만, 독립 코드 리뷰가 **작성자가 놓친 차단성 불변식 결함**을 드러냈습니다(예: Rust 엔진과 bash 훅이 동일한 감사 체인에 *호환되지 않는* 포맷을 쓰고 있어 변조 탐지가 조용히 무효화됨). 그 블로커들은 보완·재게이트되었고, 회귀/백로그가 정리됐습니다 — 알려진 모든 리뷰 결함이 해소됐습니다.

그 교훈이 곧 제품의 명제입니다: **생성 ≠ 검증.** 전체 이력은 `.agent-team/`(`10-review/`, `11-qa/`, `12-report/`, `_state/signoff.md`)에 있습니다.

---

## 기여하기

기여를 환영합니다. BATHOS *자체가* 개발 메서드이므로, 그것을 스스로에게 써 주세요.

1. 변경 사항과 그 규모(Lv0–4)를 설명하는 이슈를 엽니다.
2. 코어는 슬림하게 유지하세요 — 새 도메인 역량은 코어가 아니라 `modules/`에 속합니다(플러그인에 대한 역의존 금지).
3. 엔진 변경 시: `cd core && cargo test && cargo clippy --all-targets -- -D warnings`가 green이어야 하며; 불변식에 대한 테스트를 추가하세요.
4. 훅 변경 시: `bash .claude/hooks/_test-hooks.sh`를 실행하고; 훅을 결정론적·fail-safe하게 유지하세요.
5. 게이트 어휘(PASS/CONCERNS/FAIL)와 안전 훅(`careful`, `freeze`)을 존중하세요.

세 가지 운영 원칙(`ETHOS.md`에서): **User Sovereignty**(AI는 제안하고, 당신이 결정) · **Boil the Ocean**(몇 분만 더 들이면 완성할 수 있다면 완성하라) · **Search Before Building**.

---

## 라이선스 및 출처 고지

**MIT License**로 배포됩니다 — 전문은 아래 참조.

```
MIT License

Copyright (c) 2026 BATHOS

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

**계보와 감사의 표시.** BATHOS는 독립적으로 구현된 저작물입니다. 그 메서드 설계는 **[BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD)**(MIT © 2025 BMad Code, LLC)에 대한 엄정한 리버스 분석을 거쳐 제1원리에서 재구현되었으며, 그로부터 근간이 되는 설계 어휘를 물려받았습니다.

우리는 이 계보를 의무가 아니라 선택으로 밝힙니다. *생성은 검증에 답할 수 있어야 한다*는 것을 핵심 신조로 삼는 시스템이 자신이 딛고 선 선행 작업을 가린다면 스스로 모순에 빠질 것입니다. 그래서 BATHOS는 BMAD-METHOD에 진 빚을 분명하게, 그리고 진심 어린 존경과 함께 기록합니다 — 그것은 BATHOS가 더 깊이 파고들고자 한 지형을 개척했습니다. MIT License에 따라 BMAD-METHOD의 저작권 및 라이선스 고지는 [`LICENSE`](LICENSE)에 보존되며; 전체 감사의 글은 [`CREDITS.md`](CREDITS.md)에 있습니다.

BATHOS는 별개의 독립 구현 프로젝트이며 제품명이나 마케팅에 "BMAD", "BMad Method", "BMad Builder", "BMB", "TEA", "CIS", "GDS", "WDS" 상표를 사용하지 **않습니다**.

**구현 규율(Wave 5).** W5의 사다리는 **[ponytail](https://github.com/DietrichGebert/ponytail)**(MIT)의 엔지니어링 원칙을 차용했습니다 — YAGNI 우선 사다리, "게으르면 안 되는 것"의 경계, 그리고 유예된 단순화의 마커 규약. BATHOS는 *원칙만* 흡수합니다: 페르소나·톤·브랜딩은 의도적으로 도입하지 않았고, 규칙은 웨이브·역할 맥락에 맞게 재작성하면서 ETHOS *Boil the Ocean*과의 우선순위 규칙을 명시했습니다. 역분석과 범위 결정은 [`_recon/ponytail-analysis.md`](_recon/ponytail-analysis.md)에 기록돼 있습니다.

---

<div align="center">

**BATHOS** · βάθος — 표층이 아닌 깊이
한국어 문서: [`docs/USECASE-kr.md`](docs/USECASE-kr.md) · [`docs/FEATURES-kr.md`](docs/FEATURES-kr.md) · [`docs/USAGE-kr.md`](docs/USAGE-kr.md) · [`docs/QUOTA-kr.md`](docs/QUOTA-kr.md) · [`docs/MODULE-GUIDE-kr.md`](docs/MODULE-GUIDE-kr.md) · [`CLAUDE.md`](CLAUDE.md) · [`ETHOS.md`](ETHOS.md)

</div>
