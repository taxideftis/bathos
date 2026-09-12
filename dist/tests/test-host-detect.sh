#!/usr/bin/env bash
# =============================================================================
# BATHOS — dist/tests/test-host-detect.sh
# Story B5 §5 smoke test, updated for story-13 (the real-key implementation).
#
# This file sits outside story-13's explicit ownership list (File Structure Requirements
# names only dist/lib/host-detect.sh), yet .github/workflows/drift-guard.yml runs this
# script directly in CI — updating host-detect.sh's detection logic to the real keys
# while leaving this file untouched would break CI (the old stub assumed default=claude,
# codex=unimplemented exit 2). Being a coupled file with no owner, it was updated along
# with it (reported to the lead — see .agent-team/08-impl-notes/phillip-w5-impl-notes.md).
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/host-detect.sh
source "$SCRIPT_DIR/../lib/host-detect.sh"

FAIL=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf '[PASS] %s\n' "$desc"
  else
    printf '[FAIL] %s — 기대=%s 실제=%s\n' "$desc" "$expected" "$actual"
    FAIL=1
  fi
}

# Clear every detection-related key so no test is affected by env residue from a previous one.
_clear_detect_env() {
  unset PLUGIN_ROOT PLUGIN_DATA COPILOT_PLUGIN_DATA CLAUDE_PROJECT_DIR \
        CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA BATHOS_FORCE_HOST 2>/dev/null || true
}

# 1) default (no env vars) -> unknown (story-13 AC#1 — it used to be claude)
_clear_detect_env
got="$(bathos_detect_host)"
assert_eq "기본 호스트 판별(전부 부재)" "unknown" "$got"

# 2) PLUGIN_ROOT present -> codex ([doc-confirmed] promotion + PLUGIN_ROOT is new)
_clear_detect_env
got="$(PLUGIN_ROOT=/some/plugin bathos_detect_host)"
assert_eq "PLUGIN_ROOT 존재 -> codex" "codex" "$got"

# 3) PLUGIN_DATA present -> codex
_clear_detect_env
got="$(PLUGIN_DATA=/some/data bathos_detect_host)"
assert_eq "PLUGIN_DATA 존재 -> codex" "codex" "$got"

# 4) CLAUDE_PROJECT_DIR present -> claude
_clear_detect_env
got="$(CLAUDE_PROJECT_DIR=/some/project bathos_detect_host)"
assert_eq "CLAUDE_PROJECT_DIR 존재 -> claude" "claude" "$got"

# 5) only CLAUDE_PLUGIN_ROOT present (no 2nd-priority unprefixed var) -> claude
_clear_detect_env
got="$(CLAUDE_PLUGIN_ROOT=/some/plugin bathos_detect_host)"
assert_eq "레거시 CLAUDE_PLUGIN_ROOT만 존재 -> claude" "claude" "$got"

# 6) PLUGIN_ROOT and CLAUDE_PLUGIN_ROOT both present -> codex (priority 2 beats priority 4)
_clear_detect_env
got="$(PLUGIN_ROOT=/p CLAUDE_PLUGIN_ROOT=/p bathos_detect_host)"
assert_eq "PLUGIN_ROOT+CLAUDE_PLUGIN_ROOT 동시 -> codex(우선순위)" "codex" "$got"

# 7) COPILOT_PLUGIN_DATA present -> copilot (out of scope — original behaviour kept)
_clear_detect_env
got="$(COPILOT_PLUGIN_DATA=/x bathos_detect_host)"
assert_eq "COPILOT_PLUGIN_DATA 존재 -> copilot(변경 없음)" "copilot" "$got"

# 8) BATHOS_FORCE_HOST override with a valid value -> that value (wins over any other signal)
_clear_detect_env
got="$(BATHOS_FORCE_HOST=codex CLAUDE_PROJECT_DIR=/some/project bathos_detect_host)"
assert_eq "강제 오버라이드(유효값 codex) 우선" "codex" "$got"

# 9) BATHOS_FORCE_HOST with an invalid value -> warn, ignore it, fall back to real detection (story-13 AC#1)
_clear_detect_env
got="$(BATHOS_FORCE_HOST=bogus-typo CLAUDE_PROJECT_DIR=/some/project bathos_detect_host 2>/dev/null)"
assert_eq "강제 오버라이드(무효값) -> 무시하고 실감지 폴백" "claude" "$got"
warn_out="$(BATHOS_FORCE_HOST=bogus-typo bathos_detect_host 2>&1 1>/dev/null)"
if printf '%s' "$warn_out" | grep -q '무효'; then
  printf '[PASS] 무효 오버라이드 시 stderr 경고 출력\n'
else
  printf '[FAIL] 무효 오버라이드 시 stderr 경고 없음\n'
  FAIL=1
fi

# 10) the claude/codex/unknown output branches pass the payload straight through (story-13 §5 —
#     the format difference was never actually implemented, so they share the claude-style default)
for h in claude codex unknown; do
  out="$(bathos_write_hook_output "$h" '{"decision":"allow"}')"; rc=$?
  assert_eq "$h 출력 통과(exit)" "0" "$rc"
  assert_eq "$h 출력 내용" '{"decision":"allow"}' "$out"
done

# 11) copilot is still unimplemented -> exit 2, empty stdout (no stray output)
out="$(bathos_write_hook_output copilot '{"decision":"allow"}' 2>/dev/null)"
rc=$?
assert_eq "copilot 미구현 exit code(변경 없음)" "2" "$rc"
assert_eq "copilot 미구현 stdout 비어있음(오출력 금지)" "" "$out"

if [[ "$FAIL" -eq 0 ]]; then
  printf '[bathos test-host-detect] ✓ 전체 통과\n'
  exit 0
else
  printf '[bathos test-host-detect] ✗ 실패 항목 존재\n'
  exit 1
fi
