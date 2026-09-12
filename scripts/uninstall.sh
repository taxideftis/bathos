#!/usr/bin/env bash
# =============================================================================
# BATHOS Dynamis — scripts/uninstall.sh
# CF-B4 / SS11 (Should) — first-class script for cleaning up external state "outside" the plugin folder.
#
# ★★★ Execution-order contract (the key edge case, confirmed on ponytail) ★★★
#   The host's plugin-removal command deletes this script file itself first.
#   So this script must always be run "before the host removal command".
#   (If the script is already gone, follow §README "manual cleanup path" below —
#    see docs/uninstall-kr.md)
#
# Cleanup targets (an explicit list — no implicit glob deletion, inheriting the careful spirit):
#   1. ${BATHOS_STATE_DIR}/session-flags.json   (plan_mode/intensity session flags)
#   2. the statusLine entry inside ${BATHOS_HOME}/.claude/settings.json
#      (surgically remove only bathos-related entries — never rewrite the whole file; edit after a .bak backup)
#   3. ${BATHOS_CONFIG_DIR}/*                   (only when it exists — global-config leftovers)
#
# Explicitly never touched (protecting the SSOT):
#   - _state/manifest.json (the project SSOT, not a deletion target)
#   - _state/audit-log.jsonl (append-only audit history, not a deletion target)
#
# UX contract (implements ux-flow-map Flow C and design-handoff §2-4 as written):
#   - dry-run by default (with no arguments it only prints the plan)
#   - a strong warning ahead of the destructive run + a per-item result log
#   - `y/N` (defaults to N) or `--yes`
#   - partial failure is reported as separate success/failure counts (it does not kill the whole run)
#   - a "next action" hint once finished (no dead ends)
#
# exit: 0=finished normally (dry-run included), 1=user cancelled, or partial failures exist
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATHOS_ROOT="${BATHOS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# All of these are overridable by env var for testability (inheriting the existing hook
# convention — it has to be verifiable with fixtures without touching the real $HOME).
BATHOS_STATE_DIR="${BATHOS_STATE_DIR:-$BATHOS_ROOT/_state}"
BATHOS_HOME="${BATHOS_HOME:-$HOME}"
BATHOS_CONFIG_DIR="${BATHOS_CONFIG_DIR:-$BATHOS_HOME/.config/bathos}"

DRY_RUN=1
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y) ASSUME_YES=1; DRY_RUN=0 ;;
    --apply)  DRY_RUN=0 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      cat <<'EOF'
사용법: uninstall.sh [--apply] [--yes] [--dry-run]
  (인자 없음)   기본값 = dry-run: 삭제 대상 계획만 출력, 아무것도 지우지 않음
  --apply       실제 삭제 진행(대화형 y/N 확인, 기본 N)
  --yes, -y     --apply와 함께(또는 단독) 사용 시 확인 없이 즉시 삭제
  --dry-run     명시적 dry-run(기본값과 동일, 문서화 목적)
EOF
      exit 0
      ;;
  esac
done

PREFIX="[bathos uninstall]"
info()  { printf '%s %s\n' "$PREFIX" "$*"; }
warn()  { printf '%s ! %s\n' "$PREFIX" "$*"; }
okmsg() { printf '%s ✓ %s\n' "$PREFIX" "$*"; }
failmsg(){ printf '%s ✗ %s\n' "$PREFIX" "$*"; }

warn "되돌릴 수 없음 — 호스트의 플러그인 제거 명령보다 먼저 이 스크립트를 실행하세요."
warn "  (호스트 제거가 먼저 실행되면 이 스크립트 파일 자체가 함께 삭제됩니다.)"

# --- Build the target plan ---------------------------------------------------
declare -a PLAN_DESC=()
declare -a PLAN_KIND=()   # file | jsonkey | dircontents
declare -a PLAN_PATH=()

SESSION_FLAGS="$BATHOS_STATE_DIR/session-flags.json"
if [[ -f "$SESSION_FLAGS" ]]; then
  PLAN_DESC+=("세션 플래그(plan/intensity): $SESSION_FLAGS")
  PLAN_KIND+=("file")
  PLAN_PATH+=("$SESSION_FLAGS")
fi

SETTINGS_JSON="$BATHOS_HOME/.claude/settings.json"
if [[ -f "$SETTINGS_JSON" ]]; then
  PLAN_DESC+=("전역 settings.json의 statusLine 엔트리(bathos 관련분만): $SETTINGS_JSON")
  PLAN_KIND+=("jsonkey")
  PLAN_PATH+=("$SETTINGS_JSON")
fi

if [[ -d "$BATHOS_CONFIG_DIR" ]]; then
  PLAN_DESC+=("전역 설정 디렉터리 내용물: $BATHOS_CONFIG_DIR/*")
  PLAN_KIND+=("dircontents")
  PLAN_PATH+=("$BATHOS_CONFIG_DIR")
fi

TOTAL="${#PLAN_DESC[@]}"

if [[ "$TOTAL" -eq 0 ]]; then
  okmsg "외부 상태 없음 — 호스트 제거만 하면 됩니다."
  info "다음 행동: 호스트의 플러그인 제거 명령을 실행하세요."
  exit 0
fi

info "삭제 계획 (${TOTAL}건):"
i=0
while [[ "$i" -lt "$TOTAL" ]]; do
  printf '%s   - %s\n' "$PREFIX" "${PLAN_DESC[$i]}"
  i=$((i + 1))
done

if [[ "$DRY_RUN" -eq 1 ]]; then
  info "(dry-run) 아무것도 삭제하지 않았습니다. 실제 삭제: --apply [--yes]"
  exit 0
fi

if [[ "$ASSUME_YES" -ne 1 ]]; then
  printf '%s 위 %d건을 정말 삭제하시겠습니까? 되돌릴 수 없습니다. [y/N] ' "$PREFIX" "$TOTAL"
  read -r reply
  case "$reply" in
    y|Y|yes|YES) ;;
    *) warn "사용자 취소 — 아무것도 삭제하지 않았습니다."; exit 1 ;;
  esac
fi

# --- Perform the actual deletion ----------------------------------------------
SUCCESS=0
FAILED=0

remove_file() {
  local path="$1"
  if rm -f -- "$path" 2>/dev/null; then
    okmsg "[removed] $path"
    SUCCESS=$((SUCCESS + 1))
  else
    failmsg "[fail: 권한/경로 문제] $path"
    FAILED=$((FAILED + 1))
  fi
}

remove_dir_contents() {
  local dir="$1"
  local any_fail=0
  # Walk entry by entry instead of an implicit whole-glob delete (rm -rf) — the careful spirit:
  # a single failure must not kill the rest, and it matches careful-guard's block on broad deletes.
  local entry
  for entry in "$dir"/* "$dir"/.[!.]*; do
    [[ -e "$entry" ]] || continue
    if rm -rf -- "$entry" 2>/dev/null; then
      okmsg "[removed] $entry"
      SUCCESS=$((SUCCESS + 1))
    else
      failmsg "[fail: 권한/경로 문제] $entry"
      FAILED=$((FAILED + 1))
      any_fail=1
    fi
  done
  return "$any_fail"
}

remove_statusline_key() {
  local path="$1"
  if ! command -v jq >/dev/null 2>&1; then
    warn "[skip: jq 없음] $path — 수동 제거 안내: \"statusLine\" 키를 열어 bathos 관련 항목만 지우세요."
    return
  fi

  # Confirm the entry really is bathos-related (so an unrelated statusLine setting is never wiped by mistake).
  local is_bathos
  is_bathos="$(jq -r '(.statusLine.command // "") | test("bathos"; "i")' "$path" 2>/dev/null || echo false)"
  if [[ "$is_bathos" != "true" ]]; then
    warn "[skip: bathos 관련 아님] $path — statusLine이 있으나 bathos 참조가 확인되지 않아 건드리지 않음."
    return
  fi

  local backup="${path}.bak"
  if ! cp -p -- "$path" "$backup" 2>/dev/null; then
    failmsg "[fail: 백업 실패] $path"
    FAILED=$((FAILED + 1))
    return
  fi

  local tmp
  tmp="$(mktemp)"
  if jq 'del(.statusLine)' "$path" > "$tmp" 2>/dev/null && mv "$tmp" "$path"; then
    okmsg "[removed] $path 의 statusLine 엔트리 (백업: $backup)"
    SUCCESS=$((SUCCESS + 1))
  else
    rm -f "$tmp" 2>/dev/null
    failmsg "[fail: jq 편집 실패] $path (백업은 $backup 에 보존됨)"
    FAILED=$((FAILED + 1))
  fi
}

i=0
while [[ "$i" -lt "$TOTAL" ]]; do
  kind="${PLAN_KIND[$i]}"
  path="${PLAN_PATH[$i]}"
  case "$kind" in
    file) remove_file "$path" ;;
    jsonkey) remove_statusline_key "$path" ;;
    dircontents) remove_dir_contents "$path" ;;
  esac
  i=$((i + 1))
done

info "결과: 성공 ${SUCCESS}건 / 실패 ${FAILED}건"
if [[ "$FAILED" -gt 0 ]]; then
  warn "일부 항목 정리 실패 — 다음 행동: 위 [fail] 항목을 수동으로 확인/제거한 뒤, 그래도 호스트 제거는 진행 가능합니다."
  exit 1
fi

okmsg "외부 상태 정리 완료."
info "다음 행동: 이제 호스트의 플러그인 제거 명령을 실행하세요."
exit 0
