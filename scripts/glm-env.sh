#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# BATHOS  scripts/glm-env.sh  —  run Claude Code/BATHOS on the GLM (Z.ai) backend
# Usage:  Z_AI_API_KEY=<key> source scripts/glm-env.sh
#        (must be `source`d — the exports have to land in the current shell. Merely running it does nothing.)
# Revert:  scripts/glm-env.sh --unset  (or just open a new shell)
#
# Hard rule: never hardcode the key in this file (guards against committing it by accident). Inject it via Z_AI_API_KEY.
# Reference: docs/glm-backend-kr.md · https://docs.z.ai/scenario-example/develop-tools/claude
# ---------------------------------------------------------------------------

# --unset: drop the GLM settings and fall back to Claude (Anthropic)
if [ "${1:-}" = "--unset" ]; then
  unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN API_TIMEOUT_MS
  echo "[glm-env] 해제됨 — Claude(Anthropic) 기본 백엔드로 복귀."
  return 0 2>/dev/null || exit 0
fi

# Detect whether we were sourced (without it the exports are meaningless)
_sourced=0
if [ -n "${BASH_SOURCE:-}" ] && [ "${BASH_SOURCE[0]}" != "$0" ]; then _sourced=1; fi
if [ -n "${ZSH_EVAL_CONTEXT:-}" ] && case "$ZSH_EVAL_CONTEXT" in *:file) true;; *) false;; esac; then _sourced=1; fi

if [ -z "${Z_AI_API_KEY:-}" ]; then
  echo "[glm-env] ✗ Z_AI_API_KEY 미설정. 사용법: Z_AI_API_KEY=<키> source scripts/glm-env.sh" >&2
  [ "$_sourced" = "1" ] && return 1 2>/dev/null; exit 1
fi

export ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic"
export ANTHROPIC_AUTH_TOKEN="$Z_AI_API_KEY"
export API_TIMEOUT_MS="${API_TIMEOUT_MS:-3000000}"

echo "[glm-env] ✓ GLM 백엔드 설정 완료"
echo "          ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL"
echo "          ANTHROPIC_AUTH_TOKEN=***(Z_AI_API_KEY)"
echo "          → 이제 'claude' 실행 시 GLM으로 호출됩니다. 팀원 모델은 /config 기본값 권장(docs/glm-backend-kr.md §2)."

if [ "$_sourced" != "1" ]; then
  echo "[glm-env] ⚠ 이 스크립트는 실행이 아니라 'source' 해야 현재 셸에 적용됩니다." >&2
fi
