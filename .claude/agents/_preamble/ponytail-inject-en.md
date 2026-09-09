# W5 Implementation Discipline — The Ladder

> **Injected into:** W5 implementer roles — Phillip(#8) · Andrew(#9) · Stephen(#10).
> The lead (Paul) states this file's path and the current intensity value in the W5 spawn prompt.
> **Canonical = the Korean edition** (`ponytail-inject-kr.md`). This `-en` file is a secondary
> translation and is allowed to lag silently (`scripts/drift-exclusions.json` policy,
> `docs/agent-portability-kr.md` §4).
>
> **Source & license:** the principles are adapted from ponytail (DietrichGebert/ponytail, MIT)
> and rewritten for the BATHOS W5 context. Per the standing decision in
> `_recon/ponytail-analysis.md` §6, **the persona, tone, and branding (the "lazy senior dev"
> character, the mascot, the jokes) are NOT adopted** — only the engineering principles are
> absorbed. BATHOS is an orchestration product, not a single-persona product.

---

## 0. Precedence — how this relates to ETHOS (read first)

This discipline and ETHOS Principle 1 (Boil the Ocean) govern **different axes**. They do not conflict.

| Axis | Governing principle | What it decides |
|------|--------------------|-----------------|
| **What to build** | **The Ladder (this document)** | scope · abstraction · file count · dependencies · config knobs |
| **How completely to build the settled scope** | **ETHOS Boil the Ocean** | error paths · edge cases · tests · verification · observability |

- **Never use the Ladder to cut an error path, a test, or an input validation.** Different axis.
- **Never use Boil the Ocean to justify an abstraction nobody asked for.** Also a different axis.
- Where the two principles overlap is already written down in §4 ("When NOT to be lazy") — there they say the same thing.
- ETHOS Principle 3 (User Sovereignty) **still outranks everything**, including this discipline.

---

## 1. Before the ladder — understand the problem first

The ladder runs *after* you understand the problem, never *instead* of it.

- Read the task and the code it touches, trace the real flow end to end, and only then climb.
- **Be lazy about the solution. Never lazy about the reading.** A small diff you don't understand
  is a confident wrong fix dressed up as efficiency.

### Bug fix = root cause, not symptom

A report names a **symptom**.

- **Grep every caller** of the function you are about to touch, before you edit.
- The lazy fix IS the root-cause fix — one guard in the shared function is a smaller diff than a
  guard in every caller.
- Patching only the path the ticket names leaves every sibling caller still broken. Fix it **once**,
  where all callers route through.

---

## 2. The Ladder — before writing any code, stop at the first rung that holds

1. **Does this need to exist at all?** Speculative need = skip it, say so in one line. (YAGNI)
2. **Already in this codebase?** A helper, util, type, or pattern that already lives here → **reuse it.**
   Look before you write — re-implementing what's a few files over is the most common slop.
3. **Does the standard library do it?** Use it.
4. **Does a native platform feature cover it?** `<input type="date">` over a picker lib, CSS over JS,
   a DB constraint over app code.
5. **Does an already-installed dependency solve it?** Use it. **Never add a new dependency** for what
   a few lines can do.
6. **Can it be one line?** One line.
7. **Only then:** the minimum code that works.

Two rungs work → take the **higher** one and move on. The ladder is a reflex, not a research project.
The first lazy solution that works is the right one — **once you actually know what the change has to touch.**

---

## 3. Rules

- **No unrequested abstractions.** No interface with one implementation, no factory for one product,
  no config for a value that never changes.
- **No boilerplate, no scaffolding "for later."** Later can scaffold for itself.
- **Deletion over addition. Boring over clever.** Clever is what someone decodes at 3am.
- **Fewest files possible. The shortest working diff wins** — but only once you understand the problem.
  The smallest change in the wrong place isn't lazy, it's a second bug.
- **Complex request?** Ship the lazy version and question it in the same response:
  "Did X; Y covers it. Need full X? Say so." Never stall on an answer you can default.
- **Two stdlib options, same size?** Take the one that's **correct on edge cases**. Lazy means writing
  less code, not picking the flimsier algorithm.
- **Mark deliberate simplifications.** → §5

---

## 4. When NOT to be lazy (where this meets Boil the Ocean)

**Never** simplify away:

- **Input validation at trust boundaries**
- **Error handling that prevents data loss**
- **Security measures**
- **Accessibility basics**
- **Anything explicitly requested** — the user insists on the full version → build it, no re-arguing.
- **Understanding the problem** — the ladder shortens the solution, never the reading.
- **The calibration real hardware needs** — a real clock drifts, a real sensor reads off. Leave the
  **calibration knob**, not just less code. The physical world needs tuning a minimal model can't see.

**Lazy code without its check is unfinished.**
Non-trivial logic (a branch, a loop, a parser, a money/security path) leaves **ONE runnable check**
behind — the smallest thing that fails if the logic breaks. An `assert`-based self-check or one small
test is enough. No frameworks, no fixtures, no per-function suites unless asked.
Trivial one-liners need no test. **YAGNI applies to tests too.**

---

## 5. The `ponytail:` marker — how to apply it

When a deliberate simplification **cuts a real corner and has a known ceiling**, leave that ceiling
and its upgrade path in a source-code comment. This is the only thing that stops "later" from
quietly becoming "never."

### Format

```
ponytail: <ceiling>, <upgrade path>
```

- **ceiling** — the point where this simplification breaks down. Be specific about *what* the limit is.
- **upgrade path** — what to replace it with when that happens. **Include the trigger to revisit.**
- A marker naming no upgrade path or trigger is tagged **`no-trigger`** by `/bathos-debt`.
  **Those are the ones that silently rot.**

### Language — write it in English

Per the standing W5 rule (the "code annotation standard" in each role base), **all code comments are
written in English.** Even when documents and deliverables are in Korean, the body of a `ponytail:`
marker is English. No exception here.

### When to add it / when not to

| Add it | Don't add it |
|--------|--------------|
| One global lock (needs splitting under contention) | Something you climbed the ladder and **didn't build** — code that doesn't exist has no comment |
| O(n²) scan (fine while n is small) | A trivial one-liner, a standard uncontroversial choice |
| Naive heuristic, fixed backoff | Temporary debug code (delete that instead) |
| Hardcoded constant (config deferred) | A gate risk already recorded as `CONCERNS:` in a document (no duplication) |
| Single retry, partially implemented contract | |

### Examples

```rust
// ponytail: single global lock, split into per-wave locks if profiling shows contention
```
```typescript
// ponytail: linear scan over waves (n <= 7), swap to a Map if the wave set ever grows
```
```python
# ponytail: fixed backoff, switch to exponential once the API starts rate-limiting
```
```bash
# ponytail: assumes jq is present, add a grep fallback if a jq-less host appears
```

### Harvesting

- **Canonical:** `/bathos-debt` — collects `CONCERNS:` in markdown deliverables and `ponytail:` in
  source code into one ledger.
- Manual:
  ```bash
  grep -rnE '(#|//|--) ?ponytail:' . \
    --include='*.rs' --include='*.ts' --include='*.tsx' --include='*.py' --include='*.sh' \
    --exclude-dir=target --exclude-dir=node_modules --exclude-dir=.git
  ```

### Anchor separation

- **Source code** = `ponytail:` (this document)
- **Markdown deliverables and gate risks** = `CONCERNS:` (`CLAUDE.md` §2.1, the existing `/bathos-debt` convention)

Different media, so they never overlap. Never record the same item under both anchors.

---

## 6. Output discipline

**Code first.** Then at most three short lines: what was skipped, when to add it.

No essays, no feature tours, no design notes.
**If the explanation is longer than the code, delete the explanation.** Every paragraph defending a
simplification is complexity smuggled back in as prose.

```
[code] → skipped: [X], add when [Y].
```

**Exception:** explanation the user **explicitly asked for** (a report, a walkthrough, per-phase notes)
is not debt — give it in full. This rule targets **unrequested prose** only.
`08-impl-notes/*.md` is a deliverable required by the W5 DoD and is therefore out of this rule's scope.

---

## 7. Intensity — bound to the existing switch

The strength of this discipline reuses **the intensity switch BATHOS already has**. Do not build a new one.

- **Read:** `.intensity` in `_state/session-flags.json` (default `full`)
- **Change:** `/bathos intensity <lite|full|ultra|off>` (the intensity-tracker hook)
- **Invariant (LD-4):** intensity ≠ Lv0–4. **Lv** = project/task scale (router, `manifest.current_level`);
  **intensity** = session aggressiveness (instant toggle). They are independent.
- The lead (Paul) states the current intensity value in the W5 spawn prompt.

| Level | W5 implementer behavior |
|-------|------------------------|
| **lite** | Build what's asked, but name the lazier alternative in one line in `08-impl-notes/`. The user picks. |
| **full** | The ladder enforced. Stdlib and native first. Shortest diff, shortest explanation. **(default)** |
| **ultra** | YAGNI extremist. Deletion before addition. Ship the one-liner and challenge the requirement in the same breath. |
| **off** | Discipline inactive — ETHOS only. |

Example — "Add a cache for these API responses."

- **lite:** "Done, cache added. FYI: `lru_cache` covers this in one line if you'd rather not own a cache class."
- **full:** "`@lru_cache(maxsize=1000)` on the fetch function. Skipped the custom cache class, add when `lru_cache` measurably falls short."
- **ultra:** "No cache until a profiler says so. When it does: `@lru_cache`."

---

## 8. Boundaries (out of scope)

- This discipline governs **what you build**, not **how you talk**. Reporting format and tone follow
  ETHOS and the shared teammate conduct rules.
- **Applies to W5 only.** W2 (design) and W6 (verification) follow their own disciplines.
  Over-engineering review in W6 is the existing responsibility of Thomas(#12) and Hananiah(#14).
- **Correctness bugs, security holes, and performance regressions are out of scope here** — route them
  to W6 (Thomas #12, Michael #13).
- **Never touch anything outside your owned paths** — the existing W5 ownership boundaries still win.
- Deactivation: when the user runs `/bathos intensity off` or explicitly says to stop.
