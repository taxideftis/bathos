#!/usr/bin/env bash
# =============================================================================
# BATHOS  scripts/bathos-panes.sh  —  tmux Wave panel frontend (B3, ADR-D-0007/0009)
#
# Usage:
#   bathos-panes.sh up      [--project <abs-path>] [--waves "W2 W5"] [--interval 2]
#   bathos-panes.sh attach  [--project <abs-path>]
#   bathos-panes.sh down    [--project <abs-path>]
#   bathos-panes.sh status  [--project <abs-path>]
#
# exit 0=success / 1=run failure / 3=E-TMUX-ABSENT / 4=E-BATHOS-ABSENT
#
# What it does: takes one single data source, `bathos inspect vm --format lines`
# (bathos-inspect DashboardVM, ADR-D-0007), renders it into split tmux panes every 2s, and
# streams the confirm/feedback/answer typed in a pane into `_state/panes/inbox/` as files
# (ADR-D-0009). The canonical gate record is still `bathos gate` (the wave flow) — this panel's confirm is a "proposal channel".
#
# Why file-based input: teammates (Claude Code subagents) have no TTY — this script is the
# observe/input tool for **a second terminal that a human opens** (F9). It is also why Paul's
# (the lead's) own session does not auto-start this script: it already occupies its own TTY.
#
# Portability: bash 3.2 compatible (the macOS default) — mapfile / associative arrays (`declare -A`) / `${var,,}` / `&>` are banned.
# No jq — the TSV from `bathos inspect vm --format lines` is consumed with awk/grep/cut/read only.
# Native Windows is unsupported because it has no tmux — use WSL (`scripts/wsl-setup.sh`) or
# `bathos panes --mode tui` (§B4, crossterm) instead.
# =============================================================================
set -uo pipefail

PROG="bathos-panes.sh"
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

say()  { printf '[%s] %s\n' "$PROG" "$*"; }
warn() { printf '[%s] ⚠ %s\n' "$PROG" "$*" >&2; }
err()  { printf '[%s] ✗ %s\n' "$PROG" "$*" >&2; }

# POSIX single-quote escaping (PANES-001 fix). tmux `new-session`/`split-window`'s final
# positional argument is a *shell-command* string — tmux hands it to a brand-new pane shell
# ($SHELL -c "<string>"), which parses it a second time. The naive `'$var'` interpolation this
# script used to do breaks (and lets an attacker or an unlucky path with an apostrophe inject
# arbitrary commands) the instant $var itself contains a single quote. This closes the current
# quote, appends an escaped literal quote, then reopens quoting — the standard POSIX idiom for
# embedding a value inside single quotes safely: `'%s'` with every `'` in the value replaced by
# `'\''`. Always call this on every value interpolated into a pane spawn command below.
sh_quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

# Filename-component sanitizer (PANES-002 fix) — mirrors `bathos-tui/src/inbox.rs`'s
# `sanitize_component` exactly (strip everything but ASCII alnum/-/_ , empty result -> UNKNOWN).
# Applied to every user/caller-supplied token (`$wave`/`$w`/`$w2`/`$qid`) right before it becomes
# part of an inbox file path, so the three independent inbox writers (TUI/tmux/run-role.sh) all
# enforce the same "cannot escape `_state/panes/inbox/`" invariant the design doc requires —
# a component built only from this alphabet cannot contain `/` or `..`, so there is no traversal
# pattern to block, only an allowed character set.
sanitize() {
  local cleaned
  cleaned="$(printf '%s' "$1" | tr -cd 'A-Za-z0-9_-')"
  if [ -z "$cleaned" ]; then
    printf 'UNKNOWN'
  else
    printf '%s' "$cleaned"
  fi
}

# Guards a computed inbox file path against ever landing outside `$inbox` (belt-and-braces —
# PANES-002 defense-in-depth on top of `sanitize`, mirroring `bathos-tui/src/inbox.rs`'s
# `assert!(final_path.starts_with(dir))`). Given a sanitized component this branch should be
# unreachable; it exists anyway so a future change that forgets to sanitize fails loudly
# instead of silently writing outside the inbox. $1=candidate path, $2=inbox dir.
assert_in_inbox() {
  case "$1" in
    "$2"/*) return 0 ;;
    *) err "경로 이탈 감지 — 기록 거부: $1"; return 1 ;;
  esac
}

# Atomically writes a `printf`-formatted record to `$1` via a same-directory `.tmp` + `mv`
# (never a partial/torn file on disk — pre-existing convention) and additionally chmod's it to
# 0600 before the rename (PANES-004 fix): these files carry free-form confirm/feedback/answer
# text that previously inherited the process umask (typically 0644, world-readable), which
# matters on a shared multi-user host even though this is a local single-user tool by default.
# $1=dest path, remaining args are `printf`'s own format + arguments (kept separate, not
# pre-expanded into a string, so this never strips/mangles a trailing newline).
write_atomic600() {
  local dest="$1"
  shift
  printf "$@" > "$dest.tmp" || return 1
  chmod 600 "$dest.tmp" 2>/dev/null || true
  mv "$dest.tmp" "$dest"
}

usage() {
  cat <<'EOF'
사용: bathos-panes.sh <up|attach|down|status> [--project <절대경로>] [--waves "W2 W5"] [--interval 2]

  up      tmux 세션 생성(기존재 시 재사용) + attach
  attach  기존 세션에 attach만
  down    세션 종료 + session.info 정리
  status  세션 존재 여부 + pane 수 출력

옵션:
  --project <DIR>   대상 프로젝트 절대경로(기본: 현재 디렉터리)
  --waves "W2 W5"   렌더할 웨이브(공백 구분). 미지정 시 active|gated 웨이브 자동 선택
                    (없으면 가장 최근 done 웨이브 1개 + 안내)
  --interval N      렌더 루프 주기(초, 기본 2)

exit 0=성공 / 1=실행 실패 / 3=E-TMUX-ABSENT(tmux 미설치) / 4=E-BATHOS-ABSENT(bathos 바이너리 없음)

Windows 네이티브는 tmux가 없어 미지원 — WSL(scripts/wsl-setup.sh) 또는
`bathos panes --mode tui`(crossterm, Windows Terminal 지원)를 대신 쓴다.
EOF
}

# --------------------------------------------------------------------------
# 0. locate the bathos binary (same order as codex-adapter/hooks/pretooluse-gate.sh)
# --------------------------------------------------------------------------
find_bathos_bin() {
  local project="$1"
  if [ -n "${BATHOS_BIN:-}" ] && [ -x "${BATHOS_BIN:-}" ]; then
    printf '%s' "$BATHOS_BIN"
    return 0
  fi
  local cand
  for cand in "$project/core/target/release/bathos" "$project/core/target/debug/bathos"; do
    if [ -x "$cand" ]; then
      printf '%s' "$cand"
      return 0
    fi
  done
  if command -v bathos >/dev/null 2>&1; then
    command -v bathos
    return 0
  fi
  return 1
}

# --------------------------------------------------------------------------
# internal subcommands — invoked by tmux `send-keys` inside a fresh pane shell
# (panes don't inherit this script's function definitions, so each pane re-execs
# this same script file with a hidden `__*` verb).
# --------------------------------------------------------------------------

# renders one wave's `--format lines` output + a best-effort wave-log tail,
# looping every INTERVAL seconds. Never exits on a transient bathos failure
# (shows "[로드 실패] ..." and keeps polling) — a panel that crashes on one bad
# read is worse than one that shows a stale/error frame and keeps going (E9).
__render() {
  local at="$1" wave="$2" interval="$3" bathos_bin="$4"
  while :; do
    local out
    if out="$("$bathos_bin" inspect vm --path "$at" --wave "$wave" --format lines 2>&1)"; then
      :
    else
      out="[로드 실패] $out"
    fi
    printf '\033[2J\033[H'
    printf '=== BATHOS panel — wave %s (%ss 주기, Ctrl-C로 이 pane만 종료) ===\n' "$wave" "$interval"
    render_lines "$out"
    printf -- '--- wave-log.md tail (최선노력 필터: %s) ---\n' "$wave"
    if [ -f "$at/_state/wave-log.md" ]; then
      tail -n 15 "$at/_state/wave-log.md" 2>/dev/null | grep -i "$wave" || printf '(해당 웨이브 언급 없음)\n'
    else
      printf '(wave-log.md 없음)\n'
    fi
    sleep "$interval"
  done
}

# formats the TSV lines protocol (§B1) into human-readable text via awk (no jq).
render_lines() {
  local text="$1"
  printf '%s\n' "$text" | awk -F'\t' '
    $1=="proto" { printf "proto: %s v%s\n", $2, $3; next }
    $1=="meta"  { printf "meta   %-10s %s %s\n", $2, $3, (NF>=4?$4:""); next }
    $1=="warn"  { printf "WARN   [%s] %s\n", $2, $3; next }
    $1=="wave"  { printf "wave   %-4s %-10s %s %-16s roles=%s\n", $2, $3, $4, $5, $6; next }
    $1=="gate"  { printf "gate   %-14s wave=%-4s %-16s %-9s %s %s facilitator=%s\n", $2, $3, $4, $5, $6, $7, $8; next }
    $1=="role"  { printf "role   %-20s %-10s %s wave=%s\n", $2, $3, $4, $5; next }
    $1=="story" { printf "story  %-30s %-14s %s %s\n", $2, $3, $4, $5; next }
    $1=="artifact" { printf "artifact %-40s owner=%-12s %s\n", $2, $3, $4; next }
    $1=="audit" { printf "audit  #%-4s %s %-14s %-20s %s\n", $2, $3, $4, $5, $6; next }
    $1=="chain" { printf "chain  %s %s\n", $2, $3; next }
    { print }
  '
}

# tiny input REPL — `read`s one line at a time; a recognized verdict keyword
# writes a `confirm-<wave>-<ts>.txt`, anything else writes a `feedback-<wave>-<ts>.md`
# (§B2 contract). ts includes `$$` (pid) so same-second submissions never collide (E10).
__input() {
  local at="$1" wave="$2"
  local inbox="$at/_state/panes/inbox"
  mkdir -p "$inbox"
  # PANES-002: sanitize the wave token *once* into the value that actually becomes part of a
  # file path — the unsanitized $wave is still used in the human-facing prompt text below,
  # where it is display-only and never touches the filesystem.
  local wave_safe
  wave_safe="$(sanitize "$wave")"
  printf '[%s 입력] PASS|CONCERNS|FAIL|OK|STOP [사유] 또는 자유 서술(feedback)\n' "$wave"
  while :; do
    printf '%s> ' "$wave"
    IFS= read -r line || break
    [ -z "$line" ] && continue
    local first="${line%% *}"
    local ts
    ts="$(date +%s)-$$"
    case "$first" in
      PASS|CONCERNS|FAIL|OK|STOP)
        local rest="${line#* }"
        [ "$rest" = "$line" ] && rest=""
        local f="$inbox/confirm-$wave_safe-$ts.txt"
        assert_in_inbox "$f" "$inbox" || continue
        write_atomic600 "$f" '%s\t%s\t%s\n' "$first" "$rest" "panel"
        printf '→ inbox 기록됨: %s\n' "$(basename "$f")"
        ;;
      *)
        local f2="$inbox/feedback-$wave_safe-$ts.md"
        assert_in_inbox "$f2" "$inbox" || continue
        write_atomic600 "$f2" '# %s\n' "$line"
        printf '→ inbox 기록됨: %s\n' "$(basename "$f2")"
        ;;
    esac
  done
}

# Paul's control REPL (pane 0) — vocabulary: confirm/feedback/answer/waves/quit.
# Unrecognized input still gets recorded (as feedback-PAUL-*.md) rather than
# silently dropped — an unrecognized command is still user intent worth keeping.
__control() {
  local at="$1"
  local inbox="$at/_state/panes/inbox"
  mkdir -p "$inbox"
  printf '[Paul 제어] 명령: confirm <W> <VERDICT> [사유] | feedback <W> <메시지> | answer <qid> <메시지> | waves | quit\n'
  while :; do
    printf 'paul> '
    IFS= read -r line || break
    [ -z "$line" ] && continue
    local ts
    ts="$(date +%s)-$$"
    # shellcheck disable=SC2086 (word-splitting into positional params is intentional here)
    set -- $line
    local cmd="${1:-}"
    case "$cmd" in
      confirm)
        local w="${2:-}" verdict="${3:-}"
        shift 3 2>/dev/null || true
        local reason="$*"
        if [ -z "$w" ] || [ -z "$verdict" ]; then
          printf '사용법: confirm <W> <PASS|CONCERNS|FAIL|OK|STOP> [사유]\n'
          continue
        fi
        # PANES-002: sanitize before it becomes part of a path (display uses raw "$w" above).
        local w_safe
        w_safe="$(sanitize "$w")"
        local f="$inbox/confirm-$w_safe-$ts.txt"
        assert_in_inbox "$f" "$inbox" || continue
        write_atomic600 "$f" '%s\t%s\t%s\n' "$verdict" "$reason" "Paul"
        printf '→ inbox 기록됨: %s\n' "$(basename "$f")"
        ;;
      feedback)
        local w2="${2:-}"
        shift 2 2>/dev/null || true
        local msg="$*"
        if [ -z "$w2" ]; then
          printf '사용법: feedback <W> <메시지>\n'
          continue
        fi
        local w2_safe
        w2_safe="$(sanitize "$w2")"
        local f2="$inbox/feedback-$w2_safe-$ts.md"
        assert_in_inbox "$f2" "$inbox" || continue
        write_atomic600 "$f2" '# %s\n' "$msg"
        printf '→ inbox 기록됨: %s\n' "$(basename "$f2")"
        ;;
      answer)
        local qid="${2:-}"
        shift 2 2>/dev/null || true
        local amsg="$*"
        if [ -z "$qid" ]; then
          printf '사용법: answer <qid> <메시지>\n'
          continue
        fi
        local qid_safe
        qid_safe="$(sanitize "$qid")"
        local f3="$inbox/answer-$qid_safe-$ts.txt"
        assert_in_inbox "$f3" "$inbox" || continue
        write_atomic600 "$f3" '%s\n' "$amsg"
        printf '→ inbox 기록됨: %s\n' "$(basename "$f3")"
        ;;
      waves)
        printf '(웨이브 재구성: 다른 터미널에서 `%s up --waves "W.. W.."` 재실행)\n' "$PROG"
        ;;
      quit)
        printf '이 pane에서는 세션을 내릴 수 없습니다 — 다른 터미널에서 `%s down`을 실행하세요.\n' "$PROG"
        ;;
      *)
        local f4="$inbox/feedback-PAUL-$ts.md"
        assert_in_inbox "$f4" "$inbox" || continue
        write_atomic600 "$f4" '# %s\n' "$line"
        printf '→ 미인식 명령 — inbox 기록됨: %s\n' "$(basename "$f4")"
        ;;
    esac
  done
}

# --------------------------------------------------------------------------
# 1. dispatch — internal (__*) subcommands bypass the up/attach/down/status
#    argument parsing entirely (different calling convention: positional args).
# --------------------------------------------------------------------------
CMD="${1:-}"
case "$CMD" in
  __render) shift; __render "$@"; exit $? ;;
  __input)  shift; __input "$@";  exit $? ;;
  __control) shift; __control "$@"; exit $? ;;
  up|attach|down|status) shift ;;
  -h|--help) usage; exit 0 ;;
  "")
    usage
    exit 1
    ;;
  *)
    err "알 수 없는 명령: $CMD"
    usage
    exit 1
    ;;
esac

# --------------------------------------------------------------------------
# 2. shared argument parsing (up/attach/down/status)
# --------------------------------------------------------------------------
PROJECT="$(pwd)"
WAVES_ARG=""
INTERVAL=2

while [ $# -gt 0 ]; do
  case "$1" in
    --project) shift; PROJECT="${1:-$PROJECT}" ;;
    --waves) shift; WAVES_ARG="${1:-}" ;;
    --interval) shift; INTERVAL="${1:-2}" ;;
    -h|--help) usage; exit 0 ;;
    *) warn "알 수 없는 옵션 무시: $1" ;;
  esac
  shift || true
done

# PANES-001 defense-in-depth: --interval is later interpolated into a pane spawn command
# (via sh_quote below, which makes it *safe*, not merely "expected to be numeric") — but a
# render loop's sleep interval has no legitimate reason to be anything but a small non-negative
# integer, so reject anything else outright rather than trying to reason about what else it
# might contain.
case "$INTERVAL" in
  *[!0-9]*|'')
    err "잘못된 --interval 값: '$INTERVAL' (0 이상의 정수만 허용)"
    exit 1
    ;;
esac

AGENT_TEAM="$PROJECT/.agent-team"
PANES_DIR="$AGENT_TEAM/_state/panes"

# --------------------------------------------------------------------------
# 3. preflight — tmux · the bathos binary
# --------------------------------------------------------------------------
if ! command -v tmux >/dev/null 2>&1; then
  err "tmux가 설치돼 있지 않습니다(E-TMUX-ABSENT)."
  err "  macOS : brew install tmux"
  err "  Linux : apt-get install tmux  (또는 배포판 패키지 매니저)"
  err "  Windows: tmux 네이티브 미지원 — WSL(scripts/wsl-setup.sh) 또는 \`bathos panes --mode tui\` 사용"
  exit 3
fi

BATHOS_BIN_RESOLVED="$(find_bathos_bin "$PROJECT")" || {
  err "bathos 바이너리를 찾을 수 없습니다(E-BATHOS-ABSENT)."
  err "  빌드: cd \"$PROJECT/core\" && cargo build --release"
  err "  또는 BATHOS_BIN=<절대경로>를 지정하세요."
  exit 4
}

# --------------------------------------------------------------------------
# 4. session name — bathos-<project_id> (no jq: grep it straight out of manifest.json)
# --------------------------------------------------------------------------
MANIFEST="$AGENT_TEAM/_state/manifest.json"
PROJECT_ID=""
if [ -f "$MANIFEST" ]; then
  PROJECT_ID="$(grep -o '"project_id"[[:space:]]*:[[:space:]]*"[^"]*"' "$MANIFEST" 2>/dev/null \
    | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
fi
[ -z "$PROJECT_ID" ] && PROJECT_ID="local"
SESSION="bathos-${PROJECT_ID}"

mkdir -p "$PANES_DIR/inbox" "$PANES_DIR/processed"

session_exists() { tmux has-session -t "$SESSION" 2>/dev/null; }

# Clear a stale session.info (if it disagrees with has-session it must be recreated — E8/idempotency)
if [ -f "$PANES_DIR/session.info" ] && ! session_exists; then
  rm -f "$PANES_DIR/session.info"
fi

# --------------------------------------------------------------------------
# 5. automatic wave selection (when --waves is not given)
# --------------------------------------------------------------------------
select_waves() {
  if [ -n "$WAVES_ARG" ]; then
    printf '%s' "$WAVES_ARG"
    return 0
  fi
  local vm_lines
  vm_lines="$("$BATHOS_BIN_RESOLVED" inspect vm --path "$AGENT_TEAM" --format lines 2>/dev/null || true)"
  local active
  active="$(printf '%s\n' "$vm_lines" | awk -F'\t' '$1=="wave" && ($3=="active" || $3=="gated") {printf "%s ", $2}')"
  active="$(printf '%s' "$active" | sed 's/[[:space:]]*$//')"
  if [ -n "$active" ]; then
    printf '%s' "$active"
    return 0
  fi
  local last_done
  last_done="$(printf '%s\n' "$vm_lines" | awk -F'\t' '$1=="wave" && $3=="done" {w=$2} END{if (w!="") print w}')"
  if [ -n "$last_done" ]; then
    warn "활성/게이트 웨이브 없음 — 최근 완료 웨이브 1개만 표시: $last_done"
    printf '%s' "$last_done"
    return 0
  fi
  printf ''
}

# --------------------------------------------------------------------------
# 6. command implementations
# --------------------------------------------------------------------------
case "$CMD" in
  up)
    if session_exists; then
      say "세션 이미 존재 — 재사용(attach): $SESSION"
    else
      local_waves="$(select_waves)"
      set -- $local_waves # word-split into positional params (bash 3.2-safe "array")
      say "세션 생성: $SESSION (웨이브: ${*:-없음})"

      # Panes run our own script directly as the pane's command (tmux's shell-command
      # argument) rather than being *typed* into the pane's interactive login shell via
      # `send-keys`. This sidesteps any slow/prompting rc-file behavior the user's default
      # shell (zsh/oh-my-zsh, pyenv/nvm hooks, etc.) might have on startup — that startup is
      # entirely orthogonal to what these panes need to do, and a hung/slow rc file must not
      # be able to swallow the launch command. `send-keys` is still used below, but only to
      # feed genuine runtime input (confirm/feedback lines) into the already-running script.
      # PANES-001: every interpolated value is passed through sh_quote — the pane command
      # string below is parsed a *second* time by the pane's own shell once tmux spawns it,
      # so an unescaped single quote in any of these values (a project path is the realistic
      # case) would otherwise break out of the intended argument and inject commands.
      tmux new-session -d -s "$SESSION" -n main \
        "$(sh_quote "$SCRIPT_PATH") __control $(sh_quote "$AGENT_TEAM")"

      if [ $# -eq 0 ]; then
        warn "렌더할 웨이브가 없습니다 — control pane만 기동합니다(대기 — 활성 웨이브 없음, E7)."
      else
        for w in "$@"; do
          render_pane="$(tmux split-window -h -t "${SESSION}:main.0" -P -F '#{pane_id}' \
            "$(sh_quote "$SCRIPT_PATH") __render $(sh_quote "$AGENT_TEAM") $(sh_quote "$w") $(sh_quote "$INTERVAL") $(sh_quote "$BATHOS_BIN_RESOLVED")")"
          input_pane="$(tmux split-window -v -t "$render_pane" -P -F '#{pane_id}' \
            "$(sh_quote "$SCRIPT_PATH") __input $(sh_quote "$AGENT_TEAM") $(sh_quote "$w")")"
        done
        tmux select-layout -t "${SESSION}:main" tiled >/dev/null 2>&1 || true
      fi

      write_atomic600 "$PANES_DIR/session.info" \
        'session=%s\npid=%s\nstarted=%s\nwaves=%s\n' "$SESSION" "$$" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${*:-}"
    fi

    if [ -t 0 ] && [ -z "${BATHOS_PANES_NO_ATTACH:-}" ]; then
      tmux attach -t "$SESSION"
    else
      say "비대화형 환경(또는 BATHOS_PANES_NO_ATTACH) — attach 생략. 수동: tmux attach -t $SESSION"
    fi
    ;;

  attach)
    if ! session_exists; then
      err "세션이 없습니다: $SESSION — 먼저 \`$PROG up\`을 실행하세요."
      exit 1
    fi
    tmux attach -t "$SESSION"
    ;;

  down)
    if session_exists; then
      tmux kill-session -t "$SESSION"
      say "세션 종료: $SESSION"
    else
      say "이미 종료 상태: $SESSION"
    fi
    rm -f "$PANES_DIR/session.info"
    # wave-log.md belongs to the lead — the close stamp goes into a separate file only (no ownership trespass).
    printf 'closed %s session=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SESSION" \
      >> "$PANES_DIR/session.info.last" 2>/dev/null || true
    # PANES-004: this file accumulates across every `down` invocation via append (`>>`, not a
    # tmp+rename write — write_atomic600 doesn't fit an append), so re-assert 0600 after each
    # append rather than only at creation (a stale 0644 from an old umask would otherwise
    # persist indefinitely once set).
    chmod 600 "$PANES_DIR/session.info.last" 2>/dev/null || true
    ;;

  status)
    if session_exists; then
      pane_count="$(tmux list-panes -t "$SESSION" 2>/dev/null | wc -l | tr -d ' ')"
      say "up — session=$SESSION panes=$pane_count"
    else
      say "down — session $SESSION 없음"
    fi
    ;;
esac

exit 0
