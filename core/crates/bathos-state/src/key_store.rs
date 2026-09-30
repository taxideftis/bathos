//! `key_store` — the out-of-repo API key store (`~/.bathos/<runtime>.env`) and the repo
//! leak scan (`bathos key scan` support) — story M1, w7-model-switch design §2, ADR-D-0010.
//!
//! ## The four invariants this module exists to enforce (story M1, design §2.1)
//! 1. **Single canonical location, outside every repo tree**: `~/.bathos/<runtime>.env`
//!    (file 0600, directory 0700). This repo syncs via iCloud, so keys inside it leak to
//!    backup/sync/agent reads — the store lives in HOME instead.
//! 2. **Keys never travel through argv**: this module has no API that takes key material
//!    from a command line — the CLI rejects surplus positional args (`E-KEY-ARGV`) because
//!    the PostToolUse audit hook records Bash command strings verbatim (the L19 accident).
//! 3. **Key material is never printed**: every display path emits existence, an 8-hex
//!    SHA-256 fingerprint, mtime, and permissions — never the value.
//! 4. **Audit `target` is the runtime name only** (enforced by the CLI caller; this module
//!    never touches audit logs itself — those go through `crate::audit`'s single writer).
//!
//! ## What this module deliberately does NOT do
//! It does not read stdin, parse CLI args, or append audit entries — those live in the CLI
//! layer (`bathos-cli`). Everything here is pure functions or thin I/O over a caller-supplied
//! `bathos_dir`, so tests point it at a tempdir instead of the real home (same pattern as
//! `model_status` receiving `state_dir`).

use crate::model_plan::Runtime;
use sha2::{Digest, Sha256};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::SystemTime;

/// The runtimes whose keys this store manages — exactly [`Runtime::is_env_global`]'s set.
/// `claude` (OAuth) and `codex` (own login) are structurally absent: the CLI rejects them
/// with `E-KEY-RUNTIME-UNSUPPORTED` before anything touches disk.
pub const KEY_RUNTIMES: [Runtime; 4] = [
    Runtime::Glm,
    Runtime::Kimi,
    Runtime::Deepseek,
    Runtime::Qwen,
];

/// The env var name a runtime's store file exports (w7 design §2.2).
///
/// glm keeps its historical `Z_AI_API_KEY` — `scripts/glm-env.sh` consumes that exact name,
/// so `source ~/.bathos/glm.env && source scripts/glm-env.sh` must keep working unchanged
/// (AC8, fact L8). The other three use BATHOS-prefixed names: vendor-specific variable
/// names are unverified, so we define our own rather than inventing one; consumption-side
/// mapping to `ANTHROPIC_AUTH_TOKEN`/`ANTHROPIC_API_KEY` is `model_plan::env_auth_var`'s
/// job, not this module's.
///
/// Moved here from `bathos-cli` (story M1): the CLI's switch-plan printer anticipated this
/// module owning the mapping — one definition, two consumers.
pub fn store_var(rt: Runtime) -> &'static str {
    match rt {
        Runtime::Glm => "Z_AI_API_KEY",
        Runtime::Kimi => "BATHOS_KIMI_KEY",
        Runtime::Deepseek => "BATHOS_DEEPSEEK_KEY",
        Runtime::Qwen => "BATHOS_QWEN_KEY",
        // Unreachable through the CLI (non-env-global runtimes are rejected before this is
        // called); arm kept total so adding a Runtime variant stays a compile-checked change.
        Runtime::Claude | Runtime::Codex => "(해당 없음)",
    }
}

/// Validates a CLI-facing runtime string for key operations.
///
/// Reuses [`Runtime::parse`] + [`Runtime::is_env_global`] as the story mandates — no new
/// dispatch logic. Two distinct error shapes, both printed at exit code 2 by the caller:
/// - a *known* non-key runtime (claude/codex) is named in the message — naming them is safe
///   and tells the user why;
/// - an *unknown* token is **never echoed** — the runtime slot is exactly where users paste
///   keys by mistake, and an error message echoing the input would itself be the leak (E9).
pub fn parse_key_runtime(s: &str) -> Result<Runtime, String> {
    match Runtime::parse(s) {
        Ok(rt) if rt.is_env_global() => Ok(rt),
        Ok(rt) => Err(format!(
            "[E-KEY-RUNTIME-UNSUPPORTED] '{name}' 는 키 등록 대상이 아닙니다 — claude는 OAuth, \
             codex는 자체 로그인을 사용합니다. 키 등록 대상: glm|kimi|deepseek|qwen",
            name = rt.as_str()
        )),
        Err(_) => Err(
            "[E-KEY-RUNTIME-INVALID] 알 수 없는 런타임입니다 — glm|kimi|deepseek|qwen 중 하나를 \
             지정하세요. (입력값은 안전을 위해 오류 메시지에 표시하지 않습니다)"
                .to_string(),
        ),
    }
}

/// `<runtime>.env` — the store file name for a runtime (design §2.2 layout).
pub fn key_file_name(rt: Runtime) -> String {
    format!("{}.env", rt.as_str())
}

/// Full store path. Callers pass `~/.bathos` (resolved from HOME in the CLI) so tests can
/// point this at a tempdir — the path is never resolved from the environment here.
pub fn key_file_path(bathos_dir: &Path, rt: Runtime) -> PathBuf {
    bathos_dir.join(key_file_name(rt))
}

/// First 8 hex chars of the SHA-256 of the key material — the only key-derived string any
/// display path may emit. Deterministic by construction (no salt): the fingerprint's job is
/// "is this the same key?", not "hide the key from an offline brute-forcer" (a 8-hex prefix
/// of a strong key is not reversible in any practical sense; weak keys are out of scope —
/// rotation guidance is the scan's remediation path).
pub fn fingerprint(key_material: &str) -> String {
    let digest = Sha256::digest(key_material.as_bytes());
    hex::encode(digest)[..8].to_string()
}

/// Serializes one store line: `export VAR='value'` (AC1 format contract).
///
/// Single-quote escaping follows shell rules: a literal `'` becomes `'\''` (close quote,
/// escaped quote, reopen). Written by Rust so the escaping is consistent — and pinned by a
/// round-trip test against [`parse_env_line`] plus a real `bash -c "source …"` integration
/// test, because the whole Tier-R restart path depends on these files being sourceable.
pub fn render_env_line(var: &str, value: &str) -> String {
    format!("export {}='{}'", var, value.replace('\'', "'\\''"))
}

/// Parses one `export VAR='value'` line back into `(var, value)`.
///
/// Accepts **both** serialization styles on purpose:
/// - the Rust-written single-quoted style (with `'\''` escapes), and
/// - the historical unquoted style of the pre-M1 hand-made `~/.bathos/glm.env`
///   (`export Z_AI_API_KEY=<raw>`, fact L8) — without this, `key list`/`key scan` could not
///   fingerprint or search the user's existing glm key, which is the very key L19 leaked.
///
/// Non-`export` lines and malformed lines return `None` (callers skip them).
pub fn parse_env_line(line: &str) -> Option<(String, String)> {
    let rest = line.trim_start().strip_prefix("export ")?;
    let (var, after) = rest.split_once('=')?;
    if var.is_empty() || !var.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') {
        return None;
    }
    let after = after.trim_start();
    if let Some(quoted) = after.strip_prefix('\'') {
        let mut out = String::new();
        let mut rest = quoted;
        loop {
            let Some(i) = rest.find('\'') else {
                return None; // unterminated quote — not a line we wrote
            };
            out.push_str(&rest[..i]);
            let after_close = &rest[i..];
            if let Some(next) = after_close.strip_prefix("'\\''") {
                // `'\''` in the file = an escaped single quote; keep reading the same value.
                out.push('\'');
                rest = next;
            } else {
                // Real closing quote; anything after it on the line is ignored (we never
                // write trailing content, so this only affects hand-edited files).
                return Some((var.to_string(), out));
            }
        }
    }
    // Historical unquoted style: the value is the raw remainder (shell would end an
    // unquoted assignment at whitespace; the existing file has none, so keep it simple
    // and trim trailing whitespace/newline artifacts only).
    Some((var.to_string(), after.trim_end().to_string()))
}

/// Reads a store file and extracts its `(var, value)` — first parseable `export` line wins.
/// `Ok(None)` = file absent or no parseable line (callers distinguish via [`probe_key_file`]).
pub fn read_key_file(path: &Path) -> std::io::Result<Option<(String, String)>> {
    let raw = fs::read_to_string(path)?;
    Ok(raw.lines().find_map(parse_env_line))
}

/// Writes `<runtime>.env` atomically (AC1): dir 0700 ensured → temp file → chmod 0600 →
/// rename. A partial write or a key file briefly world-readable is never observable.
///
/// The directory mode is set **unconditionally**, not only on create: E2 specifies 0700 for
/// the store dir and the real-world `~/.bathos` was observed at 0755 — defense layer 5
/// (권한 강제) only holds if the write path enforces both layers every time.
pub fn write_key(bathos_dir: &Path, rt: Runtime, key_material: &str) -> std::io::Result<()> {
    fs::create_dir_all(bathos_dir)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(bathos_dir, fs::Permissions::from_mode(0o700))?;
    }
    let line = render_env_line(store_var(rt), key_material);
    let final_path = key_file_path(bathos_dir, rt);
    // Temp file in the same directory → rename stays on one filesystem → atomic.
    let tmp = bathos_dir.join(format!(".{}.env.tmp", rt.as_str()));
    fs::write(&tmp, format!("{line}\n"))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&tmp, fs::Permissions::from_mode(0o600))?;
    }
    fs::rename(&tmp, &final_path)?;
    Ok(())
}

/// Metadata + fingerprint probe for `key list`. Reads the file **only** to compute the
/// fingerprint; the value itself never leaves this function (invariant 3).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KeyFileInfo {
    pub present: bool,
    /// POSIX mode bits (e.g. `0o600`), `None` off-Unix or on stat failure.
    pub perm: Option<u32>,
    /// `true` only when the mode is exactly 0600 (E1: anything else warrants a `W-KEY-PERM`
    /// hint — a warning, never a block). Off-Unix there is nothing to evaluate, so a present
    /// file must not be flagged (same Windows rule as the M4 status probe).
    pub perm_ok: bool,
    /// Fingerprint of the stored key material, `None` when unreadable/unparseable.
    pub fingerprint: Option<String>,
    pub mtime: Option<SystemTime>,
    /// Variable name parsed from the file (should equal `store_var(rt)`; a mismatch means
    /// a hand-edited file — surfaced by the CLI as a format warning).
    pub var: Option<String>,
}

impl KeyFileInfo {
    pub fn absent() -> Self {
        KeyFileInfo {
            present: false,
            perm: None,
            perm_ok: false,
            fingerprint: None,
            mtime: None,
            var: None,
        }
    }
}

fn file_mode(m: &fs::Metadata) -> Option<u32> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        Some(m.permissions().mode() & 0o777)
    }
    #[cfg(not(unix))]
    {
        let _ = m;
        None
    }
}

/// Probes one store file (metadata + content fingerprint). Never errors: an unreadable
/// present file still reports `present: true` with `fingerprint: None` so `key list` can
/// say "등록은 돼 있으나 읽을 수 없음" instead of silently dropping the entry.
pub fn probe_key_file(path: &Path) -> KeyFileInfo {
    let Ok(m) = fs::metadata(path) else {
        return KeyFileInfo::absent();
    };
    let perm = file_mode(&m);
    let (fingerprint, var) = match read_key_file(path) {
        Ok(Some((var, value))) => (Some(fingerprint(&value)), Some(var)),
        _ => (None, None),
    };
    KeyFileInfo {
        present: true,
        perm_ok: perm.is_none_or(|p| p == 0o600),
        perm,
        fingerprint,
        mtime: m.modified().ok(),
        var,
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Leak scan (`bathos key scan`, AC7) — exact literal search, never pattern guessing
// ─────────────────────────────────────────────────────────────────────────────

/// One registered key to search for. `value` is the exact literal (vendor key *shapes* are
/// never guessed — AC7 forbids inventing patterns; only "does this exact string appear?" is
/// asked, because that is the question L19 actually needed answered).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RegisteredKey {
    pub runtime: String,
    pub value: String,
    /// 8-hex fingerprint — what findings display instead of the value (invariant 3).
    pub fingerprint: String,
}

/// A leak hit: `line_no` is 1-based, `key_index` indexes the `RegisteredKey` slice passed
/// to [`scan_text`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ScanHit {
    pub line_no: usize,
    pub key_index: usize,
}

/// Scans text for exact literal occurrences of the registered keys, line by line.
///
/// Order is "first key registered wins" per line — with multiple distinct keys on one line
/// (pathological) only the first is reported; the remediation (rotate + delete line) is
/// identical either way.
pub fn scan_text(text: &str, keys: &[RegisteredKey]) -> Vec<ScanHit> {
    let mut hits = Vec::new();
    for (idx, line) in text.lines().enumerate() {
        if let Some(i) = keys
            .iter()
            .position(|k| !k.value.is_empty() && line.contains(&k.value))
        {
            hits.push(ScanHit {
                line_no: idx + 1,
                key_index: i,
            });
        }
    }
    hits
}

/// Secondary (warn-only) markers: a literal `VAR=` assignment mentioning one of the auth
/// env vars. These catch a *different* (e.g. already-rotated) key sitting in a command
/// string — exactly the L19 shape. Non-blocking by design: legit script lines like
/// `glm-env.sh`'s usage comment also match, so this is an advisory, not a verdict.
pub const ASSIGNMENT_MARKERS: [&str; 3] = [
    "Z_AI_API_KEY=",
    "ANTHROPIC_AUTH_TOKEN=",
    "ANTHROPIC_API_KEY=",
];

/// 1-based line numbers containing any [`ASSIGNMENT_MARKERS`] literal.
pub fn scan_assignment_lines(text: &str) -> Vec<usize> {
    text.lines()
        .enumerate()
        .filter(|(_, line)| ASSIGNMENT_MARKERS.iter().any(|m| line.contains(m)))
        .map(|(i, _)| i + 1)
        .collect()
}

// ── scan file enumeration ────────────────────────────────────────────────────

/// Per-file byte cap. A leaked key lives in text (settings, scripts, logs); giant blobs
/// are build artifacts and packfiles.
// ponytail: files >5MB are never scanned (leaks in huge binaries are implausible); if a
// real leak is ever suspected inside a big generated file, raise the cap or add a
// byte-window scan for it — trigger: any leak report that names a file this cap skipped.
pub const SCAN_MAX_FILE_BYTES: u64 = 5 * 1024 * 1024;

/// Depth cap for the non-git fallback walk. Deepest real layout here is `core/crates/*/src`.
// ponytail: fallback walk depth-capped at 8 and skips only .git/target/node_modules; if a
// repo layout ever nests deeper, raise DEPTH — trigger: a scan report whose skipped count
// matters or a dir the walk provably never entered.
const FALLBACK_MAX_DEPTH: usize = 8;
const FALLBACK_SKIP_DIRS: [&str; 3] = [".git", "target", "node_modules"];

/// One file to scan: `path` is opened, `display` is what findings print (repo-relative —
/// findings must not leak absolute home paths into terminals/tickets).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CollectedFile {
    pub path: PathBuf,
    pub display: String,
}

/// Enumeration result — the skip counters feed the scan report (observability: "clean"
/// must be believable, so the report states what was *not* looked at).
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ScanCollection {
    pub files: Vec<CollectedFile>,
    pub dataless_skipped: usize,
    pub oversized_skipped: usize,
    /// `false` = git unavailable / not a repo → bounded fallback walk was used.
    pub used_git: bool,
}

/// `true` when a file is *probably* an iCloud-evicted ("dataless") stub: size > 0 but
/// zero blocks allocated. Opening such a file can hang the process indefinitely on this
/// repo's host (measured twice by the lead — the story mandates a skip strategy), so the
/// check runs on `metadata` **before** any read. False positives are theoretically
/// possible on other Unixes (sparse files) — skipping them from a leak scan with a
/// counter in the report is the safe trade.
pub fn looks_dataless(size: u64, blocks: u64) -> bool {
    size > 0 && blocks == 0
}

enum Scannable {
    Yes,
    Dataless,
    Oversized,
    No,
}

fn classify_for_scan(path: &Path) -> Scannable {
    let Ok(m) = fs::metadata(path) else {
        return Scannable::No;
    };
    if !m.is_file() {
        return Scannable::No;
    }
    if m.len() > SCAN_MAX_FILE_BYTES {
        return Scannable::Oversized;
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        if looks_dataless(m.len(), m.blocks()) {
            return Scannable::Dataless;
        }
    }
    Scannable::Yes
}

/// Enumerates the scan target set for a repo root (AC7): the git worktree (tracked +
/// untracked-not-ignored — which auto-excludes `.gitignore`d build outputs), plus the
/// explicit targets the ignore rules hide but L19 proved dangerous: `.claude/settings*.json`
/// (recursive) and `_state/audit-log.jsonl` (invariant 2 exists precisely because the audit
/// log records command strings, so it must be scanned too).
///
/// Dataless/oversized files are filtered **before** any open.
pub fn collect_scan_files(root: &Path) -> std::io::Result<ScanCollection> {
    // A nonexistent scan root is an I/O error (AC7: I/O 오류 = exit 1), not a silent
    // "0 files scanned, clean" — a scan that looked at nothing must never report clean.
    if !root.is_dir() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::NotFound,
            format!("스캔 루트가 디렉터리가 아닙니다: {}", root.display()),
        ));
    }
    let mut paths: std::collections::BTreeSet<PathBuf> = std::collections::BTreeSet::new();
    let mut collection = ScanCollection::default();

    // Primary enumeration: `git ls-files -z` — stats only, never reads content, so it is
    // safe on dataless files (measured: 1601 files in this repo, instant).
    let git_out = std::process::Command::new("git")
        .arg("-C")
        .arg(root)
        .args([
            "ls-files",
            "--cached",
            "--others",
            "--exclude-standard",
            "-z",
        ])
        .output();
    if let Ok(out) = git_out {
        if out.status.success() {
            collection.used_git = true;
            for rel in String::from_utf8_lossy(&out.stdout).split('\0') {
                if rel.is_empty() {
                    continue;
                }
                paths.insert(root.join(rel));
            }
        }
    }
    if !collection.used_git {
        // Fallback (non-git projects): bounded walk, skipping VCS/build dirs. It ignores
        // .gitignore rules — acceptable for a best-effort fallback, flagged in the report
        // by used_git=false.
        walk_fallback(root, 0, &mut paths);
    }

    // Explicit L19-class targets regardless of enumeration source.
    for p in collect_settings_json(root) {
        paths.insert(p);
    }
    let audit_log = root.join("_state").join("audit-log.jsonl");
    if audit_log.is_file() {
        paths.insert(audit_log);
    }

    for path in paths {
        match classify_for_scan(&path) {
            Scannable::Yes => {
                // Reports print git-style `file:line` and are consumed by logs, CI and
                // tests on every OS — normalize Windows separators to `/`.
                let display = path
                    .strip_prefix(root)
                    .map(|p| p.to_string_lossy().into_owned())
                    .unwrap_or_else(|_| path.to_string_lossy().into_owned())
                    .replace('\\', "/");
                collection.files.push(CollectedFile { path, display });
            }
            Scannable::Dataless => collection.dataless_skipped += 1,
            Scannable::Oversized => collection.oversized_skipped += 1,
            Scannable::No => {}
        }
    }
    Ok(collection)
}

fn walk_fallback(dir: &Path, depth: usize, out: &mut std::collections::BTreeSet<PathBuf>) {
    if depth > FALLBACK_MAX_DEPTH {
        return;
    }
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        match entry.file_type() {
            Ok(t) if t.is_dir() => {
                let name = entry.file_name();
                if FALLBACK_SKIP_DIRS.iter().any(|s| name == *s) {
                    continue;
                }
                walk_fallback(&path, depth + 1, out);
            }
            Ok(t) if t.is_file() => {
                out.insert(path);
            }
            _ => {}
        }
    }
}

/// `root/.claude/settings*.json`, recursively (the gitignore pattern is
/// `.claude/**/settings.local.json`, so nesting is possible). Depth-capped walk of `.claude`
/// only — cheap and name-exact.
fn collect_settings_json(root: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let claude = root.join(".claude");
    let mut stack = vec![(claude, 0usize)];
    while let Some((dir, depth)) = stack.pop() {
        if depth > 4 {
            continue;
        }
        let Ok(entries) = fs::read_dir(&dir) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            let Some(name) = path.file_name().and_then(|n| n.to_str()) else {
                continue;
            };
            let is_dir = entry.file_type().map(|t| t.is_dir()).unwrap_or(false);
            if is_dir {
                stack.push((path, depth + 1));
            } else if name.starts_with("settings") && name.ends_with(".json") {
                out.push(path);
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    // ── fingerprint (unit: determinism + known vector) ───────────────────────

    #[test]
    fn fingerprint_is_deterministic_and_matches_known_vector() {
        // sha256("test") = 9f86d081884c7d659a2feaa0c55ad015…
        assert_eq!(fingerprint("test"), "9f86d081");
        assert_eq!(fingerprint("test"), fingerprint("test"));
        assert_eq!(fingerprint("test").len(), 8);
        assert_ne!(fingerprint("test"), fingerprint("test "));
    }

    // ── serialization round-trip (unit: escape handling) ─────────────────────

    #[test]
    fn render_then_parse_roundtrips_tricky_values() {
        let cases = [
            "plain-key",
            "",    // empty value still round-trips structurally
            "a'b", // single quote → '\'' escape
            "it's got 'quotes' inside",
            "dollar-$igns & back\\slashes", // backslash is literal inside single quotes
            "한글-키값",
            " leading and trailing ",
        ];
        for value in cases {
            let line = render_env_line("BATHOS_TEST_KEY", value);
            let (var, parsed) = parse_env_line(&line).expect("must parse");
            assert_eq!(var, "BATHOS_TEST_KEY");
            assert_eq!(parsed, value, "round-trip failed for line: {line}");
        }
    }

    #[test]
    fn render_produces_the_exact_ac1_format() {
        assert_eq!(
            render_env_line("Z_AI_API_KEY", "abc"),
            "export Z_AI_API_KEY='abc'"
        );
    }

    #[test]
    fn parse_accepts_the_historical_unquoted_glm_env_line() {
        // Fact L8: the pre-M1 real file is `export Z_AI_API_KEY=<raw>` — list/scan must
        // still fingerprint and search that key.
        let (var, value) = parse_env_line("export Z_AI_API_KEY=raw-key-123").expect("must parse");
        assert_eq!(var, "Z_AI_API_KEY");
        assert_eq!(value, "raw-key-123");
        assert!(parse_env_line("no export prefix").is_none());
        assert!(parse_env_line("export =novar").is_none());
    }

    // ── runtime validation (AC4 + E9 no-echo rule) ───────────────────────────

    #[test]
    fn claude_and_codex_are_rejected_as_unsupported() {
        for rt in ["claude", "codex", "CLAUDE"] {
            let err = parse_key_runtime(rt).unwrap_err();
            assert!(err.contains("E-KEY-RUNTIME-UNSUPPORTED"), "{err}");
        }
        for rt in KEY_RUNTIMES {
            assert!(parse_key_runtime(rt.as_str()).is_ok());
        }
    }

    #[test]
    fn unknown_runtime_error_never_echoes_the_input() {
        // A key pasted into the runtime slot must not come back in the error message (E9).
        let err = parse_key_runtime("sk-real-secret-key").unwrap_err();
        assert!(err.contains("E-KEY-RUNTIME-INVALID"));
        assert!(!err.contains("sk-real-secret-key"));
    }

    // ── probe (unit: absent / present / perm semantics) ──────────────────────

    #[test]
    fn probe_reports_absent_without_touching_anything() {
        let dir = tempfile::TempDir::new().unwrap();
        let info = probe_key_file(&dir.path().join("glm.env"));
        assert_eq!(info, KeyFileInfo::absent());
        assert!(!info.present && !info.perm_ok);
    }

    #[cfg(unix)]
    #[test]
    fn probe_reads_perm_and_fingerprint_through_the_written_format() {
        use std::os::unix::fs::PermissionsExt;
        let dir = tempfile::TempDir::new().unwrap();
        let path = dir.path().join("kimi.env");
        write_key(dir.path(), Runtime::Kimi, "fixture-kimi-key").unwrap();

        let meta = std::fs::metadata(&path).unwrap();
        assert_eq!(meta.permissions().mode() & 0o777, 0o600);
        let dir_meta = std::fs::metadata(dir.path()).unwrap();
        assert_eq!(dir_meta.permissions().mode() & 0o777, 0o700);

        let info = probe_key_file(&path);
        assert!(info.present && info.perm_ok);
        assert_eq!(info.perm, Some(0o600));
        assert_eq!(info.fingerprint, Some(fingerprint("fixture-kimi-key")));
        assert_eq!(info.var, Some("BATHOS_KIMI_KEY".to_string()));
        assert!(info.mtime.is_some());
    }

    #[test]
    fn write_key_rewrites_an_existing_wrong_perm_file_to_600() {
        // E1: `key set` always rewrites at 600 — even over a pre-existing loose file.
        let dir = tempfile::TempDir::new().unwrap();
        let path = key_file_path(dir.path(), Runtime::Deepseek);
        std::fs::write(&path, "old").unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o644)).unwrap();
        }

        write_key(dir.path(), Runtime::Deepseek, "new-key").unwrap();
        let info = probe_key_file(&path);
        assert!(info.perm_ok);
        assert_eq!(info.fingerprint, Some(fingerprint("new-key")));
    }

    // ── scan text matching (unit: exact literal + masking inputs) ────────────

    fn reg(name: &str, value: &str) -> RegisteredKey {
        RegisteredKey {
            runtime: name.to_string(),
            value: value.to_string(),
            fingerprint: fingerprint(value),
        }
    }

    #[test]
    fn scan_finds_exact_literal_and_reports_one_based_lines() {
        let keys = [reg("glm", "FIXTURE-KEY-1")];
        let text = "line one\nallow: Z_AI_API_KEY=FIXTURE-KEY-1 bash -c x\nline three\n";
        let hits = scan_text(text, &keys);
        assert_eq!(
            hits,
            vec![ScanHit {
                line_no: 2,
                key_index: 0
            }]
        );
    }

    #[test]
    fn scan_does_not_guess_vendor_key_shapes() {
        // Only the registered literal matches — never a guessed key *shape* (AC7: 패턴 추측
        // 금지). A longer line CONTAINING the literal must match though (that is exactly the
        // L19 shape: a recorded command string with the key inside it).
        let keys = [reg("glm", "FIXTURE-KEY-1")];
        assert!(scan_text("sk-something-else-entirely\n", &keys).is_empty());
        assert!(scan_text("no keys here\n", &keys).is_empty());
        assert_eq!(
            scan_text("cmd: Z_AI_API_KEY=FIXTURE-KEY-1 bash\n", &keys).len(),
            1
        );
    }

    #[test]
    fn scan_skips_empty_registered_values_safely() {
        // An empty literal would match every line (contains("")) — it must be inert.
        let keys = [reg("glm", "")];
        assert!(scan_text("anything\n", &keys).is_empty());
    }

    #[test]
    fn assignment_markers_flag_l19_shaped_lines() {
        let text = "normal\nZ_AI_API_KEY=oldkey bash -c x\nexport ANTHROPIC_API_KEY=\"x\"\n";
        assert_eq!(scan_assignment_lines(text), vec![2, 3]);
        assert!(scan_assignment_lines("nothing here\n").is_empty());
    }

    // ── dataless guard (unit: the pure predicate) ────────────────────────────

    #[test]
    fn dataless_predicate_matches_zero_block_nonempty_files() {
        assert!(looks_dataless(84, 0)); // measured signature of this repo's evicted files
        assert!(!looks_dataless(84, 8)); // materialized
        assert!(!looks_dataless(0, 0)); // truly empty → normal read is harmless
    }

    // ── enumeration (integration-ish: tempdir, git optional) ─────────────────

    #[test]
    fn collect_in_non_git_dir_uses_fallback_walk_and_finds_settings() {
        let dir = tempfile::TempDir::new().unwrap();
        let root = dir.path();
        std::fs::create_dir_all(root.join("src/deep")).unwrap();
        std::fs::write(root.join("src/a.txt"), "x").unwrap();
        std::fs::write(root.join("src/deep/b.txt"), "y").unwrap();
        std::fs::create_dir_all(root.join(".claude")).unwrap();
        std::fs::write(root.join(".claude/settings.local.json"), "{}").unwrap();
        std::fs::create_dir_all(root.join(".git")).unwrap();
        std::fs::write(root.join(".git/internal"), "z").unwrap();

        let c = collect_scan_files(root).unwrap();
        assert!(!c.used_git);
        let displays: Vec<&str> = c.files.iter().map(|f| f.display.as_str()).collect();
        assert!(displays.contains(&"src/a.txt"), "{displays:?}");
        assert!(displays.contains(&"src/deep/b.txt"), "{displays:?}");
        assert!(
            displays.contains(&".claude/settings.local.json"),
            "{displays:?}"
        );
        // .git is never walked by the fallback.
        assert!(
            !displays.iter().any(|d| d.starts_with(".git/")),
            "{displays:?}"
        );
    }

    #[test]
    fn collect_in_git_repo_enumerates_tracked_and_untracked_but_not_ignored() {
        if std::process::Command::new("git")
            .arg("--version")
            .output()
            .is_err()
        {
            return; // git unavailable in this environment — fallback path is covered above
        }
        let dir = tempfile::TempDir::new().unwrap();
        let root = dir.path();
        std::fs::write(root.join("tracked.txt"), "a").unwrap();
        std::fs::write(root.join("untracked.txt"), "b").unwrap();
        std::fs::write(root.join("ignored.txt"), "c").unwrap();
        std::fs::write(root.join(".gitignore"), "ignored.txt\n").unwrap();
        std::fs::create_dir_all(root.join(".claude")).unwrap();
        std::fs::write(root.join(".claude/settings.local.json"), "{}").unwrap();
        assert!(std::process::Command::new("git")
            .arg("-C")
            .arg(root)
            .args(["init", "-q"])
            .status()
            .unwrap()
            .success());

        let c = collect_scan_files(root).unwrap();
        assert!(c.used_git);
        let displays: Vec<&str> = c.files.iter().map(|f| f.display.as_str()).collect();
        assert!(displays.contains(&"tracked.txt"), "{displays:?}");
        assert!(displays.contains(&"untracked.txt"), "{displays:?}");
        // Ignored by .gitignore, but settings files are explicitly re-added (L19 target).
        assert!(!displays.contains(&"ignored.txt"), "{displays:?}");
        assert!(
            displays.contains(&".claude/settings.local.json"),
            "{displays:?}"
        );
    }
}
