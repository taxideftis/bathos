//! Integration tests for `bathos key` (story M1) — real binary, real files, tempdir HOME.
//!
//! Every test drives the actual `bathos` binary (`env!("CARGO_BIN_EXE_bathos")`) with HOME
//! pointed at a tempdir, so `~/.bathos` — and the store's 0600/0700 permission contract —
//! is exercised for real without touching the developer's actual key store.
//!
//! The load-bearing assertion family (common DoD): **fixture key material never appears in
//! stdout, stderr, the audit log, or the scanned repo tree.** `assert_no_leak` checks all
//! four against every fixture used here.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use tempfile::TempDir;

const GLM_KEY: &str = "SK-M1FIX-glm-9f2c41ab";
const GLM_FP: &str = "bd393ce2"; // shasum -a 256 of GLM_KEY, first 8
const KIMI_KEY: &str = "SK-M1FIX-kimi-plain-3311";
const KIMI_FP: &str = "fe03356d";
const QUOTED_KEY: &str = "it's a $tricky 'key'";
const QUOTED_FP: &str = "cf3f019a";
const ARGV_KEY: &str = "SK-M1FIX-argv-secret-777";

/// Runs the real binary with HOME overridden to `home` and the given stdin payload.
fn bathos(home: &Path, stdin: &str, args: &[&str]) -> Output {
    let mut child = Command::new(env!("CARGO_BIN_EXE_bathos"))
        .args(args)
        .env("HOME", home)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .expect("spawn bathos");
    use std::io::Write;
    child
        .stdin
        .as_mut()
        .expect("stdin piped")
        .write_all(stdin.as_bytes())
        .expect("write stdin");
    child.wait_with_output().expect("wait bathos")
}

fn text(out: &Output) -> String {
    format!(
        "{}{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    )
}

fn code(out: &Output) -> i32 {
    out.status.code().expect("normal exit")
}

/// The store dir a tempdir HOME implies: `<home>/.bathos`.
fn store_dir(home: &Path) -> PathBuf {
    home.join(".bathos")
}

/// Recursive scan: which files under `dir` contain `needle`? (The no-leak proof walks the
/// whole tree — audit logs and state files included — rather than trusting any allowlist.)
fn files_containing(dir: &Path, needle: &str) -> Vec<PathBuf> {
    let mut hits = Vec::new();
    let mut stack = vec![dir.to_path_buf()];
    while let Some(d) = stack.pop() {
        let Ok(entries) = fs::read_dir(&d) else {
            continue;
        };
        for entry in entries.flatten() {
            let p = entry.path();
            if p.is_dir() {
                stack.push(p);
            } else if fs::read_to_string(&p)
                .map(|c| c.contains(needle))
                .unwrap_or(false)
            {
                hits.push(p);
            }
        }
    }
    hits
}

/// Common DoD: the fixture key must not be visible in stdout, stderr, the audit log, or
/// anywhere in the repo tree under `root`. `except` lists files the test itself seeded with
/// fixture material as scan fodder — the assertion guards what the *command* wrote, so
/// those inputs are skipped (everything else, audit log included, must be clean).
fn assert_no_leak(out: &Output, root: &Path, keys: &[&str], except: &[PathBuf]) {
    let combined = text(out);
    for key in keys {
        assert!(
            !combined.contains(key),
            "key material leaked into command output"
        );
        let hits: Vec<PathBuf> = files_containing(root, key)
            .into_iter()
            .filter(|p| !except.iter().any(|e| p == e))
            .collect();
        assert!(
            hits.is_empty(),
            "key material leaked into repo tree files: {hits:?}"
        );
    }
}

#[cfg(unix)]
fn mode(p: &Path) -> u32 {
    use std::os::unix::fs::PermissionsExt;
    fs::metadata(p).unwrap().permissions().mode() & 0o777
}

/// Per-test sandbox: isolated HOME + isolated scan root with its own `_state`.
struct Sandbox {
    _home: TempDir,
    _root: TempDir,
}

impl Sandbox {
    fn new() -> Self {
        Sandbox {
            _home: TempDir::new().unwrap(),
            _root: TempDir::new().unwrap(),
        }
    }
    fn home(&self) -> PathBuf {
        self._home.path().to_path_buf()
    }
    fn root(&self) -> PathBuf {
        self._root.path().to_path_buf()
    }
    /// `bathos --state-dir <root>/_state <args>` — state scoped to the sandbox root.
    fn run(&self, stdin: &str, args: &[&str]) -> Output {
        let state_dir = self.root().join("_state");
        let state = state_dir.to_string_lossy().into_owned();
        let mut full: Vec<&str> = vec!["--state-dir", &state];
        full.extend_from_slice(args);
        bathos(&self.home(), stdin, &full)
    }
}

// ── AC1: set writes the store atomically (600/700), prints fingerprint only, audits ──

#[test]
fn ac1_set_glm_writes_store_and_leaks_nowhere() {
    let sb = Sandbox::new();
    let out = sb.run(GLM_KEY, &["key", "set", "glm"]);
    assert_eq!(code(&out), 0, "output: {}", text(&out));

    // Exact AC1 file contract: one line, `export Z_AI_API_KEY='<key>'`, quoted by Rust.
    let key_file = store_dir(&sb.home()).join("glm.env");
    assert_eq!(
        fs::read_to_string(&key_file).unwrap(),
        format!("export Z_AI_API_KEY='{GLM_KEY}'\n")
    );

    // Permission contract: file 600, dir 700 (E2/E1 defense layer 5).
    #[cfg(unix)]
    {
        assert_eq!(mode(&key_file), 0o600);
        assert_eq!(mode(&store_dir(&sb.home())), 0o700);
    }

    // stdout shows the fingerprint — and nothing else key-derived.
    let stdout = String::from_utf8_lossy(&out.stdout).into_owned();
    assert!(stdout.contains(GLM_FP), "stdout: {stdout}");
    assert!(stdout.contains("source ~/.bathos/glm.env && source scripts/glm-env.sh"));

    // Audit entry: action key.set, target = runtime name only (invariant 4).
    let audit = fs::read_to_string(sb.root().join("_state/audit-log.jsonl")).unwrap();
    assert!(audit.contains("\"action\":\"key.set\""), "{audit}");
    assert!(audit.contains("\"target\":\"glm\""), "{audit}");

    // Common DoD: fixture key in none of stdout/stderr/audit-log/repo tree.
    assert_no_leak(&out, &sb.root(), &[GLM_KEY], &[]);

    // AC8 half-proof: the written file is sourceable by a real shell and yields the value.
    #[cfg(unix)]
    {
        let sourced = Command::new("bash")
            .arg("-c")
            .arg(format!(
                "source {} && printf %s \"$Z_AI_API_KEY\"",
                key_file.display()
            ))
            .output()
            .unwrap();
        assert_eq!(String::from_utf8_lossy(&sourced.stdout), GLM_KEY);
    }
}

#[test]
fn ac1b_set_kimi_uses_bathos_prefixed_var_and_quotes_roundtrip() {
    let sb = Sandbox::new();
    let out = sb.run(QUOTED_KEY, &["key", "set", "kimi"]);
    assert_eq!(code(&out), 0, "output: {}", text(&out));

    let key_file = store_dir(&sb.home()).join("kimi.env");
    // A single quote must survive as `'\''` — the exact Rust-side escaping contract.
    assert_eq!(
        fs::read_to_string(&key_file).unwrap(),
        "export BATHOS_KIMI_KEY='it'\\''s a $tricky '\\''key'\\'''\n"
    );
    let stdout = String::from_utf8_lossy(&out.stdout).into_owned();
    assert!(stdout.contains(QUOTED_FP), "{stdout}");

    #[cfg(unix)]
    {
        // A real shell must recover the exact value — this is what makes the Tier-R
        // restart path a one-liner (AC8's `source` requirement, non-glm shape).
        let sourced = Command::new("bash")
            .arg("-c")
            .arg(format!(
                "source {} && printf %s \"$BATHOS_KIMI_KEY\"",
                key_file.display()
            ))
            .output()
            .unwrap();
        assert_eq!(String::from_utf8_lossy(&sourced.stdout), QUOTED_KEY);
    }
    assert_no_leak(&out, &sb.root(), &[QUOTED_KEY], &[]);
}

// ── AC2: argv keys are rejected without echo ─────────────────────────────────

#[test]
fn ac2_argv_positional_key_rejected_without_echo() {
    let sb = Sandbox::new();
    let out = sb.run("", &["key", "set", "glm", ARGV_KEY]);
    assert_eq!(code(&out), 2, "output: {}", text(&out));
    let combined = text(&out);
    assert!(combined.contains("E-KEY-ARGV"), "{combined}");
    assert!(
        !combined.contains(ARGV_KEY),
        "the rejection message echoed the key"
    );
    // Nothing was written, and the store dir was never created by the rejected attempt.
    assert!(!store_dir(&sb.home()).join("glm.env").exists());
}

#[test]
fn ac2b_flag_style_key_is_never_consumed_or_echoed() {
    // `--key=<value>` is not an advertised option; whatever clap does with it, the value
    // must not appear anywhere in the process output (E9: the error message must not
    // become the leak channel).
    let sb = Sandbox::new();
    let out = sb.run("", &["key", "set", "glm", &format!("--key={ARGV_KEY}")]);
    let combined = text(&out);
    assert!(
        !combined.contains(ARGV_KEY),
        "flag-style key echoed back: {combined}"
    );
    assert!(!store_dir(&sb.home()).join("glm.env").exists());
}

// ── AC3: empty stdin ─────────────────────────────────────────────────────────

#[test]
fn ac3_empty_stdin_rejected() {
    let sb = Sandbox::new();
    let out = sb.run("", &["key", "set", "glm"]);
    assert_eq!(code(&out), 2);
    assert!(text(&out).contains("E-KEY-STDIN-EMPTY"), "{}", text(&out));

    let out = sb.run("   \n", &["key", "set", "glm"]);
    assert_eq!(code(&out), 2, "whitespace-only counts as empty");
    assert!(text(&out).contains("E-KEY-STDIN-EMPTY"));
    assert!(!store_dir(&sb.home()).join("glm.env").exists());
}

// ── AC4: claude/codex (and unknown) runtimes are rejected ────────────────────

#[test]
fn ac4_claude_and_codex_rejected_as_unsupported() {
    let sb = Sandbox::new();
    for rt in ["claude", "codex"] {
        // stdin is closed/empty — rejection must happen before any stdin read.
        let out = sb.run("", &["key", "set", rt]);
        assert_eq!(code(&out), 2, "{rt}: {}", text(&out));
        let combined = text(&out);
        assert!(combined.contains("E-KEY-RUNTIME-UNSUPPORTED"), "{combined}");
        assert!(combined.contains(rt));
        assert!(!store_dir(&sb.home()).join(format!("{rt}.env")).exists());
    }
}

#[test]
fn ac4b_unknown_runtime_token_is_never_echoed() {
    let sb = Sandbox::new();
    let out = sb.run("", &["key", "set", ARGV_KEY]);
    assert_eq!(code(&out), 2);
    let combined = text(&out);
    assert!(
        !combined.contains(ARGV_KEY),
        "invalid-runtime error echoed the input (E9): {combined}"
    );
    // rm validates the same way.
    let out = sb.run("", &["key", "rm", "claude"]);
    assert_eq!(code(&out), 2);
    assert!(text(&out).contains("E-KEY-RUNTIME-UNSUPPORTED"));
}

// ── AC5: list table, JSON, and the W-KEY-PERM warning ────────────────────────

#[test]
fn ac5_list_reports_registration_fingerprint_perm() {
    let sb = Sandbox::new();

    // Fresh HOME: absent store is a normal "등록 없음" listing (AC9 half), exit 0.
    let out = sb.run("", &["key", "list"]);
    assert_eq!(code(&out), 0, "{}", text(&out));
    assert!(text(&out).contains("등록된 키가 없습니다"));

    let out = sb.run(KIMI_KEY, &["key", "set", "kimi"]);
    assert_eq!(code(&out), 0);

    let out = sb.run("", &["key", "list"]);
    assert_eq!(code(&out), 0);
    let stdout = String::from_utf8_lossy(&out.stdout).into_owned();
    assert!(stdout.contains(KIMI_FP), "{stdout}");
    // POSIX mode bits do not exist on Windows (M4 precedent: unix_file_mode -> None),
    // so the perm cell renders "-" there; only Unix can assert 0600.
    #[cfg(unix)]
    assert!(stdout.contains("600"), "{stdout}");
    #[cfg(not(unix))]
    assert!(stdout.contains(" -\n"), "{stdout}");
    assert!(
        stdout.contains("○"),
        "unregistered marker missing: {stdout}"
    );
    assert!(!stdout.contains(KIMI_KEY), "list leaked the value");

    // Wrong perms → W-KEY-PERM warning on stderr, exit stays 0 (E1: warn, don't block).
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let kf = store_dir(&sb.home()).join("kimi.env");
        fs::set_permissions(&kf, fs::Permissions::from_mode(0o644)).unwrap();
        let out = sb.run("", &["key", "list"]);
        assert_eq!(code(&out), 0);
        assert!(text(&out).contains("W-KEY-PERM"), "{}", text(&out));
    }

    // --json: single JSON object on stdout.
    let out = sb.run("", &["key", "list", "--json"]);
    assert_eq!(code(&out), 0);
    let stdout = String::from_utf8_lossy(&out.stdout).into_owned();
    let v: serde_json::Value = serde_json::from_str(&stdout).expect("valid JSON");
    assert_eq!(v["schema"], "bathos/key-list@1");
    let kimi = v["keys"]
        .as_array()
        .unwrap()
        .iter()
        .find(|k| k["runtime"] == "kimi")
        .expect("kimi row");
    assert_eq!(kimi["registered"], true);
    assert_eq!(kimi["fingerprint"], KIMI_FP);
    assert_eq!(kimi["var"], "BATHOS_KIMI_KEY");
}

// ── AC6: rm removes, audits, and is idempotent ───────────────────────────────

#[test]
fn ac6_rm_removes_audits_and_second_rm_is_a_noop() {
    let sb = Sandbox::new();
    let out = sb.run(GLM_KEY, &["key", "set", "deepseek"]);
    assert_eq!(code(&out), 0);

    let kf = store_dir(&sb.home()).join("deepseek.env");
    assert!(kf.exists());
    let out = sb.run("", &["key", "rm", "deepseek"]);
    assert_eq!(code(&out), 0, "{}", text(&out));
    assert!(!kf.exists());

    let audit_path = sb.root().join("_state/audit-log.jsonl");
    let audit = fs::read_to_string(&audit_path).unwrap();
    assert!(audit.contains("\"action\":\"key.rm\""));
    assert!(audit.contains("\"target\":\"deepseek\""));
    assert!(!audit.contains(GLM_KEY));
    let lines_after_rm = audit.lines().count();

    // Absent file → "등재 없음(변화 없음)" exit 0, and no extra audit entry (idempotent).
    let out = sb.run("", &["key", "rm", "deepseek"]);
    assert_eq!(code(&out), 0);
    assert!(text(&out).contains("등재 없음"), "{}", text(&out));
    let audit = fs::read_to_string(&audit_path).unwrap();
    assert_eq!(audit.lines().count(), lines_after_rm);
}

// ── AC7: scan — leak found (exit 2) / clean (exit 0) / I/O (exit 1) ──────────

#[test]
fn ac7_scan_finds_exact_literal_leak_including_ignored_settings() {
    let sb = Sandbox::new();
    assert_eq!(code(&sb.run(KIMI_KEY, &["key", "set", "kimi"])), 0);

    // Seed the scan root: a git repo whose ignore rules hide the settings file — the L19
    // shape (gitignored settings.local.json holding the key) must still be found via the
    // explicit settings glob. Fixture-bearing files are recorded so the no-leak walk can
    // exempt them (they are test inputs, not command output).
    let root = sb.root();
    fs::write(
        root.join(".gitignore"),
        ".claude/settings.local.json\nsecret-ignored.txt\n",
    )
    .unwrap();
    fs::create_dir_all(root.join("docs")).unwrap();
    let tracked_leak = root.join("docs/leak.md");
    fs::write(
        &tracked_leak,
        format!("harmless first line\ntoken = {KIMI_KEY} pasted here\n"),
    )
    .unwrap();
    let ignored_leak = root.join("secret-ignored.txt");
    fs::write(&ignored_leak, KIMI_KEY).unwrap(); // gitignored → NOT a scan target (only settings files are re-added explicitly)
    fs::create_dir_all(root.join(".claude")).unwrap();
    let settings = root.join(".claude/settings.local.json");
    fs::write(
        &settings,
        format!("{{\"allow\":[\"Bash(Z_AI_API_KEY={KIMI_KEY} bash -c x)\"]}}"),
    )
    .unwrap();
    // Assignment-shaped advisory (a *different* stale key value — warns, not a leak).
    fs::write(
        root.join("notes.txt"),
        "Z_AI_API_KEY=stale-rotated-key-value\n",
    )
    .unwrap();
    assert!(Command::new("git")
        .arg("-C")
        .arg(&root)
        .args(["init", "-q"])
        .status()
        .unwrap()
        .success());

    let except = [tracked_leak, ignored_leak, settings];
    // The scan root is the seeded sandbox (the test process's cwd is the crate dir).
    let root_arg = root.to_str().unwrap();
    let out = sb.run("", &["key", "--root", root_arg, "scan"]);
    assert_eq!(code(&out), 2, "output: {}", text(&out));
    let stdout = String::from_utf8_lossy(&out.stdout).into_owned();
    // Found in the gitignored settings file, reported as file:line + fingerprint only.
    assert!(stdout.contains(".claude/settings.local.json:1"), "{stdout}");
    // And in an ordinary tracked text file, by line number.
    assert!(stdout.contains("docs/leak.md:2"), "{stdout}");
    assert!(stdout.contains(KIMI_FP), "{stdout}");
    assert_eq!(stdout.matches("W-KEY-LEAK").count(), 2, "{stdout}");
    assert!(stdout.contains("로테이션"), "remediation guidance missing");
    // Advisory present for the assignment-shaped line.
    assert!(stdout.contains("W-KEY-ASSIGN"), "{stdout}");
    // Common DoD: the value never appears in the output.
    assert!(!stdout.contains(KIMI_KEY), "scan leaked the value");
    assert_no_leak(&out, &root, &[KIMI_KEY], &except);

    // JSON shape of the same scan.
    let out = sb.run("", &["key", "--root", root_arg, "scan", "--json"]);
    assert_eq!(code(&out), 2);
    let v: serde_json::Value =
        serde_json::from_str(&String::from_utf8_lossy(&out.stdout)).expect("valid JSON");
    assert_eq!(v["schema"], "bathos/key-scan@1");
    assert_eq!(v["leaks"].as_array().unwrap().len(), 2);
    assert_eq!(v["leaks"][0]["runtime"], "kimi");
    assert_eq!(v["leaks"][0]["fingerprint"], KIMI_FP);
    assert_eq!(v["used_git"], true);
    assert!(v["scanned"].as_u64().unwrap() >= 3);
}

#[test]
fn ac7b_scan_clean_exit_zero_and_no_registered_keys_is_a_reported_noop() {
    let sb = Sandbox::new();
    // No keys registered at all → nothing to search → exit 0 with guidance.
    let out = sb.run("", &["key", "scan"]);
    assert_eq!(code(&out), 0, "{}", text(&out));
    assert!(text(&out).contains("등록된 키가 없어"), "{}", text(&out));

    // Registered key + clean tree → exit 0.
    assert_eq!(code(&sb.run(GLM_KEY, &["key", "set", "glm"])), 0);
    fs::write(sb.root().join("clean.txt"), "nothing to see here\n").unwrap();
    let root_path = sb.root();
    let root_arg = root_path.to_str().unwrap();
    let out = sb.run("", &["key", "--root", root_arg, "scan"]);
    assert_eq!(code(&out), 0, "{}", text(&out));
    assert!(text(&out).contains("유출 없음"), "{}", text(&out));
}

#[test]
fn ac7c_scan_nonexistent_root_is_io_error_exit_one() {
    let sb = Sandbox::new();
    assert_eq!(code(&sb.run(GLM_KEY, &["key", "set", "glm"])), 0);
    // `--root` belongs to the `key` group — it goes between `key` and `scan`.
    let missing = sb.root().join("does-not-exist");
    let out = sb.run("", &["key", "--root", missing.to_str().unwrap(), "scan"]);
    assert_eq!(code(&out), 1, "{}", text(&out));
}

// ── AC8: glm variable name compatibility ─────────────────────────────────────
// The Z_AI_API_KEY variable name + sourceability is asserted inside ac1 (exact file line +
// real `bash -c "source …"`). AC9's dir auto-create at 0700 is asserted there too.

// ── AC9: store dir auto-created at 0700; list on absent store is normal ──────

#[test]
fn ac9_fresh_home_creates_store_dir_with_700_on_first_set() {
    let sb = Sandbox::new();
    assert!(!store_dir(&sb.home()).exists());
    let out = sb.run(QUOTED_KEY, &["key", "set", "qwen"]);
    assert_eq!(code(&out), 0, "{}", text(&out));
    #[cfg(unix)]
    assert_eq!(mode(&store_dir(&sb.home())), 0o700);

    // qwen stores under its BATHOS-prefixed name.
    let kf = store_dir(&sb.home()).join("qwen.env");
    assert_eq!(
        fs::read_to_string(&kf).unwrap(),
        "export BATHOS_QWEN_KEY='it'\\''s a $tricky '\\''key'\\'''\n"
    );

    // list on a store that has only qwen still lists all four rows (○ for absent).
    let out = sb.run("", &["key", "list"]);
    assert_eq!(code(&out), 0);
    let stdout = String::from_utf8_lossy(&out.stdout).into_owned();
    let glm_row = stdout
        .lines()
        .find(|l| l.trim_start().starts_with("glm "))
        .expect("glm row present");
    assert!(glm_row.contains('○'), "glm row: {glm_row}");
}
