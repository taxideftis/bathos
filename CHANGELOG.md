# Changelog

All notable changes to BATHOS are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **`bathos state init`** — creates a schema-valid `manifest.json` seed for
  `/team-kickoff`, replacing error-prone LLM hand-authoring across runtimes.
  Existing state is preserved unless `--force` is explicitly supplied.

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

[Unreleased]: https://github.com/your-org/bathos/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/your-org/bathos/releases/tag/v0.1.0
