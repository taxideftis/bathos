<p align="center">
  <!-- BATHOS_LANDING_URL — replace href="#" with the landing-page URL once the landing page is live (same marker in all language READMEs) -->
  <a href="#"><img src=".github/assets/bathos-lockup-transparent.png" alt="BATHOS" width="480"></a>
</p>

# BATHOS

**English** · [한국어](README-kr.md) · [Español](README-es.md) · [Deutsch](README-de.md) · [日本語](README-ja.md)

> **βάθος** (Greek) — *“depth, the abyss.”* An AI Workflow Agent method with overwhelming depth, in deliberate contrast to surface-level AI assistance.

![version](https://img.shields.io/badge/version-0.2.0-0e9aa1)
![license](https://img.shields.io/badge/license-MIT-blue)
![engine](https://img.shields.io/badge/engine-Rust-d2691e)
![runtime](https://img.shields.io/badge/runtime-Claude%20Code%20v2.1.32%2B-7b61ff)
![status](https://img.shields.io/badge/status-v0.2.0%20early%20%C2%B7%20dogfood--verified-c8841a)

BATHOS turns a **single Claude Code session into a disciplined product team** — 17 specialist roles, a 7-wave delivery pipeline, scale-adaptive routing, and hard quality gates — backed by a small **Rust engine** that makes the critical invariants deterministic instead of vibes.

> **한국어:** BATHOS는 Claude Code 위에서 **17역할 × 7웨이브 × Scale-Adaptive Lv0~4**로 제품 개발을 오케스트레이션하는 메서드 패키지입니다. 처음이라면 **[활용 사례(새 서비스 만들기)](docs/USECASE-kr.md)** → **[특징·구동원리](docs/FEATURES-kr.md)** → **[사용 가이드](docs/USAGE-kr.md)** 순서를 권장합니다. (운영 규칙: [`CLAUDE.md`](CLAUDE.md) · 원칙: [`ETHOS.md`](ETHOS.md))

---

## Table of contents

- [Documentation](#documentation)
- [Why BATHOS](#why-bathos)
- [How it works: two planes](#how-it-works-two-planes)
- [Requirements](#requirements)
- [Quick start](#quick-start)
- [The 7-wave pipeline](#the-7-wave-pipeline)
- [Scale-adaptive routing (Lv0–4)](#scale-adaptive-routing-lv04)
- [Quality gates](#quality-gates)
- [CLI reference (`bathos` engine)](#cli-reference-bathos-engine)
- [Slash commands](#slash-commands)
- [The 17 roles](#the-17-roles)
- [Plugin modules](#plugin-modules)
- [Safety hooks](#safety-hooks)
- [Repository layout](#repository-layout)
- [Configuration](#configuration)
- [Project status](#project-status)
- [How BATHOS was built (dogfooding)](#how-bathos-was-built-dogfooding)
- [Contributing](#contributing)
- [License & attribution](#license--attribution)

---

## Documentation

| Doc | English | 한국어 | Español | What it's for |
|-----|:----------:|:---------:|:---------:|---------------|
| **Use case** — build a new service step by step | [`docs/USECASE-en.md`](docs/USECASE-en.md) | [`docs/USECASE-kr.md`](docs/USECASE-kr.md) | [`docs/USECASE-es.md`](docs/USECASE-es.md) | Start here: a hands-on walkthrough (adopt into your own project, build "ReadShelf" end-to-end) |
| **Features & operating principles** | [`docs/FEATURES-en.md`](docs/FEATURES-en.md) | [`docs/FEATURES-kr.md`](docs/FEATURES-kr.md) | [`docs/FEATURES-es.md`](docs/FEATURES-es.md) | What makes BATHOS distinctive and how the engine works under the hood |
| **Usage guide** | [`docs/USAGE-en.md`](docs/USAGE-en.md) | [`docs/USAGE-kr.md`](docs/USAGE-kr.md) | [`docs/USAGE-es.md`](docs/USAGE-es.md) | Reference: install, CLI, waves, gates, hooks, troubleshooting |
| **Install guides** — per platform | *(see USAGE-en §1)* | [`macOS/Linux`](docs/macos-linux-install-kr.md) · [`Windows (PowerShell)`](docs/windows-install-kr.md) · [`Windows (WSL)`](docs/wsl-install-kr.md) | *(see USAGE-es §1)* | Platform-specific setup: prerequisites, engine build, `install.sh`/`install.ps1`, verification, troubleshooting |
| **Token & quota management** | [`docs/QUOTA-en.md`](docs/QUOTA-en.md) | [`docs/QUOTA-kr.md`](docs/QUOTA-kr.md) | [`docs/QUOTA-es.md`](docs/QUOTA-es.md) | Control cost, sequence waves, recover from usage limits |
| **Custom module authoring** | [`docs/MODULE-GUIDE-en.md`](docs/MODULE-GUIDE-en.md) | [`docs/MODULE-GUIDE-kr.md`](docs/MODULE-GUIDE-kr.md) | [`docs/MODULE-GUIDE-es.md`](docs/MODULE-GUIDE-es.md) | Write your own plugin (module.yaml, trigger DSL, W4) without touching the core |
| **Role customization** | [`docs/ROLE-GUIDE-en.md`](docs/ROLE-GUIDE-en.md) | [`docs/ROLE-GUIDE-kr.md`](docs/ROLE-GUIDE-kr.md) | [`docs/ROLE-GUIDE-es.md`](docs/ROLE-GUIDE-es.md) | Adapt the 17 roles via the 3-layer override (base → team → user) |
| **Architecture** (contributors) | [`docs/ARCHITECTURE-en.md`](docs/ARCHITECTURE-en.md) | [`docs/ARCHITECTURE-kr.md`](docs/ARCHITECTURE-kr.md) | [`docs/ARCHITECTURE-es.md`](docs/ARCHITECTURE-es.md) | Crate map, invariants (A9, gate, audit), exit/error codes, contributing |
| **FAQ** | [`docs/FAQ-en.md`](docs/FAQ-en.md) | [`docs/FAQ-kr.md`](docs/FAQ-kr.md) | [`docs/FAQ-es.md`](docs/FAQ-es.md) | Common questions & troubleshooting |
| **Operating rules / principles** | [`CLAUDE.md`](CLAUDE.md) · [`ETHOS.md`](ETHOS.md) | | | Team operating rules and the gstack-derived ETHOS |

> **New here?** Read **Use case** → **Features** → **Usage guide**.

---

## Why BATHOS

A single long LLM conversation drifts: context is lost between “design” and “build,” quality checks are skipped, and the same model both writes and approves its own work. BATHOS replaces that with structure.

| Plain LLM chat | BATHOS |
|---|---|
| One conversation, growing context drift | **17 specialist roles** across a **7-wave** pipeline |
| Context lost between design ↔ implementation | **Zero-Context-Loss** self-contained story files (Wave 3) |
| Implicit, one-size effort | **Scale-Adaptive router** — explicit Lv0–4 |
| Implementation starts whenever | **Hard readiness gate** physically blocks build on `FAIL` |
| The author also “verifies” | **Independent reviewers** + tamper-evident audit chain |
| Advice that quietly overrides you | **User Sovereignty** — AI proposes, *you* decide |

The result: one person can drive an AI team through discovery → design → implementation → verification, with traceability and gates at every step.

---

## How it works: two planes

This is the single most important concept. BATHOS runs on **two layers**:

| Plane | What it is | What it does | Who drives it |
|---|---|---|---|
| **Orchestration** | Markdown **slash commands**, **roles**, and **hooks** under `.claude/` | Runs waves; spawns / reviews / shuts down teammates | The **lead (Paul)** — your main Claude Code session |
| **Engine** | A single static Rust binary, **`bathos`** | Computes & *enforces* state, gates, wave transitions, routing, story freshness, plugins | Invoked automatically by hooks & commands (`bathos <subcommand>`) |

You mostly type **slash commands** (e.g. `/wave1-discovery`). The `bathos` binary is the deterministic core those commands and hooks call underneath — and you can run it directly too.

---

## Requirements

- **[Claude Code](https://claude.com/claude-code) v2.1.32+** with the **Agent Teams** experimental feature enabled
  (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`; the bundled `.claude/settings.json` already sets it)
- **Rust toolchain** (cargo 1.92+ verified) — to build the engine (cross-platform: builds `bathos` on macOS/Linux, `bathos.exe` on Windows)
- **`jq`** — used by the **bash** safety hooks for JSON parsing (macOS/Linux only; the Windows PowerShell hooks use native `ConvertFrom-Json` and need no `jq`)
- **A shell for the hooks:**
  - **macOS / Linux** — a POSIX shell; hooks are bash (`.claude/hooks/*.sh`)
  - **Windows** — Windows PowerShell **5.1+** (built into Windows, no install) or PowerShell 7+; hooks are PowerShell (`.claude/hooks/*.ps1`) and are wired automatically at install time (see *Windows* under Quick start)

---

## Quick start

### 1. Get the code & build the engine

Dedicated install guides per platform: **macOS / Linux → [`docs/macos-linux-install-kr.md`](docs/macos-linux-install-kr.md)** · **Windows (native PowerShell) → [`docs/windows-install-kr.md`](docs/windows-install-kr.md)** · **Windows (WSL) → [`docs/wsl-install-kr.md`](docs/wsl-install-kr.md)** (Korean). The quick paths for each are below.

#### On macOS / Linux

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

**➜ Full macOS/Linux install guide (Korean):** [`docs/macos-linux-install-kr.md`](docs/macos-linux-install-kr.md) — prerequisites (incl. `jq`), `install.sh` flags, `BATHOS_BIN`/PATH, verification, troubleshooting.

#### On Windows (PowerShell 5.1+ / PowerShell 7+)

The engine and hooks are fully ported to PowerShell — same features, same gates. Use the PowerShell installer, which builds `bathos.exe` and (when installing into a target project) auto-wires the PowerShell hooks:

```powershell
git clone <your-fork-url> bathos; cd bathos

# Build the engine + print setup steps
.\install.ps1

# …or build AND adopt into a target project (auto-wires .ps1 hooks on Windows):
.\install.ps1 -Into C:\path\to\your\project      # add -Force to overwrite an existing .claude\
#   -NoWindowsHooks keeps the bash-wired settings.json (e.g. if you run hooks via Git Bash/WSL)

# Make the engine discoverable by hooks/commands:
$env:BATHOS_BIN = "$PWD\core\target\release\bathos.exe"
#   …or add core\target\release to your PATH
```

**How the cross-platform wiring works:** the committed `.claude/settings.json` points hooks at the bash `.sh` scripts (macOS/Linux). On Windows, `install.ps1 -Into <dir>` copies `.claude/settings.windows.json` (every hook → `.ps1`, each with `"shell": "powershell"`) over the target's `.claude/settings.json`, so the target runs the PowerShell hooks. Claude Code spawns those hooks with `-ExecutionPolicy Bypass` at process scope, so no machine policy change is needed. Both hook trees (`*.sh` and `*.ps1`) ship in `.claude/hooks/`.

**➜ Full Windows install guide (Korean):** [`docs/windows-install-kr.md`](docs/windows-install-kr.md) — prerequisites, `install.ps1` flags, install-time OS dispatch, `BATHOS_BIN`/PATH, verification, troubleshooting, and bash-vs-PowerShell behavior notes.

#### On Windows via WSL (Windows Subsystem for Linux)

WSL is a Linux environment, so BATHOS runs there as the **bash version** — the Linux `bathos` binary and the `.sh` hooks (not the `.ps1` PowerShell port). Work entirely **inside WSL** (Claude Code, Rust, and the clone all in WSL):

```bash
# Inside your WSL distro (e.g. Ubuntu), in the WSL filesystem (~/…, not /mnt/c):
git clone <your-fork-url> bathos && cd bathos

./scripts/wsl-setup.sh          # WSL preflight: normalize .sh to LF, chmod +x, check jq/cargo/claude
cd core && cargo build --release && cd ..   # → core/target/release/bathos (ELF)
export BATHOS_BIN="$PWD/core/target/release/bathos"
```

The one WSL gotcha is line endings: a repo cloned on Windows with `core.autocrlf=true` gives `.sh` files CRLF, which breaks the shebang under WSL (`bad interpreter: …bash^M`). The committed **`.gitattributes` forces `.sh` to LF**, and `scripts/wsl-setup.sh` repairs an already-CRLF tree. Then follow the macOS/Linux path above (bash hooks, `install.sh`).

**➜ Full WSL install guide (Korean):** [`docs/wsl-install-kr.md`](docs/wsl-install-kr.md) — WSL prerequisites, the CRLF/line-ending fix, building the Linux engine, `install.sh`, verification, and WSL-specific troubleshooting.

### 2. Use BATHOS in a project

**Option A — use this repo as your working directory.** The `.claude/` directory (commands, agents, hooks, settings) is already wired; just open Claude Code here.

**Option B — adopt it into your own project.** Copy `.claude/` (commands, agents, hooks, `settings.json`), `assets/`, and `modules/` into your project root, then set `BATHOS_BIN` as above.

### 3. Drive the pipeline (slash commands, in Claude Code)

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

### Try the engine directly

```bash
# Recommend a Scale-Adaptive level from "stakes" (recommend only; does not commit)
echo '{"scope":"feature","novelty":true,"regulation_ip":false,"team_size":"medium"}' \
  | bathos --state-dir .agent-team/_state route decide
#   → {"recommended_level":2,"wave_set":[...],"role_set":[...],"requires_confirmation":true}
```

---

## The 7-wave pipeline

```
(pre) kickoff → W0 Analysis → W1 Discovery → W2 Design
        → W3 Story Gate ★ → W5 Implementation → W6 Verify → (post) Confirm
                                  ↑
                       W4 IP & Research  (optional plug-in, off the critical path)
```

Mainline dependency: **W0 → W1 → W2 → W3 → W5 → W6**. W4 (IP & research) is an optional plug-in runnable any time after W2.

| Command | Wave | Team (parallel) | Gate |
|---|---|---|---|
| `/team-kickoff` | (pre) | lead only | — |
| `/wave0-analysis` | **W0** Analysis (optional) | Caleb | Brief Readiness |
| `/wave1-discovery` | **W1** Discovery & market | John ∥ Caleb | USP Readiness |
| `/wave2-design` | **W2** Plan · architecture · design | Joshua → (James, Jonnathan) | Plan Readiness |
| `/wave3-story-gate` | **W3** Story engineering ★ | Matthew + Thomas · Matthias + Timothy | **Implementation Readiness** |
| `/wave4-ip-research` | **W4** IP & research (plug-in) | Mark ∥ Nathanael | — |
| `/wave5-implement` | **W5** Implementation | Phillip, Andrew, Stephen | per-story completion |
| `/wave6-verify-report` | **W6** Verify · docs · report | (Thomas, Timothy, Matthias) → Michael → Hananiah → Martin | Release Readiness |
| `/team-confirm` | (post) | lead only | — |

**Why W3 is the heart.** Wave 3 closes the design→build context gap: role #17 **Matthew** condenses the upstream work into a **self-contained dev story file** (9 sections, every technical claim tagged `[Source: …]`), Thomas & Matthias review it independently, and if the verdict is `FAIL` the `gate-enforce` hook **physically blocks** entry into W5.

---

## Scale-adaptive routing (Lv0–4)

BATHOS activates only the waves a task actually needs. You confirm the level (User Sovereignty); it is recorded in `manifest.json`.

| Lv | Work type | Active waves | #17 Matthew | W4 |
|----|-----------|--------------|:---:|:--:|
| **0** | bug fix / trivial | W5 (+ minimal W6) | ✗ | ✗ |
| **1** | small feature / local refactor | light W2 + W3(slim) + W5 + light W6 | ✓ (slim) | ✗ |
| **2** | standard feature / module | W1 + W2 + W3 + W5 + W6 | ✓ | optional |
| **3** | new product / large | W0–W6 (W4 optional) | ✓ | recommended |
| **4** | enterprise / deep-tech / regulated | full W0–W6 + W4 | ✓ | required |

The recommendation is computed by the router from four stakes axes: `scope`, `novelty`, `regulation_ip`, `team_size`.

---

## Quality gates

Every wave gate uses one vocabulary:

| Verdict | Meaning | Effect |
|---|---|---|
| **PASS** | criteria met, no blockers | proceed to next wave |
| **CONCERNS** | conditional pass (non-blocking risk) | log risk in `_state/`, proceed |
| **FAIL** | blocking defect | entry blocked; remediate and re-gate |

Gates are **facilitators, not generators** — no evidence-free auto-PASS. The W3 gate is enforced by a hook (exit code `2` blocks W5). The verdict source of truth is the engine: `bathos gate show`.

---

## CLI reference (`bathos` engine)

Global options: `-s, --state-dir <PATH>` (default `./_state`), `--modules-dir <PATH>` (default `./modules`), `-h/--help`, `-V/--version`.
Exit codes: `0` success · `1` error · `2` gate FAIL (used by hooks to block).

| Command | Subcommands | Purpose |
|---|---|---|
| `state` | `init`, `validate`, `show` | Create, validate, and inspect the `manifest.json` single source of truth |
| `route` | `decide`, `show` | Scale-adaptive level recommendation (stdin/`--stakes-json`; `--confirm <0-4>` records) |
| `wave` | `init`, `activate`, `show` | 7-wave state transitions (concurrency ≤ 3 enforced) |
| `gate` | `verdict`, `show` | Record / read gate verdicts (PASS/CONCERNS/FAIL; FAIL → exit 2) |
| `story` | `compile`, `check-stale` | Story-file completeness (D1), source-trace (D2), freshness (D3) |
| `plug` | `list`, `enable`, `disable` | Toggle plugin modules (IP pack, research pack, …) |
| `audit` | `append`, `verify` | Append to / **verify** the tamper-evident audit hash-chain (`verify` → exit 1 on `E-AUDIT-TAMPER`) |
| `doctor` | — | **Install/wiring preflight** — `BATHOS_BIN`, `jq`, Agent Teams flag, `settings.json` hooks block (comment-key hang), hook exec bits, manifest schema, audit chain |

```bash
bathos -s _state state init --codename MYPROJECT       # create a schema-valid manifest seed
bathos -s _state state validate                       # validate manifest.json
bathos -s _state gate verdict Implementation PASS Matthew
bathos -s _state gate show                            # latest Implementation gate (JSON)
bathos --modules-dir modules plug list                # modules + enabled state
bathos -s _state audit append --actor hook --action tool.write --target manifest.json
```

Full reference with examples: **[`docs/USAGE-kr.md`](docs/USAGE-kr.md)** (Korean).

---

## Slash commands

34 commands ship under `.claude/commands/`:

- **Waves:** `wave0-analysis`, `wave1-discovery`, `wave2-design`, `wave3-story-gate`, `wave4-ip-research`, `wave5-implement`, `wave6-verify-report`
- **Routing:** `route`
- **Team:** `team-kickoff`, `team-status`, `team-confirm`, `team-cleanup`
- **Plan reviews (W2 reinforcement):** `autoplan`, `plan-ceo-review`, `plan-design-review`, `plan-eng-review`, `plan-devex-review`
- **Session save/restore:** `save-session`, `cold-start` (canonical — complete save & full cold-start restore); `save` / `resume` (short aliases); `context-save` / `context-restore` (gstack aliases)
- **Cross-project memory:** `project-handoff` (distill this project into `~/.bathos/registry/`), `recall` (pull relevant prior-project context into a new project)
- **Engineering ops:** `review`, `investigate`, `cso` (OWASP + STRIDE), `retro`, `health`, `guard`, `unfreeze`, `context-save`, `context-restore`

---

## The 17 roles

The lead (#0 Paul) is your main session and is never spawned. Roles #1–#17 are spawned per wave; concurrency is capped at 3.

| # | Name | Role | Model | Wave |
|---|------|------|-------|------|
| 0 | Paul | Lead / final confirm | Opus 4.8 | all (main session) |
| 1 | John | Reverse specialist | Opus 4.8 | W1 (+W0) |
| 2 | Caleb | Market analysis / USP (+W0 analyst) | Opus 4.8 | W1 (+W0) |
| 3 | Joshua | Service planning | Opus 4.8 | W2 (gate) |
| 4 | James | SW / cloud architect | Opus 4.8 | W2 |
| 5 | Mark | IP specialist (patents) | Opus 4.8 | W4 |
| 6 | Nathanael | Research writer (abstract/intro) | Sonnet 5 | W4 |
| 7 | Jonnathan | Chief designer (UX/UI) | Opus 4.8 | W2 |
| 8 | Phillip | Backend & data lead | Sonnet 5 | W5 |
| 9 | Andrew | Frontend & mobile lead | Sonnet 5 | W5 |
| 10 | Stephen | AI/ML lead | Sonnet 5 | W5 |
| 11 | Timothy | Dev-definition docs | Sonnet 5 | W6 (+W3) |
| 12 | Thomas | Code reviewer | Sonnet 5 | W6 (+W3) |
| 13 | Michael | Security specialist (defensive web/cyber audit & hardening) | Sonnet 5 | W6 (after Thomas) |
| 14 | Hananiah | Refactoring specialist (behavior-preserving) | Sonnet 5 | W6 (after Michael) |
| 15 | Matthias | QA / validation (E2E) | Sonnet 5 | W6 (+W3) |
| 16 | Martin | Monitoring / HTML report | Sonnet 5 | W6 |
| **17** | **Matthew** | **Scrum master / story engineer** | Opus 4.8 | **W3 only (idle otherwise)** |

Role definitions live in `.claude/agents/_base/` and support 3-layer override (base → team → user).

---

## Plugin modules

The core stays slim; domain capabilities are opt-in plugins under `modules/` (the core never depends on a module — A9). Each declares itself in `module.yaml`:

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

Bundled: **`ip-pack`** (patent specification drafting) and **`research-pack`** (academic abstract/introduction). Toggle with `bathos plug enable <id>` / `disable <id>`.

---

## Safety hooks

`.claude/settings.json` binds 6 deterministic, fail-safe hooks to Claude Code events (`PreToolUse`, `PostToolUse`, `TaskCompleted`, `SubagentStop`, `TeammateIdle`):

| Hook | Event | Purpose |
|---|---|---|
| `careful-guard.sh` | PreToolUse(Bash) | Block destructive commands (`rm -rf`, `DROP TABLE`, `git push --force`, `DELETE`-without-`WHERE`, `TRUNCATE`) |
| `freeze-guard.sh` | PreToolUse(Write/Edit) | Lock edits to owned paths |
| `audit-log.sh` | PostToolUse | Append every tool use to the audit chain |
| `artifact-verify.sh` | TaskCompleted / SubagentStop | Verify required artifacts / story-file completeness |
| `gate-enforce.sh` | TaskCompleted | **Block W5 entry when the W3 verdict is FAIL** |
| `next-action.sh` | TeammateIdle | Suggest the next action |

> Keep **only valid hook event names** inside the `settings.json` `hooks` block — a stray comment key there hangs subagent startup.

---

## Repository layout

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

Team artifacts a run produces live under `.agent-team/` (plan, discovery, architecture, story engineering, reviews, QA, reports, and `_state/`). Your actual product source code stays in your project’s normal paths (`src/`, …).

---

## Configuration

- **Engine state dir** — `--state-dir` (default `./_state`); the SSOT is `<state-dir>/manifest.json` (JSON-Schema-validated, atomic writes, audit hash-chain).
- **Modules dir** — `--modules-dir` (default `./modules`).
- **Engine path for hooks** — `BATHOS_BIN` env var (falls back to `core/target/debug/bathos`).
- **Role overrides** — 3-layer merge: `base` (fixed identity/model) → `team` (project owned-paths) → `user` (language/facilitation). Scalars overwrite; arrays append.

---

## Project status

**v0.2.0 — early but functional.** BATHOS builds and runs end-to-end today. Honest caveats for adopters:

- It is a **method package that runs on Claude Code**, not a standalone app, and depends on the **experimental Agent Teams** feature.
- The engine is verified: **510 Rust tests + 86 hook determinism checks, all green**; `cargo clippy -D warnings` clean; release builds reproducibly.
- It is **not yet production-hardened**; APIs, schemas, and command names may change before 1.0.
- Some wave commands are **orchestration prompts** the lead runs in Claude Code (they spawn/review teammates), not fully autonomous engine flows.

See `_state/signoff.md` and `12-report/` for the verification trail.

---

## How BATHOS was built (dogfooding)

BATHOS implemented itself and then **ran its own Wave 6 independent verification on its own code**. That pass intentionally separated *author* from *reviewer*: the functional QA looked green, yet an independent code review surfaced **blocking invariant defects the author had missed** (e.g. the Rust engine and the bash hooks were writing *incompatible* formats to the same audit chain, silently voiding tamper-evidence). Those blockers were remediated, re-gated, and the regression/backlog cleared — every known review defect resolved.

The lesson is the product’s thesis: **generation ≠ verification.** The full trail lives in `.agent-team/` (`10-review/`, `11-qa/`, `12-report/`, `_state/signoff.md`).

---

## Contributing

Contributions are welcome. BATHOS *is* a development method, so please use it on itself:

1. Open an issue describing the change and its scale (Lv0–4).
2. Keep the core slim — new domain capabilities belong in `modules/`, not the core (no reverse dependency on plugins).
3. For engine changes: `cd core && cargo test && cargo clippy --all-targets -- -D warnings` must be green; add tests for invariants.
4. For hook changes: run `bash .claude/hooks/_test-hooks.sh`; keep hooks deterministic and fail-safe.
5. Respect the gate vocabulary (PASS/CONCERNS/FAIL) and the safety hooks (`careful`, `freeze`).

Three operating principles (from `ETHOS.md`): **User Sovereignty** (AI proposes, you decide) · **Boil the Ocean** (finish completely if it’s only minutes more) · **Search Before Building**.

---

## License & attribution

Released under the **MIT License** — see the full text below.

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

**Lineage and acknowledgment.** BATHOS is an independently implemented work. Its method design was re-implemented from first principles following a rigorous reverse analysis of **[BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD)** (MIT © 2025 BMad Code, LLC), from which it inherits its foundational design vocabulary.

We name this lineage by choice, not obligation. A system whose central tenet is that *generation must remain answerable to verification* would contradict itself by obscuring the prior art it stands on. BATHOS therefore records its debt to BMAD-METHOD plainly and with genuine respect — it charted the terrain that BATHOS set out to deepen. In accordance with the MIT License, BMAD-METHOD’s copyright and license notice are preserved in [`LICENSE`](LICENSE); the full acknowledgment lives in [`CREDITS.md`](CREDITS.md).

BATHOS is a separate, independently implemented project and does **not** use the trademarks “BMAD”, “BMad Method”, “BMad Builder”, “BMB”, “TEA”, “CIS”, “GDS”, or “WDS” in its product name or marketing.

---

<div align="center">

**BATHOS** · βάθος — depth over surface
한국어 문서: [`docs/USECASE-kr.md`](docs/USECASE-kr.md) · [`docs/FEATURES-kr.md`](docs/FEATURES-kr.md) · [`docs/USAGE-kr.md`](docs/USAGE-kr.md) · [`docs/macos-linux-install-kr.md`](docs/macos-linux-install-kr.md) · [`docs/windows-install-kr.md`](docs/windows-install-kr.md) · [`docs/wsl-install-kr.md`](docs/wsl-install-kr.md) · [`docs/QUOTA-kr.md`](docs/QUOTA-kr.md) · [`docs/MODULE-GUIDE-kr.md`](docs/MODULE-GUIDE-kr.md) · [`CLAUDE.md`](CLAUDE.md) · [`ETHOS.md`](ETHOS.md)

</div>
