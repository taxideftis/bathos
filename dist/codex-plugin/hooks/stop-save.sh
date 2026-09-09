#!/usr/bin/env bash
# =============================================================================
# BATHOS P4 — codex-adapter/hooks/stop-save.sh
# Codex Stop 훅: SessionEnd가 없는 Codex에서 "세션 종료 시 1회 저장"(CLAUDE.md
# §9)을 물리적으로 재현할 수 없으므로, 매 턴 종료(Stop)마다 증분 저장으로
# 근사한다.
#
# 설계 원본: .agent-team/04-architecture/w2-runtime-p4-design-kr.md §B3 (James)
#
# 정직한 한계(문서·출력 양쪽에 명시):
#   - 이 근사가 주는 것: 세션이 어떻게 죽어도(크래시 포함) 마지막 완료 턴
#     시점의 상태 덤프는 남는다 — 사실상 SessionEnd보다 유실 창이 좁다
#     (턴 단위 vs 세션 단위).
#   - 이 근사가 못 주는 것:
#     (a) "종료 직전" 정확 시점 스냅샷이 아니다.
#     (b) LLM 서술 스냅샷(SESSION-SNAPSHOT.md "★ 현재 상태") 생성 불가 —
#         훅에는 모델 턴이 없다. Codex에서도 `/save-session` 상당(프롬프트)
#         수동 실행 병행이 정답이다.
#     (c) HTML 태스크리포트 생성은 이 훅 범위 밖(session-report.sh 이식은
#         P4 스코프 아님).
#
# stdin/stdout/exit 계약:
#   stdin  = Codex Stop JSON(session_id/turn_id/stop_hook_active/cwd 등).
#   stdout = 사용 안 함. stderr = 경고만(선택).
#   exit   = 항상 0. Stop 훅에서 비-0(특히 2)은 "턴 종료 차단 -> 강제 계속"
#            의미가 될 수 있어(⚠️[추정], Claude Code Stop 의미론 유추) 무한
#            루프 위험이 있다 — 어떤 내부 실패도 0으로 수렴시킨다.
# =============================================================================
set +e
# session-start.sh 스타일: 이 훅은 절대 세션 진행을 방해하지 않는다.

PROG="stop-save.sh"

# --------------------------------------------------------------------------
# 1. stdin 읽기 + 평탄화
# --------------------------------------------------------------------------
INPUT="$(cat 2>/dev/null)"
INPUT_FLAT="$(printf '%s' "$INPUT" | tr '\n\r' '  ')"

_jstr() {
  printf '%s' "$INPUT_FLAT" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
    | head -1 | sed 's/.*:[[:space:]]*"\(.*\)"$/\1/'
}
_jbool() {
  printf '%s' "$INPUT_FLAT" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\(true\|false\)" \
    | head -1 | grep -Eo '(true|false)$'
}

STOP_HOOK_ACTIVE="$(_jbool stop_hook_active)"
SESSION_ID="$(_jstr session_id)"
TURN_ID="$(_jstr turn_id)"
CWD="$(_jstr cwd)"

# 루프 이중 안전장치: stop_hook_active=true면 즉시 통과(아무 파일도 건드리지
# 않는다 — B-14가 이를 계약화).
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

# --------------------------------------------------------------------------
# 2. 경로 해석 (§B1과 동일 우선순위)
# --------------------------------------------------------------------------
PROJECT_DIR="${BATHOS_PROJECT_DIR:-${CWD:-$PWD}}"
STATE_DIR="${BATHOS_STATE_DIR:-$PROJECT_DIR/.agent-team/_state}"

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
# 3. 디바운스 판정 (§B3-4 — find -newermt 금지, 플랫폼 분기 없는 자기기록 방식)
# --------------------------------------------------------------------------
# 마커 파일 형식: 1행 = 마지막 heavy-save epoch(자기 기록), 2행~ = 사람이
# 읽는 로그(500줄 초과 시 tail -n 500으로 롤링, 1행은 항상 보존).
MARKER="$STATE_DIR/codex-stop-save.log"
DEBOUNCE="${BATHOS_STOP_SAVE_DEBOUNCE:-10}"

NOW_EPOCH="$(date +%s 2>/dev/null || echo 0)"
LAST_EPOCH=0
if [ -f "$MARKER" ]; then
  FIRST_LINE="$(head -1 "$MARKER" 2>/dev/null || echo 0)"
  # 숫자가 아니면(레거시/손상 마커) 0으로 취급 — heavy 경로로 강제 진행.
  if printf '%s' "$FIRST_LINE" | grep -Eq '^[0-9]+$'; then
    LAST_EPOCH="$FIRST_LINE"
  fi
fi

HEAVY=1
if [ "$DEBOUNCE" -gt 0 ] 2>/dev/null; then
  DELTA=$(( NOW_EPOCH - LAST_EPOCH ))
  if [ "$DELTA" -lt "$DEBOUNCE" ]; then
    HEAVY=0
  fi
fi

# --------------------------------------------------------------------------
# 4. SSOT 덤프 (원자적 tmp -> mv, heavy일 때만)
# --------------------------------------------------------------------------
DUMP_STATUS="no-bathos"
if [ "$HEAVY" = "1" ]; then
  if [ -n "$BATHOS_BIN" ] && [ -x "$BATHOS_BIN" ]; then
    TMP_STATE="$(mktemp "$STATE_DIR/session-state.json.tmp.XXXXXX" 2>/dev/null || echo "$STATE_DIR/session-state.json.tmp")"
    if "$BATHOS_BIN" -s "$STATE_DIR" state show > "$TMP_STATE" 2>/dev/null && [ -s "$TMP_STATE" ]; then
      # E-B6: 새 덤프가 비었으면 교체하지 않는다(기존본 보호) — 위 [ -s ] 검사가
      # 이를 보장한다. 성공 시에만 원자 교체.
      mv "$TMP_STATE" "$STATE_DIR/session-state.json" 2>/dev/null && DUMP_STATUS="ok"
    fi
    rm -f "$TMP_STATE" 2>/dev/null
  fi
else
  DUMP_STATUS="skip"
fi

# --------------------------------------------------------------------------
# 5. 스냅샷 날짜 아카이브 (있을 때만 — 훅은 서술을 생성하지 않는다, heavy일 때만)
# --------------------------------------------------------------------------
if [ "$HEAVY" = "1" ]; then
  SNAPSHOT="$STATE_DIR/SESSION-SNAPSHOT.md"
  if [ -f "$SNAPSHOT" ]; then
    TODAY="$(date '+%Y-%m-%d' 2>/dev/null || echo unknown-date)"
    ARCHIVE="$STATE_DIR/SESSION-SNAPSHOT-$TODAY.md"
    # 아카이브가 없거나 원본이 더 새로우면 복사(session-end.sh 아카이브 동작 근사).
    if [ ! -f "$ARCHIVE" ] || [ "$SNAPSHOT" -nt "$ARCHIVE" ]; then
      cp "$SNAPSHOT" "$ARCHIVE" 2>/dev/null || true
    fi
  fi
fi

# --------------------------------------------------------------------------
# 6. 마커 로그 append + 500줄 롤링 (1행 epoch 보존)
# --------------------------------------------------------------------------
LOG_LINE="$(date '+%Y-%m-%d %H:%M:%S %z' 2>/dev/null || echo unknown-time) | session=${SESSION_ID:-unknown} | turn=${TURN_ID:-unknown} | dump=$DUMP_STATUS"

if [ ! -f "$MARKER" ]; then
  {
    printf '%s\n' "$NOW_EPOCH"
    printf '%s\n' "$LOG_LINE"
  } > "$MARKER" 2>/dev/null
else
  # heavy 저장을 실제로 수행했을 때만 1행의 epoch을 갱신한다(디바운스 스킵 시엔
  # 기존 LAST_EPOCH을 그대로 보존해야 다음 판정이 정확하다).
  NEW_FIRST="$LAST_EPOCH"
  [ "$HEAVY" = "1" ] && NEW_FIRST="$NOW_EPOCH"
  TMP_MARKER="$(mktemp "$STATE_DIR/codex-stop-save.log.tmp.XXXXXX" 2>/dev/null || echo "$STATE_DIR/codex-stop-save.log.tmp")"
  # 1행(epoch)은 별도로 항상 보존하고, 본문(2행~)만 500줄로 롤링한다 — 본문이
  # 500줄을 넘겨도 1행이 tail에 밀려 유실되지 않도록 두 스트림을 분리 처리.
  {
    tail -n +2 "$MARKER" 2>/dev/null
    printf '%s\n' "$LOG_LINE"
  } | tail -n 500 > "${TMP_MARKER}.body" 2>/dev/null
  {
    printf '%s\n' "$NEW_FIRST"
    cat "${TMP_MARKER}.body" 2>/dev/null
  } > "$TMP_MARKER" 2>/dev/null
  if [ -s "$TMP_MARKER" ]; then
    mv "$TMP_MARKER" "$MARKER" 2>/dev/null
  fi
  rm -f "$TMP_MARKER" "${TMP_MARKER}.body" 2>/dev/null
fi

exit 0
