#!/usr/bin/env bash
# =============================================================================
# BATHOS  scripts/_test-bathos-panes.sh  —  headless tmux smoke test (T7)
#
# Verifies only the core contracts of `bathos-panes.sh`, with no real user present:
#   1) does the __control subcommand take a "confirm <W> <VERDICT> <reason>" input
#      and really create inbox/confirm-<W>-*.txt (contents included)?
#   2) does the __input subcommand honour the same contract (per-wave input pane)?
#   3) does free-form input land in feedback-*.md?
#   4) does up's preflight (E-TMUX-ABSENT/E-BATHOS-ABSENT) really return the exact exit code?
#
# SKIPs (exit 0) instead of dying in CI environments without tmux — this project's
# fail-safe convention (like codex-adapter/hooks/_test-codex-hooks.sh: an absent tool is not a failure).
#
# Run: bash scripts/_test-bathos-panes.sh
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PANES_SH="$SCRIPT_DIR/bathos-panes.sh"

PASS=0
FAIL=0

ok()   { PASS=$((PASS+1)); printf '  ✓ %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  ✗ %s\n' "$*" >&2; }

if ! command -v tmux >/dev/null 2>&1; then
  printf '[SKIP] tmux 미설치 — 헤드리스 스모크를 건너뜁니다(CI fail-safe, exit 0)\n'
  exit 0
fi

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t bathospanes)"
ALL_SESSIONS=""
cleanup() {
  for s in $ALL_SESSIONS; do
    tmux kill-session -t "$s" >/dev/null 2>&1 || true
  done
  # WORK is a mktemp-created scratch dir under the OS temp root — removing it (not a
  # project path) is the intended teardown, not the "careful" destructive-command class.
  rm -rf "$WORK" >/dev/null 2>&1 || true
}
trap cleanup EXIT

AGENT_TEAM="$WORK/.agent-team"
mkdir -p "$AGENT_TEAM/_state/panes/inbox"
cat > "$AGENT_TEAM/_state/manifest.json" <<'JSON'
{"project_id":"bathos-test-panes","codename":"BATHOS-TEST","current_level":3,"status":"active","lang":"ko","created":"2026-07-16T00:00:00Z"}
JSON

SESSION="test-bathos-panes-$$"
ALL_SESSIONS="$ALL_SESSIONS $SESSION"

printf '== T7a: __control confirm → inbox 파일 생성 ==\n'
# The pane runs __control directly as its command (not typed into an interactive login
# shell) — this keeps the test independent of the operator's shell rc/startup behavior.
tmux new-session -d -s "$SESSION" -x 200 -y 50 "'$PANES_SH' __control '$AGENT_TEAM'"
sleep 1
tmux send-keys -t "$SESSION" "confirm W5 PASS 사유동작확인" Enter
sleep 1

OUT="$(tmux capture-pane -p -t "$SESSION" 2>/dev/null || true)"
if printf '%s' "$OUT" | grep -q "inbox 기록됨"; then
  ok "pane echo에 'inbox 기록됨' 출력됨"
else
  bad "pane echo에 'inbox 기록됨' 누락: $OUT"
fi

CONFIRM_FILE="$(find "$AGENT_TEAM/_state/panes/inbox" -name 'confirm-W5-*.txt' 2>/dev/null | head -1)"
if [ -n "$CONFIRM_FILE" ] && [ -f "$CONFIRM_FILE" ]; then
  ok "confirm-W5-*.txt 파일 생성됨: $(basename "$CONFIRM_FILE")"
  CONTENT="$(cat "$CONFIRM_FILE")"
  if printf '%s' "$CONTENT" | grep -q "^PASS"; then
    ok "파일 내용 첫 필드=PASS"
  else
    bad "파일 내용 첫 필드 불일치: $CONTENT"
  fi
  if printf '%s' "$CONTENT" | grep -q "사유동작확인"; then
    ok "파일 내용에 사유 텍스트 포함"
  else
    bad "파일 내용에 사유 텍스트 누락: $CONTENT"
  fi
else
  bad "confirm-W5-*.txt 파일이 생성되지 않음"
fi

tmux kill-session -t "$SESSION" >/dev/null 2>&1 || true

printf '\n== T7b: __input(웨이브별 입력 pane) — 자유서술은 feedback-*.md ==\n'
SESSION2="test-bathos-panes-input-$$"
ALL_SESSIONS="$ALL_SESSIONS $SESSION2"
tmux new-session -d -s "$SESSION2" -x 200 -y 50 "'$PANES_SH' __input '$AGENT_TEAM' 'W3'"
sleep 1
tmux send-keys -t "$SESSION2" "이건 자유 서술 피드백입니다" Enter
sleep 1

FEEDBACK_FILE="$(find "$AGENT_TEAM/_state/panes/inbox" -name 'feedback-W3-*.md' 2>/dev/null | head -1)"
if [ -n "$FEEDBACK_FILE" ] && [ -f "$FEEDBACK_FILE" ]; then
  ok "feedback-W3-*.md 파일 생성됨: $(basename "$FEEDBACK_FILE")"
  if grep -q "자유 서술 피드백" "$FEEDBACK_FILE"; then
    ok "feedback 파일 내용에 원문 포함"
  else
    bad "feedback 파일 내용 불일치: $(cat "$FEEDBACK_FILE")"
  fi
else
  bad "feedback-W3-*.md 파일이 생성되지 않음"
fi

tmux kill-session -t "$SESSION2" >/dev/null 2>&1 || true

printf '\n== T7c: __input 웨이브별 verdict 키워드도 confirm-*.txt로 ==\n'
SESSION3="test-bathos-panes-input2-$$"
ALL_SESSIONS="$ALL_SESSIONS $SESSION3"
tmux new-session -d -s "$SESSION3" -x 200 -y 50 "'$PANES_SH' __input '$AGENT_TEAM' 'W6'"
sleep 1
tmux send-keys -t "$SESSION3" "STOP 긴급" Enter
sleep 1

STOP_FILE="$(find "$AGENT_TEAM/_state/panes/inbox" -name 'confirm-W6-*.txt' 2>/dev/null | head -1)"
if [ -n "$STOP_FILE" ]; then
  ok "confirm-W6-*.txt(STOP) 생성됨: $(basename "$STOP_FILE")"
else
  bad "confirm-W6-*.txt(STOP)이 생성되지 않음"
fi
tmux kill-session -t "$SESSION3" >/dev/null 2>&1 || true

printf '\n== T8-lite: up 프리플라이트 — E-BATHOS-ABSENT(exit 4) ==\n'
EMPTY_PROJECT="$WORK/empty-project"
mkdir -p "$EMPTY_PROJECT"
# Keep tmux's directory on PATH (we must trigger E-BATHOS-ABSENT, not E-TMUX-ABSENT),
# but narrow PATH so the bathos binary is nowhere to be found (BATHOS_BIN cleared too).
TMUX_DIR="$(dirname "$(command -v tmux)")"
if env -i PATH="/usr/bin:/bin:$TMUX_DIR" BATHOS_PANES_NO_ATTACH=1 \
     "$PANES_SH" up --project "$EMPTY_PROJECT" >/tmp/bathos-panes-preflight.$$ 2>&1; then
  EXIT_CODE=0
else
  EXIT_CODE=$?
fi
if [ "$EXIT_CODE" = "4" ]; then
  ok "bathos 바이너리 없는 프로젝트에서 up → exit 4(E-BATHOS-ABSENT)"
else
  bad "기대 exit 4, 실제 exit $EXIT_CODE ($(cat /tmp/bathos-panes-preflight.$$ 2>/dev/null))"
fi
rm -f "/tmp/bathos-panes-preflight.$$" 2>/dev/null || true

printf '\n== T7d: PANES-002 회귀 — 경로 이탈(../) 시도한 wave 토큰이 inbox 밖에 쓰지 못함 ==\n'
EVIL_TARGET="$WORK/evil-outside-inbox"
mkdir -p "$EVIL_TARGET"
SESSION4="test-bathos-panes-traversal-$$"
ALL_SESSIONS="$ALL_SESSIONS $SESSION4"
# The malicious "wave" token below is exactly what a manipulated `--waves`/auto-detected wave id
# would look like reaching `__input` positionally (§B3.1) — a real attack does not need shell
# metacharacters here, just enough `../` segments to walk out of `_state/panes/inbox/`.
tmux new-session -d -s "$SESSION4" -x 200 -y 50 \
  "'$PANES_SH' __input '$AGENT_TEAM' '../../../../../../$EVIL_TARGET'"
sleep 1
tmux send-keys -t "$SESSION4" "PASS should-not-escape" Enter
sleep 1
if find "$EVIL_TARGET" -type f 2>/dev/null | grep -q .; then
  bad "PANES-002 회귀: evil target 디렉터리에 파일이 생성됨(경로 이탈 발생)"
else
  ok "evil target 디렉터리는 비어 있음(경로 이탈 없음)"
fi
INBOX_TRAVERSAL_FILE="$(find "$AGENT_TEAM/_state/panes/inbox" -name 'confirm-*evil-outside-inbox*.txt' 2>/dev/null | head -1)"
if [ -n "$INBOX_TRAVERSAL_FILE" ]; then
  ok "sanitize된 이름으로 inbox 안에만 기록됨: $(basename "$INBOX_TRAVERSAL_FILE")"
else
  bad "sanitize된 confirm 파일을 inbox에서 찾지 못함"
fi
tmux kill-session -t "$SESSION4" >/dev/null 2>&1 || true

printf '\n== T7e: PANES-001 회귀 — 작은따옴표가 포함된 --project 경로에서도 인젝션 없이 정상 기동 ==\n'
find_release_bathos() {
  local repo_root
  repo_root="$(cd "$SCRIPT_DIR/.." && pwd)"
  for cand in "$repo_root/core/target/release/bathos" "$repo_root/core/target/debug/bathos"; do
    if [ -x "$cand" ]; then printf '%s' "$cand"; return 0; fi
  done
  return 1
}
BATHOS_FOR_T7E="$(find_release_bathos || true)"
if [ -z "$BATHOS_FOR_T7E" ]; then
  printf '[SKIP] bathos 바이너리 미빌드 — T7e 생략(cargo build --release 후 재실행 권장)\n'
else
  CANARY="$WORK/PANES001_CANARY"
  rm -f "$CANARY"
  # This directory name is exactly the shape of the PANES-001 PoC in the security finding
  # (`.agent-team/10-security/panes-model-findings.json` PANES-001 `evidence`): a single quote
  # followed by a shell command, followed by a re-opening quote. On a filesystem this is just
  # an unusual (but entirely legal) directory name — `mkdir` never interprets it as shell. The
  # only question this test answers is whether `bathos-panes.sh` does.
  QUOTE_PROJECT="$WORK/evil'; touch $CANARY; echo '"
  mkdir -p "$QUOTE_PROJECT/.agent-team/_state"
  cat > "$QUOTE_PROJECT/.agent-team/_state/manifest.json" <<'JSON'
{"project_id":"quote-test","codename":"T","current_level":3,"status":"active","lang":"ko","created":"2026-07-16T00:00:00Z"}
JSON
  SESSION5="test-bathos-panes-quote-$$"
  ALL_SESSIONS="$ALL_SESSIONS $SESSION5"
  # Before the PANES-001 fix, this --project value broke out of the `'$AGENT_TEAM'` pane
  # command interpolation and ran `touch $CANARY` as a real shell command in the spawned pane's
  # shell. After the fix it must be treated as an inert, single opaque argument end-to-end.
  BATHOS_BIN="$BATHOS_FOR_T7E" BATHOS_PANES_NO_ATTACH=1 \
    "$PANES_SH" up --project "$QUOTE_PROJECT" --waves "W5" --interval 2 \
    >/tmp/bathos-panes-quote.$$ 2>&1
  sleep 1
  if [ -f "$CANARY" ]; then
    bad "PANES-001 회귀: 작은따옴표 경로로 인젝션 발생(canary 파일 생성됨)"
    rm -f "$CANARY"
  else
    ok "작은따옴표 경로에서도 인젝션 없음(canary 미생성)"
  fi
  QUOTE_SESSION="$(tmux ls 2>/dev/null | grep '^bathos-quote-test' | cut -d: -f1 | head -1)"
  if [ -n "$QUOTE_SESSION" ]; then
    ALL_SESSIONS="$ALL_SESSIONS $QUOTE_SESSION"
    PANE_COUNT="$(tmux list-panes -t "$QUOTE_SESSION" 2>/dev/null | wc -l | tr -d ' ')"
    if [ "${PANE_COUNT:-0}" -ge 2 ]; then
      ok "작은따옴표 경로에서도 세션이 정상 기동됨(panes=$PANE_COUNT)"
    else
      bad "세션은 생겼으나 pane 수가 예상보다 적음(panes=${PANE_COUNT:-0})"
    fi
    tmux kill-session -t "$QUOTE_SESSION" >/dev/null 2>&1 || true
  else
    bad "작은따옴표 경로에서 세션이 생성되지 않음: $(cat /tmp/bathos-panes-quote.$$ 2>/dev/null)"
  fi
  rm -f "/tmp/bathos-panes-quote.$$" 2>/dev/null || true
fi

printf '\n=========================================\n'
printf '결과: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
if [ "$FAIL" -eq 0 ]; then
  printf '전체 통과\n'
  exit 0
else
  printf '실패 항목 있음\n' >&2
  exit 1
fi
