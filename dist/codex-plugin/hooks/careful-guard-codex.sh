#!/usr/bin/env bash
# =============================================================================
# BATHOS  codex-adapter/hooks/careful-guard-codex.sh  —  Codex판 careful 안전 훅 (CT-SAFETY)
#
# PreToolUse: 파괴적 명령을 실행 전에 하드 차단한다. 패턴 정본은
# `.claude/hooks/careful-guard.sh`를 그대로 승계한다(정책 분기 금지 — 목록을
# 새로 발명하지 않는다, story-15 AC#1) — 이 파일은 그 목록을 Codex의
# stdin 스키마(snake_case, tool_input 중첩, jq 없이 grep/sed만)에 맞춰
# 재배선한 것일 뿐이다.
#
# `.claude/hooks/`가 아니라 `codex-adapter/hooks/`에 두는 이유: freeze-guard의
# 소유 경로 검사와의 충돌 회피 + Codex 전용 코드의 물리 분리(§B4, 게이트
# 훅과 동일 근거).
#
# 대상 tool_name: shell/exec_command/Bash(명령 실행 도구)만 — apply_patch/
# Edit/Write는 파일 편집이지 명령 실행이 아니므로 대상 밖이다(Claude판이
# Bash만 검사하는 것과 동일 논리 — freeze-guard-codex.sh가 편집 쪽을 맡는다).
#
# stdin/stdout/exit 계약(CT-HOOK-GATE와 동일 규약 재사용):
#   stdin  = Codex PreToolUse JSON. stdout = 사용 안 함(비움 유지).
#   stderr = 차단 사유만. exit = 0(통과) | 2(차단, E-SAFETY-CAREFUL).
#   내부 오류·비-BATHOS cwd·패턴 미매치·대상 외 도구는 전부 exit 0(fail-safe).
#   **오차단 0이 판정 기준**(US11-AC3) — 정상 명령을 1건이라도 막으면 FAIL.
#
# matcher(hooks.json 배선 참조 — story-15 AC#8, _test-codex-hooks.sh가 이 줄을
# config.toml.example·.codex/hooks.json과 바이트 단위로 대조한다. 넷 중 하나만
# 고치면 드리프트 — matcher 4차 재발 방지 지점):
#   ^(Bash|shell|exec_command|apply_patch|Edit|Write)$
# =============================================================================
set -uo pipefail

PROG="careful-guard-codex.sh"

# --------------------------------------------------------------------------
# 1. stdin 읽기 + 평탄화 — pretooluse-gate.sh의 _jstr 패턴 재사용(재발명 금지).
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

# 명령 실행 도구만 대상(ADR-CX-02 광폭 3종 — Bash/shell/exec_command). 도구명
# 미확인이면 Claude판과 동일하게 보수적으로 계속 진행(빈 CMD로 자연 통과).
case "$TOOL" in
  shell|exec_command|Bash) ;;
  "") ;;
  *) exit 0 ;;
esac

CMD="$(_jstr command)"
[ -z "$CMD" ] && exit 0

# --------------------------------------------------------------------------
# 2. 경로 해석 (§B1) — 감사 로그 append용 BATHOS_BIN/STATE_DIR 탐색.
# --------------------------------------------------------------------------
PROJECT_DIR="${BATHOS_PROJECT_DIR:-${CWD:-$PWD}}"
STATE_DIR="${BATHOS_STATE_DIR:-$PROJECT_DIR/.agent-team/_state}"

# Codex 훅 등록은 유저 레벨(~/.codex/config.toml)일 수 있어 여러 프로젝트를
# 오갈 수 있다(§B1) — BATHOS 프로젝트가 아니면(=_state 없음) 조용히 통과한다.
# Claude판 careful-guard.sh는 이 검사가 없지만(Claude Code 훅은 항상 프로젝트
# 스코프), Codex 어댑터의 다른 훅들(pretooluse-gate/stop-save/session-start)과
# 동일 규약을 신설 파일에 적용하는 것이 옳다(story-15 AC#4 "비-BATHOS cwd").
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
# 3. 위험 패턴 목록 — `.claude/hooks/careful-guard.sh` 정본 그대로 승계
#    (정책 분기 금지 — 이 목록을 임의 확장/축소하지 않는다. 변경이 필요하면
#    Claude판과 동시에만).
# --------------------------------------------------------------------------
DANGER_PATTERNS=(
  # --- 파일시스템 파괴 ---
  'rm[[:space:]]+-[[:alpha:]]*r[[:alpha:]]*f([[:space:]]|$)'  # rm -rf, rm -fr, rm -Rf 등
  'rm[[:space:]]+-[[:alpha:]]*f[[:alpha:]]*r([[:space:]]|$)'  # rm -fr 변형
  'rm[[:space:]]+-rf[[:space:]]*/([^/]|$)'                   # rm -rf / (루트)
  'rm[[:space:]]+-rf[[:space:]]+~'                            # rm -rf ~ (홈)
  'rm[[:space:]]+-rf[[:space:]]+\.'                           # rm -rf . (현재 디렉터리)
  'rm[[:space:]]+-rf[[:space:]]+\*'                           # rm -rf * (와일드카드)

  # --- 디스크 초기화 / 덮어쓰기 ---
  'mkfs\.'                                                     # mkfs.ext4 등
  'dd[[:space:]]+if='                                          # dd if=... (디스크 덮어쓰기)
  ':>[[:space:]]*/[^[:space:]]'                                # :> /path (파일 덮어쓰기)
  'shred[[:space:]]'                                           # shred (복구불가 삭제)

  # --- SQL 파괴적 DML/DDL ---
  'DROP[[:space:]]+(TABLE|DATABASE|SCHEMA|INDEX)'              # DROP 계열
  'TRUNCATE[[:space:]]+TABLE'                                  # TRUNCATE (전체 삭제, 롤백 불가)
  # DELETE without WHERE는 ERE 단일 패턴으로 정확히 표현 불가 → 섹션 4b에서 2단계 검사

  # --- git 파괴적 명령 ---
  'git[[:space:]]+push[[:space:]].*--force'                   # git push --force
  'git[[:space:]]+push[[:space:]].*-f([[:space:]]|$)'         # git push -f
  'git[[:space:]]+push[[:space:]].*-f[[:space:]]'             # git push -f <remote>
  'git[[:space:]]+reset[[:space:]]+--hard'                    # git reset --hard
  'git[[:space:]]+checkout[[:space:]]+-[Bf]'                  # git checkout -B/-f
  'git[[:space:]]+clean[[:space:]]+-f'                        # git clean -f (미추적 파일 삭제)
  'git[[:space:]]+branch[[:space:]]+-D'                       # git branch -D (강제 삭제)

  # --- 권한/소유권 위험 ---
  'chmod[[:space:]]+-R[[:space:]]+777'                         # chmod -R 777
  'chown[[:space:]]+-R[[:space:]]+(root|0)'                   # chown -R root

  # --- sudo 위험 조합 ---
  'sudo[[:space:]]+(rm|dd|mkfs|shred|chmod|chown)'            # sudo + 파괴 명령

  # --- 위험 경로 Bash 우회 변경 (Dynamis A1/risk-log A-3, 완전성 미주장) ---
  '>[[:space:]]*[^&|;]*\.claude/settings\.json'                       # settings.json 리다이렉트 덮어쓰기
  '>>?[[:space:]]*[^&|;]*\.claude/hooks/'                             # hooks/ 아래 파일 리다이렉트
  'sed[[:space:]]+-i[^|;]*\.claude/(settings\.json|hooks/)'           # sed -i로 훅/설정 직접 수정
  '(curl|wget)[[:space:]][^|;]*(-o|-O|--output)[[:space:]]*[^&|;]*\.claude/(settings\.json|hooks/)'  # curl/wget으로 훅/설정 덮어쓰기
  '(printf|echo)[^|;]*>[[:space:]]*[^&|;]*_state/manifest\.json'      # manifest.json 직접 리다이렉트 쓰기
  'jq[^|;]*>[[:space:]]*[^&|;]*_state/manifest\.json'                 # jq 파이프로 manifest.json 우회 편집
  '(cp|mv)[[:space:]]+[^|;]+[[:space:]]+[^&|;]*\.claude/(settings\.json|hooks/)'  # cp/mv로 훅/설정 교체
  '>>?[[:space:]]*[^&|;]*\.github/workflows/'                         # CI 워크플로 리다이렉트 쓰기

  # --- Bash 우회 쓰기 추가 차단 (SEC-01 보강 승계) ---
  'tee[[:space:]][^|;]*\.claude/(settings\.json|hooks/)'             # tee로 훅/설정 덮어쓰기
  'tee[[:space:]][^|;]*_state/manifest\.json'                        # tee로 manifest 덮어쓰기
  'tee[[:space:]][^|;]*\.github/workflows/'                          # tee로 CI 워크플로 덮어쓰기
  'dd[[:space:]][^|;]*of=[^&|;]*\.claude/(settings\.json|hooks/)'    # dd of=로 훅/설정 덮어쓰기
  'patch[[:space:]][^|;]*\.claude/(settings\.json|hooks/)'           # patch로 훅/설정 변경
)

# --------------------------------------------------------------------------
# 4. 패턴 검사
# --------------------------------------------------------------------------
DETECTED_PATTERN=""
for PATTERN in "${DANGER_PATTERNS[@]}"; do
  if printf '%s' "$CMD" | grep -Eiq "$PATTERN"; then
    DETECTED_PATTERN="$PATTERN"
    break
  fi
done

# --------------------------------------------------------------------------
# 4b. WHERE 없는 DELETE 2단계 검사 (careful-guard.sh L-4 보강 승계 — 동일 균형 원칙)
# --------------------------------------------------------------------------
if [ -z "$DETECTED_PATTERN" ]; then
  if printf '%s' "$CMD" | grep -Eiq 'DELETE[[:space:]]+FROM[[:space:]]+[[:alnum:]_"`.]+'; then
    if ! printf '%s' "$CMD" | grep -Eiq '[[:space:]]WHERE[[:space:]]'; then
      DETECTED_PATTERN="DELETE FROM ... (WHERE 없는 전체 삭제 — L-4 보강)"
    fi
  fi
fi

# --------------------------------------------------------------------------
# 5. 감사 로그 append (best-effort, pretooluse-gate.sh와 동일 패턴)
# --------------------------------------------------------------------------
_append_audit() {
  local action="$1"
  [ -n "$BATHOS_BIN" ] && [ -x "$BATHOS_BIN" ] || return 0
  local cmd_excerpt
  cmd_excerpt="$(printf '%s' "$CMD" | head -c 200 | tr '"\\\n\r\t' "    ")"
  "$BATHOS_BIN" -s "$STATE_DIR" audit append \
    --actor "hook:codex-careful" \
    --action "$action" \
    --target "$cmd_excerpt" 2>/dev/null || true
}

# --------------------------------------------------------------------------
# 6. 차단 또는 통과
# --------------------------------------------------------------------------
if [ -n "$DETECTED_PATTERN" ]; then
  _append_audit "block"
  cat >&2 <<EOF
[bathos codex-careful] BLOCKED: 파괴적/위험경로 우회 명령이 감지되어 차단합니다(E-SAFETY-CAREFUL).
명령: $(printf '%s' "$CMD" | head -c 300)
감지 패턴: $DETECTED_PATTERN
이 명령을 실행하려면 의도·영향 범위·롤백 방법을 사용자에게 설명하고 명시적 승인을 받으십시오.
참고: exceptions.md §1 E-SAFETY-CAREFUL, .claude/hooks/careful-guard.sh(정본 패턴)
EOF
  exit 2
fi

exit 0
