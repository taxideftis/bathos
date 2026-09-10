# BATHOS — Features & How It Works

> **βάθος** (Greek) — *"depth; the deep."* An AI Workflow Agent method of overwhelming depth, deliberately positioned against surface-level AI assistance.
>
> Think of this as the "why, and how" companion to the usage guide. It explains **what BATHOS is (features) and how it actually works inside (mechanics)**. Everything here is written against the **actual v0.4.0 build** — every mechanism below is implemented and verified, and where there are limits, they are stated plainly rather than hidden.
>
> **See also:** If you'd rather run it than understand it first, go to the [usage guide](USAGE-en.md). Operating rules live in [`../CLAUDE.md`](../CLAUDE.md), and the principles behind them in [`../ETHOS.md`](../ETHOS.md). · 한국어: [`FEATURES-kr.md`](FEATURES-kr.md) · Español: [`FEATURES-es.md`](FEATURES-es.md)

---

## 0. The one idea underneath everything

A long single LLM conversation **drifts**: context leaks between "design" and "implementation," quality checks get skipped, and *the same model* both writes the work and approves it. BATHOS's thesis is one sentence:

> **Generation ≠ verification.** A generator cannot see the blind spots in its own output.

So BATHOS replaces one drifting conversation with **structure**: separated specialist roles, a staged pipeline, *independent* verifiers, and a small **deterministic engine** that enforces the key invariants **in code**, not by the model's goodwill.

This is not a metaphor — it is literally how BATHOS was built. BATHOS implemented itself, then ran Wave 6 independent verification on its own code. Functional QA was green, yet the independent code review caught a **blocking invariant defect the author had missed** (the Rust engine and the bash hooks were writing to the same audit chain in *incompatible* formats → tamper-evidence silently neutralized). It was fixed, re-gated, and the backlog burned down — a demonstration of the thesis.

---

## 1. Features (what sets BATHOS apart)

Before diving into mechanics, here's the big picture — twelve features and what each actually gives you.

| # | Feature | What it gives you |
|---|---------|-------------------|
| 1 | **17 specialist roles × 7-wave pipeline** | A single Claude Code session behaves like a disciplined product team (discovery → design → story → build → verify) instead of one ever-bloating conversation. |
| 2 | **Two execution planes: markdown orchestration + Rust engine** | Human-facing workflows stay as editable markdown, while a single static binary deterministically computes and *enforces* the key invariants. |
| 3 | **Scale-Adaptive routing (Lv0–4)** | Only the waves the work actually needs are run. A bug fix isn't shoved through full discovery, and an enterprise build isn't under-scoped. |
| 4 | **Zero-context-loss story files (Wave 3)** | Self-contained dev story files with `[Source: …]` on every technical detail close the design→implementation context gap head-on. |
| 5 | **Hard quality gates (PASS / CONCERNS / FAIL)** | A `FAIL` at the readiness gate isn't advisory — a hook (exit code 2) *physically blocks* entry into implementation. |
| 6 | **Independent verification + tamper-evident audit chain** | Verifiers are separated from authors, and every state change is recorded in an append-only sha256 hash chain. |
| 7 | **User Sovereignty** | The AI proposes; *the user* decides. Recommendations that would change the user's stated direction are presented as "recommendation + rationale + missed context" and never executed unilaterally. |
| 8 | **Safety hooks (careful / freeze)** | Destructive commands are blocked and edits are locked to owned paths. Fail-safe design (when in doubt, block). |
| 9 | **Plug modules (slim core, opt-in domains)** | The IP/patent and research packs are plugs; the core knows nothing about modules (no reverse dependency). New domains plug in without bloating the core. |
| 10 | **3-layer role overrides** | Role identity is pinned in the base layer, while project and user layers override owned paths / language / facilitation intensity without forking. |
| 11 | **One-word session save/resume** | `/save` snapshots the entire session and `/resume` restores it in the next one. Works in natural language too ("save"/"continue") → multi-session work never loses context. |
| 12 | **Cross-project memory** | A global registry (`~/.bathos/registry/`) lets even a brand-new project warm-start from earlier projects' decisions, patterns, and lessons — reuse what worked, never re-learn what hurt. |

---

## 2. How it works (the actual mechanics)

### 2.1 The two execution planes

This is the first core mechanism to understand.

| Plane | What it is | Responsibility | Who runs it |
|-------|-----------|----------------|-------------|
| **Orchestration** | Markdown **slash commands** · **role definitions** · **bash hooks** under `.claude/` | Advancing waves, spawning/inspecting/shutting down teammates, talking to the human | **The lead (Paul)** — the main Claude Code session |
| **Engine** | Single static Rust binary **`bathos`** (~5.6MB, 7 crates) | Computing and *enforcing* state · routing · wave transitions · gates · story freshness · plugs · the audit chain | Hooks/commands invoke `bathos <subcommand>` (direct use also possible) |

The human types slash commands. The `bathos` binary is the deterministic core underneath that commands and hooks call. The split is the point: **whatever must be trusted and reproducible** (did the gate really pass? are active roles ≤ 3? is the audit chain intact?) lives in the engine, guaranteed by unit tests, so a persuasive model cannot "talk its way around" it.

### 2.2 State model — single source of truth (`bathos-state`)

If the engine is the trustworthy half, this is where that trust is anchored. All project state is inlined in a single JSON file, `<state-dir>/manifest.json` (default `./_state`), validated by JSON Schema. Key fields:

- `project_id` (`bathos-<uuid>`), `codename`, `current_level` (0–4), `status` (active|paused|done), `lang`, `created`
- 1:N arrays: `routing[]` (level decisions), `waves[]`, `roles[]`, `tasks[]`, `gates[]`, `risks[]`, `modules[]`, `artifacts[]`

Two invariants make the state trustworthy:

1. **Atomic writes** — the manifest is never left half-written.
2. **Tamper-evident audit chain** (`audit-log.jsonl`) — every change appends an entry to an append-only **sha256 hash chain**:
   - Each entry stores `hash_prev` (the previous entry's `hash_self`) and `hash_self` (the sha256 of itself serialized with `hash_self` empty — avoiding circular hashing).
   - Invariants: `seq` strictly increasing; `hash_prev[n] == hash_self[n-1]`; the first entry's `hash_prev == "genesis"`.
   - A single writer (`bathos audit append`) serializes all hooks behind a blocking file lock, so concurrent appends cannot corrupt the chain. *(This is exactly the invariant the dogfooding review caught — Rust and bash had been writing incompatible formats, now unified.)*

A broken chain is detected as `E-AUDIT-TAMPER`; a schema violation as `E-STATE-CORRUPT`.

### 2.3 The Scale-Adaptive router (`bathos-router`)

The router converts four "stakes" axes into a recommended level. The scoring is fully deterministic:

| Axis | Input | Score |
|------|-------|-------|
| `scope` | bug/fix/hotfix/trivial/small | 0 |
| | feature/medium *(or unclear)* | 1 |
| | large/big/module/component | 2 |
| | enterprise/platform/product | 3 |
| `novelty` | true | +1 |
| `regulation_ip` | true | +2 *(a strong upward signal)* |
| `team_size` | solo/single/small | 0 |
| | medium/mid | 1 |
| | large/big/enterprise | 2 |

Total → level mapping: **0 → Lv0 · 1 → Lv1 · 2–3 → Lv2 · 4–5 → Lv3 · 6+ → Lv4.**

| Lv | Work type | Waves run | #17 | W4 |
|----|-----------|-----------|:---:|:--:|
| 0 | Bug fix · trivial | W5 (+ultra-light W6) | ✗ | ✗ |
| 1 | Small feature · local refactor | light W2 + W3 (abridged) + W5 + light W6 | ✓ | ✗ |
| 2 | Standard feature/module | W1 + W2 + W3 + W5 + W6 | ✓ | optional |
| 3 | New product · large | W0–W6 (W4 optional) | ✓ | recommended |
| 4 | Enterprise · deep-tech · regulated | full W0–W6 + W4 | ✓ | required |

The key is **the separation of recommendation and confirmation** (User Sovereignty): `route decide` only recommends (`requires_confirmation: true`), and the level is recorded only when the user passes `--confirm <0–4>`. If the confirmed level differs from the recommendation, the engine records a `modify` verdict and recomputes the wave/role sets. If the level changes later, `E-LEVEL-DRIFT` catches it and asks the user again.

### 2.4 The wave engine (`bathos-wave-engine`)

The pipeline is a 7-wave state machine: **W0 → W1 → W2 → W3 → W5 → W6**, with **W4 (IP · Research)** as an optional plug that can run any time after W2.

```
(pre) kickoff → W0 analysis → W1 discovery → W2 design
        → W3 story gate ★ → W5 implementation → W6 verification → (post) confirm
                                  ↑
                       W4 IP & Research  (optional plug)
```

Each wave goes through state transitions (e.g. `active → gated → …`). Two hard rules:

- **Concurrency ≤ 3.** `MAX_CONCURRENT_ROLES = 3`; `spawn_role()` rejects a 4th active role in a wave with `E-CONCURRENCY`. (Token cost is linear in active teammates, so waves run only the people they need.)
- **Wave ends → its teammates shut down → next wave.** Handoffs happen exclusively through `.agent-team/` disk artifacts; teammates never inherit the lead's conversation history.

### 2.5 The gate engine (`bathos-gate-engine`)

Every wave gate uses one vocabulary and one deterministic rule:

| Verdict | Rule | Effect |
|---------|------|--------|
| **PASS** | No issues | Enter the next wave |
| **CONCERNS** | Only non-blocking issues | Log risks to `_state/` and proceed |
| **FAIL** | `issues_critical > 0` | Entry blocked; fix and re-gate |

Issue levels are `critical | enhancement | optimization`, and **a single `critical` issue means FAIL.** The gate is a **FACILITATOR, not a generator** — a verdict's `facilitator` (who decided) can never be empty, so an unsubstantiated auto-PASS is impossible. The engine also counts *consecutive* FAILs in the gate history (`take_while(Fail)`) to track re-gate cycles. The source of truth for the latest verdict is `bathos gate show`.

### 2.6 The story engine — zero-context-loss (`bathos-story-engine`)

Wave 3 is the heart: it condenses the upstream design (W2) into **self-contained dev story files** so an implementer can start from the story alone. The engine enforces three dimensions:

- **D1 completeness** — 6 required sections must exist: `story_requirements`, `developer_context`, `architecture_compliance`, `library_framework_requirements`, `file_structure_requirements`, `testing_requirements`. Additionally, `developer_context` must be non-empty. Missing or blank sections fail compilation with `E-CTX-LOSS`. *(The markdown template carries more sections — story, acceptance criteria, tasks, Dev Notes, Dev Agent Record, etc. — but these 6 are the machine-enforced minimum.)*
- **D2 traceability** — technical claims carry a `[Source:` marker linking each detail back to an upstream artifact.
- **D3 freshness (staleness)** — `story check-stale` compares stored sha256 hashes to the current upstream files; if upstream changed, the story is `E-STALE` and must be recompiled. This blocks silent design drift between W2 and W5.

### 2.7 The plug manager (`bathos-plug`)

Domain features are opt-in plugs under `modules/`, and **the core knows nothing about modules** (invariant A9 — proven by the dependency graph). Each module declares itself via `module.yaml`:

```yaml
module_id: ip                    # ip | research | game | security ...
name: IP Pack
wave: W4
trigger: "Lv>=3 OR domain=ip"    # auto-trigger condition
enabled_default: false
provides:
  workflows: [patent-spec-draft]
  templates: [patent-spec]
outputs: ".agent-team/05-ip/"
evidence_trace: true
```

The trigger DSL combines `Lv>=N`/`Lv>N`/`Lv<=N`/`Lv<N`/`Lv=N` (N=0–4) and `domain=X` with ` OR `, treating unparseable tokens conservatively as `false`. Toggles (`plug enable`/`disable`) are persisted in `manifest.modules[]`. A missing module is `E-PLUG-NOTFOUND`. Bundled by default: **ip-pack** (patent application specification) · **research-pack** (academic Abstract/Introduction).

### 2.8 Safety hooks — where enforcement meets Claude Code (`.claude/settings.json`)

Six deterministic, fail-safe hooks bind to Claude Code events. This is where the engine's guarantees take *effect* in a live session:

| Hook | Event | Role | Blocks (exit 2) when |
|------|-------|------|----------------------|
| `careful-guard.sh` | PreToolUse(Bash) | Blocks destructive commands | `rm -rf`, `DROP TABLE`, `git push --force`, `DELETE` without WHERE, `TRUNCATE` |
| `freeze-guard.sh` | PreToolUse(Write/Edit) | Locks edits to owned paths | Edit outside `BATHOS_OWNED_PATHS` |
| `audit-log.sh` | PostToolUse | Appends every tool use to the audit chain | (non-blocking) |
| `artifact-verify.sh` | TaskCompleted / SubagentStop | Verifies artifact and story-file completeness | Missing artifacts for QA/W3 tasks; incomplete story file at #17 shutdown |
| `gate-enforce.sh` | TaskCompleted | **Blocks W5 entry when the W3 verdict is FAIL** | W5-entry task + latest Implementation verdict = FAIL |
| `next-action.sh` | TeammateIdle | Suggests the next action | (non-blocking) |

The `gate-enforce` flow: detect a W5-entry task → query the latest Implementation verdict via `bathos gate show` → `FAIL` ⇒ exit 2 (block); `PASS`/`CONCERNS` ⇒ exit 0 (allow). If the binary or gate is absent, it fails safe (warn and pass). The `artifact-verify` hook detects the #17 (Matthew) role across multiple payload field names (`.role // .agent_type // .subagent_type // .agentType` + a grep fallback), so story-file verification isn't silently skipped if the runtime field name changes.

> Operational note: the `hooks` block in `settings.json` must contain **valid hook event names only** — a comment key causes an infinite wait at subagent startup.

### 2.9 CLI surface & exit-code convention

You'll rarely call the binary by hand — hooks and commands do it for you — but the full CLI surface is catalogued here for when you need it.

Global options: `-s, --state-dir <PATH>` (default `./_state`), `--modules-dir <PATH>` (default `./modules`), `-h/--help`, `-V/--version`.
**Exit codes:** `0` success · `1` error · **`2` gate FAIL** (used by hooks to block).

| Command | Subcommands | Purpose |
|---------|-------------|---------|
| `state` | `validate`, `show` | Validate/inspect manifest.json against the schema |
| `route` | `decide`, `show` | Scale-Adaptive level recommendation/confirmation |
| `wave` | `init`, `activate`, `show` | 7-wave transitions (concurrency ≤ 3) |
| `gate` | `verdict`, `show` | Record/inspect gate verdicts (FAIL → exit 2) |
| `story` | `compile`, `check-stale` | Completeness (D1) · source tracing (D2) · freshness (D3) |
| `plug` | `list`, `enable`, `disable` | Toggle plug modules |
| `audit` | `append`, `verify` | Append to / **verify** the tamper-evident audit chain (`verify` → `E-AUDIT-TAMPER`, exit 1 on tampering) |
| `doctor` | — | Install/wiring preflight diagnostics (see §2.12) |

### 2.10 Error taxonomy (E-codes)

The engine names its failure modes so hooks and humans can react deterministically: `E-LEVEL-DRIFT` (mid-flight level change), `E-CONCURRENCY` (active roles > 3), `E-CTX-LOSS` (incomplete story file), `E-STALE` (story stale vs. upstream), `E-STATE-CORRUPT` (manifest schema violation), `E-AUDIT-TAMPER` (broken audit chain), `E-PLUG-NOTFOUND` (missing module).

### 2.11 Session save/resume

Real builds span multiple Claude Code sessions, and teammates **do not inherit** the lead's conversation history — so BATHOS makes handoff explicit and lossless with two one-word commands:

- **`/save`** — captures the *entire* session into a single authoritative snapshot, `_state/SESSION-SNAPSHOT.md` (+ a dated copy). It automatically aggregates engine state (`bathos state/wave/gate/route show`), the product code's git status, confirmed decisions (including User Sovereignty choices), the in-progress wave and active roles, remaining work, and **the exact next command to run**. It takes no arguments (the current project's `_state` is the default) and asks no follow-up questions.
- **`/resume`** — reads that snapshot (cross-checking `manifest.json` and `wave-log.md`) and restores *where you were and what to do next* (read-only). In-process teammates can't be revived, so it tells you to respawn them via the relevant `/waveN-…` command — lossless thanks to disk artifacts.

Both are **natural-language friendly**: the lead treats phrases like "save/checkpoint" as `/save` and "continue/resume" as `/resume` (a `CLAUDE.md` rule). The two are BATHOS-native simple aliases of the longer gstack `/context-save` · `/context-restore`, sharing the same `_state` and the same single source of truth.

### 2.12 Preflight diagnostics & integrity verification

Two commands turn the pitfall checks that were once only documented warnings, and the tamper-evidence promise, into *actually runnable verification*:

- **`bathos audit verify`** — verifies the audit hash chain end to end (`hash_prev[n] == hash_self[n-1]`, genesis anchor, monotonic `seq`). Intact → exit 0; broken/tampered → prints `E-AUDIT-TAMPER` with the offending `seq` and exits 1. It makes "tamper-evident" *provable*, not just claimed.
- **`bathos doctor`** — an install/wiring preflight that checks, in one pass, exactly the places adopters trip over: `BATHOS_BIN` set, `jq` present, the Agent Teams flag, **comment keys in the `settings.json` `hooks` block** (a single `_note` sends subagent startup into an infinite wait — now detected deterministically), hook files present + executable, `assets/` · `modules/` present, `manifest.json` schema validity, audit-chain integrity. Prints a ✓//✗ checklist and exits 1 on any hard error. Recommended right after `install.sh`.

### 2.13 Cross-project memory & handoff

Session save/restore is limited to *within* a project. But knowledge worth keeping — architecture decisions, design token systems, operational lessons learned the expensive way — should cross project *boundaries*. BATHOS accumulates it in a **global registry**, `~/.bathos/registry/`:

- `INDEX.md` — a one-line index of projects worked on.
- `<slug>.md` — a distilled **project card** for each project: domain, USP framing, key architecture decisions/ADRs, design-system highlights, reusable patterns, lessons & incidents, current status, plus a pointer back to that project's `.agent-team/`.

**How it's applied.** `/project-handoff` distills the current project into a card, and `/save-session` performs this upsert **automatically** — the registry grows with every save, no extra effort. In *another* project, in *another* session, `/recall` (and `/cold-start`, which also consults the registry) pulls in the relevant earlier cards.

**The benefit.** A brand-new project starts *warm*, not cold: decisions and patterns that already worked are reused, and lessons already learned (e.g. the "teammate hang = quota" operational lesson, the `settings.json` comment-key trap) come pre-warned — you never have to rediscover the same pitfall. Recall is a suggestion (User Sovereignty): it presents reusable context, but the user decides this project's direction.

---

## 3. End-to-end execution flow

Putting it all together, one full run reads top to bottom like this — each arrow is a command you run yourself in the lead session:

```
/team-kickoff        → initialize the .agent-team/ skeleton + charter + manifest (create the SSOT)
/route <abs-path>    → stakes → recommended Lv0–4 → user confirms → current_level recorded
/wave1-discovery     → John ∥ Caleb            → USP Readiness gate
/wave2-design        → Joshua → (James, Jonnathan) → Plan Readiness gate
/wave3-story-gate ★  → Matthew condenses story files; Thomas · Matthias review independently
                       → Implementation Readiness gate (PASS/CONCERNS/FAIL)
                       → a FAIL physically blocks W5 via the gate-enforce hook
/wave5-implement     → Phillip, Andrew, Stephen (concurrency ≤ 3, owned-path isolation)
/wave6-verify-report → (Thomas, Timothy, Matthias) → Michael → Hananiah → Martin → Release Readiness gate
/team-confirm        → final sign-off + cleanup
```

Throughout, roles read only their input paths and edit only their owned paths, handoffs happen only via disk, the engine records every transition and verdict, and the audit chain captures every tool use.

---

## 4. Design principles (ETHOS)

BATHOS adopts and strengthens Garry Tan's **gstack** ETHOS. Three principles govern every role:

1. **User Sovereignty (supreme)** — the AI proposes, *the user* decides. Recommendations that change the user's stated direction are presented as "recommendation + rationale + missed context" and *asked about*; never executed unilaterally.
2. **Boil the Ocean** — if the complete implementation costs only a few more minutes, choose complete; don't defer tests and edge cases.
3. **Search Before Building** — in unfamiliar territory, search first to map the terrain, then challenge conventional wisdom from first principles.

These aren't decoration: the gate's "facilitator, not generator" rule and the independent-verifier separation are User Sovereignty and "generation ≠ verification" expressed as enforced mechanisms.

---

## 5. Project status & honest limits (v0.4.0)

**Early but functional — it builds and runs end-to-end today.**

- BATHOS is a **method package running on Claude Code v2.1.32+**, not a standalone app, and it depends on the **experimental Agent Teams feature**.
- **The engine is verified:** **628 Rust tests + 86 hook determinism tests, all green**; `cargo clippy -D warnings` clean; reproducible release build.
- **Fully independent certification (dogfooding):** BATHOS applied Wave 6 to itself. **ThomasCert (independent code review, PASS) + MatthiasCert (independent QA/E2E, PASS)** ⇒ **Release Readiness = PASS**. Known Blocking/High/Medium defects: **0 open**. Verification trail: `.agent-team/` (`10-review/` · `11-qa/` · `12-report/w6-final-certification.html` · `_state/signoff.md`).
- Some wave commands are **orchestration prompts the lead runs in Claude Code** (spawning/inspecting teammates), not fully automated engine flows.
- **Not production-hardened yet** — APIs, schemas, and command names may change before 1.0.

---

## 6. License & notices

Distributed under the **MIT License**. BATHOS is an independently implemented work, re-implemented from first principles after a careful reverse analysis of [BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD) (MIT © 2025 BMad Code, LLC) — with sincere respect for the prior work that first charted the terrain BATHOS set out to explore more deeply. The trademarks "BMAD", "BMad Method", etc. are **not used** in the product name or marketing. Full text: [`../README.md`](../README.md).

---

<div align="center">

**BATHOS** · βάθος — depth, not surface
한국어: [`FEATURES-kr.md`](FEATURES-kr.md) · Español: [`FEATURES-es.md`](FEATURES-es.md)

</div>
