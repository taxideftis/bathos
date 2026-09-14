//! `limit_events` — instrumentation ledger for model limit events
//! (`_state/limit-events.jsonl`, schema `bathos/limit-event@1`) + the pure
//! classification/guess/banner-render logic behind `bathos model limit-record`
//! and `bathos model status --banner` (story M3, w7 design §3/§6/§11).
//!
//! **The honest premise this module must not betray:** session vs weekly limits
//! CANNOT be distinguished from `error_type` (officially confirmed, L17) and
//! there is no machine-readable remaining-quota path (L18). So this module never
//! predicts a limit — it preserves the `error_message` verbatim inside `raw`
//! (fabrication-proof) and marks any session/weekly reading as a *guess* whose
//! field name says so (`limit_kind_guess`). Inventing a sharper distinction here
//! is exactly the failure mode this project guards against.
//!
//! **Separation from the audit chain (AC9):** this ledger is fail-safe telemetry
//! that must be writable even when the binary is absent (hook fallback rows);
//! the audit log is a keyed HMAC chain. Different integrity models, different
//! consumers — `limit-record` never touches `audit-log.jsonl`.
//!
//! **Lenient reading (AC6/E4):** rows written by other writers (the jq fallback
//! minimal form, past Partial writes) must never block `model status`. Unknown
//! JSON keys are ignored, missing fields default, and only truly unparseable
//! lines are skipped with a `W-LIMIT-CORRUPT` warning.

use crate::model_plan::SessionBackend;
use crate::model_status::{self, ModelStatus};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::fs::OpenOptions;
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::Path;

pub const LIMIT_EVENTS_SCHEMA: &str = "bathos/limit-event@1";
pub const LIMIT_EVENTS_FILE: &str = "limit-events.jsonl";

// ── vocabulary (fixed by the design's classification table — no new values) ──

pub const SOURCE_STOP_FAILURE: &str = "StopFailure";
pub const SOURCE_NOTIFICATION: &str = "Notification";
pub const SOURCE_PRE_MODEL_SWITCH: &str = "PreModelSwitch";
pub const SOURCE_POST_MODEL_SWITCH: &str = "PostModelSwitch";
pub const SOURCE_MANUAL: &str = "manual";

pub const CLASSIFIED_LIMIT_SUSPECT: &str = "limit-suspect";
pub const CLASSIFIED_QUOTA_RESUME: &str = "quota-resume";
pub const CLASSIFIED_MODEL_SWITCH: &str = "model-switch";
pub const CLASSIFIED_OTHER: &str = "other";

pub const GUESS_SESSION: &str = "session";
pub const GUESS_WEEKLY: &str = "weekly";
pub const GUESS_UNKNOWN: &str = "unknown";

/// The only two StopFailure error types the design maps to `limit-suspect`.
/// All 12 official error types are pinned by tests; these two are the banner
/// targets, the other ten are recorded as `other` (never presented as limits).
pub const LIMIT_ERROR_TYPES: [&str; 2] = ["rate_limit", "max_output_tokens"];

/// The three officially confirmed quota notification types (L3). Their payload
/// schema is undocumented — `raw` preservation is the only treatment.
pub const QUOTA_RESUME_TYPES: [&str; 3] = [
    "quota_auto_resume_fired",
    "quota_auto_resume_stale",
    "quota_auto_resume_disabled",
];

/// Conservative classification table (design §3.1 — frozen; inventing rows here
/// is a story-fail). Everything unknown lands in `other`, which is record-only:
/// the UI must never present an unknown as a limit event.
pub fn classify(
    source: &str,
    error_type: Option<&str>,
    notification_type: Option<&str>,
) -> &'static str {
    match source {
        SOURCE_STOP_FAILURE => match error_type {
            Some(t) if LIMIT_ERROR_TYPES.contains(&t) => CLASSIFIED_LIMIT_SUSPECT,
            _ => CLASSIFIED_OTHER,
        },
        SOURCE_NOTIFICATION => match notification_type {
            Some(t) if QUOTA_RESUME_TYPES.contains(&t) => CLASSIFIED_QUOTA_RESUME,
            _ => CLASSIFIED_OTHER,
        },
        SOURCE_PRE_MODEL_SWITCH | SOURCE_POST_MODEL_SWITCH => CLASSIFIED_MODEL_SWITCH,
        _ => CLASSIFIED_OTHER,
    }
}

/// Session/weekly guess from the message string only (L17: the two officially
/// confirmed phrases are the ONLY match targets — no variant invention).
/// `unknown` is the *normal* outcome, not an error: whether these strings even
/// appear in real `error_message`s is unconfirmed (V-3).
pub fn guess_limit_kind(error_message: Option<&str>) -> &'static str {
    let Some(msg) = error_message else {
        return GUESS_UNKNOWN;
    };
    let lower = msg.to_lowercase();
    if lower.contains("session limit") {
        GUESS_SESSION
    } else if lower.contains("weekly limit") {
        GUESS_WEEKLY
    } else {
        GUESS_UNKNOWN
    }
}

/// UI suffix forcing the "guess" reading. Empty string for `unknown` — the
/// caller must omit the session/weekly mention entirely rather than guess.
pub fn guess_display(guess: Option<&str>) -> &'static str {
    match guess {
        Some(GUESS_SESSION) => "세션 한도로 추정(메시지 문자열 기반 — 확정 아님)",
        Some(GUESS_WEEKLY) => "주간 한도로 추정(메시지 문자열 기반 — 확정 아님)",
        _ => "",
    }
}

/// Only these two classes raise `banner_pending` (AC3: model-switch events are
/// recorded without a banner; `other` is never banner material).
pub fn banner_worthy(classified: Option<&str>) -> bool {
    matches!(
        classified,
        Some(CLASSIFIED_LIMIT_SUSPECT) | Some(CLASSIFIED_QUOTA_RESUME)
    )
}

/// Infer the source from the payload when `--source auto` (the hook default).
/// Returns `(source, reason)` — the reason is for `BATHOS_LIMIT_DEBUG` echo so
/// M8 can later confirm which payload shape fired which rule. Falls back to
/// `manual` when nothing in the payload is evidence; it never guesses wildly.
pub fn auto_source(payload: &Value) -> (String, String) {
    match payload.get("hook_event_name").and_then(|v| v.as_str()) {
        Some(SOURCE_STOP_FAILURE) => (SOURCE_STOP_FAILURE.into(), "hook_event_name".into()),
        Some(SOURCE_NOTIFICATION) => (SOURCE_NOTIFICATION.into(), "hook_event_name".into()),
        Some(SOURCE_PRE_MODEL_SWITCH) => (SOURCE_PRE_MODEL_SWITCH.into(), "hook_event_name".into()),
        Some(SOURCE_POST_MODEL_SWITCH) => {
            (SOURCE_POST_MODEL_SWITCH.into(), "hook_event_name".into())
        }
        _ => {
            if payload.get("error_type").is_some() {
                // error_type is a StopFailure-only field in the official schema (L1).
                (
                    SOURCE_STOP_FAILURE.into(),
                    "error_type 필드 존재(StopFailure 전용)".into(),
                )
            } else if payload.get("notification_type").is_some() {
                (
                    SOURCE_NOTIFICATION.into(),
                    "notification_type 필드 존재".into(),
                )
            } else {
                (SOURCE_MANUAL.into(), "판별 근거 없음 — manual 폴백".into())
            }
        }
    }
}

fn str_field(payload: &Value, key: &str) -> Option<String> {
    payload.get(key).and_then(|v| v.as_str()).map(String::from)
}

/// Build one ledger row from a raw hook payload. Field-per-source rules are
/// AC2's, applied literally: `error_type` only for StopFailure,
/// `notification_type` only for Notification, everything else null — and `raw`
/// keeps the payload verbatim so later re-analysis never depends on this
/// version's field guesses.
pub fn build_event(
    payload: &Value,
    source: &str,
    session_backend: &str,
    ts: DateTime<Utc>,
) -> LimitEvent {
    let error_type = if source == SOURCE_STOP_FAILURE {
        str_field(payload, "error_type")
    } else {
        None
    };
    let notification_type = if source == SOURCE_NOTIFICATION {
        str_field(payload, "notification_type")
    } else {
        None
    };
    let error_message = str_field(payload, "error_message");
    let classified = classify(source, error_type.as_deref(), notification_type.as_deref());
    let limit_kind_guess = guess_limit_kind(error_message.as_deref());
    LimitEvent {
        schema: LIMIT_EVENTS_SCHEMA.into(),
        ts: Some(ts),
        source: source.into(),
        session_id: str_field(payload, "session_id"),
        session_backend: Some(session_backend.into()),
        error_type,
        error_message,
        notification_type,
        classified: Some(classified.into()),
        limit_kind_guess: Some(limit_kind_guess.into()),
        raw: Some(payload.clone()),
        raw_text: None,
    }
}

/// Apply one recorded event to the live-status snapshot (AC5). Pure so tests
/// drive the lifecycle directly: `banner_pending` rises for banner-worthy
/// classes only and is never lowered here — only `status --banner` lowers it.
/// Re-events while pending keep pending true (E5: banner shows latest + "N more").
pub fn apply_to_status(
    status: &mut ModelStatus,
    event: &LimitEvent,
    measured: SessionBackend,
    now: DateTime<Utc>,
) {
    status.updated = now;
    status.session_backend = measured;
    status.last_limit_event = Some(model_status::LastLimitEvent {
        ts: Some(event.ts.unwrap_or(now)),
        source: event.source.clone(),
        error_type: event.error_type.clone(),
        classified: event.classified.clone(),
        limit_kind_guess: event.limit_kind_guess.clone(),
    });
    if banner_worthy(event.classified.as_deref()) {
        status.banner_pending = true;
    }
}

/// Count banner-worthy events in the tail newer than the last banner display —
/// the "외 N건" figure for E5. `since=None` (never shown) counts the whole tail.
/// Tail-bounded by construction: older events outside the window simply don't
/// inflate the count (an honest approximation for a display-only number).
pub fn count_banner_events_since(events: &[LimitEvent], since: Option<DateTime<Utc>>) -> usize {
    events
        .iter()
        .filter(|e| {
            banner_worthy(e.classified.as_deref())
                && match (e.ts, since) {
                    (Some(ts), Some(since_ts)) => ts > since_ts,
                    _ => true,
                }
        })
        .count()
}

// ── persistence ──────────────────────────────────────────────────────────────

/// Append one row via a single O_APPEND write (<4KB → POSIX-atomic on local
/// filesystems), so concurrent hook writers need no lock (E10 — same reasoning
/// as `model_plan::save`'s no-lock decision). Returns the file size after the
/// append so the caller can emit the 10MB growth warning (AC10 — rotation is
/// out of scope, deletion is a user decision).
pub fn append_event(state_dir: &Path, event: &LimitEvent) -> std::io::Result<u64> {
    std::fs::create_dir_all(state_dir)?;
    let mut line = serde_json::to_string(event).map_err(std::io::Error::other)?;
    line.push('\n');
    let path = state_dir.join(LIMIT_EVENTS_FILE);
    let mut f = OpenOptions::new().create(true).append(true).open(&path)?;
    f.write_all(line.as_bytes())?;
    Ok(f.metadata()?.len())
}

/// Initial tail window for [`load_recent`]. Status needs only the newest few
/// rows; starting small keeps the p95 <200ms @1MB NFR trivially true, and the
/// window grows only when the requested row count demands it.
// ponytail: tail read starts at 64KB and quadruples until n rows are visible;
// a corrupt-line audit of the WHOLE file is explicitly out of scope — trigger:
// a bug report where an old corrupt line (>window back) misleads status output.
const TAIL_WINDOW_BYTES: u64 = 64 * 1024;

/// How many newest rows `model status` inspects. Enough for the "최근 한도
/// 이벤트" line, the E5 "외 N건" count, and human inspection — never a full scan.
// ponytail: status reads only the newest 20 rows (banner counts are tail-bounded
// and may under-count on huge backlogs) — trigger: a user-visible wrong "외 N건"
// figure or a need for ledger-wide statistics (that would be a new command).
pub const STATUS_TAIL_ROWS: usize = 20;

/// Ledger size above which status/record emit a non-blocking growth warning.
// ponytail: 10MB soft cap only warns (no rotation, no truncation — deletion is
// a user decision per AC10) — trigger: real ledgers crossing the cap in normal
// use, which would mean the <2KB/row budget is broken and rotation is needed.
pub const SIZE_WARN_BYTES: u64 = 10 * 1024 * 1024;

/// Read the newest `n` rows, oldest-first, plus the number of unparseable rows
/// seen in the examined tail (caller emits `W-LIMIT-CORRUPT` once). Absent or
/// empty file → empty vec, zero corrupt. A head fragment cut by the window is
/// dropped (it may be partial); a trailing fragment without a newline (torn
/// final write) IS parsed — JSON decides whether it survives.
pub fn load_recent(path: &Path, n: usize) -> (Vec<LimitEvent>, usize) {
    let len = match std::fs::metadata(path) {
        Ok(m) => m.len(),
        Err(_) => return (Vec::new(), 0),
    };
    if len == 0 || n == 0 {
        return (Vec::new(), 0);
    }

    let mut window = TAIL_WINDOW_BYTES.min(len);
    let lines: Vec<String> = loop {
        let start = len - window;
        let mut bytes: Vec<u8> = Vec::new();
        let ok = std::fs::File::open(path).and_then(|mut f| {
            f.seek(SeekFrom::Start(start))?;
            f.read_to_end(&mut bytes)
        });
        if ok.is_err() {
            return (Vec::new(), 0);
        }
        let mut segments: Vec<&[u8]> = bytes.split(|&b| b == b'\n').collect();
        if start > 0 {
            // First segment is a window-cut fragment of an older line — not a row.
            segments.remove(0);
        }
        let lines: Vec<String> = segments
            .into_iter()
            .filter(|s| !s.is_empty())
            .map(|s| String::from_utf8_lossy(s).into_owned())
            .collect();
        if start == 0 || lines.len() >= n {
            break lines;
        }
        window = (window * 4).min(len);
    };

    let skip = lines.len().saturating_sub(n);
    let mut events = Vec::new();
    let mut corrupt = 0usize;
    for line in &lines[skip..] {
        match serde_json::from_str::<LimitEvent>(line) {
            Ok(e) => events.push(e),
            Err(_) => corrupt += 1,
        }
    }
    (events, corrupt)
}

// ── row shape ────────────────────────────────────────────────────────────────

/// One `limit-events.jsonl` row. Writer-side rows carry every AC2 field (nulls
/// where not applicable) plus the verbatim payload in `raw`. Reader-side the
/// struct is deliberately lenient — every field defaults — so the jq-fallback
/// minimal row (`schema`/`ts`/`source`/`raw_text`, design §3.3) and forward
/// schema growth (`bathos/limit-event@2`) still load instead of corrupting the
/// tail. Values are stored verbatim (not enums) precisely so rows written by
/// other/older writers are reported as-is, never silently rewritten.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LimitEvent {
    #[serde(default = "default_schema")]
    pub schema: String,
    #[serde(default)]
    pub ts: Option<DateTime<Utc>>,
    #[serde(default)]
    pub source: String,
    #[serde(default)]
    pub session_id: Option<String>,
    #[serde(default)]
    pub session_backend: Option<String>,
    #[serde(default)]
    pub error_type: Option<String>,
    #[serde(default)]
    pub error_message: Option<String>,
    #[serde(default)]
    pub notification_type: Option<String>,
    #[serde(default)]
    pub classified: Option<String>,
    #[serde(default)]
    pub limit_kind_guess: Option<String>,
    #[serde(default)]
    pub raw: Option<Value>,
    /// Hook-fallback rows only (binary absent, jq wrote the payload verbatim).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub raw_text: Option<String>,
}

fn default_schema() -> String {
    LIMIT_EVENTS_SCHEMA.into()
}

impl Default for LimitEvent {
    /// All-None row — test scaffolding and serde field-defaults baseline only;
    /// real rows always come from [`build_event`].
    fn default() -> Self {
        LimitEvent {
            schema: default_schema(),
            ts: None,
            source: String::new(),
            session_id: None,
            session_backend: None,
            error_type: None,
            error_message: None,
            notification_type: None,
            classified: None,
            limit_kind_guess: None,
            raw: None,
            raw_text: None,
        }
    }
}

// ── banner rendering (single source of truth — design §11; hooks never        │
//    duplicate this text, they only call `model status --banner`) ─────────────

/// One-line squash of a multi-line payload message for banner display — display
/// only, the ledger keeps the verbatim original in `raw`/`error_message`.
fn clamp_message(msg: &str) -> String {
    let flat = msg.split_whitespace().collect::<Vec<_>>().join(" ");
    let mut out: String = flat.chars().take(100).collect();
    if flat.chars().count() > 100 {
        out.push('…');
    }
    out
}

/// Banner A — "한도 도달 추정". With `limit_kind_guess=unknown` the message line
/// (and any session/weekly wording) is omitted entirely: never pretend to know.
pub fn render_banner_a(
    event: &LimitEvent,
    backend: &str,
    ts_display: &str,
    more_count: usize,
) -> String {
    let error_type = event.error_type.as_deref().unwrap_or("(미기록)");
    let mut out = vec![
        "────────────────────────────────────────────────────────────".to_string(),
        "[BATHOS 모델 상태 알림] 토큰 한도 도달로 추정되는 오류가 발생했습니다".to_string(),
        format!("  · 감지: {SOURCE_STOP_FAILURE} error_type={error_type} ({ts_display})"),
    ];
    if more_count > 0 {
        out.push(format!(
            "  · 외 {more_count}건의 동종 이벤트가 대기 중입니다(최신 1건 표시)"
        ));
    }
    let guess = event.limit_kind_guess.as_deref();
    if matches!(guess, Some(GUESS_SESSION) | Some(GUESS_WEEKLY)) {
        if let Some(msg) = event.error_message.as_deref() {
            out.push(format!(
                "  · 메시지: \"{}\" → {}",
                clamp_message(msg),
                guess_display(guess)
            ));
        }
    }
    out.push(format!("  · 현재 백엔드: {backend}"));
    out.push(
        "  · 정확한 사용량·리셋 시각은 /usage 로 확인하세요(기계 조회 경로는 공식적으로 없음)."
            .to_string(),
    );
    out.push(String::new());
    out.push("  계속 작업하려면 GLM-5.3으로 전환할 수 있습니다 (복사해 실행):".to_string());
    out.push("    /model-switch glm                    # 또는 아래 CLI 직접 실행".to_string());
    out.push("    bathos key set glm                   # (키 미등록 시 1회 — 키는 터미널 stdin으로 입력, 채팅에 붙여넣기 금지)".to_string());
    out.push(
        "    bathos model switch glm --apply      # 전환 계획 확정 → 아래 2줄이 안내됩니다"
            .to_string(),
    );
    out.push("  새 터미널에서:".to_string());
    out.push("    source ~/.bathos/glm.env && source scripts/glm-env.sh".to_string());
    out.push("    claude --continue".to_string());
    out.push("  전환 후 확인:".to_string());
    out.push(
        "    bathos model status                  # 실측 백엔드가 계획과 일치하는지 검증 표시"
            .to_string(),
    );
    out.push(String::new());
    out.push("  한도 해제 후 Claude 복귀:  bathos model switch claude --apply".to_string());
    out.push("────────────────────────────────────────────────────────────".to_string());
    out.join("\n")
}

/// Banner B — quota auto-resume state change. Payload schema is undocumented
/// (L3), so the banner points at the ledger row instead of paraphrasing it.
pub fn render_banner_b(event: &LimitEvent) -> String {
    let ntype = event.notification_type.as_deref().unwrap_or("(미기록)");
    format!(
        "[BATHOS 모델 상태 알림] 쿼터 자동 재개 상태 변화: {ntype}\n\
         \x20 · 세부: payload 원문은 _state/limit-events.jsonl 최신 행 참조\n\
         \x20 · 지금 바로 다른 백엔드로 작업을 잇고 싶다면: /model-switch glm"
    )
}

/// Banner C — model switch detected. Not hook-triggered (AC3: model-switch
/// events raise no banner); rendered only on explicit `status --banner` so the
/// text still has a single Rust source for M6's use.
pub fn render_banner_c() -> String {
    "[BATHOS 모델 상태 알림] 모델 전환이 감지되었습니다. bathos model status 로 현재 백엔드·플랜 정합을 확인하세요.\n\
     \x20 · 참고: env-global 백엔드(GLM 등) 세션에서는 모델 별칭이 해당 프로바이더 모델로 매핑됩니다."
        .to_string()
}

// ── tests ────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;
    use std::collections::BTreeSet;
    use tempfile::TempDir;

    fn ts(y: i32, m: u32, d: u32, h: u32, mi: u32) -> DateTime<Utc> {
        Utc.with_ymd_and_hms(y, m, d, h, mi, 0).unwrap()
    }

    fn stop_failure(error_type: &str, message: &str) -> Value {
        serde_json::json!({
            "session_id": "sess-123",
            "hook_event_name": "StopFailure",
            "error_type": error_type,
            "error_message": message,
            "cwd": "/tmp/x",
            "permission_mode": "default"
        })
    }

    // ── AC3: the full classification table, every branch pinned ─────────────

    #[test]
    fn classification_table_all_12_error_types() {
        let limit = ["rate_limit", "max_output_tokens"];
        let other = [
            "overloaded",
            "authentication_failed",
            "oauth_org_not_allowed",
            "account_on_hold",
            "billing_error",
            "invalid_request",
            "model_not_found",
            "server_error",
            "cloud_credential_error",
            "unknown",
        ];
        for t in limit {
            assert_eq!(
                classify(SOURCE_STOP_FAILURE, Some(t), None),
                CLASSIFIED_LIMIT_SUSPECT,
                "{t}"
            );
        }
        for t in other {
            assert_eq!(
                classify(SOURCE_STOP_FAILURE, Some(t), None),
                CLASSIFIED_OTHER,
                "{t}"
            );
        }
        // An error_type outside the official 12 must NOT be presented as a limit
        // (invention guard) — it degrades to `other`, record-only.
        assert_eq!(
            classify(SOURCE_STOP_FAILURE, Some("brand_new_type"), None),
            CLASSIFIED_OTHER
        );
        assert_eq!(classify(SOURCE_STOP_FAILURE, None, None), CLASSIFIED_OTHER);
    }

    #[test]
    fn classification_table_notifications_pre_post_manual() {
        for t in QUOTA_RESUME_TYPES {
            assert_eq!(
                classify(SOURCE_NOTIFICATION, None, Some(t)),
                CLASSIFIED_QUOTA_RESUME,
                "{t}"
            );
        }
        // Unknown notification types are NOT quota-resume (schema undocumented —
        // the three confirmed types are the whole known set).
        assert_eq!(
            classify(SOURCE_NOTIFICATION, None, Some("something_else")),
            CLASSIFIED_OTHER
        );
        assert_eq!(classify(SOURCE_NOTIFICATION, None, None), CLASSIFIED_OTHER);
        assert_eq!(
            classify(SOURCE_PRE_MODEL_SWITCH, None, None),
            CLASSIFIED_MODEL_SWITCH
        );
        assert_eq!(
            classify(SOURCE_POST_MODEL_SWITCH, None, None),
            CLASSIFIED_MODEL_SWITCH
        );
        assert_eq!(
            classify(SOURCE_MANUAL, Some("rate_limit"), None),
            CLASSIFIED_OTHER
        );
    }

    // ── AC4: guess matching (case-insensitive, two phrases only) ────────────

    #[test]
    fn guess_matches_official_phrases_case_insensitively() {
        assert_eq!(
            guess_limit_kind(Some("You've hit your session limit")),
            GUESS_SESSION
        );
        assert_eq!(
            guess_limit_kind(Some("Weekly Limit reached. Try again Monday.")),
            GUESS_WEEKLY
        );
        assert_eq!(
            guess_limit_kind(Some("quota exceeded for org")),
            GUESS_UNKNOWN
        );
        assert_eq!(guess_limit_kind(Some("")), GUESS_UNKNOWN);
        assert_eq!(guess_limit_kind(None), GUESS_UNKNOWN);
    }

    // ── AC2: exact writer schema — key set is frozen ────────────────────────

    #[test]
    fn build_event_produces_exactly_the_ac2_key_set() {
        let payload = stop_failure("rate_limit", "You've hit your session limit");
        let event = build_event(&payload, SOURCE_STOP_FAILURE, "glm", ts(2026, 9, 14, 7, 31));
        let line = serde_json::to_string(&event).unwrap();
        let v: Value = serde_json::from_str(&line).unwrap();
        let keys: BTreeSet<&str> = v.as_object().unwrap().keys().map(|s| s.as_str()).collect();
        let expected: BTreeSet<&str> = [
            "schema",
            "ts",
            "source",
            "session_id",
            "session_backend",
            "error_type",
            "error_message",
            "notification_type",
            "classified",
            "limit_kind_guess",
            "raw",
        ]
        .into_iter()
        .collect();
        assert_eq!(
            keys, expected,
            "field invention or omission is a story-fail"
        );

        assert_eq!(v["classified"], "limit-suspect");
        assert_eq!(v["limit_kind_guess"], "session");
        assert_eq!(v["session_backend"], "glm");
        assert_eq!(
            v["raw"]["permission_mode"], "default",
            "raw must be the verbatim payload"
        );
        // Source-scoped nulls per AC2.
        let notif = build_event(
            &serde_json::json!({"hook_event_name": "Notification", "notification_type": "quota_auto_resume_fired"}),
            SOURCE_NOTIFICATION,
            "claude",
            ts(2026, 9, 14, 7, 31),
        );
        assert_eq!(notif.error_type, None, "error_type only for StopFailure");
        assert_eq!(
            notif.notification_type.as_deref(),
            Some("quota_auto_resume_fired")
        );
    }

    #[test]
    fn guess_is_recorded_for_any_message_but_display_only_for_limit_suspect() {
        // AC4 wording is unconditional (any error_message is matched); the UI
        // simply only surfaces the guess for limit-suspect rows.
        let event = build_event(
            &stop_failure("server_error", "weekly limit check failed upstream"),
            SOURCE_STOP_FAILURE,
            "claude",
            ts(2026, 9, 14, 0, 0),
        );
        assert_eq!(event.classified.as_deref(), Some(CLASSIFIED_OTHER));
        assert_eq!(event.limit_kind_guess.as_deref(), Some(GUESS_WEEKLY));
        assert!(!banner_worthy(event.classified.as_deref()));
    }

    // ── auto source inference ───────────────────────────────────────────────

    #[test]
    fn auto_source_uses_hook_event_name_then_field_fallbacks() {
        let (s, _) = auto_source(&stop_failure("rate_limit", "x"));
        assert_eq!(s, SOURCE_STOP_FAILURE);
        let (s, _) = auto_source(&serde_json::json!({"hook_event_name": "PostModelSwitch"}));
        assert_eq!(s, SOURCE_POST_MODEL_SWITCH);
        let (s, _) = auto_source(&serde_json::json!({"error_type": "rate_limit"}));
        assert_eq!(s, SOURCE_STOP_FAILURE);
        let (s, _) =
            auto_source(&serde_json::json!({"notification_type": "quota_auto_resume_fired"}));
        assert_eq!(s, SOURCE_NOTIFICATION);
        let (s, _) = auto_source(&serde_json::json!({"unrelated": true}));
        assert_eq!(s, SOURCE_MANUAL);
    }

    // ── AC5: banner_pending lifecycle ───────────────────────────────────────

    #[test]
    fn status_lifecycle_raises_keeps_and_does_not_raise() {
        let now = ts(2026, 9, 14, 8, 0);
        let mut status = ModelStatus::default();

        let limit_ev = build_event(
            &stop_failure("rate_limit", "session limit"),
            SOURCE_STOP_FAILURE,
            "claude",
            now,
        );
        apply_to_status(&mut status, &limit_ev, SessionBackend::Claude, now);
        assert!(status.banner_pending);
        assert_eq!(
            status
                .last_limit_event
                .as_ref()
                .unwrap()
                .classified
                .as_deref(),
            Some("limit-suspect")
        );

        // E5: a second event while pending refreshes the latest and KEEPS pending.
        let later = ts(2026, 9, 14, 8, 5);
        let ev2 = build_event(
            &stop_failure("max_output_tokens", "m"),
            SOURCE_STOP_FAILURE,
            "claude",
            later,
        );
        apply_to_status(&mut status, &ev2, SessionBackend::Claude, later);
        assert!(status.banner_pending);
        assert_eq!(
            status
                .last_limit_event
                .as_ref()
                .unwrap()
                .error_type
                .as_deref(),
            Some("max_output_tokens")
        );

        // model-switch records + refreshes status but never raises pending.
        let switch_ev = build_event(
            &serde_json::json!({"hook_event_name": "PostModelSwitch"}),
            SOURCE_POST_MODEL_SWITCH,
            "glm",
            ts(2026, 9, 14, 8, 10),
        );
        apply_to_status(
            &mut status,
            &switch_ev,
            SessionBackend::Glm,
            ts(2026, 9, 14, 8, 10),
        );
        assert_eq!(status.session_backend, SessionBackend::Glm);
        assert!(
            status.banner_pending,
            "model-switch must not lower a pending banner"
        );
        assert_eq!(
            status
                .last_limit_event
                .as_ref()
                .unwrap()
                .classified
                .as_deref(),
            Some("model-switch")
        );

        // `other` events from a clean state never raise pending.
        let mut clean = ModelStatus::default();
        let other_ev = build_event(
            &stop_failure("server_error", "boom"),
            SOURCE_STOP_FAILURE,
            "claude",
            now,
        );
        apply_to_status(&mut clean, &other_ev, SessionBackend::Claude, now);
        assert!(!clean.banner_pending);
    }

    #[test]
    fn count_banner_events_since_supports_e5_more_count() {
        let events: Vec<LimitEvent> = [
            (CLASSIFIED_LIMIT_SUSPECT, ts(2026, 9, 14, 7, 0)),
            (CLASSIFIED_LIMIT_SUSPECT, ts(2026, 9, 14, 7, 30)),
            (CLASSIFIED_QUOTA_RESUME, ts(2026, 9, 14, 7, 40)),
            (CLASSIFIED_OTHER, ts(2026, 9, 14, 7, 45)),
        ]
        .iter()
        .map(|(c, t)| LimitEvent {
            schema: LIMIT_EVENTS_SCHEMA.into(),
            ts: Some(*t),
            source: SOURCE_STOP_FAILURE.into(),
            classified: Some(c.to_string()),
            ..LimitEvent::default()
        })
        .collect();
        assert_eq!(count_banner_events_since(&events, None), 3);
        // After a banner shown at 7:30, only the 7:40 event is "more".
        assert_eq!(
            count_banner_events_since(&events, Some(ts(2026, 9, 14, 7, 30))),
            1
        );
    }

    // ── persistence: append + lenient tail read ─────────────────────────────

    #[test]
    fn append_then_load_recent_roundtrips_with_trailing_newlines() {
        let dir = TempDir::new().unwrap();
        for i in 0..3 {
            let payload = stop_failure("rate_limit", &format!("msg{i}"));
            let ev = build_event(
                &payload,
                SOURCE_STOP_FAILURE,
                "claude",
                ts(2026, 9, 14, 7, i),
            );
            append_event(dir.path(), &ev).unwrap();
        }
        let path = dir.path().join(LIMIT_EVENTS_FILE);
        let raw = std::fs::read_to_string(&path).unwrap();
        assert_eq!(raw.matches('\n').count(), 3, "one line per event");
        let (events, corrupt) = load_recent(&path, 10);
        assert_eq!(corrupt, 0);
        assert_eq!(events.len(), 3);
        assert_eq!(
            events[0].error_message.as_deref(),
            Some("msg0"),
            "oldest-first"
        );
        assert_eq!(events[2].error_message.as_deref(), Some("msg2"));
    }

    #[test]
    fn lenient_reader_skips_corrupt_and_accepts_fallback_rows() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join(LIMIT_EVENTS_FILE);
        let good = r#"{"schema":"bathos/limit-event@1","ts":"2026-09-14T07:00:00Z","source":"StopFailure","error_type":"rate_limit","classified":"limit-suspect","limit_kind_guess":"unknown","raw":{}}"#;
        let fallback = r#"{"schema":"bathos/limit-event@1","ts":"2026-09-14T07:05:00Z","source":"Notification","raw_text":"<payload 원문>"}"#;
        let garbage = "{ broken json !!";
        std::fs::write(&path, format!("{good}\n{garbage}\n{fallback}\n")).unwrap();

        let (events, corrupt) = load_recent(&path, 10);
        assert_eq!(corrupt, 1, "exactly the garbage line is skipped");
        assert_eq!(events.len(), 2);
        assert_eq!(events[0].error_type.as_deref(), Some("rate_limit"));
        // The designed jq-fallback minimal row must LOAD (not count as corrupt):
        assert_eq!(events[1].source, SOURCE_NOTIFICATION);
        assert_eq!(events[1].raw_text.as_deref(), Some("<payload 원문>"));
        assert_eq!(events[1].classified, None);
    }

    #[test]
    fn tail_read_returns_only_the_newest_n_rows() {
        let dir = TempDir::new().unwrap();
        for i in 0..50 {
            let payload = stop_failure("rate_limit", &format!("m{i}"));
            let ev = build_event(
                &payload,
                SOURCE_STOP_FAILURE,
                "claude",
                ts(2026, 9, 14, 0, i % 60),
            );
            append_event(dir.path(), &ev).unwrap();
        }
        let (events, corrupt) = load_recent(&dir.path().join(LIMIT_EVENTS_FILE), 5);
        assert_eq!(corrupt, 0);
        assert_eq!(events.len(), 5);
        assert_eq!(
            events[4].error_message.as_deref(),
            Some("m49"),
            "newest last"
        );
        assert_eq!(events[0].error_message.as_deref(), Some("m45"));
    }

    #[test]
    fn load_recent_on_absent_and_empty_files_is_empty_not_error() {
        let dir = TempDir::new().unwrap();
        let (events, corrupt) = load_recent(&dir.path().join("nope.jsonl"), 20);
        assert!(events.is_empty() && corrupt == 0);
        let path = dir.path().join(LIMIT_EVENTS_FILE);
        std::fs::write(&path, "").unwrap();
        let (events, corrupt) = load_recent(&path, 20);
        assert!(events.is_empty() && corrupt == 0);
    }

    // ── banner rendering (single text source) ───────────────────────────────

    #[test]
    fn banner_a_shows_guess_line_only_when_known_and_lists_more_count() {
        let known = build_event(
            &stop_failure("rate_limit", "You've hit your session limit, wait 4 hours"),
            SOURCE_STOP_FAILURE,
            "claude",
            ts(2026, 9, 14, 7, 0),
        );
        let text = render_banner_a(&known, "claude", "2026-09-14 16:00 KST", 2);
        assert!(text.contains("토큰 한도 도달로 추정"));
        assert!(text.contains("error_type=rate_limit"));
        assert!(text.contains("외 2건"));
        assert!(text.contains("세션 한도로 추정(메시지 문자열 기반 — 확정 아님)"));
        assert!(text.contains("/usage"));
        assert!(text.contains("bathos model switch glm --apply"));
        assert!(text.contains("bathos model switch claude --apply"));

        // unknown guess → the message line and session/weekly wording are omitted.
        let unknown = build_event(
            &stop_failure("rate_limit", "quota exceeded"),
            SOURCE_STOP_FAILURE,
            "claude",
            ts(2026, 9, 14, 7, 0),
        );
        assert_eq!(unknown.limit_kind_guess.as_deref(), Some(GUESS_UNKNOWN));
        let text = render_banner_a(&unknown, "claude", "t", 0);
        assert!(
            !text.contains("메시지:"),
            "no message line when guessing is impossible"
        );
        assert!(!text.contains("세션"), "no session wording at all");
        assert!(!text.contains("주간"), "no weekly wording at all");
    }

    #[test]
    fn banner_b_and_c_render_with_fixed_guidance() {
        let ev = build_event(
            &serde_json::json!({"hook_event_name": "Notification", "notification_type": "quota_auto_resume_fired"}),
            SOURCE_NOTIFICATION,
            "claude",
            ts(2026, 9, 14, 7, 0),
        );
        let b = render_banner_b(&ev);
        assert!(b.contains("quota_auto_resume_fired"));
        assert!(b.contains("limit-events.jsonl"));
        assert!(b.contains("/model-switch glm"));
        let c = render_banner_c();
        assert!(c.contains("모델 전환이 감지"));
        assert!(c.contains("bathos model status"));
    }

    #[test]
    fn clamp_message_flattens_and_truncates_for_display() {
        assert_eq!(clamp_message("a\n  b\t c"), "a b c");
        let long = "x".repeat(250);
        let clamped = clamp_message(&long);
        assert!(clamped.chars().count() == 101 && clamped.ends_with('…'));
        // The ledger row keeps the verbatim message regardless of display clamp.
        let ev = build_event(
            &stop_failure("rate_limit", &long),
            SOURCE_STOP_FAILURE,
            "claude",
            ts(2026, 9, 14, 0, 0),
        );
        assert_eq!(ev.error_message.as_deref().map(str::len), Some(250));
    }
}
