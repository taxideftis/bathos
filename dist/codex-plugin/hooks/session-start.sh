#!/usr/bin/env bash
# =============================================================================
# BATHOS  codex-adapter/hooks/session-start.sh  —  SessionStart 재개 안내 훅 (CT-HOOK-SESSIONSTART)
#
# Codex `resume`(그리고 `startup`) 첫 턴에, 이전 세션이 저장분을 남겨 뒀다면
# `$cold-start`로 복원 브리핑이 가능하다는 사실을 1줄 stdout으로 주입한다.
# Codex에는 SessionEnd가 없어 "종료 시 저장"을 물리 재현할 수 없다(L1) —
# stop-save.sh의 턴별 증분 저장 + 이 훅의 재개 안내 + `$save-session` 수동
# 실행 병행이 L1의 3단 완화다(design §5 참고). 이 훅은 저장을 수행하지
# 않는다(읽기·안내만) — 저장은 stop-save.sh의 몫이다.
#
# 설계 원본: .agent-team/04-architecture/adapter-contracts.md §4 (CT-HOOK-SESSIONSTART)
#
# stdin/stdout/exit 계약:
#   stdin  = Codex SessionStart JSON(hook_event_name/source/cwd 등).
#   stdout = source가 startup|resume이고 스냅샷이 있을 때만 1줄 주입.
#            그 외(스냅샷 부재·source=clear|compact 등)는 무출력.
#            **stdout이 컨텍스트로 처리된다**(Stop과 정반대 — Stop은 무출력이
#            계약, 여기는 "있으면 주입"이 계약. 혼동 금지).
#   stderr = 사용 안 함(소음 금지).
#   exit   = 항상 0(내부 오류·비-BATHOS cwd 포함) — session-start.sh(Claude판)와
#            동일 철칙: 세션 시작을 절대 막지 않는다.
# =============================================================================
set +e

PROG="session-start.sh"

# --------------------------------------------------------------------------
# 1. stdin 읽기 + 평탄화 — pretooluse-gate.sh의 _jstr 패턴 재사용(재발명 금지).
# --------------------------------------------------------------------------
INPUT="$(cat 2>/dev/null)"
INPUT_FLAT="$(printf '%s' "$INPUT" | tr '\n\r' '  ')"

_jstr() {
  printf '%s' "$INPUT_FLAT" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
    | head -1 | sed 's/.*:[[:space:]]*"\(.*\)"$/\1/'
}

EVENT="$(_jstr hook_event_name)"
SOURCE="$(_jstr source)"
CWD="$(_jstr cwd)"

# 잘못 배선돼도(다른 이벤트에 물려도) 무해하게 통과.
if [ -n "$EVENT" ] && [ "$EVENT" != "SessionStart" ]; then
  exit 0
fi

# clear/compact는 무시(무주입 통과) — 새 세션/재개가 아니므로 안내 대상이 아니다.
case "$SOURCE" in
  startup|resume) ;;
  *) exit 0 ;;
esac

# --------------------------------------------------------------------------
# 2. 경로 해석 (§B1과 동일 우선순위 — pretooluse-gate.sh와 동일 규약)
# --------------------------------------------------------------------------
PROJECT_DIR="${BATHOS_PROJECT_DIR:-${CWD:-$PWD}}"
STATE_DIR="${BATHOS_STATE_DIR:-$PROJECT_DIR/.agent-team/_state}"

# BATHOS 프로젝트가 아니면(=_state 없음) 조용히 통과 — pretooluse-gate.sh와 동일 원칙.
[ -d "$STATE_DIR" ] || exit 0

# --------------------------------------------------------------------------
# 3. 스냅샷 존재 확인 — 존재·mtime만 읽는다(내용 파싱·요약 금지, 훅에는 모델
#    턴이 없으므로 서술을 만들 수 없다).
# --------------------------------------------------------------------------
SNAPSHOT="$STATE_DIR/SESSION-SNAPSHOT.md"
[ -f "$SNAPSHOT" ] || exit 0

# mtime 포맷 — bash 3.2, macOS(BSD stat)/Linux(GNU stat) 양쪽 이식. BSD stat 우선
# 시도(이 어댑터의 1차 개발 환경) 후 GNU stat, 둘 다 실패하면 ls -l로 폴백한다
# (어느 쪽도 실패하면 빈 문자열 — 아래 메시지에서 "(시각 확인 불가)"로 대체).
_snapshot_mtime() {
  local f="$1" out
  out="$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$f" 2>/dev/null)"
  if [ -n "$out" ]; then printf '%s' "$out"; return 0; fi
  out="$(stat -c '%y' "$f" 2>/dev/null | cut -d'.' -f1)"
  if [ -n "$out" ]; then printf '%s' "$out"; return 0; fi
  ls -l "$f" 2>/dev/null | awk '{print $6, $7, $8}'
}

MTIME="$(_snapshot_mtime "$SNAPSHOT")"
[ -z "$MTIME" ] && MTIME="(시각 확인 불가)"

# --------------------------------------------------------------------------
# 4. 컨텍스트 주입 — 1줄만(장문 주입은 매 세션 소음, 상세 고지는 cold-start
#    skill 본문이 담당). L1(수동 저장 권장) 고지를 함께 담는다.
# --------------------------------------------------------------------------
printf '[bathos] 이전 세션 저장분 있음(_state/SESSION-SNAPSHOT.md, %s) — $cold-start 로 복원 브리핑 가능. 종료 훅이 없는 Codex에서는 마무리 전 $save-session 권장.\n' "$MTIME"

exit 0
