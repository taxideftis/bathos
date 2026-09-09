#!/usr/bin/env bash
# =============================================================================
# BATHOS  codex-adapter/hooks/freeze-guard-codex.sh  —  Codex판 freeze 안전 훅 (CT-SAFETY)
#
# PreToolUse: 소유 경로(BATHOS_OWNED_PATHS) 밖 파일 편집을 차단한다. 스코프는
# adapter-contracts.md §10이 명시한 대로 **apply_patch(및 별칭 Edit/Write)의
# 절대경로 검사**뿐이다 — Claude판 freeze-guard.sh의 §5 "위험 경로 fingerprint
# 게이트"(jq 필수, Dynamis A1 추가분)는 이 포트의 스코프 밖이다(jq 금지 규율과
# 정면 충돌하고, story-15 AC에도 명시되지 않음 — 새로 발명 금지 원칙에 따라
# 요청된 부분만 포팅한다). 소유 경로 검사(§6-8, jq 불요)만 승계한다.
#
# `.claude/hooks/`가 아니라 `codex-adapter/hooks/`에 두는 이유: 이 파일 자신의
# 소유 경로 검사와 Claude판이 충돌하지 않도록 물리 분리(§B4, 게이트 훅과 동일
# 근거).
#
# 대상 tool_name: apply_patch/Edit/Write(파일 편집 도구)만 — shell/exec_command/
# Bash는 careful-guard-codex.sh의 파괴 명령 패턴이 담당한다(Claude판이 Bash를
# freeze 대상에서 제외하는 것과 동일 논리 — "활성 상태 소스" 재사용 원칙,
# story-15 AC#5).
#
# 경로 추출: apply_patch는 패치 헤더의 "Update File: <path>"에서(P5.1 실측 —
# 절대경로로 옴), Edit/Write는 tool_input.file_path 필드에서(문서 별칭 스키마
# 가정, freeze-guard.sh와 동일 필드명 관례).
#
# stdin/stdout/exit 계약(CT-HOOK-GATE와 동일 규약):
#   stdout = 사용 안 함. stderr = 차단 사유만. exit = 0(통과) | 2(차단, E-SAFETY-FREEZE).
#   내부 오류·비-BATHOS cwd·소유 경로 미설정·경로 없음은 전부 exit 0(fail-safe).
#
# matcher(hooks.json 배선 참조 — story-15 AC#8, _test-codex-hooks.sh가 이 줄을
# config.toml.example·.codex/hooks.json과 바이트 단위로 대조한다. 넷 중 하나만
# 고치면 드리프트 — matcher 4차 재발 방지 지점):
#   ^(Bash|shell|exec_command|apply_patch|Edit|Write)$
# =============================================================================
set -uo pipefail

PROG="freeze-guard-codex.sh"

# --------------------------------------------------------------------------
# 1. stdin 읽기 + 평탄화
# --------------------------------------------------------------------------
INPUT="$(cat 2>/dev/null || true)"
INPUT_FLAT="$(printf '%s' "$INPUT" | tr '\n\r' '  ')"

_jstr() {
  printf '%s' "$INPUT_FLAT" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
    | head -1 | sed 's/.*:[[:space:]]*"\(.*\)"$/\1/'
}

EVENT="$(_jstr hook_event_name)"
TOOL="$(_jstr tool_name)"
CWD="$(_jstr cwd)"

if [ -n "$EVENT" ] && [ "$EVENT" != "PreToolUse" ]; then
  exit 0
fi

# 파일 편집 도구만 대상 — 그 외(shell/exec_command/Bash 등)는 통과
# (Claude판이 Write/Edit/MultiEdit만 검사하는 것과 동일 관례).
case "$TOOL" in
  apply_patch|Edit|Write) ;;
  "") ;;   # 도구명 미확인 -> 보수적으로 계속(아래에서 FILE_PATH 없으면 자연 통과)
  *) exit 0 ;;
esac

# --------------------------------------------------------------------------
# 2. 경로 해석 (§B1)
# --------------------------------------------------------------------------
PROJECT_DIR="${BATHOS_PROJECT_DIR:-${CWD:-$PWD}}"
STATE_DIR="${BATHOS_STATE_DIR:-$PROJECT_DIR/.agent-team/_state}"

# Codex 훅 등록은 유저 레벨일 수 있어 여러 프로젝트를 오갈 수 있다(§B1) —
# BATHOS 프로젝트가 아니면(=_state 없음) 조용히 통과한다(story-15 AC#4,
# careful-guard-codex.sh와 동일 근거 — 신설 Codex 훅 공통 규약).
[ -d "$STATE_DIR" ] || exit 0

BATHOS_BIN="${BATHOS_BIN:-}"
if [ -z "$BATHOS_BIN" ]; then
  for cand in \
    "$PROJECT_DIR/core/target/release/bathos" \
    "$PROJECT_DIR/core/target/debug/bathos"
  do
    if [ -x "$cand" ]; then BATHOS_BIN="$cand"; break; fi
  done
  if [ -z "$BATHOS_BIN" ] && command -v bathos >/dev/null 2>&1; then
    BATHOS_BIN="$(command -v bathos)"
  fi
fi

# --------------------------------------------------------------------------
# 3. 대상 파일 경로 추출 — apply_patch(패치 헤더) 우선, 없으면 file_path 필드
#    (Edit/Write 별칭 스키마 가정).
# --------------------------------------------------------------------------
FILE_PATH="$(printf '%s' "$INPUT_FLAT" | grep -oE 'Update File:[[:space:]]*[^[:space:]]+' \
  | head -1 | sed -E 's/^Update File:[[:space:]]*//')"
if [ -z "$FILE_PATH" ]; then
  FILE_PATH="$(_jstr file_path)"
fi

[ -z "$FILE_PATH" ] && exit 0

# --------------------------------------------------------------------------
# 4. 경로 정규화 — PROJECT_DIR 기준 상대 경로로 변환(freeze-guard.sh §3과 동일
#    로직 — P5.1 절대경로 실측을 여기서도 반영: apply_patch는 절대경로로 옴).
# --------------------------------------------------------------------------
case "$FILE_PATH" in
  "$PROJECT_DIR"/*) REL_PATH="${FILE_PATH#"$PROJECT_DIR"/}" ;;
  *) REL_PATH="$FILE_PATH" ;;
esac

# --------------------------------------------------------------------------
# 5. 감사 로그 append (best-effort)
# --------------------------------------------------------------------------
_append_audit() {
  local action="$1"
  [ -n "$BATHOS_BIN" ] && [ -x "$BATHOS_BIN" ] || return 0
  local safe_path
  safe_path="$(printf '%s' "$REL_PATH" | tr '"\\\n\r' "   ")"
  "$BATHOS_BIN" -s "$STATE_DIR" audit append \
    --actor "hook:codex-freeze" \
    --action "$action" \
    --target "$safe_path" 2>/dev/null || true
}

# --------------------------------------------------------------------------
# 6. BATHOS_OWNED_PATHS 미설정 시 freeze 비활성 — Claude판과 동일한 상태 소스
#    (Codex 전용 상태 파일 신설 금지, story-15 AC#5). Paul이 스폰 시 동일 env로
#    양쪽(Claude 팀원/Codex run-role) 소유 경로를 주입할 책임을 진다.
# --------------------------------------------------------------------------
OWNED_PATHS="${BATHOS_OWNED_PATHS:-}"
if [ -z "$OWNED_PATHS" ]; then
  exit 0
fi

# --------------------------------------------------------------------------
# 7. owned_paths 패턴 매칭 — freeze-guard.sh is_owned()와 동일 규칙:
#      "foo/bar/**"   → foo/bar/ 하위 모든 경로 허용 (prefix 매칭)
#      "foo/bar/*.md" → bash glob (단일 세그먼트 와일드카드)
#      "foo/bar.txt"  → 정확 일치
# --------------------------------------------------------------------------
is_owned() {
  local path="$1"
  local IFS=':'
  local pattern
  for pattern in $OWNED_PATHS; do
    [ -z "$pattern" ] && continue
    case "$pattern" in
      */\*\*)
        local prefix="${pattern%/**}/"
        case "$path" in
          "$prefix"*) return 0 ;;
        esac
        ;;
      *)
        # shellcheck disable=SC2254
        case "$path" in
          $pattern) return 0 ;;
        esac
        ;;
    esac
  done
  return 1
}

# --------------------------------------------------------------------------
# 8. 소유 경로 검사
# --------------------------------------------------------------------------
if is_owned "$REL_PATH"; then
  exit 0
fi

_append_audit "freeze-violation"

cat >&2 <<EOF
[bathos codex-freeze] BLOCKED: 소유 경로 밖 편집이 차단되었습니다(E-SAFETY-FREEZE).
대상 파일: $REL_PATH
허용 경로(BATHOS_OWNED_PATHS): $OWNED_PATHS
소유 경로 밖을 수정해야 한다면:
  1. 해당 경로 소유자와 메시지로 합의하거나
  2. 리드(Paul)에게 보고하십시오.
참고: exceptions.md §1 E-SAFETY-FREEZE, .claude/hooks/freeze-guard.sh(정본 로직)
EOF
exit 2
