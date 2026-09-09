//! `model_plan` — per-role model/runtime selection SSOT (`_state/model-plan.json`, schema
//! `bathos/model-plan@1`).
//!
//! **Why this exists (ADR-D-0005/0006, `w2-panes-model-design-kr.md` §A):** BATHOS teammates
//! can run on three different runtimes — Claude (in-process teammate, per-role model), GLM
//! (process-wide `ANTHROPIC_BASE_URL` override — no per-role granularity is physically
//! possible), and Codex (a separate CLI process). `model-plan.json` is the single place that
//! records "which runtime/model each role should use this session", so `bathos model
//! show|set|validate|resolve` (bathos-cli) and the wave commands all agree on one answer.
//!
//! **Backward compatibility is the load-bearing constraint.** A project that has never run
//! `bathos model set` must behave *exactly* as before this feature existed: every role falls
//! back to its agent-definition frontmatter `model:` field. [`resolve_effective`] encodes this
//! as an explicit 4-step priority chain (plan.roles → plan.defaults → frontmatter → runtime
//! default) so "no plan file" and "plan file present but this role unset" both degrade to the
//! same pre-existing behavior — no silent behavior change for projects that don't opt in.
//!
//! **What this module does NOT do:** it never spawns a teammate, never touches
//! `manifest.json`, and never talks to GLM/Codex processes. It only reads/writes
//! `model-plan.json` and computes pure resolve/validate decisions. The actual runtime
//! dispatch (spawn with `model:` param / require GLM session env / delegate to
//! `codex-adapter/run-role.sh`) is the wave command's/CLI caller's job — kept out of this
//! crate on purpose (bathos-state stays a state/decision layer, not an orchestrator).

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::Path;

/// The only schema string this module writes. A file with a different (or missing) `schema`
/// value is treated as **absent** (lenient — same as no file at all) rather than erroring, per
/// `w2-panes-model-design-kr.md` §A1.2 "불일치 시 lenient 경고 후 무시하고 frontmatter 폴백".
pub const SCHEMA_ID: &str = "bathos/model-plan@1";

/// The three runtimes a role can be assigned to. `Copy`/`Eq` because resolve/validate compare
/// these constantly and never need ownership of anything beyond the tag itself.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Runtime {
    Claude,
    Glm,
    Codex,
}

impl Runtime {
    /// Parses a CLI-facing runtime string (`bathos model set <slug> --runtime <r>`).
    /// Case-insensitive (matches `GateEngine::parse_verdict`'s convention in this workspace).
    pub fn parse(s: &str) -> Result<Self, String> {
        match s.to_ascii_lowercase().as_str() {
            "claude" => Ok(Runtime::Claude),
            "glm" => Ok(Runtime::Glm),
            "codex" => Ok(Runtime::Codex),
            other => Err(format!(
                "[E-MODEL-RUNTIME-INVALID] 알 수 없는 runtime '{other}' (claude|glm|codex 중 하나)"
            )),
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            Runtime::Claude => "claude",
            Runtime::Glm => "glm",
            Runtime::Codex => "codex",
        }
    }
}

/// The **actual backend** the current Claude Code process is running under. Determined by
/// `bathos model detect` inspecting `ANTHROPIC_BASE_URL` — this is a process-wide fact
/// (`[실측 F2]` in the design doc: GLM env vars are not per-teammate), never a per-role choice.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SessionBackend {
    Claude,
    Glm,
}

impl SessionBackend {
    /// Pure classification so this is unit-testable without touching real env vars —
    /// `bathos model detect` (bathos-cli) supplies `std::env::var("ANTHROPIC_BASE_URL").ok()`.
    pub fn detect_from_base_url(base_url: Option<&str>) -> Self {
        match base_url {
            Some(url) if url.contains("api.z.ai") => SessionBackend::Glm,
            _ => SessionBackend::Claude,
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            SessionBackend::Claude => "claude",
            SessionBackend::Glm => "glm",
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
/// this falls through further down the resolve chain — frontmatter/runtime default; for
/// `glm`/`codex` it means "let the session env / Codex install default decide").
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
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct WavePolicy {
    #[serde(default)]
    pub mixed_policy: MixedPolicy,
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
///   every project that hasn't opted in — E1 "정상" case, not an error).
/// - **Unparseable JSON** → `ModelPlan::empty()` + `W-MODELPLAN-CORRUPT` warning (E1).
/// - **Parses but `schema` field mismatched/missing** → `ModelPlan::empty()` +
///   `W-MODELPLAN-SCHEMA` warning (§A1.1 "불일치 시 lenient 경고 후 무시하고 frontmatter 폴백").
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
/// "set 시엔 .bak 백업 후 재생성 물음") — a schema-mismatch file is well-formed JSON and does
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
/// set/unset/detect` calls (§A1.3 "쓰기 주체는 `bathos model set` 단일 경로"). Adding a lock
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
// resolve — the 4-step priority chain (§A1.3, T1)
// ─────────────────────────────────────────────────────────────────────────────

/// Where an [`EffectiveModel`] value came from — surfaced by `bathos model show`/`resolve` so
/// the user always sees *why* a role has the model it has (never a silent black box).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Source {
    /// `model-plan.json` `roles.<slug>` entry.
    Plan,
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

/// Implements the exact 4-step priority chain from `w2-panes-model-design-kr.md` §A1.3:
///
/// ```text
/// effective(role) =
///   1. model-plan.roles[slug]      (존재·유효 시)
///   2. model-plan.defaults          (defaults.model != null 시)
///   3. agent frontmatter `model`    (현행 동작 — plan 부재/파손 시 여기로 폴백)
///   4. 런타임 기본 (claude=세션 기본 모델)
/// ```
///
/// Step 2 is read literally: `defaults` is consulted **only** when `defaults.model` is
/// non-null — an all-null `defaults` block (the common case) is skipped entirely, falling
/// through to frontmatter. This is what makes "no plan file" and "plan file with an empty
/// `defaults`" behave identically (both reach step 3/4) — the backward-compat guarantee.
///
/// Pure function — no filesystem access (the caller reads `model-plan.json` via [`load`] and
/// frontmatter via [`find_frontmatter_model`] beforehand) — fully unit-testable (T1).
pub fn resolve_effective(
    plan: &ModelPlan,
    slug: &str,
    frontmatter_model: Option<&str>,
) -> EffectiveModel {
    if let Some(spec) = plan.roles.get(slug) {
        return EffectiveModel {
            runtime: spec.runtime,
            model: spec.model.clone(),
            reasoning_effort: spec.reasoning_effort.clone(),
            source: Source::Plan,
        };
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
pub fn resolve_effective_runtime(plan: &ModelPlan, slug: &str) -> Runtime {
    if let Some(spec) = plan.roles.get(slug) {
        return spec.runtime;
    }
    if plan.defaults.model.is_some() {
        return plan.defaults.runtime;
    }
    Runtime::Claude
}

// ─────────────────────────────────────────────────────────────────────────────
// validate — mixed-batch rules R1~R4 (§A3.2, T2)
// ─────────────────────────────────────────────────────────────────────────────

/// A blocked `bathos model validate` result — always exit-2 material. Carries the resolution
/// menu verbatim from §A3.2 R3 so the CLI/hook layer never has to re-derive it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MixViolation {
    pub code: &'static str,
    pub message: String,
    pub resolutions: Vec<String>,
}

/// The R3 resolution menu (identical wording regardless of which rule fired — both R2/R3 and
/// R4 are solved by the same three moves: go all-GLM, move the role elsewhere, or split the
/// wave across two sessions).
fn r3_resolutions() -> Vec<String> {
    vec![
        "1) 배치 전체 GLM: 이 웨이브 모든 역할을 runtime=glm으로 통일(사용자 승인 필요)".into(),
        "2) 역할 이동: GLM 희망 역할을 claude 또는 codex로 변경".into(),
        "3) 웨이브 순차 분할: claude 배치를 현 세션에서 먼저 완료·shutdown → \
           GLM 세션으로 재기동 후 재개(`source scripts/glm-env.sh` → `claude`)"
            .into(),
    ]
}

/// Validates a wave's role batch against the GLM process-wide-env constraint (ADR-D-0005).
///
/// - **R2/R3 (`E-MODEL-MIX`)**: any role in `role_slugs` resolves to `Runtime::Glm` while
///   `plan.session_backend != Glm` — GLM cannot run for just that one role in this session.
/// - **R4 (`E-MODEL-BACKEND-MISMATCH`)**: `plan.session_backend == Glm` but some role has an
///   *explicit* `roles.<slug>.runtime = claude` entry — that explicit choice cannot be honored
///   (the whole process is already GLM). A role that simply has no plan entry (implicit
///   claude via the runtime default) does **not** trigger this — only an explicit, contradicted
///   choice is a violation (nothing to contradict = nothing to reject).
/// - **Codex roles never block**: a separate process, no env conflict either direction
///   (ADR-D-0006 "정직한 비대칭").
///
/// `role_slugs` should be the wave's role roster (see `WAVE_ROLE_MAP` in bathos-cli, sourced
/// from `CLAUDE.md` §1/§2's role↔wave table) — or, if the caller wants a whole-plan check
/// (`--wave` omitted), every key currently present in `plan.roles`.
pub fn validate_wave(
    plan: &ModelPlan,
    wave_id: &str,
    role_slugs: &[String],
) -> Result<(), MixViolation> {
    let runtimes: Vec<(String, Runtime)> = role_slugs
        .iter()
        .map(|s| (s.clone(), resolve_effective_runtime(plan, s)))
        .collect();

    let glm_roles: Vec<&str> = runtimes
        .iter()
        .filter(|(_, r)| *r == Runtime::Glm)
        .map(|(s, _)| s.as_str())
        .collect();

    if !glm_roles.is_empty() && plan.session_backend != SessionBackend::Glm {
        return Err(MixViolation {
            code: "E-MODEL-MIX",
            message: format!(
                "[E-MODEL-MIX] wave={wave_id} — GLM 지정 역할({}) 존재하나 session_backend={}(GLM 아님). \
                 GLM은 프로세스 전역 env라 역할 단위 분리가 물리적으로 불가합니다.",
                glm_roles.join(", "),
                plan.session_backend.as_str()
            ),
            resolutions: r3_resolutions(),
        });
    }

    if plan.session_backend == SessionBackend::Glm {
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
                    "[E-MODEL-BACKEND-MISMATCH] wave={wave_id} — session_backend=glm인데 \
                     명시적 runtime=claude 역할({}) 존재. 이 세션에서 claude 지정은 이행 불가(전부 GLM으로 나감).",
                    explicit_claude.join(", ")
                ),
                resolutions: r3_resolutions(),
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

    // ── T1: resolve priority chain (4 steps × missing/corrupt) ──────────────

    #[test]
    fn resolve_step1_plan_role_wins_over_everything() {
        let plan = plan_with_role("phillip-backend-engineer", Runtime::Codex, None);
        let eff = resolve_effective(&plan, "phillip-backend-engineer", Some("claude-sonnet-5"));
        assert_eq!(eff.runtime, Runtime::Codex);
        assert_eq!(eff.source, Source::Plan);
    }

    #[test]
    fn resolve_step2_defaults_used_when_model_set_and_no_role_entry() {
        let mut plan = ModelPlan::empty("Paul");
        plan.defaults = RoleModelSpec {
            runtime: Runtime::Glm,
            model: Some("glm-4.7".into()),
            reasoning_effort: None,
        };
        let eff = resolve_effective(&plan, "andrew-frontend-engineer", Some("claude-sonnet-5"));
        assert_eq!(eff.runtime, Runtime::Glm);
        assert_eq!(eff.model.as_deref(), Some("glm-4.7"));
        assert_eq!(eff.source, Source::Default);
    }

    #[test]
    fn resolve_step2_skipped_when_defaults_model_is_null() {
        // defaults.model == None → step 2 is a no-op even though defaults.runtime is set —
        // this is the literal reading of "(defaults.model != null 시)" that keeps an empty
        // plan behaviorally identical to no plan at all.
        let plan = ModelPlan::empty("Paul");
        let eff = resolve_effective(&plan, "andrew-frontend-engineer", Some("claude-sonnet-5"));
        assert_eq!(eff.source, Source::Frontmatter);
        assert_eq!(eff.model.as_deref(), Some("claude-sonnet-5"));
    }

    #[test]
    fn resolve_step3_frontmatter_fallback_when_plan_absent() {
        let plan = ModelPlan::empty("system");
        let eff = resolve_effective(&plan, "james-architect", Some("claude-fable-5"));
        assert_eq!(eff.runtime, Runtime::Claude);
        assert_eq!(eff.model.as_deref(), Some("claude-fable-5"));
        assert_eq!(eff.source, Source::Frontmatter);
    }

    #[test]
    fn resolve_step4_runtime_default_when_nothing_matches() {
        let plan = ModelPlan::empty("system");
        let eff = resolve_effective(&plan, "unknown-slug", None);
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
        let eff_loaded = resolve_effective(&loaded, "phillip-backend-engineer", Some("m"));
        let eff_empty = resolve_effective(
            &ModelPlan::empty("system"),
            "phillip-backend-engineer",
            Some("m"),
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

    // ── Runtime::parse ────────────────────────────────────────────────────────

    #[test]
    fn runtime_parse_case_insensitive_and_rejects_unknown() {
        assert_eq!(Runtime::parse("CLAUDE").unwrap(), Runtime::Claude);
        assert_eq!(Runtime::parse("glm").unwrap(), Runtime::Glm);
        assert_eq!(Runtime::parse("Codex").unwrap(), Runtime::Codex);
        assert!(Runtime::parse("bogus").is_err());
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
