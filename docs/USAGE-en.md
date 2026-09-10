# BATHOS Usage Guide (v0.4.0)

> **BATHOS** — βάθος, Greek for "depth; the deep." The name signals an ambition: an **AI Workflow Agent method package of overwhelming depth**, the exact opposite of knowledge that skims the surface.
> On a single runtime — Claude Code — it orchestrates the entire product-development lifecycle with a **17-role × 7-wave × Scale-Adaptive Lv0–4** structure.
> This document is written against the **actually built deliverables (B1–B4)**, not concepts. Anything not yet implemented or still stubbed is stated plainly rather than hidden.
>
> **See also:** If you're new, start with the [use case (building a new service)](USECASE-en.md) to get a feel → then [features & mechanics](FEATURES-en.md) to understand the principles → then come back to this usage guide. · 한국어: [USAGE-kr](USAGE-kr.md) · Español: [`USAGE-es.md`](USAGE-es.md)

---

## 0. Core concept — distinguish the two execution planes

There's exactly one thing to grasp before using BATHOS properly. BATHOS runs simultaneously on **two layers** of completely different character. The moment you separate the two, most of the rest of the usage follows naturally.

| Layer | What it is | What it does | Who runs it |
|-------|-----------|--------------|-------------|
| **Orchestration plane** | Claude Code slash commands (`.claude/commands/*.md`) + roles (`.claude/agents/`) + hooks (`.claude/hooks/`) | Advances waves; spawns, inspects, and shuts down teammates | **The lead (Paul) = the main Claude Code session** |
| **Engine plane** | The `bathos` single static binary (Rust) | **Deterministically** computes and enforces state (SSOT) · gates · wave transitions · routing · stories · plugs | Hooks/commands invoke `bathos <subcommand>` internally |

> In short: what you type by hand is usually a **slash command** (like `/wave1-discovery`). The `bathos` binary is the underlying engine that **hooks and commands call for you**. Of course, you can also drive both directly when needed.

---

## 1. Requirements · installation · wiring into a target project

### 1.1 Prerequisites
- **Claude Code v2.1.32 or later**
- **Agent Teams experimental feature enabled** — `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (already set in the package's `bathos/.claude/settings.json`).
- **Rust toolchain** (to build the engine) — verified with cargo 1.92.0.

### 1.2 Building the engine
```bash
cd bathos/core
cargo build --release        # → target/release/bathos (single static binary, ~5.7MB)
cargo test                   # full verification (18 test groups)
cargo clippy --all-targets -- -D warnings   # lint (0 warnings)
```
Put the build output `bathos/core/target/release/bathos` on your PATH, or point the `BATHOS_BIN` environment variable at it so the hooks can find it (if unset, the default lookup path is `core/target/debug/bathos`).

### 1.3 Wiring into a target project (install · adopt)

> **Key point:** BATHOS is not a monolithic app — it's a **method package that runs on Claude Code** (see the two execution planes in §0). So "wiring" here means two things: **① build the engine binary once, and ② plant the orchestration assets (`.claude/` · `assets/` · `modules/`) into the target project.**

#### 1.3.1 `install.sh` — build the engine + inject `.claude/`
`install.sh` does two things. And **it deletes nothing.** If a `.claude/` already exists, it refuses to overwrite without `--force`.

```bash
# A) Build the engine only (+ prints next-step guidance)
./install.sh

# B) Build the engine + copy the method package into a target project
./install.sh --into /abs/path/to/your-project
#   → cp -R  .claude/  assets/  modules/  into your-project/
```

The three things copied into the target project are the **"wiring assets"** planted in it:
- **`.claude/`** — 32 slash commands + 17 role base definitions + 6 safety hooks + `settings.json` (including the Agent Teams flag)
- **`assets/`** — templates/workflows/checklists referenced by the W3 story engine and the plugs
- **`modules/`** — plug modules (`ip-pack`, `research-pack`)

#### 1.3.2 Making the hooks find the engine (required env vars)
The copied hooks call the `bathos` binary, so you must tell them where it lives:

```bash
export BATHOS_BIN="/abs/path/to/bathos/core/target/release/bathos"
#   (if unset, falls back to core/target/debug/bathos — release recommended)
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1   # also already set in settings.json
```

#### 1.3.3 Two adoption styles
| | Style A — use the BATHOS repo as the working directory | Style B — adopt into your own project |
|---|---|---|
| **How** | Open Claude Code right inside `bathos/` (`.claude/` is already wired) | Copy `.claude/` · `assets/` · `modules/` via `install.sh --into` |
| **Best for** | Hacking on BATHOS itself, or a quick trial | Applying it to your actual product project |

### 1.4 The two directories that appear in the target project (important)

Once wired, the target project gains **two paths of different character** side by side. The two never mix:

```
your-project/
├── .claude/          ← (wiring assets) commands · roles · hooks · settings   ※ injected by install
├── .agent-team/      ← (runtime output) team work & output metadata          ※ created by /team-kickoff
│   ├── 00-plan/ ... 12-report/
│   └── _state/manifest.json   ← SSOT (all state in one JSON; schema-validated + audit hash chain)
└── src/ ...          ← your actual product source code (in its usual place)
```

- **`.agent-team/`** holds the work products BATHOS produces (planning, design, stories, reviews, QA, reports, state).
- Meanwhile, **your actual product code accumulates in its usual place, like `src/`.** Think of BATHOS as the **"process"** laid on top of it.

> **One-line summary:** plant `.claude/` · `assets/` · `modules/` with `install.sh --into <target>` → set `BATHOS_BIN` and the Agent Teams flag → open Claude Code in the target and run `/team-kickoff` → `/route` → the wave commands in order, each with an absolute-path argument. **Outputs accumulate in `.agent-team/`, real code in `src/`, and the key invariants are enforced by the `bathos` Rust engine.**

### 1.5 Package layout
```
bathos/
├── core/                      # Rust workspace (the engine)
│   ├── Cargo.toml             # 7-crate workspace
│   └── crates/
│       ├── bathos-state/      # M1 state SSOT (manifest.json · audit chain)
│       ├── bathos-router/     # M2 Scale-Adaptive router (Lv0–4)
│       ├── bathos-wave-engine/# M3 7-wave transitions (concurrency ≤ 3)
│       ├── bathos-gate-engine/# M4 gate verdicts (PASS/CONCERNS/FAIL)
│       ├── bathos-story-engine/#M5 story compilation · staleness
│       ├── bathos-plug/       # M12 plug module manager
│       └── bathos-cli/        # bin: bathos
├── .claude/
│   ├── agents/_base/          # M8 17 role base definitions (00-paul … 17-matthew)
│   ├── commands/              # M7 32 slash commands
│   ├── hooks/                 # M6 6 safety/event hooks + test harness
│   └── settings.json          # hook bindings + Agent Teams enabled
├── assets/                    # M9 templates · workflows · checklists · glossary
├── modules/                   # plug modules (W4)
│   ├── ip-pack/               # M10 patent application specification module
│   └── research-pack/         # M11 paper Abstract/Introduction module
├── CLAUDE.md  ETHOS.md  README.md  VERSION
└── docs/USAGE-en.md           # (this document)
```

---

## 2. Quick Start

Open a Claude Code session (= the lead, Paul) at the root of your target project, then advance the waves one at a time via slash commands.

```
# 1) Kickoff — initialize the .agent-team skeleton + charter + manifest
/team-kickoff

# 2) Route the work size — get a Lv0–4 recommendation from the stakes; the user confirms
/route /abs/path/to/project

# 3) Run the waves of the recommended level in order (e.g. Lv2–3)
/wave1-discovery   /abs/path
/wave2-design      /abs/path
/wave3-story-gate  /abs/path     # ← the heart: Readiness Gate (must PASS to enter W5)
/wave5-implement   /abs/path
/wave6-verify-report /abs/path

# 4) (Optional · off-mainline) IP/paper plug
/wave4-ip-research /abs/path

# 5) Progress check / final confirmation
/team-status
/team-confirm
```

> **Mainline dependencies:** W0 → W1 → W2 → **W3** → W5 → W6. **W4 (IP & Research) is an optional plug** that can be inserted any time after W2.
> Each wave shuts down its teammates when it ends and moves on to the next (keeping concurrent active teammates ≤ 3 is recommended).

---

## 3. The 7-wave workflow

| Command | Wave | Teammates (concurrent) | Gate |
|---------|------|------------------------|------|
| `/team-kickoff` | (pre) | Lead alone | — |
| `/wave0-analysis` | **W0** Analysis (optional) | Caleb (doubling as Analyst) | Brief Readiness |
| `/wave1-discovery` | **W1** Discovery · Market | John ∥ Caleb | USP Readiness |
| `/wave2-design` | **W2** Planning · Architecture · Design | Joshua → (James, Jonnathan) | Plan Readiness |
| `/wave3-story-gate` | **W3** Story engineering · Gate ★ | Matthew (#17) + Thomas · Matthias (independent review) + Timothy | **Implementation Readiness (dual)** |
| `/wave4-ip-research` | **W4** IP · Research (plug) | Mark ∥ Nathanael | none |
| `/wave5-implement` | **W5** Implementation | Phillip, Andrew, Stephen | Per-story completion |
| `/wave6-verify-report` | **W6** Verification · Docs · Report | (Thomas, Timothy, Matthias) → Michael → Hananiah → Martin | Release Readiness |
| `/team-confirm` | (post) | Lead alone | — |

Each slash command takes the **absolute path of the target project** (`$1`) as an argument. A command spawns teammates from the lead session, inspects their outputs, adjudicates the gate, and shuts the teammates down. Handoffs between teammates happen exclusively via **disk files** (`.agent-team/...`) — never via conversation history.

### Why W3 is the heart
Between design (W2) and implementation (W5) there is always a **crack where context leaks out**. W3 blocks that crack head-on. #17 Matthew condenses the W2 outputs into **self-contained dev story files** (9 sections, with `[Source:...]` evidence on every technical detail), and Thomas and Matthias review them independently. If the verdict comes back **FAIL, the `gate-enforce` hook physically blocks entry into W5** (§7).

---

## 4. Scale-Adaptive routing (Lv0–4)

BATHOS **explicitly adjusts which waves and roles run** to match the size of the work — it never runs everything at full throttle by default. Feed the stakes into `/route` to get a recommended level; **the final decision belongs to the user** (User Sovereignty). The current level is recorded in `current_level` in `_state/manifest.json`.

| Lv | Work type | Waves run | #17 Matthew | W4 |
|----|-----------|-----------|:----:|:--:|
| **Lv0** | Bug fix · trivial change | W5 only (+ultra-light W6) | ✗ | ✗ |
| **Lv1** | Small feature · local refactor | light W2 + W3 (abridged) + W5 + light W6 | ✓ (abridged) | ✗ |
| **Lv2** | Standard feature/module | W1 + W2 + W3 + W5 + W6 | ✓ | optional |
| **Lv3** | New product · large | W0–W6 (W4 optional) | ✓ | optional (recommended) |
| **Lv4** | Enterprise · deep-tech · regulated | full W0–W6 + full W4 | ✓ | ✓ required |

The recommendation rules that map stakes to a level are computed by `bathos-router`. Stakes have four axes — `scope`, `novelty`, `regulation_ip`, `team_size`. (See the `route.md` command for the mapping table.)

---

## 5. The gate system (PASS / CONCERNS / FAIL)

Every wave gate shares **one vocabulary**.

| Verdict | Meaning | Action |
|---------|---------|--------|
| **PASS** | Criteria met, no blockers | Enter the next wave immediately |
| **CONCERNS** | Conditional pass (non-blocking risks) | Log the risks to `_state/` and proceed |
| **FAIL** | Blocking defects | Entry blocked; fix, then **re-gate** |

The principle is clear. The gate is a **FACILITATOR that assists the verdict, not a generator that fabricates one** — an unsubstantiated auto-PASS is not allowed. The key W3 gate is hard-enforced by a hook, and the gate's deciding party (`facilitator`) can never be empty (an invariant).

---

## 6. CLI reference (the `bathos` binary)

Global options (common to all subcommands):
- `-s, --state-dir <PATH>` — state directory (default `./_state`)
- `--modules-dir <PATH>` — plug module directory (default `./modules`)
- `-h, --help` · `-V, --version`

**Exit-code convention:** `0` = success · `1` = general error · `2` = gate FAIL (used by hooks to block entry).

### 6.1 `bathos state` — state SSOT (B1)
```bash
bathos --state-dir .agent-team/_state state init \
       --codename MYPROJECT                            # create a schema-valid manifest.json seed
bathos --state-dir .agent-team/_state state validate   # validate manifest.json against the JSON Schema (VALID/violation list)
bathos --state-dir .agent-team/_state state show        # print the current state JSON
```

`state init` creates the minimal valid state with defaults `level=0`, `lang=ko`,
and an automatic `project_id=bathos-<uuid>`. It refuses to replace an existing
manifest unless `--force` is given. `/team-kickoff` calls it for normal use.

### 6.2 `bathos gate` — gate verdicts (B3)
```bash
# Record a verdict — GATE_TYPE: Brief|Usp|Plan|Implementation|Release / VERDICT: PASS|CONCERNS|FAIL
bathos -s _state gate verdict Implementation PASS Matthew
bathos -s _state gate verdict Implementation FAIL Matthew \
       --issues-json '[{"level":"critical","description":"...","source":"..."}]'
#   → recording a FAIL exits with code 2

# Query the latest Implementation gate (the SSOT gate-enforce.sh consults)
bathos -s _state gate show
#   → {"gate_type":"Implementation","verdict":"PASS","issues_total":0,"issues_critical":0,...}
#   no gate → empty output (exit 0)
```
- Options: `--report <path>`, `--story-key <key>`, `--issues-json <JSON array>`
- **Issue level enum:** `critical` | `enhancement` | `optimization` (a single `critical` means FAIL).

### 6.3 `bathos story` — story verification (B3)
```bash
# D1 completeness + D2 source tracing (stdin or --file)
bathos story compile 1-2-payment-auth --file story-1-2-en.md
#   → {"is_valid":true,"missing_sections":[],...}  / on failure exit 1 (E-CTX-LOSS)

# D3 freshness (staleness) — stored hash vs. current upstream files
bathos story check-stale 1-2-payment-auth \
       --stored-hash <sha256> --upstream archi.md --upstream design.md
#   → fresh: "FRESH" exit 0 / stale: E-STALE exit 1
```

### 6.4 `bathos wave` / `bathos route` (B2)
```bash
bathos -s _state wave activate W2     # transition a wave to active (enforces concurrent active ≤ 3, else E-CONCURRENCY)
bathos -s _state wave show            # all wave states as JSON
bathos -s _state route show           # level decision history

# Recommend a level from stakes (JSON) — stdin or --stakes-json. Default is recommend-only (no commit).
echo '{"scope":"feature","novelty":true,"regulation_ip":false,"team_size":"medium"}' \
  | bathos -s _state route decide
#   → {"recommended_level":2,"wave_set":[...],"role_set":[...],"requires_confirmation":true}

# --confirm <0-4>: the user explicitly confirms → recorded in manifest routing[] + current_level updated
bathos -s _state route decide \
  --stakes-json '{"scope":"product","novelty":true,"regulation_ip":true,"team_size":"large"}' --confirm 4
```
- `route decide` **deliberately separates recommendation from confirmation** (User Sovereignty). Without arguments it only recommends; only with `--confirm <level>` does it actually record.
- The 4 stakes axes: `scope` (bug|feature|module|product…) · `novelty` (bool) · `regulation_ip` (bool) · `team_size` (solo|medium|large).

### 6.5 `bathos plug` — plug modules (B4)
```bash
bathos --modules-dir modules plug list              # module list + enabled state (JSON)
bathos -s _state --modules-dir modules plug enable ip      # enable a module (persisted)
bathos -s _state --modules-dir modules plug disable ip     # disable a module
#   nonexistent module → exit 1 (E-PLUG-NOTFOUND)
```

### 6.6 `bathos audit` — audit log (B-1)
```bash
# append: via the single Rust writer (format unified with the bash hooks). Always exit 0 (avoids blocking hooks).
bathos -s _state audit append --actor hook --action tool.write --target manifest.json

# verify: verify the integrity of the audit hash chain (check the tamper-evident promise directly)
bathos -s _state audit verify
#   → intact: "OK — audit hash chain intact (N entries ...)" exit 0
#   → tampered/broken: "[E-AUDIT-TAMPER] ... seq=N hash_prev mismatch ..." exit 1
```

### 6.7 `bathos doctor` — install/wiring preflight diagnostics
```bash
bathos -s .agent-team/_state doctor --root .
#   checks: BATHOS_BIN · jq · Agent Teams flag · comment-key trap in settings.json hooks ·
#           hook presence/executability · assets · modules · manifest schema · audit chain
#   → prints a ✓//✗ checklist. Exit 0 if zero errors, exit 1 if any.
```
- Run it once right after `install.sh`. It deterministically catches, in particular, **the trap where a comment key (`_note`, etc.) mixed into the `hooks` block of settings.json causes an infinite wait** (§13 troubleshooting).
- `--root` is the base path for finding `.claude/` · `assets/` · `modules/` (defaults to the current directory), and `-s` points at the manifest and audit chain.

---

## 7. Hooks / safety layer (M6)

`bathos/.claude/settings.json` binds hooks to each Claude Code event. Every blocking hook is **deterministic and fail-safe** by design — when in doubt, it leans toward blocking.

| Hook | Event | Role | Blocks (exit 2) when |
|------|-------|------|----------------------|
| `careful-guard.sh` | PreToolUse(Bash) | Blocks destructive commands | `rm -rf` · `DROP TABLE` · `git push --force`, etc. |
| `freeze-guard.sh` | PreToolUse(Write/Edit/MultiEdit) | Locks the edit scope | Edit outside `BATHOS_OWNED_PATHS` |
| `audit-log.sh` | PostToolUse | Appends to the audit log | (non-blocking) `_state/audit-log.jsonl` |
| `artifact-verify.sh` | TaskCompleted | Verifies artifacts exist | Missing artifacts on QA/W3 tasks |
| `gate-enforce.sh` | TaskCompleted | **W3 FAIL → physically blocks W5 entry** | W5-entry task + W3 verdict=FAIL |
| `next-action.sh` | TeammateIdle | Suggests the next action | (non-blocking) |

**How `gate-enforce` runs:** on detecting a W5-entry task → it queries the latest Implementation verdict via `bathos gate show` → if the value is `FAIL`, exit 2 blocks; if `PASS` or `CONCERNS`, exit 0 allows. If the binary or the gate is absent, it follows the fail-safe principle: warn and pass.

> **Operational note:** the `hooks` block in `settings.json` must contain **valid hook event names only**. Mixing in comment keys (`_note`, etc.) sends subagents into an infinite wait at startup.

To verify the hooks themselves: `bash .claude/hooks/_test-hooks.sh` (46 determinism tests, all PASS).

---

## 8. The 17 roles (M8)

Base definitions live in `bathos/.claude/agents/_base/`. Overrides are 3-layered (base→team→user); scalar values are overwritten and arrays are appended.

| # | Name | Role | Model | Wave |
|---|------|------|-------|------|
| 0 | Paul | Overall lead / final confirm | Opus 4.8 | all waves (main session) |
| 1 | John | Reverse Specialist | Opus 4.8 | W1 (+W0) |
| 2 | Caleb | Market analysis/USP (+W0 Analyst) | Opus 4.8 | W1 (+W0) |
| 3 | Joshua | Service planning | Opus 4.8 | W2 (gate) |
| 4 | James | SW · cloud architect | Opus 4.8 | W2 |
| 5 | Mark | IP Specialist (patents) | Opus 4.8 | W4 (plug) |
| 6 | Nathanael | Paper Abstract/Intro | Sonnet 5 | W4 (plug) |
| 7 | Jonnathan | Principal designer (UX/UI) | Opus 4.8 | W2 |
| 8 | Phillip | Backend · data principal | Sonnet 5 | W5 |
| 9 | Andrew | Frontend · mobile principal | Sonnet 5 | W5 |
| 10 | Stephen | AI/ML principal | Sonnet 5 | W5 |
| 11 | Timothy | Development definition docs | Sonnet 5 | W6 (+W3) |
| 12 | Thomas | Code reviewer | Sonnet 5 | W6 (+W3 independent review) |
| 13 | Michael | Security audit/hardening (defensive web/cyber) | Sonnet 5 | W6 (after Thomas) |
| 14 | Hananiah | Refactoring (behavior-preserving) | Sonnet 5 | W6 (after Michael) |
| 15 | Matthias | QA/verification (E2E) | Sonnet 5 | W6 (+W3 independent review) |
| 16 | Martin | Monitoring/HTML report | Sonnet 5 | W6 (aggregation) |
| **17** | **Matthew** | **Scrum Master / Story Engineer** | Opus 4.8 | **W3 only (idle otherwise)** |

> Paul is the **main session** and is never spawned as a teammate. #17 Matthew is spawned **only while W3 is active**, so he consumes no tokens the rest of the time. His agent-type slug is `matthew-story-engineer`.

---

## 9. Plug modules (W4 extensions)

The core stays slim; domain features are **toggled on and off as plug modules.** The core doesn't know the modules exist — reverse dependencies are forbidden (A9). Each module declares itself via `modules/<id>/module.yaml`.

### 9.1 The module.yaml contract
```yaml
module_id: ip                      # ip | research | game | security ...
name: IP Pack
wave: W4
trigger: "Lv>=3 OR domain=ip"      # auto-trigger condition (Lv comparisons + domain= , OR-joined)
enabled_default: false
provides:
  workflows: [patent-spec-draft]
  templates: [patent-spec]
outputs: ".agent-team/05-ip/"
evidence_trace: true               # claims → [Source:] evidence tracing
```

### 9.2 Bundled modules
| Module | id | Output | Workflow |
|--------|----|--------|----------|
| IP pack (Mark) | `ip` | `.agent-team/05-ip/` | `patent-spec-draft` (patent-office-format application spec) |
| Research pack (Nathanael) | `research` | `.agent-team/06-research/` | `abstract-introduction` (academic Abstract+Intro) |

### 9.3 Trigger syntax (`bathos-plug`)
- `Lv>=N` `Lv>N` `Lv<=N` `Lv<N` `Lv=N` (N=0–4) · `domain=X` / `domain:X`
- Joined with ` OR `, it triggers when any term is true. Unparseable tokens are treated as `false` (conservatively).

---

## 10. Assets (M9, `assets/`)

A collection of assets — consistently written in Korean — referenced by the W3 story engine and the plugs.
- `templates/` — `story-template.md`, `project-context-template.md`, `readiness-report-template.md`, `session-snapshot-template.md`, `design-system-template.md` (design tokens · component contracts)
- `workflows/` — `create-story.md` (story compilation procedure), `check-implementation-readiness.md` (gate procedure), `design-excellence.md` (top-tier UI/UX in 10 steps)
- `checklists/` — `story-context-quality.md` (adversarial re-verification of the 8 fatal mistakes), `design-quality.md` (design quality, 11 dimensions, 0–10 rubric)
- `_index.md`, `_glossary-kr.md` (glossary)

---

## 11. State model & directory conventions

### 11.1 SSOT — `_state/manifest.json`
All project state is inlined in a single JSON (validated by JSON Schema). Key fields:
`project_id` (`bathos-<uuid>`), `codename`, `current_level` (0–4), `status` (active|paused|done), `lang`, `created`, plus the 1:N arrays — `routing[]` (LevelDecision), `waves[]`, `roles[]`, `tasks[]`, `gates[]` (GateVerdict), `risks[]`, `modules[]` (PlugModule), `artifacts[]`.
Every write is recorded via **atomic writes + the audit hash chain** (`audit-log.jsonl`).

### 11.2 Output directory `.agent-team/`
```
00-plan/  00-analysis/  01-reverse/  02-market-analysis/  03-service-planning/
03-story-engineering/   04-architecture/  05-ip/  06-research/  07-design/
08-impl-notes/  09-docs/  10-review/  11-qa/  12-report/  _state/
```
**Actual product source code** stays in its usual place at the project root (`src/`, etc.); `.agent-team/` accumulates only the team's work and output metadata.

---

## 12. Operational commands & gstack reinforcements

- **Team:** `/team-kickoff` · `/team-status` · `/team-confirm` · `/team-cleanup` (emergency cleanup)
- **Session save/restore:** `/save-session` (full save) · `/cold-start` (full restore in a new session). Short aliases `/save` · `/resume`, gstack aliases `/context-save` · `/context-restore`. See §12.1.
- **Cross-project memory:** `/project-handoff` (distill the current project into `~/.bathos/registry/`) · `/recall` (recall relevant earlier projects' context in a new project). See §12.1.
- **Safety:** `/guard` (activate careful+freeze) · `/unfreeze`
- **Plan-review gates (W2 reinforcement):** `/plan-ceo-review` · `/plan-design-review` · `/plan-eng-review` · `/plan-devex-review` · `/autoplan` (runs all four in sequence)
- **Other:** `/review` (PR review) · `/investigate` (root-cause debugging) · `/cso` (OWASP+STRIDE security audit) · `/retro` · `/health` · `/context-save` · `/context-restore`

### 12.1 Session save & cold start (complete, lossless handoff)

Real builds stretch across multiple Claude Code sessions. Yet teammates **do not inherit the lead's conversation history.** So BATHOS persists everything to disk, letting even a brand-new session with zero context restore it completely. The two canonical commands (no arguments needed — they default to the current project's `.agent-team/_state`):

**`/save-session` — saves *all* session information.** Run it before you stop working. It leaves two deliverables (+ a dated archive):

| Deliverable | What it holds |
|-------------|---------------|
| `_state/session-state.json` | The complete machine SSOT — the full manifest (`routing` · `waves` · `roles` · `tasks` · `gates` · `risks` · `modules` · `artifacts`) dumped via `bathos state show`. |
| `_state/SESSION-SNAPSHOT.md` | The human-readable narrative — its **"★ Current status"** paragraph is the cold-start entry point (one-paragraph summary + the next command to run). |

On top of that it also captures audit-chain verification (`bathos audit verify`), the product code's git status, the `.agent-team/` inventory, and this session's decisions, the in-progress wave, teammates to respawn, remaining work, and the next command.

**`/cold-start` — restores everything in a new session.** Run it in a fresh session with zero context. It reads `SESSION-SNAPSHOT.md` → `session-state.json` → `manifest.json` → `wave-log.md`/`signoff.md` in order, cross-checks the three state sources for drift, verifies audit integrity, and then delivers a complete briefing: project identity, current level, wave states and gate verdicts, what's already done, what was in progress, **which teammates to respawn** (via the relevant `/waveN-…` commands — artifacts remain on disk, so nothing is lost), outstanding risks, and **▶ the next command to run**. The process is read-only and never auto-advances the next step on the user's behalf (User Sovereignty).

```text
# At the end of a session:
/save-session            # (or /save — identical)

# At the start of the next session, in the same project directory:
/cold-start              # (or /resume — identical)
```

> **Aliases & triggers.** `/save` = `/save-session`, `/resume` = `/cold-start`, and `/context-save` · `/context-restore` are the gstack aliases. All share the same `_state`/SSOT. Natural language works too: "save session / save / checkpoint" → save, "cold start / continue / resume / load" → restore.
> **Usage-limit note.** If a teammate suddenly goes quiet, it's usually a quota limit rather than a crash — save with `/save-session`, wait for the reset, restore with `/cold-start`, and re-run the wave. See [`QUOTA-en.md`](QUOTA-en.md).

**Cross-project memory (warm cold-starts across projects).** The two commands above are confined to a single project. Context that must cross project *boundaries* — decisions to reuse, recurring patterns, lessons learned the expensive way — accumulates in the global registry `~/.bathos/registry/` (`INDEX.md` + per-project `<slug>.md` cards):
- **`/project-handoff`** — distills the current project into a registry card. `/save-session` performs this upsert automatically, so memory builds up naturally with every save.
- **`/recall`** — pulls relevant earlier project cards (decisions/patterns to reuse + lessons to avoid) into a new project for a **warm start**. `/cold-start` also consults the registry.

In other words, **even in a different project and a different session**, what was learned in earlier projects is reused in depth. Recall remains a suggestion (User Sovereignty) — the user sets this project's direction.

### The three gstack principles (ETHOS.md)
1. **User Sovereignty (supreme):** the AI proposes, **the user decides.** Direction-changing recommendations are asked as "recommendation + rationale + missed context."
2. **Boil the Ocean:** if the complete implementation costs only a few more minutes, choose complete. Don't defer tests and edge cases.
3. **Search Before Building:** in unfamiliar territory, search first to map the terrain.

---

## 13. Troubleshooting (field lessons)

| Symptom | Cause | Fix |
|---------|-------|-----|
| Infinite wait at subagent startup | Comment key mixed into the `settings.json` `hooks` block | Keep only valid event names · **detect with `bathos doctor`** (§6.7) |
| A teammate seems stuck with no output | Claude account **usage (session) limit** — not a code bug | Wait for the reset, then respawn (artifacts persist on disk, lossless). Details: [`QUOTA-en.md`](QUOTA-en.md) |
| Unsure whether install/wiring is correct | — | Run **`bathos doctor`** (§6.7) |
| `state validate` rejects a valid manifest | Confusing the old (operational) schema with the bathos-product schema | Use the bathos manifest schema (§11.1) |
| `gate verdict ... noncritical` fails to parse | Wrong issue level enum | Use `critical`/`enhancement`/`optimization` |
| Role-name collisions when running multiple projects at once | Same agent type/name colliding in the swarm registry | Add a per-project unique suffix, or run one at a time |
| Teammate doesn't respond to shutdown | The TeammateIdle hook re-triggered it | `tmux -L claude-swarm-<pid> kill-pane -t <id>` (work is preserved on disk) |
| `gate-enforce` doesn't block | Hook input field mismatch (`.title`/`.description`) or no gate recorded | Check the input shape and the `bathos gate show` output |

---

## 14. Current implementation status & limits (honesty notice)

**v0.4.0 — early, but it actually works.** BATHOS builds and runs end-to-end today. For anyone weighing adoption, stated honestly:

- This is **not a standalone app but a method package running on Claude Code v2.1.32+**, and it depends on the **experimental Agent Teams feature**.
- **The engine is verified:** **628 Rust tests + 86 hook determinism tests, all green**, `clippy -D warnings` clean, `cargo build --release` reproduces successfully; gate hard-enforcement and plug integration were confirmed end-to-end, and the core's independence from modules (A9) was proven.
- **Fully independent certification completed (dogfooding):** BATHOS applied its own W6 independent verification to its own code. Both certifications — **ThomasCert (independent code review, PASS) and MatthiasCert (independent QA/E2E, PASS)** — passed, reaching **Release Readiness = PASS (fully independent certification)**. The interesting part: even though functional QA was green, the independent code review caught a **blocking invariant defect the author had missed** — the Rust engine and the bash hooks were writing to the same audit chain in mutually incompatible formats, neutralizing tamper-evidence. It was fully resolved via fix, re-gate, and backlog burn-down. Verification trail: `.agent-team/` (`10-review/` · `11-qa/` · `12-report/w6-final-certification.html` · `_state/signoff.md`).
- Some wave commands are **orchestration prompts the lead runs directly** (spawning/inspecting teammates), not fully automated engine flows.
- **Not production-hardened yet** — APIs, schemas, and command names may change before 1.0.

> **The methodological thesis:** what the dogfooding above proved is precisely **"generation ≠ verification."** When the same model writes and self-approves, blind spots always remain. That's why BATHOS separates author from verifier, positions the gate as a FACILITATOR, and nails the key invariants down in the Rust engine.

---

## 15. License

BATHOS is a package independently implemented from first principles after a careful reverse analysis of BMAD-METHOD (MIT © 2025 BMad Code, LLC); with respect for that foundational prior work, it is distributed under the **MIT License**. The original authors' trademarks — "BMAD"/"BMad Method", etc. — are not used in the product name or marketing. (Full text: see `README.md`.)

---

*Document version: v0.4.0 · Author: lead Paul · Basis: the actually built deliverables (B1–B4).*
[USAGE-kr](USAGE-kr.md) · [USAGE-es](USAGE-es.md)
