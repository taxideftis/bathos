//! `model_status` — session live-status snapshot SSOT (`_state/model-status.json`,
//! schema `bathos/model-status@1`).
//!
//! **Why this exists (story M4, `w7-model-switch-limit-design-kr.md` §3.2):**
//! `model-plan.json` answers "who should use which runtime/model" (the plan); this file
//! answers "what is the session actually doing right now" (the live state) — most notably
//! the **last switch plan** (`bathos model switch --apply` writes it with `verified:false`,
//! and `bathos model status` later re-detects the real env and flips `verified` — AC9,
//! "a switch is not done until it is verified", generation ≠ verification).
//!
//! **Forward compatibility is the load-bearing constraint.** M3 (limit events) and M6
//! (banner) will grow more fields onto this same schema (`last_limit_event`,
//! `banner_pending`, ...). Every field below is therefore either `#[serde(default)]` or
//! `#[serde(default, skip_serializing_if = "Option::is_none")]`, and unknown fields are
//! ignored by serde's default behavior — an old binary reading a new file drops the new
//! keys instead of failing, and a new binary reading an old file fills defaults. The one
//! deliberate non-default is nothing: even `schema`/`updated`/`session_backend` default so
//! a hand-truncated file still loads (the writer always emits all three).
//!
//! **What this module does NOT do:** it never touches `model-plan.json` (the plan SSOT —
//! `bathos model detect` keeps owning `plan.session_backend`), never reads key material
//! (`~/.bathos/<rt>.env` is consumed by the user's shell, not by this process), and never
//! edits `.claude/settings.local.json` (that Tier-S inject/clear path is CLI-owned — the
//! design's §1 responsibility table puts settings editing in the CLI, not the state crate).

use crate::model_plan::{PlanWarning, Runtime, SessionBackend};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

/// The only schema string this module writes. A file with a different (or missing) `schema`
/// value is treated as **absent** (lenient — same as no file at all) with a warning, mirroring
/// `model_plan::load`'s lenient philosophy: an unreadable status file must never block a
/// switch or a status report (fail-safe > fail-closed for this file).
pub const SCHEMA_ID: &str = "bathos/model-status@1";

/// How a switch plan is meant to take effect (w7 design §4).
///
/// - `Restart` — Tier-R: the user pastes shell commands into a **new terminal**; this process
///   never touches settings. Always works (GLM live PASS 2026-07-16).
/// - `Settings` — Tier-S: a temporary key copy injected into `.claude/settings.local.json`.
///   Not openable until story M5 (V-13/V-14 measurement + user approval of temporary
///   plaintext); the *return* direction of this path (clearing) is already implemented by
///   the CLI in M4 as a lead-directed backport.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SwitchVia {
    Restart,
    Settings,
}

impl SwitchVia {
    pub fn as_str(&self) -> &'static str {
        match self {
            SwitchVia::Restart => "restart",
            SwitchVia::Settings => "settings",
        }
    }
}

/// The last `bathos model switch --apply` plan this binary recorded. `verified` starts
/// `false` (a printed command is not an applied switch) and is flipped by `bathos model
/// status` after re-detecting the live env against [`ModelStatus::expected_backend`].
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SwitchPlan {
    /// Target runtime (`claude` = the return path). `codex` never appears here — it is
    /// rejected upstream (`E-MODEL-SWITCH-UNSUPPORTED`) because it is a subprocess
    /// delegation, not a session backend (ADR-D-0006).
    pub target: Runtime,
    pub via: SwitchVia,
    /// When the plan was printed/recorded — lets `status` tell "plan from before your
    /// restart" apart from "plan just recorded".
    pub printed_at: DateTime<Utc>,
    #[serde(default)]
    pub verified: bool,
}

/// Tier-S residue marker (w7 design §3.2): non-null while a temporary key copy sits in
/// `.claude/settings.local.json`. Set by M5's injection; cleared to `None` by the M4
/// return path after the env keys are blanked. A lingering non-null value after a return
/// is exactly what `model status` must surface (E15 "crash before return").
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TransientInjection {
    pub target: Runtime,
    pub injected_at: DateTime<Utc>,
}

/// The full `model-status.json` document (`bathos/model-status@1`).
///
/// All fields default so this struct stays load-compatible in both directions (see the
/// module doc's forward-compatibility constraint).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ModelStatus {
    #[serde(default = "default_schema")]
    pub schema: String,
    #[serde(default = "utc_now")]
    pub updated: DateTime<Utc>,
    /// The backend measured at the time this snapshot was *written* — a historical record,
    /// never a live answer (the live answer is always a fresh `detect_from_base_url`).
    #[serde(default = "default_backend")]
    pub session_backend: SessionBackend,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_switch_plan: Option<SwitchPlan>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub transient_injection: Option<TransientInjection>,
}

fn utc_now() -> DateTime<Utc> {
    Utc::now()
}

fn default_schema() -> String {
    SCHEMA_ID.to_string()
}

fn default_backend() -> SessionBackend {
    SessionBackend::Claude
}

impl Default for ModelStatus {
    fn default() -> Self {
        ModelStatus {
            schema: default_schema(),
            updated: utc_now(),
            session_backend: default_backend(),
            last_switch_plan: None,
            transient_injection: None,
        }
    }
}

impl ModelStatus {
    /// The backend the process must be running under for a switch to `target` to count as
    /// applied. `Runtime::env_backend` covers the four env-global runtimes; `claude` has no
    /// `env_backend` (it is the *absence* of an override), so it maps to
    /// [`SessionBackend::Claude`] — "ANTHROPIC_BASE_URL unset or an Anthropic host".
    pub fn expected_backend(target: Runtime) -> SessionBackend {
        target.env_backend().unwrap_or(SessionBackend::Claude)
    }
}

pub fn status_path(state_dir: &Path) -> PathBuf {
    state_dir.join("model-status.json")
}

/// Loads `<state_dir>/model-status.json` leniently — same contract as `model_plan::load`:
/// absent file → default, no warning; unparseable JSON → default + `W-MODELSTATUS-CORRUPT`;
/// schema mismatch → default + `W-MODELSTATUS-SCHEMA`. Never errors, never panics: a broken
/// status file must not block a verification report.
pub fn load(state_dir: &Path) -> (ModelStatus, Vec<PlanWarning>) {
    let path = status_path(state_dir);
    let raw = match fs::read_to_string(&path) {
        Ok(s) => s,
        Err(_) => return (ModelStatus::default(), Vec::new()),
    };

    let value: serde_json::Value = match serde_json::from_str(&raw) {
        Ok(v) => v,
        Err(e) => {
            return (
                ModelStatus::default(),
                vec![PlanWarning {
                    code: "W-MODELSTATUS-CORRUPT".to_string(),
                    message: format!("model-status.json 파싱 실패(빈 상태로 폴백): {e}"),
                }],
            )
        }
    };

    let schema_ok = value
        .get("schema")
        .and_then(|s| s.as_str())
        .map(|s| s == SCHEMA_ID)
        .unwrap_or(false);
    if !schema_ok {
        return (
            ModelStatus::default(),
            vec![PlanWarning {
                code: "W-MODELSTATUS-SCHEMA".to_string(),
                message: format!(
                    "model-status.json schema 불일치(기대: {SCHEMA_ID}) — 빈 상태로 폴백"
                ),
            }],
        );
    }

    match serde_json::from_value::<ModelStatus>(value) {
        Ok(status) => (status, Vec::new()),
        Err(e) => (
            ModelStatus::default(),
            vec![PlanWarning {
                code: "W-MODELSTATUS-CORRUPT".to_string(),
                message: format!("model-status.json 필드 역직렬화 실패(빈 상태로 폴백): {e}"),
            }],
        ),
    }
}

/// Atomically writes `status` to `<state_dir>/model-status.json` (temp file + rename —
/// `model_plan::save` pattern: a partial write is never observable). No file lock, same
/// rationale as `model_plan::save`: the writers are sequential user-invoked CLI calls
/// (`model switch` / `model status`), not concurrent hooks.
pub fn save(state_dir: &Path, status: &ModelStatus) -> std::io::Result<()> {
    fs::create_dir_all(state_dir)?;
    let path = status_path(state_dir);
    let tmp = state_dir.join(".model-status.tmp");
    let json = serde_json::to_string_pretty(status)?;
    fs::write(&tmp, json.as_bytes())?;
    fs::rename(&tmp, &path)?;
    Ok(())
}

/// The AC9 comparison: does the live measured backend match what the plan intended?
/// Pure — the CLI supplies `measured` from a fresh `SessionBackend::detect_from_base_url`
/// call so tests can inject any env without polluting the real one.
pub fn plan_matches_backend(plan: &SwitchPlan, measured: SessionBackend) -> bool {
    ModelStatus::expected_backend(plan.target) == measured
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;
    use tempfile::TempDir;

    fn ts(y: i32, m: u32, d: u32) -> DateTime<Utc> {
        Utc.with_ymd_and_hms(y, m, d, 0, 0, 0).unwrap()
    }

    fn plan(target: Runtime, via: SwitchVia) -> SwitchPlan {
        SwitchPlan {
            target,
            via,
            printed_at: ts(2026, 9, 12),
            verified: false,
        }
    }

    // ── roundtrip + forward/backward compatibility (DoD: old-version file loads) ──

    #[test]
    fn save_then_load_roundtrips_all_fields() {
        let dir = TempDir::new().unwrap();
        let mut status = ModelStatus {
            session_backend: SessionBackend::Glm,
            ..ModelStatus::default()
        };
        status.last_switch_plan = Some(plan(Runtime::Glm, SwitchVia::Restart));
        status.transient_injection = Some(TransientInjection {
            target: Runtime::Kimi,
            injected_at: ts(2026, 9, 12),
        });

        save(dir.path(), &status).unwrap();
        let (loaded, warnings) = load(dir.path());
        assert!(warnings.is_empty());
        assert_eq!(loaded.schema, SCHEMA_ID);
        assert_eq!(loaded.session_backend, SessionBackend::Glm);
        assert_eq!(
            loaded.last_switch_plan,
            Some(plan(Runtime::Glm, SwitchVia::Restart))
        );
        assert_eq!(
            loaded.transient_injection,
            Some(TransientInjection {
                target: Runtime::Kimi,
                injected_at: ts(2026, 9, 12)
            })
        );
    }

    #[test]
    fn old_version_file_with_fewer_fields_loads_with_defaults() {
        // The exact shape an M4-era binary writes minus the optional blocks — a future
        // reader (M3/M6) must still load today's minimal file, and today's reader must load
        // a file where the optional blocks were omitted.
        let dir = TempDir::new().unwrap();
        fs::write(
            dir.path().join("model-status.json"),
            r#"{"schema":"bathos/model-status@1","updated":"2026-09-12T00:00:00Z","session_backend":"glm"}"#,
        )
        .unwrap();
        let (status, warnings) = load(dir.path());
        assert!(warnings.is_empty());
        assert_eq!(status.session_backend, SessionBackend::Glm);
        assert_eq!(status.last_switch_plan, None);
        assert_eq!(status.transient_injection, None);
    }

    #[test]
    fn future_version_file_with_unknown_fields_loads_ignoring_extras() {
        // M3 will add e.g. `last_limit_event`; serde's default (unknown fields ignored)
        // must keep today's reader working against that shape — this is the "구본 호환"
        // guarantee the lead asked to see pinned by a test.
        let dir = TempDir::new().unwrap();
        fs::write(
            dir.path().join("model-status.json"),
            r#"{"schema":"bathos/model-status@1","updated":"2026-09-12T00:00:00Z","session_backend":"kimi","last_switch_plan":{"target":"kimi","via":"restart","printed_at":"2026-09-12T00:00:00Z","verified":false},"last_limit_event":{"ts":"2026-09-12T00:00:00Z","error_type":"rate_limit"},"banner_pending":true}"#,
        )
        .unwrap();
        let (status, warnings) = load(dir.path());
        assert!(warnings.is_empty());
        assert_eq!(
            status.last_switch_plan.map(|p| p.target),
            Some(Runtime::Kimi)
        );
        assert_eq!(status.transient_injection, None);
    }

    /// Two `ModelStatus::default()` values never compare equal (`updated` is
    /// `Utc::now()` per call), so fallback assertions compare every field *except*
    /// the timestamp — the semantic content of "empty state".
    fn assert_default_content(status: &ModelStatus) {
        assert_eq!(status.schema, SCHEMA_ID);
        assert_eq!(status.session_backend, SessionBackend::Claude);
        assert_eq!(status.last_switch_plan, None);
        assert_eq!(status.transient_injection, None);
    }

    #[test]
    fn absent_file_loads_default_no_warning() {
        let dir = TempDir::new().unwrap();
        let (status, warnings) = load(dir.path());
        assert!(warnings.is_empty());
        assert_default_content(&status);
    }

    #[test]
    fn corrupt_json_and_schema_mismatch_fall_back_with_warnings() {
        let dir = TempDir::new().unwrap();
        fs::write(dir.path().join("model-status.json"), "{ not json").unwrap();
        let (status, warnings) = load(dir.path());
        assert_default_content(&status);
        assert_eq!(warnings[0].code, "W-MODELSTATUS-CORRUPT");

        fs::write(
            dir.path().join("model-status.json"),
            r#"{"schema":"bathos/model-status@999","updated":"2026-09-12T00:00:00Z","session_backend":"claude"}"#,
        )
        .unwrap();
        let (status, warnings) = load(dir.path());
        assert_default_content(&status);
        assert_eq!(warnings[0].code, "W-MODELSTATUS-SCHEMA");
    }

    #[test]
    fn save_leaves_no_tmp_file_behind() {
        let dir = TempDir::new().unwrap();
        save(dir.path(), &ModelStatus::default()).unwrap();
        assert!(dir.path().join("model-status.json").exists());
        assert!(!dir.path().join(".model-status.tmp").exists());
    }

    // ── verification comparison (AC9: match / mismatch) ──────────────────────

    #[test]
    fn plan_matches_backend_for_match_and_mismatch() {
        // glm plan + glm measured → verified
        assert!(plan_matches_backend(
            &plan(Runtime::Glm, SwitchVia::Restart),
            SessionBackend::Glm
        ));
        // glm plan + still-on-claude (user never ran the commands) → not verified
        assert!(!plan_matches_backend(
            &plan(Runtime::Glm, SwitchVia::Restart),
            SessionBackend::Claude
        ));
        // return plan (claude) + genuinely back on claude → verified
        assert!(plan_matches_backend(
            &plan(Runtime::Claude, SwitchVia::Settings),
            SessionBackend::Claude
        ));
        // return plan but env still points at kimi → not verified
        assert!(!plan_matches_backend(
            &plan(Runtime::Claude, SwitchVia::Restart),
            SessionBackend::Kimi
        ));
    }

    #[test]
    fn expected_backend_maps_every_switchable_runtime() {
        assert_eq!(
            ModelStatus::expected_backend(Runtime::Glm),
            SessionBackend::Glm
        );
        assert_eq!(
            ModelStatus::expected_backend(Runtime::Kimi),
            SessionBackend::Kimi
        );
        assert_eq!(
            ModelStatus::expected_backend(Runtime::Deepseek),
            SessionBackend::Deepseek
        );
        assert_eq!(
            ModelStatus::expected_backend(Runtime::Qwen),
            SessionBackend::Qwen
        );
        // claude = absence of an override, not "an anthropic-looking URL"
        assert_eq!(
            ModelStatus::expected_backend(Runtime::Claude),
            SessionBackend::Claude
        );
    }
}
