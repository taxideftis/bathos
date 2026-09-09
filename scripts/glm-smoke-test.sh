#!/usr/bin/env bash
# =============================================================================
# BATHOS P4 — scripts/glm-smoke-test.sh
# GLM(Z.ai) 실연결 스모크 테스트: Claude Code를 띄우지 않고 curl로 직접
# Z.ai의 Anthropic 호환 엔드포인트(`POST /v1/messages`)를 두드려 연결·인증·
# 응답 형태를 검증하는 읽기성(read-only) 테스트다.
#
# 설계 원본: .agent-team/04-architecture/w2-runtime-p4-design-kr.md §A (James, 2026-07-16)
# 상태 변경 없음(라이브 모드는 소량 토큰을 소비함 — max_tokens<=64, 0은 아님).
#
# 사용법:
#   scripts/glm-smoke-test.sh --dry-run                 # 키 불요, 요청 구성만 출력
#   Z_AI_API_KEY=<키> scripts/glm-smoke-test.sh          # 라이브 텍스트 검증
#   Z_AI_API_KEY=<키> scripts/glm-smoke-test.sh --tool-use
#
# 종료 코드 규약(설계 §A4 — 서로 겹치지 않게 유지, CI 원인 분기용):
#   0 = 통과(dry-run 포함)      1 = HTTP 200이나 응답 검증 실패
#   2 = HTTP 비-200             3 = 키 없음(라이브 모드)
#   4 = 네트워크/전송 오류       5 = curl 미설치
# =============================================================================
set -uo pipefail
# `set -e`는 쓰지 않는다 — curl 비-0 종료(exit 4 분기)를 우리가 직접 처리해야
# 하고, set -e 하에서는 `HTTP="$(curl ...)"` 같은 명령 치환의 실패가 스크립트를
# 조기 종료시켜 원인별 메시지를 낼 기회를 잃는다(기존 훅과 동일한 이유).

PROG="glm-smoke-test.sh"

# --------------------------------------------------------------------------
# 0. 옵션 기본값 + 인자 파싱
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
# 1. curl 존재 확인 (exit 5)
# --------------------------------------------------------------------------
if ! command -v curl >/dev/null 2>&1; then
  printf '[%s] curl이 설치되어 있지 않습니다. RESULT: FAIL (curl 미설치)\n' "$PROG" >&2
  exit 5
fi

# --------------------------------------------------------------------------
# 2. 설정 해석 (옵션 > 환경 > 기본값)
# --------------------------------------------------------------------------
BASE_URL="${OPT_BASE_URL:-${ANTHROPIC_BASE_URL:-https://api.z.ai/api/anthropic}}"
# ponytail: hardcoded latest model id goes stale each time Z.ai ships a new one, override with
# GLM_SMOKE_MODEL or --model; revisit when a docs.z.ai check shows a newer flagship than glm-5.3
MODEL="${OPT_MODEL:-${GLM_SMOKE_MODEL:-glm-5.3}}"
TIMEOUT="${OPT_TIMEOUT:-60}"
# 정규화: trailing slash 제거 후 /v1/messages를 붙인다(E-A1 — "//v1/messages" 방지).
URL="${BASE_URL%/}/v1/messages"

# 모델 값 검증(A-10): 인젝션 표면을 없애기 위해 안전 문자만 허용.
# printf 조립 시 유일한 변수 삽입 지점이 이 값이므로, 여기를 통과하면 본문
# 조립은 안전하다고 간주할 수 있다(그 외 필드는 고정 리터럴).
if ! printf '%s' "$MODEL" | grep -Eq '^[A-Za-z0-9._-]+$'; then
  printf '[%s] 모델 ID에 허용되지 않은 문자가 포함되어 있습니다: %s\n' "$PROG" "$MODEL" >&2
  printf '[%s] 허용 문자: A-Z a-z 0-9 . _ -\n' "$PROG" >&2
  printf 'RESULT: FAIL (모델 ID 검증 실패)\n'
  exit 1
fi

# 키 우선순위: ANTHROPIC_AUTH_TOKEN(Claude Code가 실제 export하는 변수) > Z_AI_API_KEY.
KEY="${ANTHROPIC_AUTH_TOKEN:-${Z_AI_API_KEY:-}}"

# 키 마스킹 헬퍼(로그에 실키가 절대 노출되지 않도록 --verbose에서도 사용).
_mask_key() {
  local k="$1"
  if [ -z "$k" ]; then
    printf '<미설정>'
  else
    printf '***(%s자)' "${#k}"
  fi
}

# --------------------------------------------------------------------------
# 3. 요청 본문 조립 (printf, heredoc 미사용 — 변수 삽입 지점은 MODEL 하나뿐)
# --------------------------------------------------------------------------
build_text_request() {
  printf '{"model":"%s","max_tokens":64,"messages":[{"role":"user","content":"Reply with exactly this token and nothing else: BATHOS-GLM-OK"}]}' "$1"
}

build_tool_request() {
  printf '{"model":"%s","max_tokens":128,"tools":[{"name":"echo_token","description":"Echo the given token back verbatim.","input_schema":{"type":"object","properties":{"token":{"type":"string"}},"required":["token"]}}],"tool_choice":{"type":"tool","name":"echo_token"},"messages":[{"role":"user","content":"Call echo_token with token=BATHOS-TOOL-OK"}]}' "$1"
}

REQ_JSON="$(build_text_request "$MODEL")"

# --------------------------------------------------------------------------
# 4. --dry-run: 키 없이도 동작. 구성 결과만 출력하고 exit 0.
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
# 5. 라이브 모드: 키 확인 (exit 3)
# --------------------------------------------------------------------------
if [ -z "$KEY" ]; then
  printf '[%s] ANTHROPIC_AUTH_TOKEN 또는 Z_AI_API_KEY 필요.\n' "$PROG" >&2
  printf '[%s] 사용: Z_AI_API_KEY=<키> scripts/glm-smoke-test.sh\n' "$PROG" >&2
  printf '[%s] 키 없이 요청 구성만 보려면 --dry-run\n' "$PROG" >&2
  printf 'RESULT: FAIL (키 없음)\n'
  exit 3
fi

# --------------------------------------------------------------------------
# 6. 임시 파일 + 정리 트랩 (§A7)
# --------------------------------------------------------------------------
BODY_FILE="$(mktemp)"
ERR_FILE="$(mktemp)"
BODY_FILE2="$(mktemp)"
ERR_FILE2="$(mktemp)"
trap 'rm -f "$BODY_FILE" "$ERR_FILE" "$BODY_FILE2" "$ERR_FILE2"' EXIT INT TERM

# --------------------------------------------------------------------------
# 7. curl 실행 헬퍼 — auth_style: bearer | x-api-key
# --------------------------------------------------------------------------
# $1=auth_style  $2=요청 본문 JSON  $3=본문 저장 파일  $4=stderr 저장 파일
# stdout으로 "HTTP_CODE CURL_EXIT"를 출력(공백 구분, 두 값 모두 항상 존재).
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

# curl exit code -> 사람이 읽는 원인 메시지 (§A4 exit 4 분기)
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
# 8. 2단 인증 전략 (ADR-P4-3): Bearer 1차 -> 401/403 시 x-api-key 1회 재시도
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
    # 재시도도 실패 — 최종 상태코드/본문은 재시도(x-api-key) 응답 기준으로 보고.
    HTTP_CODE="$HTTP_CODE2"
    BODY_FILE="$BODY_FILE2"
  fi
fi

# --------------------------------------------------------------------------
# 9. HTTP 상태코드 판정 (문자열 비교 — 산술 강제 금지, §A5 지시)
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
# 10. 응답 검증 V2~V5 (jq 없이 grep/sed — §A3)
# --------------------------------------------------------------------------
RESP_BODY="$(cat "$BODY_FILE" 2>/dev/null || true)"
RESP_FLAT="$(printf '%s' "$RESP_BODY" | tr '\n\r' '  ')"

_die_v() {
  # $1=검증 실패 사유
  printf '[%s] 응답 검증 실패: %s\n' "$PROG" "$1" >&2
  printf '[%s] 응답 본문(앞 300자): %s\n' "$PROG" "$(printf '%s' "$RESP_BODY" | head -c 300)" >&2
  printf 'RESULT: FAIL (%s)\n' "$1"
  exit 1
}

# E-A3: 강제 스트리밍 감지 — SSE 'event:' 라인이 보이면 비지원으로 처리.
if printf '%s' "$RESP_FLAT" | grep -Eq '^event:|"event:"'; then
  _die_v "스트리밍 응답 감지 — 비지원(단일 JSON 응답 가정)"
fi

# V2: 에러 본문 아님
if printf '%s' "$RESP_FLAT" | grep -Eq '"type"[[:space:]]*:[[:space:]]*"error"'; then
  _die_v "V2 실패 — 응답이 에러 본문(\"type\":\"error\")"
fi

# V3: content 존재 + text 블록 존재
if ! printf '%s' "$RESP_FLAT" | grep -Eq '"content"'; then
  _die_v "V3 실패 — content 키 없음"
fi
if ! printf '%s' "$RESP_FLAT" | grep -Eq '"type"[[:space:]]*:[[:space:]]*"text"'; then
  _die_v "V3 실패 — text 타입 블록 없음"
fi

# V4: 텍스트 비어있지 않음 (표시용 best-effort 추출 — E-A4: 이스케이프 포함 시 잘릴 수 있음, 판정은 "존재 여부"만)
TEXT_MATCH="$(printf '%s' "$RESP_FLAT" | grep -o '"text":"[^"]*"' | head -1)"
if [ -z "$TEXT_MATCH" ]; then
  _die_v "V4 실패 — 비어있지 않은 text 값 없음"
fi
TEXT_VALUE="$(printf '%s' "$TEXT_MATCH" | sed 's/^"text":"\(.*\)"$/\1/')"

# V5: 모델 echo (경고만, 비차단)
RESP_MODEL="$(printf '%s' "$RESP_FLAT" | grep -o '"model"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"\([^"]*\)"$/\1/')"
if [ -n "$RESP_MODEL" ] && [ "$RESP_MODEL" != "$MODEL" ]; then
  printf '[%s] 참고(V5, 비차단): 요청 모델 "%s" != 응답 모델 "%s" — Z.ai 내부 재매핑일 수 있음\n' "$PROG" "$MODEL" "$RESP_MODEL" >&2
fi

printf '[%s] V1~V4 통과: HTTP 200, 정상 응답 본문, text 블록 존재.\n' "$PROG"
printf '[%s] 응답 텍스트(표시용, 이스케이프 포함 시 잘릴 수 있음): %s\n' "$PROG" "$TEXT_VALUE"
# 날조 금지 원칙: "연결 성공"과 "지시 이행"은 별개다 — 참고 출력만, 판정에 미사용.
if printf '%s' "$TEXT_VALUE" | grep -q 'BATHOS-GLM-OK'; then
  printf '[%s] 참고: 모델이 지시된 토큰(BATHOS-GLM-OK)을 포함해 응답함(참고용, 판정 기준 아님)\n' "$PROG"
else
  printf '[%s] 참고: 모델 응답에 지시된 토큰(BATHOS-GLM-OK)이 없음 — 연결 자체는 정상(참고용, 판정 기준 아님)\n' "$PROG"
fi
if [ "$AUTH_USED" = "x-api-key" ]; then
  printf '[%s] 참고: 이 요청은 x-api-key 인증으로 성공했습니다(Bearer는 401/403).\n' "$PROG"
fi

# --------------------------------------------------------------------------
# 11. --tool-use: 2차 요청(같은 auth_style 재사용) -> V6, V7
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
  # V6: tool_use 블록 + echo_token 이름 존재
  if printf '%s' "$TOOL_RESP_FLAT" | grep -Eq '"type"[[:space:]]*:[[:space:]]*"tool_use"' \
     && printf '%s' "$TOOL_RESP_FLAT" | grep -Eq '"name"[[:space:]]*:[[:space:]]*"echo_token"'; then
    printf '[%s] V6 통과 — tool_use 블록(echo_token) 존재\n' "$PROG"
  else
    printf '[%s] tool-use 응답 본문(앞 300자): %s\n' "$PROG" "$(printf '%s' "$TOOL_RESP_FLAT" | head -c 300)" >&2
    printf 'RESULT: FAIL (V6 — tool_use 블록 없음)\n'
    exit 1
  fi
  # V7: stop_reason 참고(경고만, 비차단 — 호환 레이어별 편차 가능 ⚠️[추정])
  if printf '%s' "$TOOL_RESP_FLAT" | grep -Eq '"stop_reason"[[:space:]]*:[[:space:]]*"tool_use"'; then
    printf '[%s] V7 참고 — stop_reason=tool_use\n' "$PROG"
  else
    printf '[%s] V7 참고(비차단) — stop_reason이 "tool_use"가 아니거나 없음(호환 레이어 편차 가능)\n' "$PROG"
  fi
fi

# --------------------------------------------------------------------------
# 12. 최종 결과
# --------------------------------------------------------------------------
printf 'RESULT: PASS — GLM 백엔드 실연결 확인 (model: %s -> %s)\n' "$MODEL" "${RESP_MODEL:-$MODEL}"
exit 0
