#!/usr/bin/env bash
# =============================================================================
# BATHOS P4 — scripts/glm-smoke-test.sh
# GLM (Z.ai) live-connection smoke test: without starting Claude Code, curl hits Z.ai's
# Anthropic-compatible endpoint (`POST /v1/messages`) directly to verify connectivity,
# authentication and response shape. A read-only test.
#
# Design source: .agent-team/04-architecture/w2-runtime-p4-design-kr.md §A (James, 2026-07-16)
# Changes no state (live mode does spend a few tokens — max_tokens<=64, not 0).
#
# Usage:
#   scripts/glm-smoke-test.sh --dry-run                 # no key needed, prints the request only
#   Z_AI_API_KEY=<key> scripts/glm-smoke-test.sh         # live text verification
#   Z_AI_API_KEY=<key> scripts/glm-smoke-test.sh --tool-use
#
# Exit-code contract (design §A4 — kept mutually exclusive so CI can branch on the cause):
#   0 = pass (including dry-run)   1 = HTTP 200 but response verification failed
#   2 = non-200 HTTP               3 = no key (live mode)
#   4 = network/transport error    5 = curl not installed
# =============================================================================
set -uo pipefail
# `set -e` is deliberately not used — we must handle curl's non-zero exit ourselves (the exit-4
# branch), and under `set -e` a failing command substitution such as `HTTP="$(curl ...)"` would
# end the script early and cost us the chance to report a cause-specific message (the same
# reason as in the existing hooks).

PROG="glm-smoke-test.sh"

# --------------------------------------------------------------------------
# 0. Option defaults + argument parsing
# --------------------------------------------------------------------------
OPT_DRY_RUN=0
OPT_TOOL_USE=0
OPT_MODEL=""
OPT_BASE_URL=""
OPT_TIMEOUT=""
OPT_VERBOSE=0

usage() {
  cat <<'EOF'
사용법: scripts/glm-smoke-test.sh [옵션]

옵션:
  --dry-run           요청을 구성만 하고 전송하지 않는다(키 불요). 구성 결과 출력 후 exit 0.
  --tool-use          텍스트 검증에 더해 tool-use 호출 검증을 추가 수행(선택 2차 요청).
  --model <id>        요청 model 필드 (기본: 환경 GLM_SMOKE_MODEL > "glm-5.3")
  --base-url <url>    엔드포인트 (기본: 환경 ANTHROPIC_BASE_URL > "https://api.z.ai/api/anthropic")
  --timeout <sec>     curl --max-time (기본: 60)
  --verbose           요청/응답 원문(키 마스킹) 출력
  -h | --help         도움말

환경변수:
  ANTHROPIC_AUTH_TOKEN   1순위 키 (glm-env.sh가 export하는 그 변수)
  Z_AI_API_KEY           2순위 키 (glm-env.sh 주입 규약과 동일)
  ANTHROPIC_BASE_URL     엔드포인트 오버라이드
  GLM_SMOKE_MODEL        모델 오버라이드
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) OPT_DRY_RUN=1; shift ;;
    --tool-use) OPT_TOOL_USE=1; shift ;;
    --model) OPT_MODEL="${2:-}"; shift 2 ;;
    --base-url) OPT_BASE_URL="${2:-}"; shift 2 ;;
    --timeout) OPT_TIMEOUT="${2:-}"; shift 2 ;;
    --verbose) OPT_VERBOSE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      printf '%s: 알 수 없는 옵션: %s\n' "$PROG" "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

# --------------------------------------------------------------------------
# 1. Check that curl exists (exit 5)
# --------------------------------------------------------------------------
if ! command -v curl >/dev/null 2>&1; then
  printf '[%s] curl이 설치되어 있지 않습니다. RESULT: FAIL (curl 미설치)\n' "$PROG" >&2
  exit 5
fi

# --------------------------------------------------------------------------
# 2. Resolve configuration (flag > environment > default)
# --------------------------------------------------------------------------
BASE_URL="${OPT_BASE_URL:-${ANTHROPIC_BASE_URL:-https://api.z.ai/api/anthropic}}"
# ponytail: hardcoded latest model id goes stale each time Z.ai ships a new one, override with
# GLM_SMOKE_MODEL or --model; revisit when a docs.z.ai check shows a newer flagship than glm-5.3
MODEL="${OPT_MODEL:-${GLM_SMOKE_MODEL:-glm-5.3}}"
TIMEOUT="${OPT_TIMEOUT:-60}"
# Normalization: strip a trailing slash before appending /v1/messages (E-A1 — avoids "//v1/messages").
URL="${BASE_URL%/}/v1/messages"

# Model-value validation (A-10): only safe characters are allowed, to remove the injection
# surface. This value is the single variable interpolated during printf assembly, so once it
# passes here the body assembly can be considered safe (every other field is a fixed literal).
if ! printf '%s' "$MODEL" | grep -Eq '^[A-Za-z0-9._-]+$'; then
  printf '[%s] 모델 ID에 허용되지 않은 문자가 포함되어 있습니다: %s\n' "$PROG" "$MODEL" >&2
  printf '[%s] 허용 문자: A-Z a-z 0-9 . _ -\n' "$PROG" >&2
  printf 'RESULT: FAIL (모델 ID 검증 실패)\n'
  exit 1
fi

# Key precedence: ANTHROPIC_AUTH_TOKEN (the variable Claude Code actually exports) > Z_AI_API_KEY.
KEY="${ANTHROPIC_AUTH_TOKEN:-${Z_AI_API_KEY:-}}"

# Key-masking helper (used even under --verbose so a real key is never exposed in logs).
_mask_key() {
  local k="$1"
  if [ -z "$k" ]; then
    printf '<미설정>'
  else
    printf '***(%s자)' "${#k}"
  fi
}

# --------------------------------------------------------------------------
# 3. Assemble the request body (printf, no heredoc — MODEL is the only interpolation point)
# --------------------------------------------------------------------------
build_text_request() {
  printf '{"model":"%s","max_tokens":64,"messages":[{"role":"user","content":"Reply with exactly this token and nothing else: BATHOS-GLM-OK"}]}' "$1"
}

build_tool_request() {
  printf '{"model":"%s","max_tokens":128,"tools":[{"name":"echo_token","description":"Echo the given token back verbatim.","input_schema":{"type":"object","properties":{"token":{"type":"string"}},"required":["token"]}}],"tool_choice":{"type":"tool","name":"echo_token"},"messages":[{"role":"user","content":"Call echo_token with token=BATHOS-TOOL-OK"}]}' "$1"
}

REQ_JSON="$(build_text_request "$MODEL")"

# --------------------------------------------------------------------------
# 4. --dry-run: works without a key. Prints the composed request and exits 0.
# --------------------------------------------------------------------------
if [ "$OPT_DRY_RUN" = "1" ]; then
  printf '[%s] --- dry-run: 요청 구성만 출력합니다(전송하지 않음) ---\n' "$PROG"
  printf '[%s] URL: %s\n' "$PROG" "$URL"
  printf '[%s] 헤더: Authorization: Bearer %s\n' "$PROG" "$(_mask_key "$KEY")"
  printf '[%s] 헤더: Content-Type: application/json\n' "$PROG"
  printf '[%s] 헤더: anthropic-version: 2023-06-01\n' "$PROG"
  printf '[%s] 본문(텍스트): %s\n' "$PROG" "$REQ_JSON"
  if [ "$OPT_TOOL_USE" = "1" ]; then
    printf '[%s] 본문(tool-use): %s\n' "$PROG" "$(build_tool_request "$MODEL")"
  fi
  printf '[%s] 미전송(dry-run). 라이브 검증엔 키(ANTHROPIC_AUTH_TOKEN 또는 Z_AI_API_KEY)가 필요합니다.\n' "$PROG"
  printf 'RESULT: PASS — dry-run 구성 완료 (전송 없음)\n'
  exit 0
fi

# --------------------------------------------------------------------------
# 5. Live mode: require a key (exit 3)
# --------------------------------------------------------------------------
if [ -z "$KEY" ]; then
  printf '[%s] ANTHROPIC_AUTH_TOKEN 또는 Z_AI_API_KEY 필요.\n' "$PROG" >&2
  printf '[%s] 사용: Z_AI_API_KEY=<키> scripts/glm-smoke-test.sh\n' "$PROG" >&2
  printf '[%s] 키 없이 요청 구성만 보려면 --dry-run\n' "$PROG" >&2
  printf 'RESULT: FAIL (키 없음)\n'
  exit 3
fi

# --------------------------------------------------------------------------
# 6. Temp files + cleanup trap (§A7)
# --------------------------------------------------------------------------
BODY_FILE="$(mktemp)"
ERR_FILE="$(mktemp)"
BODY_FILE2="$(mktemp)"
ERR_FILE2="$(mktemp)"
trap 'rm -f "$BODY_FILE" "$ERR_FILE" "$BODY_FILE2" "$ERR_FILE2"' EXIT INT TERM

# --------------------------------------------------------------------------
# 7. curl execution helper — auth_style: bearer | x-api-key
# --------------------------------------------------------------------------
# $1=auth_style  $2=request body JSON  $3=body output file  $4=stderr output file
# Prints "HTTP_CODE CURL_EXIT" on stdout (space-separated; both values are always present).
do_request() {
  local auth_style="$1" body="$2" body_file="$3" err_file="$4"
  local auth_header http_code curl_exit
  if [ "$auth_style" = "bearer" ]; then
    auth_header="Authorization: Bearer $KEY"
  else
    auth_header="x-api-key: $KEY"
  fi
  http_code="$(curl -sS -o "$body_file" -w '%{http_code}' \
    --connect-timeout 10 --max-time "$TIMEOUT" \
    -H "Content-Type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -H "$auth_header" \
    -X POST "$URL" \
    --data "$body" 2>"$err_file")"
  curl_exit=$?
  printf '%s %s' "${http_code:-}" "$curl_exit"
}

# curl exit code -> human-readable cause (the §A4 exit-4 branch)
_curl_exit_reason() {
  case "$1" in
    6) echo "DNS 해석 실패(오프라인?)" ;;
    7) echo "연결 거부" ;;
    28) echo "타임아웃(--timeout 증가 시도)" ;;
    35) echo "TLS 협상 실패" ;;
    *) echo "curl exit $1" ;;
  esac
}

# --------------------------------------------------------------------------
# 8. Two-step auth strategy (ADR-P4-3): Bearer first -> on 401/403, retry once with x-api-key
# --------------------------------------------------------------------------
if [ "$OPT_VERBOSE" = "1" ]; then
  printf '[%s] 요청 URL: %s\n' "$PROG" "$URL" >&2
  printf '[%s] 요청 본문: %s\n' "$PROG" "$REQ_JSON" >&2
fi

READ_OUT="$(do_request bearer "$REQ_JSON" "$BODY_FILE" "$ERR_FILE")"
HTTP_CODE="${READ_OUT%% *}"
CURL_EXIT="${READ_OUT##* }"
AUTH_USED="bearer"

if [ "$CURL_EXIT" != "0" ]; then
  REASON="$(_curl_exit_reason "$CURL_EXIT")"
  printf '[%s] curl 전송 실패(exit %s): %s\n' "$PROG" "$CURL_EXIT" "$REASON" >&2
  [ -s "$ERR_FILE" ] && printf '[%s] curl stderr: %s\n' "$PROG" "$(head -c 300 "$ERR_FILE")" >&2
  printf 'RESULT: FAIL (네트워크/전송 오류 — %s)\n' "$REASON"
  exit 4
fi

if [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
  printf '[%s] Bearer 인증 %s — x-api-key 헤더로 1회 재시도합니다.\n' "$PROG" "$HTTP_CODE" >&2
  READ_OUT2="$(do_request x-api-key "$REQ_JSON" "$BODY_FILE2" "$ERR_FILE2")"
  HTTP_CODE2="${READ_OUT2%% *}"
  CURL_EXIT2="${READ_OUT2##* }"
  if [ "$CURL_EXIT2" != "0" ]; then
    REASON="$(_curl_exit_reason "$CURL_EXIT2")"
    printf '[%s] curl 전송 실패(exit %s, x-api-key 재시도): %s\n' "$PROG" "$CURL_EXIT2" "$REASON" >&2
    printf 'RESULT: FAIL (네트워크/전송 오류 — %s)\n' "$REASON"
    exit 4
  fi
  if [ "$HTTP_CODE2" = "200" ]; then
    printf '[%s] 참고: Bearer 미지원, x-api-key로 성공 — docs/glm-backend-kr.md 갱신 근거.\n' "$PROG" >&2
    HTTP_CODE="$HTTP_CODE2"
    BODY_FILE="$BODY_FILE2"
    AUTH_USED="x-api-key"
  else
    # The retry failed too — report the final status code/body from the x-api-key response.
    HTTP_CODE="$HTTP_CODE2"
    BODY_FILE="$BODY_FILE2"
  fi
fi

# --------------------------------------------------------------------------
# 9. HTTP status-code decision (string comparison — never coerce to arithmetic, per §A5)
# --------------------------------------------------------------------------
if [ "$HTTP_CODE" != "200" ]; then
  BODY_EXCERPT="$(head -c 300 "$BODY_FILE" 2>/dev/null || true)"
  case "$HTTP_CODE" in
    401|403)
      printf '[%s] 키 무효·만료 — Z.ai 콘솔에서 키 재확인 (Bearer/x-api-key 둘 다 %s)\n' "$PROG" "$HTTP_CODE" >&2
      ;;
    404)
      printf '[%s] 엔드포인트 경로 확인(--base-url) — HTTP 404\n' "$PROG" >&2
      ;;
    429)
      printf '[%s] 티어 할당량 초과(Lite/Pro/Max) — HTTP 429\n' "$PROG" >&2
      ;;
    400)
      printf '[%s] HTTP 400 — 모델 ID 미지원 가능. --model glm-4.6 또는 claude 별칭 시도\n' "$PROG" >&2
      printf '[%s] 응답 본문: %s\n' "$PROG" "$BODY_EXCERPT" >&2
      ;;
    5*)
      printf '[%s] Z.ai 서버 측 오류(HTTP %s) — 재시도\n' "$PROG" "$HTTP_CODE" >&2
      ;;
    *)
      printf '[%s] 예기치 않은 HTTP 상태코드: %s\n' "$PROG" "$HTTP_CODE" >&2
      ;;
  esac
  printf '[%s] 응답 본문(앞 300자): %s\n' "$PROG" "$BODY_EXCERPT" >&2
  printf 'RESULT: FAIL (HTTP %s)\n' "$HTTP_CODE"
  exit 2
fi

# --------------------------------------------------------------------------
# 10. Response verification V2-V5 (grep/sed, no jq — §A3)
# --------------------------------------------------------------------------
RESP_BODY="$(cat "$BODY_FILE" 2>/dev/null || true)"
RESP_FLAT="$(printf '%s' "$RESP_BODY" | tr '\n\r' '  ')"

_die_v() {
  # $1=reason the verification failed
  printf '[%s] 응답 검증 실패: %s\n' "$PROG" "$1" >&2
  printf '[%s] 응답 본문(앞 300자): %s\n' "$PROG" "$(printf '%s' "$RESP_BODY" | head -c 300)" >&2
  printf 'RESULT: FAIL (%s)\n' "$1"
  exit 1
}

# E-A3: detect forced streaming — an SSE 'event:' line means unsupported, so bail out.
if printf '%s' "$RESP_FLAT" | grep -Eq '^event:|"event:"'; then
  _die_v "스트리밍 응답 감지 — 비지원(단일 JSON 응답 가정)"
fi

# V2: not an error body
if printf '%s' "$RESP_FLAT" | grep -Eq '"type"[[:space:]]*:[[:space:]]*"error"'; then
  _die_v "V2 실패 — 응답이 에러 본문(\"type\":\"error\")"
fi

# V3: content present + a text block present
if ! printf '%s' "$RESP_FLAT" | grep -Eq '"content"'; then
  _die_v "V3 실패 — content 키 없음"
fi
if ! printf '%s' "$RESP_FLAT" | grep -Eq '"type"[[:space:]]*:[[:space:]]*"text"'; then
  _die_v "V3 실패 — text 타입 블록 없음"
fi

# V4: the text is non-empty (best-effort extraction for display — E-A4: it can be truncated when
# escapes are present, so the decision rests on presence alone)
TEXT_MATCH="$(printf '%s' "$RESP_FLAT" | grep -o '"text":"[^"]*"' | head -1)"
if [ -z "$TEXT_MATCH" ]; then
  _die_v "V4 실패 — 비어있지 않은 text 값 없음"
fi
TEXT_VALUE="$(printf '%s' "$TEXT_MATCH" | sed 's/^"text":"\(.*\)"$/\1/')"

# V5: model echo (warning only, non-blocking)
RESP_MODEL="$(printf '%s' "$RESP_FLAT" | grep -o '"model"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"\([^"]*\)"$/\1/')"
if [ -n "$RESP_MODEL" ] && [ "$RESP_MODEL" != "$MODEL" ]; then
  printf '[%s] 참고(V5, 비차단): 요청 모델 "%s" != 응답 모델 "%s" — Z.ai 내부 재매핑일 수 있음\n' "$PROG" "$MODEL" "$RESP_MODEL" >&2
fi

printf '[%s] V1~V4 통과: HTTP 200, 정상 응답 본문, text 블록 존재.\n' "$PROG"
printf '[%s] 응답 텍스트(표시용, 이스케이프 포함 시 잘릴 수 있음): %s\n' "$PROG" "$TEXT_VALUE"
# No-fabrication rule: "the connection worked" and "the instruction was followed" are separate
# things — printed for information only, never used in the verdict.
if printf '%s' "$TEXT_VALUE" | grep -q 'BATHOS-GLM-OK'; then
  printf '[%s] 참고: 모델이 지시된 토큰(BATHOS-GLM-OK)을 포함해 응답함(참고용, 판정 기준 아님)\n' "$PROG"
else
  printf '[%s] 참고: 모델 응답에 지시된 토큰(BATHOS-GLM-OK)이 없음 — 연결 자체는 정상(참고용, 판정 기준 아님)\n' "$PROG"
fi
if [ "$AUTH_USED" = "x-api-key" ]; then
  printf '[%s] 참고: 이 요청은 x-api-key 인증으로 성공했습니다(Bearer는 401/403).\n' "$PROG"
fi

# --------------------------------------------------------------------------
# 11. --tool-use: a second request (reusing the same auth_style) -> V6, V7
# --------------------------------------------------------------------------
if [ "$OPT_TOOL_USE" = "1" ]; then
  TOOL_REQ_JSON="$(build_tool_request "$MODEL")"
  BODY_FILE3="$(mktemp)"
  ERR_FILE3="$(mktemp)"
  trap 'rm -f "$BODY_FILE" "$ERR_FILE" "$BODY_FILE2" "$ERR_FILE2" "$BODY_FILE3" "$ERR_FILE3"' EXIT INT TERM

  if [ "$OPT_VERBOSE" = "1" ]; then
    printf '[%s] tool-use 요청 본문: %s\n' "$PROG" "$TOOL_REQ_JSON" >&2
  fi

  TOOL_OUT="$(do_request "$AUTH_USED" "$TOOL_REQ_JSON" "$BODY_FILE3" "$ERR_FILE3")"
  TOOL_HTTP="${TOOL_OUT%% *}"
  TOOL_CURL_EXIT="${TOOL_OUT##* }"

  if [ "$TOOL_CURL_EXIT" != "0" ]; then
    REASON="$(_curl_exit_reason "$TOOL_CURL_EXIT")"
    printf '[%s] tool-use 요청 전송 실패(exit %s): %s\n' "$PROG" "$TOOL_CURL_EXIT" "$REASON" >&2
    printf 'RESULT: FAIL (네트워크/전송 오류 — tool-use 요청 — %s)\n' "$REASON"
    exit 4
  fi
  if [ "$TOOL_HTTP" != "200" ]; then
    printf '[%s] tool-use 요청 HTTP %s — 응답 본문(앞 300자): %s\n' "$PROG" "$TOOL_HTTP" "$(head -c 300 "$BODY_FILE3" 2>/dev/null || true)" >&2
    printf 'RESULT: FAIL (HTTP %s — tool-use 요청)\n' "$TOOL_HTTP"
    exit 2
  fi

  TOOL_RESP_FLAT="$(cat "$BODY_FILE3" 2>/dev/null | tr '\n\r' '  ' || true)"
  # V6: a tool_use block plus the echo_token name are present
  if printf '%s' "$TOOL_RESP_FLAT" | grep -Eq '"type"[[:space:]]*:[[:space:]]*"tool_use"' \
     && printf '%s' "$TOOL_RESP_FLAT" | grep -Eq '"name"[[:space:]]*:[[:space:]]*"echo_token"'; then
    printf '[%s] V6 통과 — tool_use 블록(echo_token) 존재\n' "$PROG"
  else
    printf '[%s] tool-use 응답 본문(앞 300자): %s\n' "$PROG" "$(printf '%s' "$TOOL_RESP_FLAT" | head -c 300)" >&2
    printf 'RESULT: FAIL (V6 — tool_use 블록 없음)\n'
    exit 1
  fi
  # V7: stop_reason for reference (warning only, non-blocking — may vary by compatibility layer ⚠️[assumed])
  if printf '%s' "$TOOL_RESP_FLAT" | grep -Eq '"stop_reason"[[:space:]]*:[[:space:]]*"tool_use"'; then
    printf '[%s] V7 참고 — stop_reason=tool_use\n' "$PROG"
  else
    printf '[%s] V7 참고(비차단) — stop_reason이 "tool_use"가 아니거나 없음(호환 레이어 편차 가능)\n' "$PROG"
  fi
fi

# --------------------------------------------------------------------------
# 12. Final result
# --------------------------------------------------------------------------
printf 'RESULT: PASS — GLM 백엔드 실연결 확인 (model: %s -> %s)\n' "$MODEL" "${RESP_MODEL:-$MODEL}"
exit 0
