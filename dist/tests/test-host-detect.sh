#!/usr/bin/env bash
# =============================================================================
# BATHOS — dist/tests/test-host-detect.sh
# Story B5 §5 스모크 테스트 → story-13(실키 구현) 갱신.
#
# 이 파일은 story-13의 명시 소유 목록 밖이지만(File Structure Requirements는
# dist/lib/host-detect.sh만 지정), .github/workflows/drift-guard.yml이 이
# 스크립트를 CI에서 직접 실행한다 — host-detect.sh의 판정 로직을 실키로
# 갱신하면서 이 파일을 그대로 두면 CI가 깨진다(구 스텁 가정: 기본값=claude,
# codex=미구현 exit 2). 소유자가 없는 결합 파일이라 함께 갱신했다(리드 보고
# 사항 — .agent-team/08-impl-notes/phillip-w5-impl-notes.md 참고).
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

# 매 테스트가 이전 테스트의 env 잔재에 영향받지 않도록 판별 관련 키를 전부 비운다.
_clear_detect_env() {
  unset PLUGIN_ROOT PLUGIN_DATA COPILOT_PLUGIN_DATA CLAUDE_PROJECT_DIR \
        CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA BATHOS_FORCE_HOST 2>/dev/null || true
}

# 1) 기본값(환경변수 없음) -> unknown (story-13 AC#1 — 과거엔 claude였다)
_clear_detect_env
got="$(bathos_detect_host)"
assert_eq "기본 호스트 판별(전부 부재)" "unknown" "$got"

# 2) PLUGIN_ROOT 존재 -> codex ([문서확정] 승격 + PLUGIN_ROOT 신규)
_clear_detect_env
got="$(PLUGIN_ROOT=/some/plugin bathos_detect_host)"
assert_eq "PLUGIN_ROOT 존재 -> codex" "codex" "$got"

# 3) PLUGIN_DATA 존재 -> codex
_clear_detect_env
got="$(PLUGIN_DATA=/some/data bathos_detect_host)"
assert_eq "PLUGIN_DATA 존재 -> codex" "codex" "$got"

# 4) CLAUDE_PROJECT_DIR 존재 -> claude
_clear_detect_env
got="$(CLAUDE_PROJECT_DIR=/some/project bathos_detect_host)"
assert_eq "CLAUDE_PROJECT_DIR 존재 -> claude" "claude" "$got"

# 5) CLAUDE_PLUGIN_ROOT만 존재(2순위 unprefixed 부재) -> claude
_clear_detect_env
got="$(CLAUDE_PLUGIN_ROOT=/some/plugin bathos_detect_host)"
assert_eq "레거시 CLAUDE_PLUGIN_ROOT만 존재 -> claude" "claude" "$got"

# 6) PLUGIN_ROOT와 CLAUDE_PLUGIN_ROOT 동시 존재 -> codex (2순위가 4순위보다 우선)
_clear_detect_env
got="$(PLUGIN_ROOT=/p CLAUDE_PLUGIN_ROOT=/p bathos_detect_host)"
assert_eq "PLUGIN_ROOT+CLAUDE_PLUGIN_ROOT 동시 -> codex(우선순위)" "codex" "$got"

# 7) COPILOT_PLUGIN_DATA 존재 -> copilot(스코프 밖 — 원 동작 유지)
_clear_detect_env
got="$(COPILOT_PLUGIN_DATA=/x bathos_detect_host)"
assert_eq "COPILOT_PLUGIN_DATA 존재 -> copilot(변경 없음)" "copilot" "$got"

# 8) BATHOS_FORCE_HOST 유효값 오버라이드 -> 그 값(다른 신호가 있어도 우선)
_clear_detect_env
got="$(BATHOS_FORCE_HOST=codex CLAUDE_PROJECT_DIR=/some/project bathos_detect_host)"
assert_eq "강제 오버라이드(유효값 codex) 우선" "codex" "$got"

# 9) BATHOS_FORCE_HOST 무효값 -> 경고 후 무시하고 실감지로 폴백(story-13 AC#1)
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

# 10) claude/codex/unknown 출력분기는 payload를 그대로 통과(story-13 §5 — 포맷
#     차이가 실제로 구현된 적이 없으므로 claude-형 기본을 공유한다)
for h in claude codex unknown; do
  out="$(bathos_write_hook_output "$h" '{"decision":"allow"}')"; rc=$?
  assert_eq "$h 출력 통과(exit)" "0" "$rc"
  assert_eq "$h 출력 내용" '{"decision":"allow"}' "$out"
done

# 11) copilot은 여전히 미구현 -> exit 2, stdout 비어있음(오출력 금지)
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
