#!/usr/bin/env bash
# =============================================================================
# BATHOS story-21 (SS21, optional) — scripts/codex-glm/verify-relay.sh
#
# Checks that a local codex-relay (https://github.com/MetaFARS/codex-relay)
# process and this repo's example config are set up correctly for the
# Codex-CLI-through-GLM path — WITHOUT attempting a real GLM/Zhipu API call.
#
# This is intentionally narrower than scripts/glm-smoke-test.sh (the Claude
# Code GLM path, live-verified in commit 8ee6dd7): that script sends a real
# authenticated request to Z.ai. This script never does — story-21's L5
# honesty requirement (ux-parity-limits.md#l5) is "example config + proxy
# liveness check", not "connection verified". What this script checks:
#   1. codex-relay binary is on PATH (or a path was given).
#   2. relay-config.toml.example has the required TOML keys (grep, no jq —
#      this repo's bash-3.2/no-jq convention, code-structure.md §layer boundaries).
#   3. IF a relay happens to already be running locally, its /v1/models
#      endpoint is reachable — this only proves "a proxy is listening", not
#      "GLM behind it is reachable/authenticated". No API key is read, sent,
#      or required by this script at all.
#
# Usage:
#   scripts/codex-glm/verify-relay.sh                  # checks 1+2, and 3 best-effort
#   scripts/codex-glm/verify-relay.sh --port 4453       # override relay port (default 4453,
#                                                        # matching codex-relay's suggested
#                                                        # port for the GLM/Zhipu upstream)
#
# Exit codes (own small registry — do not overload the hook exit-code registry
# in exceptions.md#6, this script is not a hook):
#   0 = all checks that could run passed (missing-relay-process is a WARN, not FAIL)
#   1 = config file missing a required key (static check failure)
#   2 = codex-relay binary not found on PATH
# =============================================================================
set -uo pipefail

PROG="verify-relay.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_EXAMPLE="$SCRIPT_DIR/relay-config.toml.example"
PORT=4453   # codex-relay README's suggested port for the GLM (Zhipu) upstream

while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT="${2:-}"; shift 2 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      printf '[%s] unknown option: %s\n' "$PROG" "$1" >&2
      exit 1
      ;;
  esac
done

FAIL=0

# --------------------------------------------------------------------------
# 1. codex-relay binary presence (WARN only — this is a fact-finding script,
#    not a gate; a missing binary just means "not installed yet", not a bug).
# --------------------------------------------------------------------------
if command -v codex-relay >/dev/null 2>&1; then
  RELAY_BIN="$(command -v codex-relay)"
  printf '[%s] OK  — codex-relay binary found: %s\n' "$PROG" "$RELAY_BIN"
else
  printf '[%s] WARN — codex-relay not found on PATH.\n' "$PROG"
  printf '[%s]       Install: pip install codex-relay  |  cargo install codex-relay\n' "$PROG"
  printf '[%s]       (source: https://github.com/MetaFARS/codex-relay)\n' "$PROG"
fi

# --------------------------------------------------------------------------
# 2. Example config static check — required TOML keys present (grep only,
#    no TOML parser dependency — matches this repo's no-jq/native-parsing rule).
# --------------------------------------------------------------------------
if [ ! -f "$CONFIG_EXAMPLE" ]; then
  printf '[%s] FAIL — example config not found: %s\n' "$PROG" "$CONFIG_EXAMPLE" >&2
  FAIL=1
else
  for key in 'model_provider' 'base_url' 'wire_api' 'env_key'; do
    if grep -q "$key" "$CONFIG_EXAMPLE"; then
      printf '[%s] OK  — example config has key: %s\n' "$PROG" "$key"
    else
      printf '[%s] FAIL — example config missing key: %s\n' "$PROG" "$key" >&2
      FAIL=1
    fi
  done
  # wire_api must be "responses" — a Chat-Completions-only entry here would
  # silently defeat the whole point of routing through codex-relay.
  if grep -Eq 'wire_api[[:space:]]*=[[:space:]]*"responses"' "$CONFIG_EXAMPLE"; then
    printf '[%s] OK  — wire_api = "responses" (correct for Codex CLI)\n' "$PROG"
  else
    printf '[%s] FAIL — wire_api is not set to "responses" in the example config\n' "$PROG" >&2
    FAIL=1
  fi
fi

# --------------------------------------------------------------------------
# 3. Best-effort proxy liveness check — NOT a GLM connectivity test. If
#    nothing is listening on $PORT this is a WARN (relay simply isn't running
#    right now), not a FAIL. We never send credentials or hit the real
#    upstream (open.bigmodel.cn) — only the local relay's own /v1/models
#    passthrough, and only if it answers at all.
# --------------------------------------------------------------------------
if command -v curl >/dev/null 2>&1; then
  HTTP_CODE="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 3 \
    "http://127.0.0.1:${PORT}/v1/models" 2>/dev/null || true)"
  if [ -n "$HTTP_CODE" ] && [ "$HTTP_CODE" != "000" ]; then
    printf '[%s] OK  — a proxy answered on 127.0.0.1:%s (HTTP %s). This confirms a process\n' "$PROG" "$PORT" "$HTTP_CODE"
    printf '[%s]       is listening — it does NOT confirm GLM upstream is reachable/authenticated.\n' "$PROG"
  else
    printf '[%s] WARN — nothing answered on 127.0.0.1:%s. Start the relay first if you want\n' "$PROG" "$PORT"
    printf '[%s]        this check to run (see relay-config.toml.example for the launch command).\n' "$PROG"
  fi
else
  printf '[%s] WARN — curl not installed, skipping proxy liveness check.\n' "$PROG"
fi

# --------------------------------------------------------------------------
# 4. Summary — anti-fabrication banner (L5, ux-parity-limits.md#l5)
# --------------------------------------------------------------------------
printf '\n[%s] --- summary ---\n' "$PROG"
printf '[%s] This script never contacted GLM/Zhipu and never required an API key.\n' "$PROG"
printf '[%s] "Codex CLI + GLM live connectivity" remains UNVERIFIED from this repo/session.\n' "$PROG"
if [ "$FAIL" = "1" ]; then
  printf '[%s] RESULT: FAIL (static config check)\n' "$PROG"
  exit 1
fi
if ! command -v codex-relay >/dev/null 2>&1; then
  printf '[%s] RESULT: PASS (config OK) — codex-relay binary not installed, install to proceed.\n' "$PROG"
  exit 0
fi
printf '[%s] RESULT: PASS\n' "$PROG"
exit 0
