# BATHOS — Frequently Asked Questions (FAQ)

> Quick answers to the questions that come up first — what BATHOS is, what it takes to run, what it costs, and where to go for depth. Each answer points to the full document when you need more detail.
>
> **See also:** [Usage (USAGE-en)](USAGE-en.md) · [Features (FEATURES-en)](FEATURES-en.md) · [Cost & quota (QUOTA-en)](QUOTA-en.md) · 한국어: [`FAQ-kr.md`](FAQ-kr.md) · Español: [`FAQ-es.md`](FAQ-es.md)

### What exactly is BATHOS?
A **method package that runs on top of Claude Code** — a 16-specialized-roles × 7-wave pipeline + Scale-Adaptive routing + hard quality gates, plus a small Rust engine. It is **not a standalone app**; it orchestrates a single Claude Code session into a disciplined product team.

### What do I need to run it?
Claude Code **v2.1.32+** + the experimental **Agent Teams** feature (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`), a **Rust toolchain** (one-time engine build), and **`jq`** (safety hooks). macOS/Linux.

### How do I add it to my project?
`./install.sh --into /abs/path/to/your-project` copies `.claude/` · `assets/` · `modules/`, then point `BATHOS_BIN` at the built engine. Full walkthrough: [`USECASE-en.md`](USECASE-en.md). Afterwards, verify the wiring with **`bathos doctor`**.

### A teammate stopped with no output — is it broken?
Almost certainly **not** — the most common cause is the **account usage (session) limit**, not a code bug. Respawn after the reset and it resumes losslessly thanks to the `.agent-team/` disk artifacts. See [`QUOTA-en.md`](QUOTA-en.md).

### A subagent hangs at startup.
Check `.claude/settings.json` — a **comment key** (e.g. `_note`) in the `hooks` block sends subagent startup into an infinite wait. Keep only valid event names. **`bathos doctor`** catches this deterministically.

### What does it cost to run? How do I save?
Token cost scales with the number of active teammates and the level. Pick the lowest level that fits, keep concurrent teammates ≤ 3, spawn only needed roles, and defer W4. Details: [`QUOTA-en.md`](QUOTA-en.md).

### Is the "tamper-evident audit chain" real or a claim?
Real and verifiable: `bathos audit verify` validates the sha256 chain end to end (`hash_prev[n] == hash_self[n-1]`, genesis anchor, monotonic seq). A break yields `E-AUDIT-TAMPER` + exit 1.

### Can I save work and continue in a new session?
Yes. `/save-session` snapshots everything (machine SSOT + narrative) into `_state/`, and `/cold-start` fully restores in a fresh session. Short aliases: `/save` · `/resume`. [`USAGE-en.md`](USAGE-en.md) §12.1.

### Why did the independent review find a bug the tests missed?
That's the point — **generation ≠ verification**. Tests only prove what they check; an independent reviewer (Thomas) attacks invariants and integration points the author didn't see. BATHOS separates author and verifier by design.

### How do I add a new capability (e.g. security audit)?
For a **domain pack**, use a plug — [`MODULE-GUIDE-en.md`](MODULE-GUIDE-en.md). To change *how roles behave in your project*, use team/user overrides — [`ROLE-GUIDE-en.md`](ROLE-GUIDE-en.md). Keep the core slim (invariant A9).

### Is it production-ready?
**Not yet.** v0.4.0 is early but functional and dogfooding-validated (628 tests + 86 hook tests green, fully independent certification). APIs, schemas, and command names may change before 1.0. So far it has only been validated against itself — real external pilots are the next milestone.

### License? Is this BMAD?
MIT. BATHOS was independently implemented from first principles after a careful reverse analysis of [BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD) (MIT © 2025 BMad Code, LLC), with sincere respect for the prior work it builds on. The BMAD trademarks are not used.

---

<div align="center">한국어: <a href="FAQ-kr.md">FAQ-kr</a> · Español: <a href="FAQ-es.md">FAQ-es</a></div>
