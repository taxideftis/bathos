//! `model_plan` — per-role/per-wave model/runtime selection SSOT (`_state/model-plan.json`,
//! schema `bathos/model-plan@1`).
//!
//! **Why this exists (ADR-D-0005/0006, `w2-panes-model-design-kr.md` §A, W5 task brief §3):**
//! BATHOS teammates can run on six runtimes, in two dispatch shapes — Claude (in-process
//! teammate, real per-role model) and Codex (a separate CLI process, no env conflict either
//! way) need no process-wide coordination; Glm/Kimi/Deepseek/Qwen are all the *same* shape
//! (process-wide `ANTHROPIC_BASE_URL` override — no per-role granularity is physically
//! possible, [`Runtime::is_env_global`]). `model-plan.json` is the single place that records
//! "which runtime/model each role (or each wave, as a whole) should use this session", so
//! `bathos model show|set|validate|resolve` (bathos-cli) and the wave commands all agree on one
//! answer.
//!
//! **Backward compatibility is the load-bearing constraint.** A project that has never run
//! `bathos model set` must behave *exactly* as before this feature existed: every role falls
//! back to its agent-definition frontmatter `model:` field. [`resolve_effective`] encodes this
//! as an explicit 5-step priority chain (plan.roles → plan.waves\[wave\] → plan.defaults →
//! frontmatter → runtime default) so "no plan file", "plan file present but this role/wave
//! unset", and "plan file from before the wave step existed" all degrade to the same
//! pre-existing behavior — no silent behavior change for projects that don't opt in.
//!
//! **What this module does NOT do:** it never spawns a teammate, never touches
//! `manifest.json`, and never talks to any of the env-global/Codex processes. It only
//! reads/writes `model-plan.json` and computes pure resolve/validate decisions. The actual
//! runtime dispatch (spawn with `model:` param / require the matching session env / delegate to
//! `codex-adapter/run-role.sh`) is the wave command's/CLI caller's job — kept out of this
//! crate on purpose (bathos-state stays a state/decision layer, not an orchestrator).

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::Path;

/// The only schema string this module writes. A file with a different (or missing) `schema`
/// value is treated as **absent** (lenient — same as no file at all) rather than erroring, per
/// `w2-panes-model-design-kr.md` §A1.2 ("on mismatch, warn leniently, ignore the file, and
/// fall back to frontmatter").
pub const SCHEMA_ID: &str = "bathos/model-plan@1";

/// The runtimes a role can be assigned to. `Copy`/`Eq` because resolve/validate compare these
/// constantly and never need ownership of anything beyond the tag itself.
///
/// **Two dispatch shapes, not three (user decision 3):**
/// - `Claude` — native in-process teammate, per-role model is a real capability.
/// - `Codex` — a separate CLI subprocess (`codex-adapter/run-role.sh`); never touches
///   `ANTHROPIC_BASE_URL`, so it never conflicts with anything else in the batch (ADR-D-0006).
/// - `Glm`/`Kimi`/`Deepseek`/`Qwen` — all four are the *same* dispatch shape: a process-wide
///   `ANTHROPIC_BASE_URL` swap (ADR-D-0005), just pointed at a different vendor endpoint (the
///   auth env var name is *not* uniform across them — see [`env_auth_var`]; DeepSeek reads
///   `ANTHROPIC_API_KEY`, the other three read `ANTHROPIC_AUTH_TOKEN`).
///   [`Runtime::is_env_global`] is what tells the mixing rules "this one needs the whole
///   process, not just this role" — adding a fifth such vendor later means adding one enum
///   variant + one arm each in `is_env_global`/`env_backend`/`parse`/`as_str`, never new
///   branching logic in [`validate_wave`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Runtime {
    Claude,
    Glm,
    Codex,
    Kimi,
    Deepseek,
    Qwen,
}

impl Runtime {
    /// Parses a CLI-facing runtime string (`bathos model set <slug> --runtime <r>`).
    /// Case-insensitive (matches `GateEngine::parse_verdict`'s convention in this workspace).
    pub fn parse(s: &str) -> Result<Self, String> {
        match s.to_ascii_lowercase().as_str() {
            "claude" => Ok(Runtime::Claude),
            "glm" => Ok(Runtime::Glm),
            "codex" => Ok(Runtime::Codex),
            "kimi" => Ok(Runtime::Kimi),
            "deepseek" => Ok(Runtime::Deepseek),
            "qwen" => Ok(Runtime::Qwen),
            other => Err(format!(
                "[E-MODEL-RUNTIME-INVALID] 알 수 없는 runtime '{other}' \
                 (claude|glm|codex|kimi|deepseek|qwen 중 하나)"
            )),
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            Runtime::Claude => "claude",
            Runtime::Glm => "glm",
            Runtime::Codex => "codex",
            Runtime::Kimi => "kimi",
            Runtime::Deepseek => "deepseek",
            Runtime::Qwen => "qwen",
        }
    }

    /// **Single source of truth for the mixed-batch rule (§4-1 of the W5 task brief).**
    /// `true` = this runtime can only run via a process-wide `ANTHROPIC_BASE_URL` swap, so it
    /// can never coexist with a *different* backend (including plain `claude`) in the same
    /// Claude Code process. `Codex` is deliberately `false` here even though it is also not
    /// "plain claude" — it dispatches through a separate OS process (ADR-D-0006) and therefore
    /// never touches this process's env, so it never needs to be excluded from a batch.
    pub fn is_env_global(&self) -> bool {
        matches!(
            self,
            Runtime::Glm | Runtime::Kimi | Runtime::Deepseek | Runtime::Qwen
        )
    }

    /// The [`SessionBackend`] this runtime requires the *whole process* to already be running
    /// under, or `None` for the two runtimes that don't need a process-wide env swap at all
    /// (`Claude`, `Codex`). This is the one place that has to know the 1:1 correspondence
    /// between an env-global `Runtime` variant and its `SessionBackend` counterpart — necessary
    /// glue between the two enums (a role's *desired* runtime vs. the session's *actual*
    /// backend), independent of the `is_env_global` boolean above.
    pub fn env_backend(&self) -> Option<SessionBackend> {
        match self {
            Runtime::Glm => Some(SessionBackend::Glm),
            Runtime::Kimi => Some(SessionBackend::Kimi),
            Runtime::Deepseek => Some(SessionBackend::Deepseek),
            Runtime::Qwen => Some(SessionBackend::Qwen),
            Runtime::Claude | Runtime::Codex => None,
        }
    }
}

/// The **actual backend** the current Claude Code process is running under. Determined by
/// `bathos model detect` inspecting `ANTHROPIC_BASE_URL` — this is a process-wide fact
/// (`[measured F2]` in the design doc: env-global vars are not per-teammate), never a per-role
/// choice. Mirrors [`Runtime`]'s env-global variants 1:1 (see [`Runtime::env_backend`]) but
/// deliberately has **no** `Codex` variant: Codex is a subprocess, never "the backend this
/// Claude Code process is running under".
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SessionBackend {
    Claude,
    Glm,
    Kimi,
    Deepseek,
    Qwen,
}

impl SessionBackend {
    /// Pure classification so this is unit-testable without touching real env vars —
    /// `bathos model detect` (bathos-cli) supplies `std::env::var("ANTHROPIC_BASE_URL").ok()`.
    ///
    /// Host substrings come from the user-confirmed integration table (W5 task brief §3):
    /// `api.z.ai` (GLM), `api.moonshot.ai` (Kimi), `api.deepseek.com` (Deepseek). An
    /// unrecognized/unset host falls back to `Claude` — lenient by design (§A1.1 "honest limits":
    /// a typo'd or future host must never silently become an *error*, only an
    /// under-detection).
    ///
    /// **Qwen matches two known URL shapes, not one** — `assets/model-catalog.json`'s
    /// `_url_discrepancy` note (added independently, in parallel, by the lead) found that
    /// Alibaba's own docs disagree with itself: some material shows a fixed
    /// `dashscope[-intl].aliyuncs.com` host, but the two official Model Studio pages instead
    /// show a **templated** `{workspace}.{region}.maas.aliyuncs.com` host. Since either shape
    /// might be what actually reaches Claude Code in practice, this matches both substrings
    /// (`dashscope` and `maas.aliyuncs.com`) rather than picking one and silently
    /// under-detecting the other — same lenient philosophy as the "unrecognized host" case
    /// above, just with two known-good substrings instead of one.
    pub fn detect_from_base_url(base_url: Option<&str>) -> Self {
        match base_url {
            Some(url) if url.contains("api.z.ai") => SessionBackend::Glm,
            Some(url) if url.contains("api.moonshot.ai") => SessionBackend::Kimi,
            Some(url) if url.contains("api.deepseek.com") => SessionBackend::Deepseek,
            Some(url) if url.contains("dashscope") || url.contains("maas.aliyuncs.com") => {
                SessionBackend::Qwen
            }
            _ => SessionBackend::Claude,
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            SessionBackend::Claude => "claude",
            SessionBackend::Glm => "glm",
            SessionBackend::Kimi => "kimi",
            SessionBackend::Deepseek => "deepseek",
            SessionBackend::Qwen => "qwen",
        }
    }

    /// Inverse of [`Runtime::env_backend`] — `None` for `Claude` (no runtime *requires* the
    /// plain-claude session backend; it's simply the absence of an env-global override).
    pub fn as_runtime(&self) -> Option<Runtime> {
        match self {
            SessionBackend::Claude => None,
            SessionBackend::Glm => Some(Runtime::Glm),
            SessionBackend::Kimi => Some(Runtime::Kimi),
            SessionBackend::Deepseek => Some(Runtime::Deepseek),
            SessionBackend::Qwen => Some(Runtime::Qwen),
        }
    }
}

/// Mixed-batch policy for a wave (`waves.<W?>.mixed_policy`). Currently informational/reserved:
/// [`validate_wave`] always surfaces all 3 resolution options (§A3.2 R3) regardless of this
/// value — a future iteration may vary the message by policy, but changing *enforcement*
/// behavior without also implementing the "sequential" auto-split would be fabricating a
/// capability that doesn't exist yet, so today it's documentation-only (honest scope).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum MixedPolicy {
    #[default]
    Forbid,
    Sequential,
}

/// One role's assignment. `model: None` means "use the runtime's own default" (for `claude`
/// this falls through further down the resolve chain — frontmatter/runtime default; for the
/// env-global runtimes / `codex` it means "let the session env / Codex install default
/// decide").
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RoleModelSpec {
    pub runtime: Runtime,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    /// codex-only (`model_reasoning_effort` passed through to `to-codex.sh`/`run-role.sh`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reasoning_effort: Option<String>,
}

impl Default for RoleModelSpec {
    fn default() -> Self {
        RoleModelSpec {
            runtime: Runtime::Claude,
            model: None,
            reasoning_effort: None,
        }
    }
}

/// Per-wave override block (`waves.<W?>`).
///
/// **Backward compatibility (DoD-required regression):** every new field below is
/// `#[serde(default)]` + `skip_serializing_if` so an existing `model-plan.json` that only ever
/// wrote `{"mixed_policy": "forbid"}` (or omitted `waves` entirely) still deserializes byte-for-
/// byte the same as before this struct grew — see `wave_policy_backcompat_*` tests.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct WavePolicy {
    #[serde(default)]
    pub mixed_policy: MixedPolicy,
    /// Declarative "this wave runs on runtime X" plan entry (§4-5 resolve chain step 2). Gated
    /// the same way `defaults.model` gates `defaults` (§A1.3 step 2): the wave step only fires
    /// when `runtime` is set. A `WavePolicy` with only `model`/`reasoning_effort` set (no
    /// `runtime`) is inert by design — a model string alone doesn't say *which* channel to send
    /// it through, so requiring `runtime` keeps the wave step meaningful rather than adding a
    /// second ad-hoc gate to reason about.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub runtime: Option<Runtime>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    /// codex-only, same meaning as [`RoleModelSpec::reasoning_effort`].
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reasoning_effort: Option<String>,
}

/// The full `model-plan.json` document (`bathos/model-plan@1`).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelPlan {
    pub schema: String,
    pub updated: DateTime<Utc>,
    pub updated_by: String,
    pub session_backend: SessionBackend,
    #[serde(default)]
    pub defaults: RoleModelSpec,
    /// keyed by agent-definition slug (e.g. `"phillip-backend-engineer"`).
    #[serde(default)]
    pub roles: HashMap<String, RoleModelSpec>,
    #[serde(default)]
    pub waves: HashMap<String, WavePolicy>,
}

impl ModelPlan {
    /// A plan with no overrides at all — behaviorally identical to "no `model-plan.json`
    /// file" (every role falls through to frontmatter). Used both as the absent-file default
    /// and as the safe fallback when the on-disk file is corrupt/schema-mismatched.
    pub fn empty(updated_by: &str) -> Self {
        ModelPlan {
            schema: SCHEMA_ID.to_string(),
            updated: Utc::now(),
            updated_by: updated_by.to_string(),
            session_backend: SessionBackend::Claude,
            defaults: RoleModelSpec::default(),
            roles: HashMap::new(),
            waves: HashMap::new(),
        }
    }
}

/// A lenient-load warning — never blocks, only informs (`bathos model show` prints these).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlanWarning {
    pub code: String,
    pub message: String,
}

fn plan_path(state_dir: &Path) -> std::path::PathBuf {
    state_dir.join("model-plan.json")
}

/// Loads `<state_dir>/model-plan.json` leniently.
///
/// - **Absent file** → `ModelPlan::empty()`, no warning (this is the expected steady state for
///   every project that hasn't opted in — E1 "normal" case, not an error).
/// - **Unparseable JSON** → `ModelPlan::empty()` + `W-MODELPLAN-CORRUPT` warning (E1).
/// - **Parses but `schema` field mismatched/missing** → `ModelPlan::empty()` +
///   `W-MODELPLAN-SCHEMA` warning (§A1.1 "on mismatch, warn leniently, ignore, fall back to
///   frontmatter").
/// - Otherwise the parsed plan is returned as-is.
///
/// Never panics, never returns `Err` — this mirrors `bathos-inspect::loader`'s "only a truly
/// Fatal condition (there is no state_dir at all) is an error; everything else is a warning"
/// philosophy, appropriate here because an unreadable model-plan.json must never block a wave
/// spawn (fail-safe > fail-closed for this particular file).
pub fn load(state_dir: &Path) -> (ModelPlan, Vec<PlanWarning>) {
    let path = plan_path(state_dir);
    let raw = match fs::read_to_string(&path) {
        Ok(s) => s,
        Err(_) => return (ModelPlan::empty("system"), Vec::new()),
    };

    let value: serde_json::Value = match serde_json::from_str(&raw) {
        Ok(v) => v,
        Err(e) => {
            return (
                ModelPlan::empty("system"),
                vec![PlanWarning {
                    code: "W-MODELPLAN-CORRUPT".to_string(),
                    message: format!("model-plan.json 파싱 실패(폴백=frontmatter): {e}"),
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
            ModelPlan::empty("system"),
            vec![PlanWarning {
                code: "W-MODELPLAN-SCHEMA".to_string(),
                message: format!(
                    "model-plan.json schema 불일치(기대: {SCHEMA_ID}) — 폴백=frontmatter"
                ),
            }],
        );
    }

    match serde_json::from_value::<ModelPlan>(value) {
        Ok(plan) => (plan, Vec::new()),
        Err(e) => (
            ModelPlan::empty("system"),
            vec![PlanWarning {
                code: "W-MODELPLAN-CORRUPT".to_string(),
                message: format!("model-plan.json 필드 역직렬화 실패(폴백=frontmatter): {e}"),
            }],
        ),
    }
}

/// Whether an on-disk `model-plan.json` exists but is unparseable JSON (distinct from
/// "well-formed but wrong schema" and from "absent"). `bathos model set` uses this to decide
/// whether to back up the existing file to `.bak` before overwriting it (E1 second half:
/// "on set, back up to .bak, then ask before regenerating") — a schema-mismatch file is
/// well-formed JSON and does
/// not need this protection (overwriting it loses nothing unrecoverable-looking).
pub fn is_corrupt_json(state_dir: &Path) -> bool {
    let path = plan_path(state_dir);
    match fs::read_to_string(&path) {
        Ok(raw) => serde_json::from_str::<serde_json::Value>(&raw).is_err(),
        Err(_) => false,
    }
}

/// Atomically writes `plan` to `<state_dir>/model-plan.json` (temp file + rename, same pattern
/// as `store::StateStore::atomic_write` — a partial write is never observable).
///
/// Deliberately **no file lock**: unlike `manifest.json` (written by multiple concurrent
/// engines/hooks), `model-plan.json` is written only by the lead's sequential `bathos model
/// set/unset/detect` calls (§A1.3 "the single write path is `bathos model set`"). Adding a lock
/// here would be complexity with no corresponding risk to mitigate — a deliberate simplicity
/// call, not an oversight.
pub fn save(state_dir: &Path, plan: &ModelPlan) -> std::io::Result<()> {
    fs::create_dir_all(state_dir)?;
    let path = plan_path(state_dir);
    let tmp = state_dir.join(".model-plan.tmp");
    let json = serde_json::to_string_pretty(plan)?;
    fs::write(&tmp, json.as_bytes())?;
    fs::rename(&tmp, &path)?;
    Ok(())
}

/// Backs up a corrupt `model-plan.json` to `model-plan.json.bak` (overwriting any previous
/// backup — this module keeps only the most recent). No-op (`Ok(())`) if the source file is
/// absent, since there is nothing to back up.
pub fn backup_corrupt(state_dir: &Path) -> std::io::Result<()> {
    let path = plan_path(state_dir);
    if !path.exists() {
        return Ok(());
    }
    let bak = state_dir.join("model-plan.json.bak");
    fs::copy(&path, &bak)?;
    Ok(())
}

// ─────────────────────────────────────────────────────────────────────────────
// frontmatter fallback — step 3 of the resolve priority chain (§A1.3)
// ─────────────────────────────────────────────────────────────────────────────

/// Extracts one `key: value` field from a role-definition file's frontmatter block (the
/// `---\n...\n---` header at the top of `.claude/agents/_base/<n>-<slug>.md`). Strips a
/// trailing `# inline comment` (these files consistently use `model: claude-sonnet-5   #
/// Sonnet 5 (was ...)` — see `.claude/agents/_base/08-phillip-backend-engineer.md`).
///
/// Pure string function — no filesystem access — so it is directly unit-testable against
/// fixture strings without needing real agent files on disk.
fn frontmatter_field(content: &str, key: &str) -> Option<String> {
    let mut in_frontmatter = false;
    for (i, line) in content.lines().enumerate() {
        let trimmed = line.trim_end();
        if i == 0 && trimmed == "---" {
            in_frontmatter = true;
            continue;
        }
        if in_frontmatter && trimmed == "---" {
            break; // closing delimiter — frontmatter block ended
        }
        if !in_frontmatter {
            continue;
        }
        let prefix = format!("{key}:");
        if let Some(rest) = trimmed.trim_start().strip_prefix(&prefix) {
            let no_comment = rest.split('#').next().unwrap_or(rest);
            let value = no_comment.trim();
            if !value.is_empty() {
                return Some(value.to_string());
            }
        }
    }
    None
}

/// Scans `agents_dir` (typically `<project_root>/.claude/agents/_base`) for the role file
/// whose frontmatter `slug:` field equals `slug`, and returns its `model:` field.
///
/// Matches by the `slug:` frontmatter field rather than by filename pattern (`<n>-<slug>.md`)
/// because filenames are not guaranteed to be a reliable 1:1 key in this repository — this
/// module previously (incorrectly) documented `13-michael-security-specialist.md` and
/// `13-mishael-security-specialist.md` as coexisting; that was stale (the `mishael-` spelling
/// was a typo fixed story-19, CF9 — only `13-michael-security-specialist.md` exists now). The
/// frontmatter `slug:` field remains the right lookup key regardless: it's the actual identity
/// contract every other BATHOS tool (`to-codex.sh`'s `fm_val`) already relies on, not filename
/// prefix guessing.
///
/// Returns `None` if `agents_dir` is absent/unreadable or no file's `slug:` matches — this is
/// not an error (the caller falls through to the final "runtime default" resolve step).
pub fn find_frontmatter_model(agents_dir: &Path, slug: &str) -> Option<String> {
    let entries = fs::read_dir(agents_dir).ok()?;
    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) != Some("md") {
            continue;
        }
        let content = match fs::read_to_string(&path) {
            Ok(c) => c,
            Err(_) => continue,
        };
        if frontmatter_field(&content, "slug").as_deref() == Some(slug) {
            return frontmatter_field(&content, "model");
        }
    }
    None
}

// ─────────────────────────────────────────────────────────────────────────────
// resolve — the 5-step priority chain (§4-5 of the W5 task brief, extends §A1.3's 4 steps)
// ─────────────────────────────────────────────────────────────────────────────

/// Where an [`EffectiveModel`] value came from — surfaced by `bathos model show`/`resolve` so
/// the user always sees *why* a role has the model it has (never a silent black box).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Source {
    /// `model-plan.json` `roles.<slug>` entry.
    Plan,
    /// `model-plan.json` `waves.<W?>` entry (only reached when that wave's `runtime` is set) —
    /// new step inserted between `Plan` and `Default` (§4-5).
    Wave,
    /// `model-plan.json` `defaults` block (only reached when `defaults.model` is set).
    Default,
    /// Agent-definition frontmatter `model:` field (pre-existing, 100% backward-compat path).
    Frontmatter,
    /// No plan, no default, no frontmatter match — the bare runtime default (`claude`, model
    /// unspecified = whatever Claude Code's own session default is).
    RuntimeDefault,
}

impl Source {
    pub fn as_str(&self) -> &'static str {
        match self {
            Source::Plan => "plan",
            Source::Wave => "wave",
            Source::Default => "default",
            Source::Frontmatter => "frontmatter",
            Source::RuntimeDefault => "runtime-default",
        }
    }
}

/// The resolved runtime/model for one role, plus where the decision came from.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EffectiveModel {
    pub runtime: Runtime,
    pub model: Option<String>,
    pub reasoning_effort: Option<String>,
    pub source: Source,
}

/// Implements the 5-step priority chain (§4-5 of the W5 task brief, extending
/// `w2-panes-model-design-kr.md` §A1.3's original 4 steps with a wave-level step inserted
/// between `roles` and `defaults` — more specific always wins):
///
/// ```text
/// effective(role, wave) =
///   1. model-plan.roles[slug]         (if present and valid)
///   2. model-plan.waves[wave]          (if a wave is given and waves[wave].runtime != null)
///   3. model-plan.defaults             (if defaults.model != null)
///   4. agent frontmatter `model`       (current behavior — fallback when the plan is absent/corrupt)
///   5. runtime default                 (claude = the session's default model)
/// ```
///
/// `wave_id` is an **explicit** parameter rather than something this function infers on its
/// own (e.g. via a reverse role→wave lookup) — deliberately, for two reasons: (1) it keeps this
/// a pure function of its arguments (no hidden dependency on a wave-roster table), and (2) a
/// handful of roles (Thomas/Matthias/Timothy) belong to *two* waves (W3 and W6), so "the wave
/// this role belongs to" is not always a single well-defined answer — only the caller (which
/// knows which wave command is currently running) can say which one applies. Callers with no
/// wave context at all (e.g. `bathos model resolve <slug>` without `--wave`) may pass
/// `wave_roles::role_wave(slug)` as a best-effort default; see that function's doc comment for
/// exactly what "best-effort" means for multi-wave roles.
///
/// Step 2 (wave) is gated on `waves[wave].runtime` being non-null for the same reason step 3
/// (defaults) is gated on `defaults.model` being non-null: it's what makes "no plan file" and
/// "plan file with an unrelated/empty wave entry" behave identically (both fall through) — the
/// backward-compat guarantee.
///
/// Pure function — no filesystem access (the caller reads `model-plan.json` via [`load`] and
/// frontmatter via [`find_frontmatter_model`] beforehand) — fully unit-testable (T1).
pub fn resolve_effective(
    plan: &ModelPlan,
    slug: &str,
    frontmatter_model: Option<&str>,
    wave_id: Option<&str>,
) -> EffectiveModel {
    if let Some(spec) = plan.roles.get(slug) {
        return EffectiveModel {
            runtime: spec.runtime,
            model: spec.model.clone(),
            reasoning_effort: spec.reasoning_effort.clone(),
            source: Source::Plan,
        };
    }
    if let Some(wave_policy) = wave_id.and_then(|w| plan.waves.get(w)) {
        if let Some(runtime) = wave_policy.runtime {
            return EffectiveModel {
                runtime,
                model: wave_policy.model.clone(),
                reasoning_effort: wave_policy.reasoning_effort.clone(),
                source: Source::Wave,
            };
        }
    }
    if let Some(m) = &plan.defaults.model {
        return EffectiveModel {
            runtime: plan.defaults.runtime,
            model: Some(m.clone()),
            reasoning_effort: None,
            source: Source::Default,
        };
    }
    if let Some(fm) = frontmatter_model {
        return EffectiveModel {
            runtime: Runtime::Claude,
            model: Some(fm.to_string()),
            reasoning_effort: None,
            source: Source::Frontmatter,
        };
    }
    EffectiveModel {
        runtime: Runtime::Claude,
        model: None,
        reasoning_effort: None,
        source: Source::RuntimeDefault,
    }
}

/// The runtime-only projection of [`resolve_effective`] — used by [`validate_wave`], which
/// only ever needs to know *which runtime* a role lands on (never the concrete model string),
/// and critically does **not** need a frontmatter lookup to compute it: frontmatter can only
/// ever produce `Runtime::Claude` (agent definitions have no `runtime:` field, only `model:`),
/// so the frontmatter-fallback step of the full chain is a no-op runtime-wise. This lets
/// mixed-batch validation stay a pure, filesystem-free function (fully unit-testable, T2)
/// while still being consistent with [`resolve_effective`]'s behavior.
pub fn resolve_effective_runtime(plan: &ModelPlan, slug: &str, wave_id: Option<&str>) -> Runtime {
    if let Some(spec) = plan.roles.get(slug) {
        return spec.runtime;
    }
    if let Some(wave_policy) = wave_id.and_then(|w| plan.waves.get(w)) {
        if let Some(runtime) = wave_policy.runtime {
            return runtime;
        }
    }
    if plan.defaults.model.is_some() {
        return plan.defaults.runtime;
    }
    Runtime::Claude
}

// ─────────────────────────────────────────────────────────────────────────────
// validate — mixed-batch rules, generalized from GLM-only R1~R4 to any env-global runtime
// (§A3.2 original design + §4-6 of the W5 task brief's "session-backend mismatch gate")
// ─────────────────────────────────────────────────────────────────────────────

/// A blocked `bathos model validate` result — always exit-2 material. Carries the resolution
/// menu verbatim so the CLI/hook layer never has to re-derive it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MixViolation {
    pub code: &'static str,
    pub message: String,
    pub resolutions: Vec<String>,
}

/// The connection detail for one env-global runtime, used **only** to render an honest,
/// concrete transition instruction in [`MixViolation::resolutions`] — this module makes no
/// network calls, it only ever prints where the caller could point `ANTHROPIC_BASE_URL`.
///
/// ponytail: Glm/Kimi/Deepseek's endpoints are hardcoded here as fixed constants (there are
/// only 3 of them and they change about as often as `Runtime` itself gains a variant — a code
/// change either way). **Qwen is a different kind of limitation, not the same one** — its
/// endpoint is inherently *not* a constant (`{workspace}.{region}.maas.aliyuncs.com` is a
/// template with two required substitutions this crate has no way to fill in), so hardcoding a
/// single Qwen URL would be actively wrong, not just brittle; that's why its arm below prints
/// the template shape plus a pointer to the catalog/console instead of a URL string. Ceiling:
/// a vendor migrates one of the 3 fixed endpoints, or the Glm/Kimi/Deepseek→Qwen shape ratio
/// stops being 3-fixed/1-templated (e.g. a 5th runtime is also templated). Upgrade path: load
/// `assets/model-catalog.json` (the lead's model catalog already carries `env.ANTHROPIC_BASE_URL`
/// per provider, plus `url_is_templated`/`regions[]` for Qwen specifically) once this crate is
/// allowed to depend on runtime asset I/O for a CLI-only display string.
///
/// Promoted from private to `pub` for `bathos model switch` (story M4): the Tier-R
/// copy-paste command generator reuses this as the **single source of truth** for endpoint
/// text — the wording is frozen by contract ("문안 변경 금지"), only visibility changed.
pub fn env_endpoint_hint(runtime: Runtime) -> &'static str {
    match runtime {
        Runtime::Glm => "https://api.z.ai/api/anthropic (scripts/glm-env.sh 존재)",
        Runtime::Kimi => "https://api.moonshot.ai/anthropic",
        Runtime::Deepseek => "https://api.deepseek.com/anthropic",
        Runtime::Qwen => {
            // Two URL shapes are both attested (see `SessionBackend::detect_from_base_url`'s
            // doc comment) and this crate cannot pick a winner without fabricating certainty
            // the source material doesn't have — so the hint says both, explicitly flagged as
            // unconfirmed, instead of asserting one as fact.
            "https://dashscope-intl.aliyuncs.com/apps/anthropic 또는 \
             https://{workspace}.{region}.maas.aliyuncs.com/apps/anthropic \
             (⚠ 두 URL 형태가 자료마다 다름 — assets/model-catalog.json qwen._url_discrepancy \
             참고, 사용 전 Model Studio 콘솔에서 실제 엔드포인트 확인 필요)"
        }
        Runtime::Claude | Runtime::Codex => "(env-global 아님 — 해당 없음)",
    }
}

/// Which env var carries the API key for a given env-global runtime's `ANTHROPIC_BASE_URL`
/// swap. **Not uniform across providers** — this is a fact, confirmed against DeepSeek's own
/// docs (api-docs.deepseek.com/guides/anthropic_api/), not an assumption: DeepSeek's Anthropic-
/// compat endpoint reads `ANTHROPIC_API_KEY` (or an `x-api-key` header), *not*
/// `ANTHROPIC_AUTH_TOKEN` the way Glm/Kimi/Qwen do. Naming the wrong var in a transition
/// instruction is worse than a vague one (it actively misleads), so this small mapping exists
/// specifically to keep resolution #3 below correct per-provider instead of copy-pasting one
/// var name for all four.
///
/// Promoted from private to `pub` for `bathos model switch` (story M4): the Tier-R raw
/// `export` line names the auth var per runtime — same frozen-wording, visibility-only
/// change as [`env_endpoint_hint`].
pub fn env_auth_var(runtime: Runtime) -> &'static str {
    match runtime {
        Runtime::Deepseek => "ANTHROPIC_API_KEY",
        Runtime::Glm | Runtime::Kimi | Runtime::Qwen => "ANTHROPIC_AUTH_TOKEN",
        Runtime::Claude | Runtime::Codex => "(env-global 아님 — 해당 없음)",
    }
}

/// The resolution menu for an env-global mixing violation — same 3 moves regardless of which
/// runtime triggered it (go all-in on that runtime, move the conflicting role elsewhere, or
/// split the wave across two sessions), but now naming the *actual* target runtime and its
/// real endpoint instead of hardcoding "GLM"/`glm-env.sh` the way the original R3 menu did.
///
/// ponytail: only `scripts/glm-env.sh` exists on disk today (Kimi/Deepseek/Qwen have no
/// equivalent env-swap script yet — that's `scripts/` territory, owned by the lead, not this
/// crate). Resolution #3 below therefore gives the raw `export ANTHROPIC_BASE_URL=...` /
/// `<auth var>=...` pair rather than inventing a script path that doesn't exist.
/// Upgrade path: once `scripts/<runtime>-env.sh` exists for a given runtime, this can name it
/// directly the way the Glm case already does.
fn transition_resolutions(target: Runtime) -> Vec<String> {
    let endpoint = env_endpoint_hint(target);
    let auth_var = env_auth_var(target);
    let name = target.as_str();
    vec![
        format!(
            "1) 배치 전체 {name}: 이 웨이브 모든 역할을 runtime={name}으로 통일(사용자 승인 필요) \
             — ANTHROPIC_BASE_URL={endpoint}"
        ),
        format!("2) 역할 이동: {name} 희망 역할을 claude 또는 codex로 변경"),
        format!(
            "3) 웨이브 순차 분할: 현재 배치를 먼저 완료·shutdown → \
             ANTHROPIC_BASE_URL={endpoint} + {auth_var}=<키> 로 새 세션 재기동 후 재개"
        ),
    ]
}

/// Resolution menu for Rule 1 (two-or-more *different* env-global runtimes requested in the
/// same batch). Deliberately generic — with N>=2 conflicting runtimes there is no single
/// "target" to name the way [`transition_resolutions`] can for the one-vs-session case, so this
/// lists the conflict set once and gives the same 3 structural moves without repeating a full
/// per-runtime endpoint block for each candidate (which would multiply with N and bury the
/// actually-actionable choice: pick one).
fn multi_env_global_resolutions(conflicting: &[&str]) -> Vec<String> {
    let list = conflicting.join(", ");
    vec![
        format!("1) 하나만 선택: {list} 중 하나를 이 웨이브의 env-global 런타임으로 통일"),
        format!(
            "2) 역할 이동: {list} 중 소수 역할을 claude 또는 codex로 변경해 후보를 하나로 축소"
        ),
        "3) 웨이브 순차 분할: 후보 런타임별로 세션을 나눠(각자 env swap 후 재기동) 순차 진행"
            .into(),
    ]
}

/// Validates a wave's role batch against the env-global process-wide-env constraint
/// (ADR-D-0005, generalized from GLM-only to `Glm|Kimi|Deepseek|Qwen` via
/// [`Runtime::is_env_global`] — adding a 5th env-global runtime touches that one predicate, not
/// this function's branching).
///
/// - **Rule 1 (`E-MODEL-MIX`, new — no GLM-only equivalent existed because only one env-global
///   runtime existed before): two *different* env-global runtimes both requested in the same
///   batch** (e.g. one role wants `kimi`, another wants `deepseek`). No single process-wide
///   `ANTHROPIC_BASE_URL` can satisfy both, independent of what `session_backend` currently is.
/// - **Rule 2 (`E-MODEL-MIX`, generalizes old R2/R3): the session-backend mismatch gate
///   (§4-6)** — exactly one env-global runtime is requested but `plan.session_backend` isn't
///   already running under that runtime's backend. `resolutions` carries the concrete
///   transition steps (which env var, which endpoint, how to restart).
/// - **Rule 3 (`E-MODEL-BACKEND-MISMATCH`, generalizes old R4): `plan.session_backend` is
///   already some env-global backend, but a role has an *explicit* `roles.<slug>.runtime =
///   claude` entry** — that explicit choice cannot be honored (the whole process is already
///   that backend). A role with no plan entry at all (implicit claude via the runtime default)
///   does **not** trigger this — only an explicit, contradicted choice is a violation.
/// - **Codex roles never block**: a separate process, no env conflict either direction
///   (ADR-D-0006 "honest asymmetry") — `is_env_global()` is `false` for `Codex`, so it's simply
///   never a candidate in Rule 1/2 and never `session_backend`'s value in Rule 3.
///
/// `role_slugs` should be the wave's role roster (see `bathos_state::wave_roles`, sourced from
/// `CLAUDE.md` §1/§2's role↔wave table) — or, if the caller wants a whole-plan check (`--wave`
/// omitted), every key currently present in `plan.roles`. `wave_id` is used both as the label in
/// error messages and, via [`resolve_effective_runtime`]'s wave step, to apply that wave's
/// `waves.<wave_id>` policy (if any) to roles with no explicit `roles.<slug>` entry.
pub fn validate_wave(
    plan: &ModelPlan,
    wave_id: &str,
    role_slugs: &[String],
) -> Result<(), MixViolation> {
    let runtimes: Vec<(String, Runtime)> = role_slugs
        .iter()
        .map(|s| (s.clone(), resolve_effective_runtime(plan, s, Some(wave_id))))
        .collect();

    let env_global_roles: Vec<(&str, Runtime)> = runtimes
        .iter()
        .filter(|(_, r)| r.is_env_global())
        .map(|(s, r)| (s.as_str(), *r))
        .collect();

    let mut distinct_runtimes: Vec<Runtime> = env_global_roles.iter().map(|(_, r)| *r).collect();
    distinct_runtimes.sort_by_key(|r| r.as_str());
    distinct_runtimes.dedup();

    // Rule 1 — two different env-global runtimes both wanted in one batch.
    if distinct_runtimes.len() > 1 {
        let names: Vec<&str> = distinct_runtimes.iter().map(|r| r.as_str()).collect();
        return Err(MixViolation {
            code: "E-MODEL-MIX",
            message: format!(
                "[E-MODEL-MIX] wave={wave_id} — 서로 다른 env-global 런타임({}) 이 한 배치에 \
                 동시 요청됨. env-global 백엔드는 프로세스 전역 하나뿐이라 둘 이상 동시 구동이 \
                 불가합니다.",
                names.join(", ")
            ),
            resolutions: multi_env_global_resolutions(&names),
        });
    }

    // Rule 2 — the session-backend transition gate (§4-6): exactly one env-global runtime is
    // requested; it must already match the session's actual backend.
    if let Some(&target) = distinct_runtimes.first() {
        let expected_backend = target
            .env_backend()
            .expect("is_env_global() true implies env_backend() is Some");
        if plan.session_backend != expected_backend {
            let names: Vec<&str> = env_global_roles.iter().map(|(s, _)| *s).collect();
            return Err(MixViolation {
                code: "E-MODEL-MIX",
                message: format!(
                    "[E-MODEL-MIX] wave={wave_id} — {} 지정 역할({}) 존재하나 session_backend={}\
                     ({} 아님). env-global 런타임은 프로세스 전역이라 역할 단위 분리가 물리적으로 \
                     불가합니다.",
                    target.as_str(),
                    names.join(", "),
                    plan.session_backend.as_str(),
                    target.as_str()
                ),
                resolutions: transition_resolutions(target),
            });
        }
    }

    // Rule 3 — the session is already running under SOME env-global backend; an explicit
    // `runtime=claude` role entry contradicts that and cannot be honored.
    if let Some(session_runtime) = plan.session_backend.as_runtime() {
        let explicit_claude: Vec<&str> = role_slugs
            .iter()
            .filter(|s| {
                plan.roles
                    .get(s.as_str())
                    .map(|spec| spec.runtime == Runtime::Claude)
                    .unwrap_or(false)
            })
            .map(|s| s.as_str())
            .collect();
        if !explicit_claude.is_empty() {
            return Err(MixViolation {
                code: "E-MODEL-BACKEND-MISMATCH",
                message: format!(
                    "[E-MODEL-BACKEND-MISMATCH] wave={wave_id} — session_backend={}인데 \
                     명시적 runtime=claude 역할({}) 존재. 이 세션에서 claude 지정은 이행 불가\
                     (전부 {}로 나감).",
                    plan.session_backend.as_str(),
                    explicit_claude.join(", "),
                    plan.session_backend.as_str()
                ),
                resolutions: transition_resolutions(session_runtime),
            });
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn plan_with_role(slug: &str, runtime: Runtime, model: Option<&str>) -> ModelPlan {
        let mut plan = ModelPlan::empty("Paul");
        plan.roles.insert(
            slug.to_string(),
            RoleModelSpec {
                runtime,
                model: model.map(str::to_string),
                reasoning_effort: None,
            },
        );
        plan
    }

    // ── T1: resolve priority chain (5 steps × missing/corrupt) ──────────────

    #[test]
    fn resolve_step1_plan_role_wins_over_everything() {
        let plan = plan_with_role("phillip-backend-engineer", Runtime::Codex, None);
        let eff = resolve_effective(
            &plan,
            "phillip-backend-engineer",
            Some("claude-sonnet-5"),
            None,
        );
        assert_eq!(eff.runtime, Runtime::Codex);
        assert_eq!(eff.source, Source::Plan);
    }

    #[test]
    fn resolve_step1_plan_role_wins_even_over_a_matching_wave_entry() {
        // roles[slug] is more specific than waves[wave] — it must win even when a wave policy
        // for the same wave also exists (§4-5 "the more specific one wins").
        let mut plan = plan_with_role("phillip-backend-engineer", Runtime::Codex, None);
        plan.waves.insert(
            "W5".into(),
            WavePolicy {
                runtime: Some(Runtime::Kimi),
                ..Default::default()
            },
        );
        let eff = resolve_effective(&plan, "phillip-backend-engineer", None, Some("W5"));
        assert_eq!(eff.runtime, Runtime::Codex);
        assert_eq!(eff.source, Source::Plan);
    }

    #[test]
    fn resolve_step2_wave_used_when_runtime_set_and_no_role_entry() {
        let mut plan = ModelPlan::empty("Paul");
        plan.waves.insert(
            "W5".into(),
            WavePolicy {
                runtime: Some(Runtime::Deepseek),
                model: Some("deepseek-chat".into()),
                ..Default::default()
            },
        );
        let eff = resolve_effective(
            &plan,
            "andrew-frontend-engineer",
            Some("claude-sonnet-5"),
            Some("W5"),
        );
        assert_eq!(eff.runtime, Runtime::Deepseek);
        assert_eq!(eff.model.as_deref(), Some("deepseek-chat"));
        assert_eq!(eff.source, Source::Wave);
    }

    #[test]
    fn resolve_step2_skipped_when_wave_runtime_is_null_or_wave_unset() {
        // a WavePolicy with only `mixed_policy` set (no `runtime`) is inert — falls through
        // exactly like no wave entry existed (this is the backward-compat fixture shape: old
        // files only ever wrote `mixed_policy`).
        let mut plan = ModelPlan::empty("Paul");
        plan.waves.insert("W5".into(), WavePolicy::default());
        let eff = resolve_effective(
            &plan,
            "andrew-frontend-engineer",
            Some("claude-sonnet-5"),
            Some("W5"),
        );
        assert_eq!(eff.source, Source::Frontmatter);

        // no `wave_id` passed at all → the wave step is skipped outright, even though a
        // matching (and populated) wave entry exists in the plan.
        plan.waves.insert(
            "W5".into(),
            WavePolicy {
                runtime: Some(Runtime::Qwen),
                ..Default::default()
            },
        );
        let eff_no_wave_ctx = resolve_effective(
            &plan,
            "andrew-frontend-engineer",
            Some("claude-sonnet-5"),
            None,
        );
        assert_eq!(eff_no_wave_ctx.source, Source::Frontmatter);
    }

    #[test]
    fn resolve_step3_defaults_used_when_model_set_and_no_role_or_wave_entry() {
        let mut plan = ModelPlan::empty("Paul");
        plan.defaults = RoleModelSpec {
            runtime: Runtime::Glm,
            model: Some("glm-4.7".into()),
            reasoning_effort: None,
        };
        let eff = resolve_effective(
            &plan,
            "andrew-frontend-engineer",
            Some("claude-sonnet-5"),
            None,
        );
        assert_eq!(eff.runtime, Runtime::Glm);
        assert_eq!(eff.model.as_deref(), Some("glm-4.7"));
        assert_eq!(eff.source, Source::Default);
    }

    #[test]
    fn resolve_step3_skipped_when_defaults_model_is_null() {
        // defaults.model == None → step 3 is a no-op even though defaults.runtime is set —
        // this is the literal reading of "(if defaults.model != null)" that keeps an empty
        // plan behaviorally identical to no plan at all.
        let plan = ModelPlan::empty("Paul");
        let eff = resolve_effective(
            &plan,
            "andrew-frontend-engineer",
            Some("claude-sonnet-5"),
            None,
        );
        assert_eq!(eff.source, Source::Frontmatter);
        assert_eq!(eff.model.as_deref(), Some("claude-sonnet-5"));
    }

    #[test]
    fn resolve_step4_frontmatter_fallback_when_plan_absent() {
        let plan = ModelPlan::empty("system");
        let eff = resolve_effective(&plan, "james-architect", Some("claude-fable-5"), None);
        assert_eq!(eff.runtime, Runtime::Claude);
        assert_eq!(eff.model.as_deref(), Some("claude-fable-5"));
        assert_eq!(eff.source, Source::Frontmatter);
    }

    #[test]
    fn resolve_step5_runtime_default_when_nothing_matches() {
        let plan = ModelPlan::empty("system");
        let eff = resolve_effective(&plan, "unknown-slug", None, None);
        assert_eq!(eff.runtime, Runtime::Claude);
        assert_eq!(eff.model, None);
        assert_eq!(eff.source, Source::RuntimeDefault);
    }

    #[test]
    fn resolve_backward_compat_absent_plan_equals_empty_plan() {
        // The core B-2-style regression guard: a totally-absent plan file (`load` on an empty
        // dir) and an explicitly-constructed `ModelPlan::empty()` must resolve identically.
        let dir = TempDir::new().unwrap();
        let (loaded, warnings) = load(dir.path());
        assert!(warnings.is_empty());
        let eff_loaded = resolve_effective(&loaded, "phillip-backend-engineer", Some("m"), None);
        let eff_empty = resolve_effective(
            &ModelPlan::empty("system"),
            "phillip-backend-engineer",
            Some("m"),
            None,
        );
        assert_eq!(eff_loaded, eff_empty);
    }

    // ── load(): E1 corrupt/schema-mismatch fixtures ──────────────────────────

    #[test]
    fn load_missing_file_returns_empty_plan_no_warning() {
        let dir = TempDir::new().unwrap();
        let (plan, warnings) = load(dir.path());
        assert_eq!(plan.session_backend, SessionBackend::Claude);
        assert!(plan.roles.is_empty());
        assert!(warnings.is_empty());
    }

    #[test]
    fn load_corrupt_json_falls_back_with_warning() {
        let dir = TempDir::new().unwrap();
        fs::write(dir.path().join("model-plan.json"), "{ not json ").unwrap();
        let (plan, warnings) = load(dir.path());
        assert!(plan.roles.is_empty());
        assert_eq!(warnings.len(), 1);
        assert_eq!(warnings[0].code, "W-MODELPLAN-CORRUPT");
        assert!(is_corrupt_json(dir.path()));
    }

    #[test]
    fn load_schema_mismatch_falls_back_with_warning() {
        let dir = TempDir::new().unwrap();
        fs::write(
            dir.path().join("model-plan.json"),
            r#"{"schema":"bathos/model-plan@999","updated":"2026-07-16T00:00:00Z","updated_by":"x","session_backend":"claude"}"#,
        )
        .unwrap();
        let (plan, warnings) = load(dir.path());
        assert!(plan.roles.is_empty());
        assert_eq!(warnings[0].code, "W-MODELPLAN-SCHEMA");
        // a schema-mismatched-but-valid-JSON file is not "corrupt JSON" — no .bak needed.
        assert!(!is_corrupt_json(dir.path()));
    }

    #[test]
    fn save_then_load_roundtrips() {
        let dir = TempDir::new().unwrap();
        let plan = plan_with_role(
            "phillip-backend-engineer",
            Runtime::Claude,
            Some("claude-sonnet-5"),
        );
        save(dir.path(), &plan).unwrap();
        let (loaded, warnings) = load(dir.path());
        assert!(warnings.is_empty());
        assert_eq!(loaded.schema, SCHEMA_ID);
        assert_eq!(
            loaded.roles["phillip-backend-engineer"].model.as_deref(),
            Some("claude-sonnet-5")
        );
    }

    // ── WavePolicy backward compatibility (DoD-required regression) ─────────

    #[test]
    fn wave_policy_backcompat_old_mixed_policy_only_file_loads_unchanged() {
        // The exact shape `w2-panes-model-design-kr.md` §A1.1 documented BEFORE this task added
        // `runtime`/`model`/`reasoning_effort` to `WavePolicy` — a project that ran `bathos
        // model set` before this feature existed must still load without error or field loss.
        let dir = TempDir::new().unwrap();
        fs::write(
            dir.path().join("model-plan.json"),
            r#"{
                "schema": "bathos/model-plan@1",
                "updated": "2026-07-16T12:00:00Z",
                "updated_by": "Paul",
                "session_backend": "claude",
                "defaults": {"runtime": "claude", "model": null},
                "roles": {},
                "waves": {"W5": {"mixed_policy": "forbid"}}
            }"#,
        )
        .unwrap();
        let (plan, warnings) = load(dir.path());
        assert!(warnings.is_empty());
        let w5 = &plan.waves["W5"];
        assert_eq!(w5.mixed_policy, MixedPolicy::Forbid);
        assert_eq!(w5.runtime, None);
        assert_eq!(w5.model, None);
        assert_eq!(w5.reasoning_effort, None);
    }

    #[test]
    fn wave_policy_backcompat_missing_waves_field_entirely_loads_unchanged() {
        // Even older shape: no `waves` key at all (pre-dates `mixed_policy` too).
        let dir = TempDir::new().unwrap();
        fs::write(
            dir.path().join("model-plan.json"),
            r#"{
                "schema": "bathos/model-plan@1",
                "updated": "2026-07-16T12:00:00Z",
                "updated_by": "Paul",
                "session_backend": "claude"
            }"#,
        )
        .unwrap();
        let (plan, warnings) = load(dir.path());
        assert!(warnings.is_empty());
        assert!(plan.waves.is_empty());
        assert!(plan.roles.is_empty());
    }

    #[test]
    fn wave_policy_new_fields_roundtrip_through_save_and_load() {
        let dir = TempDir::new().unwrap();
        let mut plan = ModelPlan::empty("Paul");
        plan.waves.insert(
            "W5".into(),
            WavePolicy {
                mixed_policy: MixedPolicy::Forbid,
                runtime: Some(Runtime::Kimi),
                model: Some("kimi-k2".into()),
                reasoning_effort: None,
            },
        );
        save(dir.path(), &plan).unwrap();
        let (loaded, warnings) = load(dir.path());
        assert!(warnings.is_empty());
        assert_eq!(loaded.waves["W5"].runtime, Some(Runtime::Kimi));
        assert_eq!(loaded.waves["W5"].model.as_deref(), Some("kimi-k2"));
    }

    // ── frontmatter parsing (pure string fixtures — T1 support) ─────────────

    #[test]
    fn frontmatter_field_extracts_model_and_strips_inline_comment() {
        let content = "---\nslug: phillip-backend-engineer\nmodel: claude-sonnet-5   # Sonnet 5 (was Sonnet 4.6)\nwave: W5\n---\nbody\n";
        assert_eq!(
            frontmatter_field(content, "model").as_deref(),
            Some("claude-sonnet-5")
        );
        assert_eq!(
            frontmatter_field(content, "slug").as_deref(),
            Some("phillip-backend-engineer")
        );
    }

    #[test]
    fn frontmatter_field_none_when_key_absent_or_no_frontmatter() {
        assert_eq!(frontmatter_field("no frontmatter here", "model"), None);
        assert_eq!(frontmatter_field("---\nslug: x\n---\n", "model"), None);
    }

    #[test]
    fn find_frontmatter_model_matches_by_slug_field_not_filename() {
        let dir = TempDir::new().unwrap();
        // Deliberately misleading filename (does not contain the slug at all) — matching must
        // go through the `slug:` field, not filename pattern-guessing (see doc comment).
        fs::write(
            dir.path().join("08-anything.md"),
            "---\nslug: phillip-backend-engineer\nmodel: claude-sonnet-5\n---\n",
        )
        .unwrap();
        fs::write(
            dir.path().join("09-other.md"),
            "---\nslug: andrew-frontend-engineer\nmodel: claude-sonnet-5\n---\n",
        )
        .unwrap();
        assert_eq!(
            find_frontmatter_model(dir.path(), "phillip-backend-engineer").as_deref(),
            Some("claude-sonnet-5")
        );
        assert_eq!(find_frontmatter_model(dir.path(), "nonexistent-slug"), None);
    }

    #[test]
    fn find_frontmatter_model_absent_dir_returns_none_not_panic() {
        assert_eq!(
            find_frontmatter_model(Path::new("/nonexistent/agents/_base"), "any"),
            None
        );
    }

    // ── T2: validate_wave — R1~R4 mixed-batch rules ─────────────────────────

    #[test]
    fn validate_all_claude_passes() {
        let mut plan = ModelPlan::empty("Paul");
        plan.roles.insert(
            "phillip-backend-engineer".into(),
            RoleModelSpec {
                runtime: Runtime::Claude,
                model: Some("claude-sonnet-5".into()),
                reasoning_effort: None,
            },
        );
        let roles = vec!["phillip-backend-engineer".to_string()];
        assert!(validate_wave(&plan, "W5", &roles).is_ok());
    }

    #[test]
    fn validate_glm_role_in_claude_session_is_mix_violation() {
        let plan = plan_with_role("stephen-ml-engineer", Runtime::Glm, Some("glm-4.7"));
        let roles = vec!["stephen-ml-engineer".to_string()];
        let err = validate_wave(&plan, "W5", &roles).unwrap_err();
        assert_eq!(err.code, "E-MODEL-MIX");
        assert_eq!(err.resolutions.len(), 3);
    }

    #[test]
    fn validate_glm_role_in_glm_session_passes() {
        let mut plan = plan_with_role("stephen-ml-engineer", Runtime::Glm, Some("glm-4.7"));
        plan.session_backend = SessionBackend::Glm;
        let roles = vec!["stephen-ml-engineer".to_string()];
        assert!(validate_wave(&plan, "W5", &roles).is_ok());
    }

    #[test]
    fn validate_explicit_claude_in_glm_session_is_backend_mismatch() {
        let mut plan = plan_with_role(
            "phillip-backend-engineer",
            Runtime::Claude,
            Some("claude-sonnet-5"),
        );
        plan.session_backend = SessionBackend::Glm;
        let roles = vec!["phillip-backend-engineer".to_string()];
        let err = validate_wave(&plan, "W5", &roles).unwrap_err();
        assert_eq!(err.code, "E-MODEL-BACKEND-MISMATCH");
    }

    #[test]
    fn validate_implicit_claude_default_in_glm_session_does_not_mismatch() {
        // A role with NO plan entry at all (implicit claude via runtime default) is not an
        // "explicit" claude choice — R4 only fires on a contradicted explicit choice.
        let mut plan = ModelPlan::empty("Paul");
        plan.session_backend = SessionBackend::Glm;
        let roles = vec!["some-role-with-no-plan-entry".to_string()];
        assert!(validate_wave(&plan, "W5", &roles).is_ok());
    }

    #[test]
    fn validate_codex_role_never_blocks_regardless_of_session_backend() {
        let plan = plan_with_role("thomas-code-reviewer", Runtime::Codex, None);
        let roles = vec!["thomas-code-reviewer".to_string()];
        assert!(validate_wave(&plan, "W3", &roles).is_ok());

        let mut glm_session = plan;
        glm_session.session_backend = SessionBackend::Glm;
        assert!(validate_wave(&glm_session, "W3", &roles).is_ok());
    }

    #[test]
    fn validate_codex_and_claude_coexist_in_same_wave() {
        let mut plan = ModelPlan::empty("Paul");
        plan.roles.insert(
            "phillip-backend-engineer".into(),
            RoleModelSpec {
                runtime: Runtime::Claude,
                model: None,
                reasoning_effort: None,
            },
        );
        plan.roles.insert(
            "thomas-code-reviewer".into(),
            RoleModelSpec {
                runtime: Runtime::Codex,
                model: None,
                reasoning_effort: Some("high".into()),
            },
        );
        let roles = vec![
            "phillip-backend-engineer".to_string(),
            "thomas-code-reviewer".to_string(),
        ];
        assert!(validate_wave(&plan, "W5", &roles).is_ok());
    }

    #[test]
    fn validate_kimi_role_in_claude_session_is_mix_violation() {
        // Same shape as the old GLM-only R2/R3 case, but for one of the 3 newly-added
        // env-global runtimes — proves the generalization via `is_env_global()` actually covers
        // them, not just `Glm`.
        let plan = plan_with_role("stephen-ml-engineer", Runtime::Kimi, Some("kimi-k2"));
        let roles = vec!["stephen-ml-engineer".to_string()];
        let err = validate_wave(&plan, "W5", &roles).unwrap_err();
        assert_eq!(err.code, "E-MODEL-MIX");
        assert_eq!(err.resolutions.len(), 3);
    }

    #[test]
    fn validate_matching_env_global_session_passes_for_every_new_runtime() {
        for (runtime, backend) in [
            (Runtime::Glm, SessionBackend::Glm),
            (Runtime::Kimi, SessionBackend::Kimi),
            (Runtime::Deepseek, SessionBackend::Deepseek),
            (Runtime::Qwen, SessionBackend::Qwen),
        ] {
            let mut plan = plan_with_role("stephen-ml-engineer", runtime, None);
            plan.session_backend = backend;
            let roles = vec!["stephen-ml-engineer".to_string()];
            assert!(
                validate_wave(&plan, "W5", &roles).is_ok(),
                "runtime {runtime:?} should pass when session_backend already matches"
            );
        }
    }

    #[test]
    fn validate_two_distinct_env_global_runtimes_in_one_batch_is_mix_violation() {
        // Rule 1 — this case was *impossible* before Kimi/Deepseek/Qwen existed (there was only
        // one env-global runtime, so "two different ones requested" couldn't happen).
        let mut plan = ModelPlan::empty("Paul");
        plan.roles.insert(
            "stephen-ml-engineer".into(),
            RoleModelSpec {
                runtime: Runtime::Kimi,
                model: None,
                reasoning_effort: None,
            },
        );
        plan.roles.insert(
            "andrew-frontend-engineer".into(),
            RoleModelSpec {
                runtime: Runtime::Deepseek,
                model: None,
                reasoning_effort: None,
            },
        );
        let roles = vec![
            "stephen-ml-engineer".to_string(),
            "andrew-frontend-engineer".to_string(),
        ];
        let err = validate_wave(&plan, "W5", &roles).unwrap_err();
        assert_eq!(err.code, "E-MODEL-MIX");
        assert_eq!(err.resolutions.len(), 3);
    }

    #[test]
    fn validate_wave_policy_runtime_feeds_into_mix_check_for_unassigned_roles() {
        // A role with NO `roles.<slug>` entry still picks up the wave's `runtime` override
        // (§4-5 resolve chain step 2) — validate_wave must see that, not just explicit
        // per-role entries, or the transition gate would silently miss wave-level assignments.
        let mut plan = ModelPlan::empty("Paul");
        plan.waves.insert(
            "W5".into(),
            WavePolicy {
                runtime: Some(Runtime::Qwen),
                ..Default::default()
            },
        );
        let roles = vec!["andrew-frontend-engineer".to_string()];
        let err = validate_wave(&plan, "W5", &roles).unwrap_err();
        assert_eq!(err.code, "E-MODEL-MIX");

        // ...but validating a *different* wave with no such policy entry doesn't see it at all
        // (the wave-scoping is real, not a global default in disguise).
        assert!(validate_wave(&plan, "W6", &roles).is_ok());
    }

    #[test]
    fn validate_explicit_claude_in_deepseek_session_is_backend_mismatch() {
        // Rule 3 generalized beyond GLM: session already env-global under a DIFFERENT
        // runtime, explicit claude still cannot be honored.
        let mut plan = plan_with_role(
            "phillip-backend-engineer",
            Runtime::Claude,
            Some("claude-sonnet-5"),
        );
        plan.session_backend = SessionBackend::Deepseek;
        let roles = vec!["phillip-backend-engineer".to_string()];
        let err = validate_wave(&plan, "W5", &roles).unwrap_err();
        assert_eq!(err.code, "E-MODEL-BACKEND-MISMATCH");
    }

    // ── SessionBackend detection ─────────────────────────────────────────────

    #[test]
    fn session_backend_detects_glm_from_zai_url() {
        assert_eq!(
            SessionBackend::detect_from_base_url(Some("https://api.z.ai/api/anthropic")),
            SessionBackend::Glm
        );
    }

    #[test]
    fn session_backend_defaults_to_claude_when_unset_or_other() {
        assert_eq!(
            SessionBackend::detect_from_base_url(None),
            SessionBackend::Claude
        );
        assert_eq!(
            SessionBackend::detect_from_base_url(Some("https://api.anthropic.com")),
            SessionBackend::Claude
        );
    }

    #[test]
    fn session_backend_detects_each_new_env_global_host() {
        assert_eq!(
            SessionBackend::detect_from_base_url(Some("https://api.moonshot.ai/anthropic")),
            SessionBackend::Kimi
        );
        assert_eq!(
            SessionBackend::detect_from_base_url(Some("https://api.deepseek.com/anthropic")),
            SessionBackend::Deepseek
        );
        // Qwen: both attested URL shapes must be detected — the fixed `dashscope[-intl]` host
        // some material shows, AND the templated `{workspace}.{region}.maas.aliyuncs.com` host
        // Alibaba's own Model Studio docs show (see `detect_from_base_url`'s doc comment on
        // this `_url_discrepancy` — not picking a winner between two attested shapes).
        assert_eq!(
            SessionBackend::detect_from_base_url(Some(
                "https://dashscope-intl.aliyuncs.com/apps/anthropic"
            )),
            SessionBackend::Qwen
        );
        assert_eq!(
            SessionBackend::detect_from_base_url(Some(
                "https://dashscope.aliyuncs.com/apps/anthropic"
            )),
            SessionBackend::Qwen
        );
        assert_eq!(
            SessionBackend::detect_from_base_url(Some(
                "https://my-workspace.ap-southeast-1.maas.aliyuncs.com/apps/anthropic"
            )),
            SessionBackend::Qwen
        );
    }

    // ── Runtime::parse / is_env_global / env_backend ─────────────────────────

    #[test]
    fn runtime_parse_case_insensitive_and_rejects_unknown() {
        assert_eq!(Runtime::parse("CLAUDE").unwrap(), Runtime::Claude);
        assert_eq!(Runtime::parse("glm").unwrap(), Runtime::Glm);
        assert_eq!(Runtime::parse("Codex").unwrap(), Runtime::Codex);
        assert_eq!(Runtime::parse("KIMI").unwrap(), Runtime::Kimi);
        assert_eq!(Runtime::parse("deepseek").unwrap(), Runtime::Deepseek);
        assert_eq!(Runtime::parse("Qwen").unwrap(), Runtime::Qwen);
        assert!(Runtime::parse("bogus").is_err());
    }

    #[test]
    fn is_env_global_is_true_only_for_the_four_process_wide_runtimes() {
        assert!(!Runtime::Claude.is_env_global());
        assert!(!Runtime::Codex.is_env_global());
        assert!(Runtime::Glm.is_env_global());
        assert!(Runtime::Kimi.is_env_global());
        assert!(Runtime::Deepseek.is_env_global());
        assert!(Runtime::Qwen.is_env_global());
    }

    #[test]
    fn env_backend_and_session_backend_as_runtime_are_inverses() {
        for r in [
            Runtime::Glm,
            Runtime::Kimi,
            Runtime::Deepseek,
            Runtime::Qwen,
        ] {
            let backend = r
                .env_backend()
                .expect("env-global runtime must map to a backend");
            assert_eq!(backend.as_runtime(), Some(r));
        }
        assert_eq!(Runtime::Claude.env_backend(), None);
        assert_eq!(Runtime::Codex.env_backend(), None);
        assert_eq!(SessionBackend::Claude.as_runtime(), None);
    }

    #[test]
    fn env_auth_var_is_not_uniform_deepseek_differs_from_the_other_three() {
        // Pins the lead-confirmed correction (DeepSeek docs: api-docs.deepseek.com) that
        // DeepSeek's Anthropic-compat endpoint reads `ANTHROPIC_API_KEY`, not the
        // `ANTHROPIC_AUTH_TOKEN` the other three env-global runtimes use — a transition
        // instruction naming the wrong var would actively mislead, so this is locked down.
        assert_eq!(env_auth_var(Runtime::Deepseek), "ANTHROPIC_API_KEY");
        for r in [Runtime::Glm, Runtime::Kimi, Runtime::Qwen] {
            assert_eq!(env_auth_var(r), "ANTHROPIC_AUTH_TOKEN");
        }
    }

    #[test]
    fn transition_resolutions_deepseek_names_the_correct_auth_var() {
        let resolutions = transition_resolutions(Runtime::Deepseek);
        assert!(resolutions[2].contains("ANTHROPIC_API_KEY"));
        assert!(!resolutions[2].contains("ANTHROPIC_AUTH_TOKEN"));
    }

    #[test]
    fn env_endpoint_hint_qwen_presents_both_shapes_not_one_as_fact() {
        // Must not silently commit to a single Qwen URL — both attested shapes are surfaced
        // (see `SessionBackend::detect_from_base_url`'s doc comment on the same discrepancy).
        let hint = env_endpoint_hint(Runtime::Qwen);
        assert!(hint.contains("dashscope"));
        assert!(hint.contains("maas.aliyuncs.com"));
    }

    // ── backup_corrupt ────────────────────────────────────────────────────────

    #[test]
    fn backup_corrupt_copies_existing_file() {
        let dir = TempDir::new().unwrap();
        fs::write(dir.path().join("model-plan.json"), "{ broken").unwrap();
        backup_corrupt(dir.path()).unwrap();
        assert!(dir.path().join("model-plan.json.bak").exists());
    }

    #[test]
    fn backup_corrupt_noop_when_absent() {
        let dir = TempDir::new().unwrap();
        backup_corrupt(dir.path()).unwrap(); // must not error
        assert!(!dir.path().join("model-plan.json.bak").exists());
    }
}
