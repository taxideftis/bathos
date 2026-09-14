//! Integration tests for story M3 — `bathos model limit-record` and the M3
//! extensions of `bathos model status` (limit-event section, credential-path
//! diagnostics, `--banner`).
//!
//! Every test drives the real binary with a tempdir `--state-dir`/HOME, so the
//! ledger (`limit-events.jsonl`) and snapshot (`model-status.json`) contracts
//! are exercised end-to-end. Load-bearing assertion families:
//! - **fail-safe (AC1):** limit-record exits 0 even on empty stdin, bad JSON,
//!   and an unwritable state dir — telemetry must never fail the session.
//! - **no credential material (AC8):** fixture env token values never appear in
//!   stdout/stderr; only their fingerprints do.
//! - **separation (AC9):** limit-record never creates/touches `audit-log.jsonl`.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use tempfile::TempDir;

/// StopFailure payload per the official schema (L1) plus one unknown field —
/// the ledger's `raw` must keep the unknown field verbatim (AC2).
const STOP_PAYLOAD: &str = r#"{
  "session_id": "sess-m3-it",
  "hook_event_name": "StopFailure",
  "error_type": "rate_limit",
  "error_message": "You've hit your session limit",
  "cwd": "/tmp/m3",
  "permission_mode": "default",
  "extra_unknown_field": {"keep": true}
}"#;

/// A fixture credential — its VALUE must never appear in any output; only its
/// sha256 fingerprint (first 8 hex) may.
const SECRET_TOKEN: &str = "SK-M3FIX-auth-token-a91f3c";

fn expected_fp(value: &str) -> String {
    bathos_state::key_store::fingerprint(value)
}

struct Sandbox {
    home: TempDir,
    state: TempDir,
    _root: TempDir,
}

impl Sandbox {
    fn new() -> Self {
        Sandbox {
            home: TempDir::new().unwrap(),
            state: TempDir::new().unwrap(),
            _root: TempDir::new().unwrap(),
        }
    }

    fn state_str(&self) -> String {
        self.state.path().display().to_string()
    }

    fn ledger_path(&self) -> PathBuf {
        self.state.path().join("limit-events.jsonl")
    }

    fn status_path(&self) -> PathBuf {
        self.state.path().join("model-status.json")
    }

    /// Runs the real binary against this sandbox. Credential env vars are
    /// blanked so diagnostics are deterministic regardless of the host machine.
    fn run(&self, stdin: &str, args: &[&str]) -> Output {
        self.run_with(stdin, &[("ANTHROPIC_AUTH_TOKEN", SECRET_TOKEN)], args)
    }

    fn run_with(&self, stdin: &str, envs: &[(&str, &str)], args: &[&str]) -> Output {
        self.run_raw_with(stdin, envs, args, true)
    }

    /// `sandbox_state = true` prepends this sandbox's `--state-dir`; pass false
    /// to supply the flag yourself (the unwritable-state case needs a custom
    /// one, and clap 4 rejects a repeated global flag).
    fn run_raw_with(
        &self,
        stdin: &str,
        envs: &[(&str, &str)],
        args: &[&str],
        sandbox_state: bool,
    ) -> Output {
        let mut cmd = Command::new(env!("CARGO_BIN_EXE_bathos"));
        if sandbox_state {
            cmd.args(["--state-dir", &self.state_str()]);
        }
        cmd.args(args)
            .env("HOME", self.home.path())
            .env("ANTHROPIC_AUTH_TOKEN", "")
            .env("ANTHROPIC_API_KEY", "")
            .env("ANTHROPIC_BASE_URL", "")
            .env("ANTHROPIC_MODEL", "")
            .env("CLAUDE_CODE_OAUTH_TOKEN", "")
            .env("CLAUDE_CODE_USE_BEDROCK", "")
            .env("CLAUDE_CODE_USE_VERTEX", "")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        for (k, v) in envs {
            cmd.env(k, v);
        }
        let mut child = cmd.spawn().expect("spawn bathos");
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

    fn record(&self, payload: &str) -> Output {
        self.run(payload, &["model", "limit-record", "--source", "auto"])
    }

    fn ledger_rows(&self) -> Vec<serde_json::Value> {
        let raw = fs::read_to_string(self.ledger_path()).expect("ledger exists");
        raw.lines()
            .filter(|l| !l.is_empty())
            .map(|l| serde_json::from_str(l).expect("every row parses"))
            .collect()
    }

    fn status_doc(&self) -> serde_json::Value {
        let raw = fs::read_to_string(self.status_path()).expect("status file exists");
        serde_json::from_str(&raw).expect("status file parses")
    }
}

// ── AC1: record roundtrip + fail-safe exit 0 ─────────────────────────────────

#[test]
fn ac1_limit_record_roundtrip_writes_row_and_status() {
    let sb = Sandbox::new();
    // env points at GLM so the row's session_backend reflects record-time detect.
    let out = sb.run_with(
        STOP_PAYLOAD,
        &[
            ("ANTHROPIC_AUTH_TOKEN", SECRET_TOKEN),
            ("ANTHROPIC_BASE_URL", "https://api.z.ai/api/anthropic"),
        ],
        &["model", "limit-record", "--source", "auto"],
    );
    assert_eq!(Sandbox::code(&out), 0, "success exit 0");

    let rows = sb.ledger_rows();
    assert_eq!(rows.len(), 1);
    let row = &rows[0];
    assert_eq!(row["schema"], "bathos/limit-event@1");
    assert_eq!(
        row["source"], "StopFailure",
        "auto infers from hook_event_name"
    );
    assert_eq!(row["session_id"], "sess-m3-it");
    assert_eq!(row["session_backend"], "glm");
    assert_eq!(row["error_type"], "rate_limit");
    assert_eq!(row["error_message"], "You've hit your session limit");
    assert_eq!(row["notification_type"], serde_json::Value::Null);
    assert_eq!(row["classified"], "limit-suspect");
    assert_eq!(
        row["limit_kind_guess"], "session",
        "message contains the official phrase"
    );

    let status = sb.status_doc();
    assert_eq!(
        status["banner_pending"], true,
        "limit-suspect raises the banner latch"
    );
    assert_eq!(status["last_limit_event"]["classified"], "limit-suspect");
    assert_eq!(status["session_backend"], "glm");
}

#[test]
fn ac1_failsafe_exit_0_on_empty_bad_and_unwritable() {
    let sb = Sandbox::new();

    // Empty stdin → skip with a note, exit 0.
    let out = sb.record("   ");
    assert_eq!(Sandbox::code(&out), 0);
    assert!(Sandbox::text(&out).contains("비어 있어"));

    // Malformed JSON → skip with a note, exit 0.
    let out = sb.record("{ definitely not json");
    assert_eq!(Sandbox::code(&out), 0);
    assert!(Sandbox::text(&out).contains("파싱 실패"));

    // State dir path occupied by a FILE → write fails, still exit 0.
    let sb2 = Sandbox::new();
    let blocker = sb2.state.path().join("blocker");
    fs::write(&blocker, "x").unwrap();
    let blocker_str = blocker.display().to_string();
    let out = sb2.run_raw_with(
        STOP_PAYLOAD,
        &[],
        &[
            "--state-dir",
            &blocker_str,
            "model",
            "limit-record",
            "--source",
            "auto",
        ],
        false,
    );
    assert_eq!(Sandbox::code(&out), 0, "unwritable state must still exit 0");
    assert!(Sandbox::text(&out).contains("기록 실패"));

    assert!(
        !sb.ledger_path().exists(),
        "nothing recorded in the first sandbox"
    );
}

// ── AC2: raw verbatim + field-scoping rules ─────────────────────────────────

#[test]
fn ac2_raw_keeps_unknown_payload_fields_verbatim() {
    let sb = Sandbox::new();
    sb.record(STOP_PAYLOAD);
    let row = &sb.ledger_rows()[0];
    assert_eq!(
        row["raw"]["extra_unknown_field"]["keep"], true,
        "fabrication-proof: raw is the whole payload"
    );
    assert_eq!(row["raw"]["permission_mode"], "default");
    assert_eq!(row["error_message"], "You've hit your session limit");
}

// ── AC3: classification drives the banner latch ──────────────────────────────

#[test]
fn ac3_other_error_records_without_raising_banner() {
    let sb = Sandbox::new();
    let payload = r#"{"hook_event_name":"StopFailure","error_type":"server_error","error_message":"upstream exploded"}"#;
    sb.record(payload);
    let row = &sb.ledger_rows()[0];
    assert_eq!(row["classified"], "other", "server_error is never a limit");
    assert_eq!(sb.status_doc()["banner_pending"], false);
}

#[test]
fn ac3_quota_resume_notification_raises_banner() {
    let sb = Sandbox::new();
    let payload =
        r#"{"hook_event_name":"Notification","notification_type":"quota_auto_resume_fired"}"#;
    sb.record(payload);
    let row = &sb.ledger_rows()[0];
    assert_eq!(row["classified"], "quota-resume");
    assert_eq!(
        row["error_type"],
        serde_json::Value::Null,
        "error_type only for StopFailure"
    );
    assert_eq!(row["notification_type"], "quota_auto_resume_fired");
    assert_eq!(sb.status_doc()["banner_pending"], true);
}

// ── AC4: guess stays a guess, unknown is normal ──────────────────────────────

#[test]
fn ac4_guess_unknown_when_no_official_phrase() {
    let sb = Sandbox::new();
    sb.record(r#"{"hook_event_name":"StopFailure","error_type":"rate_limit","error_message":"quota exceeded for org"}"#);
    let row = &sb.ledger_rows()[0];
    assert_eq!(row["classified"], "limit-suspect");
    assert_eq!(row["limit_kind_guess"], "unknown", "no invented variants");
}

// ── AC5/E5: banner lifecycle ─────────────────────────────────────────────────

#[test]
fn ac5_banner_lifecycle_and_e5_more_count() {
    let sb = Sandbox::new();
    sb.record(STOP_PAYLOAD);

    // First exposure: banner A renders, latch drops, shown-at stamps.
    let out = sb.run("", &["model", "status", "--banner"]);
    assert_eq!(Sandbox::code(&out), 0);
    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(stdout.contains("토큰 한도 도달로 추정"), "{stdout}");
    assert!(stdout.contains("error_type=rate_limit"));
    assert!(
        stdout.contains("/usage"),
        "banner must include the verification path"
    );
    assert!(stdout.contains("bathos model switch glm --apply"));
    assert!(stdout.contains("세션 한도로 추정(메시지 문자열 기반 — 확정 아님)"));

    let status = sb.status_doc();
    assert_eq!(status["banner_pending"], false);
    assert!(status["banner_shown_at"].is_string());

    // Nothing pending now → quiet note, still exit 0.
    let out = sb.run("", &["model", "status", "--banner"]);
    assert_eq!(Sandbox::code(&out), 0);
    assert!(String::from_utf8_lossy(&out.stderr).contains("표시 대기 중인 배너가 없습니다"));

    // E5: a re-event re-raises the latch with the LATEST event.
    sb.record(r#"{"hook_event_name":"StopFailure","error_type":"max_output_tokens","error_message":"output cap"}"#);
    assert_eq!(sb.status_doc()["banner_pending"], true);
    let out = sb.run("", &["model", "status", "--banner"]);
    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(
        stdout.contains("max_output_tokens"),
        "latest event is the banner subject"
    );

    // E5 "외 N건": two fresh events before showing → the banner says one more.
    let sb2 = Sandbox::new();
    sb2.record(
        r#"{"hook_event_name":"StopFailure","error_type":"rate_limit","error_message":"x"}"#,
    );
    sb2.record(
        r#"{"hook_event_name":"StopFailure","error_type":"rate_limit","error_message":"y"}"#,
    );
    let out = sb2.run("", &["model", "status", "--banner"]);
    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(stdout.contains("외 1건"), "{stdout}");
}

// ── AC6: lenient reader + corrupt warning once ───────────────────────────────

#[test]
fn ac6_corrupt_line_warns_once_and_fallback_row_loads() {
    let sb = Sandbox::new();
    fs::write(
        sb.ledger_path(),
        concat!(
            r#"{"schema":"bathos/limit-event@1","ts":"2026-09-14T07:00:00Z","source":"StopFailure","error_type":"rate_limit","classified":"limit-suspect","limit_kind_guess":"unknown"}"#,
            "\n{ broken line !!\n",
            r#"{"schema":"bathos/limit-event@1","ts":"2026-09-14T07:05:00Z","source":"Notification","raw_text":"<payload 원문>"}"#,
            "\n"
        ),
    )
    .unwrap();

    let out = sb.run("", &["model", "status"]);
    assert_eq!(Sandbox::code(&out), 0);
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert_eq!(
        stderr.matches("W-LIMIT-CORRUPT").count(),
        1,
        "exactly one warning regardless of position"
    );
    // The human report surfaced the newest row (the fallback one), not a crash.
    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(stdout.contains("최근 한도 이벤트"));
}

// ── AC7: report sections + JSON view ─────────────────────────────────────────

#[test]
fn ac7_status_sections_and_json_schema() {
    let sb = Sandbox::new();
    sb.record(STOP_PAYLOAD);

    let out = sb.run("", &["model", "status"]);
    assert_eq!(Sandbox::code(&out), 0);
    let stdout = String::from_utf8_lossy(&out.stdout);
    for section in [
        "적용 모델 경로",
        "자격증명 진단",
        "키 스토어",
        "최근 한도 이벤트",
        "안내",
    ] {
        assert!(
            stdout.contains(section),
            "missing section {section}: {stdout}"
        );
    }
    assert!(stdout.contains("배너 미표시 한도 이벤트 대기 중"));
    assert!(
        stdout.contains("추정"),
        "guess must surface with the 추정 wording"
    );

    let out = sb.run("", &["model", "status", "--json"]);
    assert_eq!(Sandbox::code(&out), 0);
    let stdout = String::from_utf8_lossy(&out.stdout);
    let doc: serde_json::Value = serde_json::from_str(stdout.trim()).expect("single JSON document");
    assert_eq!(
        doc["schema"], "bathos/model-status-view@1",
        "existing schema id unchanged"
    );
    assert!(doc["credential_diagnostics"].is_array());
    assert_eq!(doc["banner_pending"], true);
    assert!(doc["last_limit_event"].is_object());
    assert!(doc["limit_recent"].is_array());
    let winner = doc["credential_diagnostics"]
        .as_array()
        .unwrap()
        .iter()
        .find(|c| c["winner"] == true)
        .expect("exactly one winner row exists");
    assert_eq!(
        winner["rank"], 2,
        "AUTH_TOKEN fixture is the configured winner"
    );
}

// ── AC8: credential values never printed — fingerprints only ────────────────

#[test]
fn ac8_credential_value_never_printed_fingerprint_is() {
    let sb = Sandbox::new();
    let out = sb.run("", &["model", "status"]);
    assert_eq!(Sandbox::code(&out), 0);

    let combined = Sandbox::text(&out);
    let fp = expected_fp(SECRET_TOKEN);
    assert!(
        combined.contains(&format!("설정됨(지문 {fp})")),
        "fingerprint shown: {combined}"
    );
    assert!(combined.contains("← 현재 이 경로가 우선(공식 우선순위 2위)"));
    assert!(!combined.contains(SECRET_TOKEN), "VALUE LEAKED: {combined}");

    // The whole sandbox tree (state files included) carries no value either.
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
    assert!(
        files_containing(sb.state.path(), SECRET_TOKEN).is_empty(),
        "token must not reach any state file"
    );
}

// ── AC9: limit-record stays out of the audit chain ──────────────────────────

#[test]
fn ac9_limit_record_does_not_touch_audit_log() {
    let sb = Sandbox::new();
    sb.record(STOP_PAYLOAD);
    sb.record(STOP_PAYLOAD);
    assert!(
        !sb.state.path().join("audit-log.jsonl").exists(),
        "observability data must never enter the audit chain"
    );
}

// ── AC10: concurrent appends all land intact ─────────────────────────────────

#[test]
fn ac10_concurrent_appends_stay_atomic_per_line() {
    let sb = Sandbox::new();
    let mut children = Vec::new();
    for i in 0..8 {
        let payload = format!(
            r#"{{"hook_event_name":"StopFailure","error_type":"rate_limit","error_message":"writer {i}"}}"#
        );
        let mut cmd = Command::new(env!("CARGO_BIN_EXE_bathos"));
        cmd.args(["--state-dir", &sb.state_str()])
            .args(["model", "limit-record", "--source", "auto"])
            .env("HOME", sb.home.path())
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        let mut child = cmd.spawn().expect("spawn writer");
        child
            .stdin
            .as_mut()
            .expect("piped")
            .write_all(payload.as_bytes())
            .expect("stdin");
        children.push(child);
    }
    for child in children {
        let out = child.wait_with_output().expect("wait writer");
        assert_eq!(
            out.status.code(),
            Some(0),
            "every writer exits 0 (fail-safe)"
        );
    }
    let rows = sb.ledger_rows();
    assert_eq!(rows.len(), 8, "no torn lines — every append landed whole");
}

// ── source flag variants + debug echo ────────────────────────────────────────

#[test]
fn source_flag_variants_and_unknown_fallback() {
    let sb = Sandbox::new();
    let out = sb.run(
        STOP_PAYLOAD,
        &["model", "limit-record", "--source", "PostModelSwitch"],
    );
    assert_eq!(Sandbox::code(&out), 0);
    assert_eq!(sb.ledger_rows()[0]["source"], "PostModelSwitch");
    assert_eq!(sb.ledger_rows()[0]["classified"], "model-switch");

    let out = sb.run(
        STOP_PAYLOAD,
        &["model", "limit-record", "--source", "not-a-source"],
    );
    assert_eq!(Sandbox::code(&out), 0, "unknown source value still exits 0");
    assert!(Sandbox::text(&out).contains("알 수 없는 --source"));
    assert_eq!(sb.ledger_rows()[1]["source"], "manual");

    // Default (no --source) = auto.
    let out = sb.run(STOP_PAYLOAD, &["model", "limit-record"]);
    assert_eq!(Sandbox::code(&out), 0);
    assert_eq!(sb.ledger_rows()[2]["source"], "StopFailure");
}

#[test]
fn bathos_limit_debug_echoes_classification_to_stderr_only() {
    let sb = Sandbox::new();
    let out = sb.run_with(
        STOP_PAYLOAD,
        &[
            ("BATHOS_LIMIT_DEBUG", "1"),
            ("ANTHROPIC_AUTH_TOKEN", SECRET_TOKEN),
        ],
        &["model", "limit-record"],
    );
    assert_eq!(Sandbox::code(&out), 0);
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(stderr.contains("[debug] source=StopFailure"));
    assert!(stderr.contains("[debug] classified=limit-suspect"));
    assert!(stderr.contains("[debug] limit_kind_guess=session"));
    assert!(
        !String::from_utf8_lossy(&out.stdout).contains("[debug]"),
        "debug echo is stderr-only"
    );

    // Without the flag: no echo.
    let sb2 = Sandbox::new();
    let out = sb2.record(STOP_PAYLOAD);
    assert!(!Sandbox::text(&out).contains("[debug]"));
}
