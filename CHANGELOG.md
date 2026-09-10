# Changelog

All notable changes to BATHOS are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] — 2026-09-10

Everything accumulated since 0.1.0 is released under this version. The 0.2.0 and
0.3.0 numbers were used in build metadata and on the landing page but never carried
a changelog section of their own, so their contents are folded in here.

### Added

- **웨이브별 멀티 프로바이더 모델 선택 — Kimi·DeepSeek·Qwen 추가 + `waves.<W?>` 정책 배선**
  (User 결정, 2026-09-09). 기존 per-role 선택 위에 **웨이브 단위** 선택을 얹었다.
  - **신규 런타임 3개**: `kimi`(`https://api.moonshot.ai/anthropic`) ·
    `deepseek`(`https://api.deepseek.com/anthropic`) · `qwen`(Model Studio Anthropic 호환).
    **`gpt` 런타임은 만들지 않았다** — OpenAI는 1차 Anthropic 호환 엔드포인트를 제공하지 않고,
    기존 `codex` 서브프로세스 경로가 이미 GPT를 커버한다(사다리 2단: 이미 있는 것 재사용).
  - **`Runtime::is_env_global()`** 이 혼합 규칙의 **단일 진실 원천** — 런타임을 추가할 때 한 곳만
    고치면 된다. 옛 GLM 전용 R1~R4를 이 술어 기반으로 일반화하고, 3개가 늘면서 **처음 가능해진**
    "서로 다른 env-global 런타임이 한 배치에 동시 요청" 케이스를 새 Rule 1로 추가했다.
  - **`waves.<W?>`에 `runtime`/`model`/`reasoning_effort` 필드 신설.** 스키마에 `waves` 맵은
    이미 있었고 `mixed_policy` 하나만 담고 있었다 — 새 SSOT를 만들지 않고 그 빈 그릇을 채웠다.
    해석 체인은 5단계로: **역할 → 웨이브 → defaults → frontmatter → 런타임 기본**(`Source::Wave` 추가).
  - **세션-백엔드 전환 게이트**: 웨이브가 요구하는 env-global 런타임과 현재 `session_backend`가
    다르면 `validate`가 exit 2로 차단하고 **런타임별 실제 엔드포인트를 명명한** 전환 절차를 제시한다
    (옛 R3 메뉴의 "GLM"/`glm-env.sh` 하드코딩 제거).
  - **`wave_roles.rs` 신설** — wave↔role 로스터를 `bathos-cli` private 함수에서 `bathos-state`로
    이관(중복 정의 제거). W3·W6 겸직 역할(Thomas·Matthias·Timothy)은 양쪽에 그대로 전사하고,
    역방향 `role_wave()`는 "가장 이른 웨이브"를 반환하되 **그것이 주 웨이브가 아님을 주석에 명시**한다
    — 근거 없는 두 번째 우선순위 테이블을 만드는 대신 한계를 솔직히 적는 쪽을 택했다.
  - **CLI**: `bathos model set/unset/show/validate`에 `--wave` 지원(새 서브커맨드 없음).
  - **`/model-config` 커맨드 신설** + 웨이브 커맨드 7종의 프로바이더 풀 문구 갱신.
  - **`assets/model-catalog.json` 신설** — 6 프로바이더·30 모델 항목. **allowlist가 아니라 선택
    UI용 데이터**이므로 카탈로그에 없는 구형·저가 모델 ID도 그대로 동작한다(하위 호환 자동).
    새 모델 출시 시 이 JSON만 고치면 되고 엔진 재빌드가 불필요하다. 항목별 `verified` 플래그로
    1차 출처 확인 여부를 표기하고, 폐지된 ID는 `retired`로 분리했다.
  - **하위 호환**: `waves` 필드가 없거나 `mixed_policy`만 있는 기존 `model-plan.json`이 그대로
    로드됨을 명명된 회귀 테스트 3개로 증명. 기존 GLM R1~R4 테스트는 문구 무수정 재사용.
  - **미검증 정직 표기**: Kimi/DeepSeek/Qwen 라이브 API 연결은 실증하지 않았다(키 부재).
    Qwen 엔드포인트는 `dashscope[-intl].aliyuncs.com`과 `{workspace}.{region}.maas.aliyuncs.com`
    두 형태가 공식 자료 간 불일치 상태여서 **어느 쪽도 정답으로 확정하지 않고 둘 다 호스트 매칭에
    반영**했다(한쪽만 매칭하면 실제 Qwen 세션을 조용히 Claude로 오판하는 침묵 실패가 발생).

- **W5 구현 규율(사다리) — 4개 언어** — Wave 5 구현자(Phillip #8 · Andrew #9 · Stephen #10)에게
  주입되는 명시적 구현 규율을 신설했다. 7단 사다리(①존재해야 하는가 →②이미 있는가 →③표준
  라이브러리 →④플랫폼 네이티브 →⑤설치된 의존성 →⑥한 줄 →⑦최소 코드)가 **무엇을 만들지**를
  지배하고, ETHOS *Boil the Ocean*이 **정한 범위의 완전성**을 지배한다 — 두 축을 명시 분리해
  검증·에러 처리·보안·접근성·테스트는 사다리의 사정거리 밖임을 못박았다(User 결정, 2026-09-09).
  - `.claude/agents/_preamble/ponytail-inject-{kr,en,ja,es}.md` — **정본 = kr**,
    `-en`/`-ja`/`-es`는 보조 번역(무언 노후화 허용 계층, 기존 i18n 정책 계승).
  - `/wave5-implement` — 스폰 시 규율 문서 경로 + 현재 intensity 주입을 필수화. DoD 3항목과
    검수 거절 기준 3항목 추가.
  - 3개 구현자 역할 base에 규율 포인터 삽입(산문 복제 없이 역할별 경계만 명시 —
    백엔드=정합성 불가침, 프론트=네이티브 우선·접근성 불가침, ML=베이스라인 우선·재현성 불가침).
  - **강도 스위치는 신설하지 않았다** — 기존 `/bathos intensity <lite|full|ultra|off>`
    (`session-flags.json`)에 의미를 부여해 연동했다. `intensity ≠ Lv0~4` 불변식(LD-4) 유지.
  - 출처: ponytail(DietrichGebert/ponytail, MIT)의 **원칙만** 차용 — 페르소나·톤·브랜딩은
    `_recon/ponytail-analysis.md` §6 기존 결정에 따라 도입하지 않음. 고지는 `CREDITS.md`·README 4종.

- **`bathos state init`** — creates a schema-valid `manifest.json` seed for
  `/team-kickoff`, replacing error-prone LLM hand-authoring across runtimes.
  Existing state is preserved unless `--force` is explicitly supplied.

- **Codex CLI runtime porting layer** — added the Codex-native distribution path for the
  BATHOS workflow: `.agents/skills/**` skills, `.codex/agents/*.toml` subagents,
  `.codex/hooks.json` project hooks, `dist/codex-plugin/**` plugin bundle assets, and
  `.codex-out/**` legacy prompt/agent scaffold output. The adapter now includes Codex
  careful/freeze hooks, SessionStart resume guidance, `probe.sh` drift diagnostics,
  `bathos runtime` host detection, run-role CI coverage, and generated-skill drift checks.
  Target baseline is Codex CLI v0.145.0+; authenticated live walkthrough (`story-20`) and
  `SessionEnd` behavior remain explicitly documented as release-readiness verification
  items rather than claimed complete.

- **팀 역할 체계 16역할 → 17역할** — Thomas(#12) 다음에 **Michael (#13, Security
  Specialist)** 을 신설했다. 방어적(defensive) 웹·사이버 보안 감사·하드닝 전담 —
  승인 범위 내 취약점을 증거 기반으로 식별·분류·보고(CWE/OWASP/CVSS·SARIF)하고
  검증 가능한 하드닝을 제안·적용하며, 무해성·승인 경계·인간 승인 게이트를 준수한다.
  모델 = Sonnet 5, W6(Thomas 리뷰 이후) 가동, 소유 산출물 디렉터리 = `10-security/`.
  이후 역할 전원 +1 재번호: Hananiah #13→#14, Matthias #14→#15, Martin #15→#16,
  Matthew #16→#17. 근거: 사용자 결정(2026-07-12).

- **Cross-project memory** — a global registry at `~/.bathos/registry/` (`INDEX.md` +
  per-project `<slug>.md` cards) that persists context *across projects and sessions*, so a
  brand-new project can warm-start from prior work:
  - `/project-handoff` distills the current project (domain, USP, architecture decisions,
    design system, reusable patterns, lessons/incidents, pointers) into a registry card;
    `/save-session` performs this upsert automatically.
  - `/recall` pulls relevant prior-project context (reusable decisions/patterns and lessons
    to avoid) into a new session; `/cold-start` now also consults the registry.
  - New template `assets/templates/project-card-template.md`. Registry bootstrapped with a
    card for BATHOS itself (dogfooding).

- **`bathos audit verify`** — new CLI subcommand exposing the engine's `verify_chain`
  so the tamper-evident audit hash-chain can be checked on demand (intact → exit 0;
  broken → `E-AUDIT-TAMPER`, exit 1). +3 unit tests (260 total).
- **`bathos doctor`** — install/wiring preflight: checks `BATHOS_BIN`, `jq`, the Agent
  Teams flag, the `settings.json` `hooks` block for comment-key footguns, hook exec
  bits, `manifest.json` schema, and audit-chain integrity; ✓/⚠/✗ checklist, exit 1 on
  any hard error.

- **Session save / cold-start** — complete, lossless hand-off between sessions:
  - `/save-session` (canonical) — saves *all* session information as two artifacts:
    `_state/session-state.json` (full machine SSOT via `bathos state show`) +
    `_state/SESSION-SNAPSHOT.md` (narrative, cold-start entry point), plus audit-chain
    verification, git status, artifact inventory, and dated archives. Argument-free.
  - `/cold-start` (canonical) — in a fresh, zero-context session, reads the snapshot +
    machine SSOT + manifest/wave-log, cross-checks for drift, verifies audit integrity,
    and briefs completely (identity, level, wave/gate state, re-spawn list, next command).
    Read-only.
  - Short aliases `/save`·`/resume` and gstack aliases `/context-save`·`/context-restore`
    delegate to the same `_state`/SSOT. Natural-language triggers documented in
    `CLAUDE.md §8` (e.g. "save session"/"저장" → save; "cold start"/"이어서" → restore).
  - New template `assets/templates/session-snapshot-template.md`.
- **All 16 roles upgraded to top-tier** — every base role (#0 Paul lead, #1 John, #2 Caleb,
  #3 Joshua, #4 James, #5 Mark, #6 Nathanael, #7 Jonnathan, #8 Phillip, #9 Andrew,
  #10 Stephen, #11 Timothy, #12 Thomas, #13 Matthias, #14 Martin; #15 Matthew was already
  detailed) rewritten to a consistent standard: a working philosophy, non-negotiable
  craft/expertise standards, an anti-pattern list, an explicit process, and a stricter DoD.
  "Top-tier" is now uniform across discovery, planning, architecture, design,
  implementation, review, QA, docs, and reporting — not just design.
- **New contributor/usage docs (bilingual):** `docs/ARCHITECTURE-{en,kr}.md` (crate map,
  invariants, exit/error codes), `docs/ROLE-GUIDE-{en,kr}.md` (3-layer role override),
  `docs/FAQ-{en,kr}.md`. Wired into the README Documentation hub.
- **CODE_OF_CONDUCT** enforcement contact now points to GitHub Issues/Discussions (no
  email placeholder).
- **Design capability upgraded to top-tier** — role #7 (Jonnathan) rewritten with a
  design philosophy, non-negotiable craft standards (typography, chosen neutrals, layout,
  motion, content), an "AI-generated design" anti-pattern list, a Claude Design (Pencil
  MCP) visual workflow, and a stricter DoD. New assets: `workflows/design-excellence.md`
  (10-step process), `templates/design-system-template.md` (token + component contract),
  `checklists/design-quality.md` (11-dimension 0–10 rubric with "what a 10 looks like").
  `/plan-design-review` now drives the 11-dimension rubric and Pencil-based visual verification.
- **Landing site** `site/index.html` — a self-contained, bilingual (EN + 한국어 toggle)
  introduction page: two planes, the 7-wave descent, scale-adaptive levels, gates,
  features, the top-tier design capability, honest status, and get-started. Depth-themed
  identity; no external assets (CSP-clean); Pretendard-first Korean type.
- Documentation: `docs/FEATURES-{en,kr}.md`, `docs/USECASE-{en,kr}.md`,
  `docs/USAGE-en.md` (English usage reference), `docs/QUOTA-{en,kr}.md` (token/quota
  management), `docs/MODULE-GUIDE-{en,kr}.md` (custom plugin authoring), and a
  Documentation navigation hub in `README.md`.

### Changed

- **GLM 기본 모델 `glm-4.7` → `glm-5.3` 갱신** (User 결정, 2026-09-09) — `docs.z.ai` pricing 페이지
  실확인 기준 현재 플래그십. 실제 하드코딩 기본값은 `scripts/glm-smoke-test.sh` **한 곳**뿐이었고
  (`glm-env.sh`에는 모델 설정이 없음 — 조사 주장 실측으로 반증), 문서의 라인업 서술을 함께 갱신했다.
  - `docs/glm-backend-kr.md` · `docs/PORTABILITY-kr.md` — 현재 라인업(`glm-5.3`/`glm-5.3-flash`,
    이전 세대·경량·무료 티어) 명시. 별칭 매핑 서술은 **2026-07 시점 기준·현재 미재확인**으로 표기
    (검증하지 않은 매핑을 최신인 척 쓰지 않음).
  - **측정 기록은 보존** — `glm-backend-kr.md`의 2026-07-16 라이브 실증 항목(`model echo =
    glm-4.7 → glm-4.7`)은 그 시점의 실측값이므로 수정하지 않고, 기본값이 바뀐 사실과 옛 모델
    재현법(`GLM_SMOKE_MODEL=glm-4.7`)을 주석으로 덧붙였다.
  - ⚠️ **`glm-5.3` 라이브 재실증은 미수행** — 기본값만 갱신했음을 문서에 명시(날조 금지).
  - 하드코딩된 최신 모델 ID는 천장이 있으므로 `ponytail:` 마커로 표기(override = `GLM_SMOKE_MODEL`).

- **`/bathos-debt` 앵커 2종으로 확장** — 마크다운 산출물의 `CONCERNS:`에 더해 소스코드의
  `ponytail: <ceiling>, <upgrade path>` 마커를 함께 수집한다. 매체별 분업(중복 기록 금지)이며,
  업그레이드 트리거가 없는 마커는 `no-trigger`(`[x]`)로 표시해 "조용히 썩는 부채"를 드러낸다.
  소스코드 마커는 웨이브 `W5`로 귀속. json 출력에 `anchor`·`ceiling`·`upgrade`·`no_trigger` 필드
  추가(가산적). 최초 설계의 "`ponytail:` 대신 `CONCERNS:`로 재정의" 결정을 이 확장으로 갱신했다.

### Fixed

- **Codex adapter W3 gate no longer fails open on absolute `apply_patch` paths.**
  Real Codex `apply_patch` PreToolUse input carries the patch in `tool_input.command`
  and names files by absolute path (`/…/project/src/…`). The old `SRC_ERE` boundary
  class excluded `/`, so `src/` preceded by `/` never matched — the T1 source-write
  trigger stayed silent and a `FAIL` W3 gate let source edits through
  (`hook_exit=0`). `SRC_ERE` now treats `/` as a source-path boundary, so absolute
  and nested source paths trigger the block (`hook_exit=2`). Guarded by new
  regression cases **B-19/B-20** in `codex-adapter/hooks/_test-codex-hooks.sh`
  (20 cases · 40 assertions), and the Codex adapter harness is now run in CI
  (`.github/workflows/ci.yml` `hooks` job) so this can't silently regress.

## [0.1.0] — 2026-06-30

First public release. BATHOS builds and runs end-to-end on Claude Code.

### Added

- **Rust engine** (`core/`, 7 crates, single `bathos` binary):
  - `bathos-state` — `manifest.json` single source of truth, JSON-Schema validation,
    atomic writes, and a tamper-evident audit hash-chain.
  - `bathos-router` — Scale-Adaptive Lv0–4 routing from "stakes" (recommend / confirm).
  - `bathos-wave-engine` — 7-wave transitions with concurrency ≤ 3.
  - `bathos-gate-engine` — PASS / CONCERNS / FAIL verdicts.
  - `bathos-story-engine` — story-file compilation with zero-context-loss defenses
    (completeness, source-trace, freshness).
  - `bathos-plug` — plugin module manager (core stays independent of plugins).
  - `bathos-cli` — `state`, `route`, `wave`, `gate`, `story`, `plug`, `audit` commands.
- **Orchestration layer** (`.claude/`): 26 slash commands, 16 role definitions
  (0 Paul … 15 Matthew), and 6 deterministic safety hooks
  (`careful-guard`, `freeze-guard`, `audit-log`, `artifact-verify`, `gate-enforce`,
  `next-action`) bound to 5 Claude Code events.
- **Plugin modules**: `ip-pack` (patent drafting) and `research-pack` (academic abstract/intro).
- **Assets** (`assets/`): story / project-context / readiness-report templates,
  story-creation and readiness workflows, a story-quality checklist, and a glossary.
- **Docs**: English `README.md`, Korean `docs/USAGE-kr.md`, `CLAUDE.md`, `ETHOS.md`.
- **CI**: GitHub Actions running build · fmt · clippy · test · hook harness.

### Verified

- 257 Rust unit/integration tests and 46 hook determinism checks, all green;
  `cargo clippy -D warnings` clean; release builds reproducibly.
- BATHOS ran its own Wave 6 independent verification on its own code (dogfooding):
  independent review found blocking invariant defects that functional tests missed
  (notably an incompatible audit-log format between the Rust engine and bash hooks
  that silently voided tamper-evidence). All blocking, high, medium, and low review
  defects were remediated and re-gated to zero known open defects.

### Known limitations

- Runs only on Claude Code v2.1.32+ with the experimental Agent Teams feature.
- Not yet production-hardened; APIs, schemas, and command names may change before 1.0.
- The final independent re-certification of the medium/low fix layer is lead-verified
  (an independent re-review attempt hung); independent re-cert is planned.

[Unreleased]: https://github.com/taxideftis/bathos/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/taxideftis/bathos/compare/v0.1.0...v0.4.0
[0.1.0]: https://github.com/taxideftis/bathos/releases/tag/v0.1.0
