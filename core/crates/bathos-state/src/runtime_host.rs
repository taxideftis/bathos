//! `runtime_host` — CLI host runtime detection (`bathos runtime`, CT-ENGINE-5, ADR-CX-01).
//!
//! **Why this is a separate module/enum, not a `SessionBackend` variant (ADR-CX-01):**
//! `SessionBackend` (`model_plan.rs`) answers "which in-process LLM backend is this Claude Code
//! session running under" (claude|glm, decided by `ANTHROPIC_BASE_URL`). `RuntimeHost` answers a
//! different question — "which CLI host process is executing right now" (claude-code|codex) — and
//! a Codex-hosted run has no `ANTHROPIC_BASE_URL` semantics at all, so folding it into
//! `SessionBackend` would give `model-plan.json`'s `session_backend` field an undefined "codex
//! backend" case, and an old binary would fail to deserialize a plan written with it (silently
//! dropping the whole plan on downgrade — see the ADR's rejected alternative (a)). Keeping the
//! two axes as two types means neither question's future changes leak into the other.
//!
//! Unlike `SessionBackend`, a `RuntimeHost` is **never serialized** into `model-plan.json` — it's
//! recomputed from env on every call (`bathos runtime`), not state that needs to survive a
//! process boundary, so `model-plan@1`'s schema is untouched by this module's existence.
//!
//! `dist/lib/host-detect.sh` (story-13) is the intentional bash twin of [`detect`] — same
//! priority table, cross-validated by a shared test fixture so the two can't silently drift.

use serde::{Deserialize, Serialize};

/// Which CLI host runtime the current process is executing under.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RuntimeHost {
    Claude,
    Codex,
    Unknown,
}

impl RuntimeHost {
    pub fn as_str(&self) -> &'static str {
        match self {
            RuntimeHost::Claude => "claude",
            RuntimeHost::Codex => "codex",
            RuntimeHost::Unknown => "unknown",
        }
    }
}

/// Detection result — `bathos runtime --json` emits this verbatim so the answer always comes
/// with its reasoning (same "no silent black box" philosophy as `model_plan`'s `ResolvedModel
/// { source, .. }`: never just the verdict, always why).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HostDetection {
    pub host: RuntimeHost,
    /// `"forced"` | `"env:PLUGIN_ROOT"` | `"env:CLAUDE_PROJECT_DIR"` | `"env:CLAUDE_PLUGIN_ROOT"`
    /// | `"default"`.
    pub source: &'static str,
    /// Observed env **key names** only — never values. A path could leak local filesystem
    /// layout into a report/log; the priority table only needs to know a key was *set*
    /// (runtime-abstraction-design.md §4: "env 값의 존재 여부만 본다").
    pub evidence: Vec<String>,
}

/// Pure env-driven classification. Takes an env accessor rather than reading `std::env` directly
/// — the same shape as `SessionBackend::detect_from_base_url` — so this is unit-testable with a
/// fake table and never touches real process state; `bathos-cli` supplies
/// `|k| std::env::var(k).ok()`. Never fails: every input combination has a defined answer.
///
/// Priority table (runtime-abstraction-design.md §4 is the canonical source — do not duplicate
/// this logic elsewhere; extend the table there first, then mirror the change here and in
/// `dist/lib/host-detect.sh`):
///   1. `BATHOS_FORCE_HOST` (valid value `claude`|`codex`|`unknown`) wins outright — test/debug
///      override. An *invalid* value is not this function's concern to warn about (it stays
///      pure/side-effect-free); it is silently treated as absent and detection falls through to
///      step 2 — the one-line `W-RUNTIME-FORCE-INVALID` stderr warning is `bathos-cli`'s job
///      (`handle_runtime`), which re-checks the same validity before calling this.
///   2. `PLUGIN_ROOT` or `PLUGIN_DATA` present → codex (Codex plugin/hook context injects these).
///   3. `CLAUDE_PROJECT_DIR` present → claude (Claude Code hook context).
///   4. `CLAUDE_PLUGIN_ROOT`/`CLAUDE_PLUGIN_DATA` present, with step 2's *unprefixed* keys
///      absent → claude. Codex also sets the `CLAUDE_PLUGIN_*` legacy-compat keys, so on their
///      own they are not codex evidence — only confirmed-absent unprefixed keys make this
///      unambiguous, which is exactly why this step must run after step 2, not before it.
///   5. Nothing present → unknown. Not an error — the honest report for "plain shell, no
///      hook/plugin context" (§5: "no adapter selected = current behavior unchanged").
pub fn detect(env: &dyn Fn(&str) -> Option<String>) -> HostDetection {
    if let Some(forced) = env("BATHOS_FORCE_HOST") {
        match forced.as_str() {
            "claude" => return forced_result(RuntimeHost::Claude),
            "codex" => return forced_result(RuntimeHost::Codex),
            "unknown" => return forced_result(RuntimeHost::Unknown),
            // Invalid override: ignored here (caller warns), fall through to real detection.
            _ => {}
        }
    }

    let mut plugin_evidence = Vec::new();
    if env("PLUGIN_ROOT").is_some() {
        plugin_evidence.push("PLUGIN_ROOT".to_string());
    }
    if env("PLUGIN_DATA").is_some() {
        plugin_evidence.push("PLUGIN_DATA".to_string());
    }
    if !plugin_evidence.is_empty() {
        return HostDetection {
            host: RuntimeHost::Codex,
            source: "env:PLUGIN_ROOT",
            evidence: plugin_evidence,
        };
    }

    if env("CLAUDE_PROJECT_DIR").is_some() {
        return HostDetection {
            host: RuntimeHost::Claude,
            source: "env:CLAUDE_PROJECT_DIR",
            evidence: vec!["CLAUDE_PROJECT_DIR".to_string()],
        };
    }

    let mut legacy_evidence = Vec::new();
    if env("CLAUDE_PLUGIN_ROOT").is_some() {
        legacy_evidence.push("CLAUDE_PLUGIN_ROOT".to_string());
    }
    if env("CLAUDE_PLUGIN_DATA").is_some() {
        legacy_evidence.push("CLAUDE_PLUGIN_DATA".to_string());
    }
    if !legacy_evidence.is_empty() {
        return HostDetection {
            host: RuntimeHost::Claude,
            source: "env:CLAUDE_PLUGIN_ROOT",
            evidence: legacy_evidence,
        };
    }

    HostDetection {
        host: RuntimeHost::Unknown,
        source: "default",
        evidence: Vec::new(),
    }
}

fn forced_result(host: RuntimeHost) -> HostDetection {
    HostDetection {
        host,
        source: "forced",
        evidence: vec!["BATHOS_FORCE_HOST".to_string()],
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    /// Builds an env-accessor closure from a fixture table — the shared shape used by both
    /// this module's tests and (mirrored, not shared-code) `dist/lib/host-detect.sh`'s bash
    /// table test (story-13 AC#4).
    fn env_from(pairs: &[(&str, &str)]) -> impl Fn(&str) -> Option<String> {
        let map: HashMap<String, String> = pairs
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect();
        move |k: &str| map.get(k).cloned()
    }

    // ── priority table §4, 5 rows ────────────────────────────────────────────

    #[test]
    fn detect_forced_valid_override_wins_over_everything_else() {
        // Forced "codex" wins even though CLAUDE_PROJECT_DIR (a claude signal) is also set.
        let env = env_from(&[
            ("BATHOS_FORCE_HOST", "codex"),
            ("CLAUDE_PROJECT_DIR", "/some/project"),
        ]);
        let d = detect(&env);
        assert_eq!(d.host, RuntimeHost::Codex);
        assert_eq!(d.source, "forced");
        assert_eq!(d.evidence, vec!["BATHOS_FORCE_HOST".to_string()]);
    }

    #[test]
    fn detect_plugin_root_or_data_maps_to_codex() {
        let env = env_from(&[("PLUGIN_ROOT", "/some/plugin")]);
        let d = detect(&env);
        assert_eq!(d.host, RuntimeHost::Codex);
        assert_eq!(d.source, "env:PLUGIN_ROOT");
        assert_eq!(d.evidence, vec!["PLUGIN_ROOT".to_string()]);
    }

    #[test]
    fn detect_claude_project_dir_maps_to_claude() {
        let env = env_from(&[("CLAUDE_PROJECT_DIR", "/some/project")]);
        let d = detect(&env);
        assert_eq!(d.host, RuntimeHost::Claude);
        assert_eq!(d.source, "env:CLAUDE_PROJECT_DIR");
        assert_eq!(d.evidence, vec!["CLAUDE_PROJECT_DIR".to_string()]);
    }

    #[test]
    fn detect_legacy_claude_plugin_only_maps_to_claude_when_unprefixed_absent() {
        // Codex also sets CLAUDE_PLUGIN_* for legacy compat, but with PLUGIN_ROOT/PLUGIN_DATA
        // and CLAUDE_PROJECT_DIR both absent, this is the "old-style Claude Code plugin
        // context" signal, not codex evidence (§4 row 4's key nuance).
        let env = env_from(&[("CLAUDE_PLUGIN_ROOT", "/some/plugin")]);
        let d = detect(&env);
        assert_eq!(d.host, RuntimeHost::Claude);
        assert_eq!(d.source, "env:CLAUDE_PLUGIN_ROOT");
        assert_eq!(d.evidence, vec!["CLAUDE_PLUGIN_ROOT".to_string()]);
    }

    #[test]
    fn detect_nothing_present_is_unknown() {
        let env = env_from(&[]);
        let d = detect(&env);
        assert_eq!(d.host, RuntimeHost::Unknown);
        assert_eq!(d.source, "default");
        assert!(d.evidence.is_empty());
    }

    // ── forced-invalid (6th row) ─────────────────────────────────────────────

    #[test]
    fn detect_invalid_forced_value_falls_through_to_real_detection() {
        // W-RUNTIME-FORCE-INVALID: an unrecognized BATHOS_FORCE_HOST value must not be trusted
        // (exceptions.md §4) — detection continues past it to the next priority level.
        let env = env_from(&[
            ("BATHOS_FORCE_HOST", "bogus-typo"),
            ("CLAUDE_PROJECT_DIR", "/some/project"),
        ]);
        let d = detect(&env);
        assert_eq!(d.host, RuntimeHost::Claude);
        assert_eq!(d.source, "env:CLAUDE_PROJECT_DIR");
    }

    // ── ordering nuance (§4 row 4 depends on row 2 running first) ────────────

    #[test]
    fn detect_plugin_root_wins_over_legacy_claude_plugin_when_both_present() {
        // Codex sets both PLUGIN_ROOT and the legacy CLAUDE_PLUGIN_* keys — priority order
        // (step 2 before step 4) must resolve this as codex, not claude.
        let env = env_from(&[
            ("PLUGIN_ROOT", "/some/plugin"),
            ("CLAUDE_PLUGIN_ROOT", "/some/plugin"),
        ]);
        let d = detect(&env);
        assert_eq!(d.host, RuntimeHost::Codex);
        assert_eq!(d.source, "env:PLUGIN_ROOT");
    }
}
