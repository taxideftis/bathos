#!/usr/bin/env bash
# =============================================================================
# BATHOS M6 — careful-guard.sh   [Dynamis A1 — 위험 경로 Bash 우회 하드닝 추가]
# PreToolUse(Bash): 파괴적 명령을 실행 전에 하드 차단 + 사용자 확인 요구
# =============================================================================
# 계약:  api-contracts.md §D (PreToolUse careful-guard)
# 예외:  exceptions.md §5 E-DESTRUCTIVE
# DoD:   파괴명령 → exit 2(차단) + stderr 피드백; 정상 명령 → exit 0(통과)
# 안전:  거짓양성(과차단) > 거짓음성(놓침) — ETHOS careful 원칙
# 바이너리 의존: 없어도 동작(감사로그 선택적 append만 시도)
#
# [Dynamis A1 추가 — risk-log A-3 재기술 준수]
#   위험 경로(.claude/settings.json · .claude/hooks/* · .github/workflows/* ·
#   _state/manifest.json)를 리다이렉트(`>`)·sed -i·curl -o·jq 파이프 등 Bash로
#   우회 변경하려는 시도를 추가로 차단한다(open-swe pr_creation_guard 사상 —
#   "지정 도구로만 변경 가능, 우회 시 하드 블록").
#   ⚠️  **완전성 미주장**: 이 목록은 흔한 우회 패턴만 다룬다(기존 DANGER_PATTERNS와
#   동일하게 "알려진 한계"가 있다 — 예: 복잡한 서브셸/변수 치환으로 명령을 조립하면
#   놓칠 수 있음). 100% 차단이 필요한 경로는 Write/Edit/MultiEdit 경로를 통해서만
#   보장된다(freeze-guard.sh의 dangerous-path fingerprint 게이트, AC2 참고).
# =============================================================================
set -uo pipefail

# --------------------------------------------------------------------------
# 1. 자기 위치 기반 경로 해석 (standalone / 내포 모두 지원)
# --------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# SCRIPT_DIR = <root>/bathos/.claude/hooks  or  <bathos-root>/.claude/hooks
BATHOS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$BATHOS_ROOT}"
BATHOS_BIN="${BATHOS_BIN:-$BATHOS_ROOT/core/target/debug/bathos}"
STATE_DIR="${BATHOS_STATE_DIR:-$PROJECT_DIR/.agent-team/_state}"

# --------------------------------------------------------------------------
# 2. stdin JSON 파싱 (jq 있으면 파싱, 없으면 원문 사용)
# --------------------------------------------------------------------------
INPUT="$(cat || true)"
CMD=""
TOOL=""
if command -v jq >/dev/null 2>&1; then
  CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
  TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"
else
  # jq 없으면 원문 전체를 CMD로 처리 (보수적: 위험 패턴이 있으면 차단)
  CMD="$INPUT"
fi

# Bash 도구가 아니면 통과 (도구명 확인 가능한 경우만)
if [[ -n "$TOOL" && "$TOOL" != "Bash" ]]; then
  exit 0
fi

# 명령이 비어 있으면 통과
[[ -z "$CMD" ]] && exit 0

# --------------------------------------------------------------------------
# 3. 위험 패턴 목록
# --------------------------------------------------------------------------
# 각 원소: ERE(Extended Regular Expression), grep -Eiq 로 검사 — **대소문자 무시**.
# ⚠️ 대소문자가 의미를 갖는 패턴은 이 배열이 아니라 아래 DANGER_PATTERNS_CS 에 둔다.
#    (예: `git branch -D`는 강제 삭제지만 `-d`는 머지된 브랜치만 지우는 안전 삭제다.
#     여기에 두면 -i 탓에 안전한 쪽까지 차단된다 — #39)
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

  # --- git 파괴적 명령 → DANGER_PATTERNS_CS 로 이전(#39) ---
  #   git 플래그는 대소문자가 곧 의미라 -i 검사에 둘 수 없다.

  # --- 권한/소유권 위험 ---
  'chmod[[:space:]]+-R[[:space:]]+777'                         # chmod -R 777
  'chown[[:space:]]+-R[[:space:]]+(root|0)'                   # chown -R root

  # --- sudo 위험 조합 ---
  'sudo[[:space:]]+(rm|dd|mkfs|shred|chmod|chown)'            # sudo + 파괴 명령

  # --- [Dynamis A1 신규] 위험 경로 Bash 우회 변경 (risk-log A-3, 완전성 미주장) ---
  '>[[:space:]]*[^&|;]*\.claude/settings\.json'                       # settings.json 리다이렉트 덮어쓰기
  '>>?[[:space:]]*[^&|;]*\.claude/hooks/'                             # hooks/ 아래 파일 리다이렉트
  'sed[[:space:]]+-i[^|;]*\.claude/(settings\.json|hooks/)'           # sed -i로 훅/설정 직접 수정
  '(curl|wget)[[:space:]][^|;]*(-o|-O|--output)[[:space:]]*[^&|;]*\.claude/(settings\.json|hooks/)'  # curl/wget으로 훅/설정 덮어쓰기
  '(printf|echo)[^|;]*>[[:space:]]*[^&|;]*_state/manifest\.json'      # manifest.json 직접 리다이렉트 쓰기
  'jq[^|;]*>[[:space:]]*[^&|;]*_state/manifest\.json'                 # jq 파이프로 manifest.json 우회 편집
  '(cp|mv)[[:space:]]+[^|;]+[[:space:]]+[^&|;]*\.claude/(settings\.json|hooks/)'  # cp/mv로 훅/설정 교체
  '>>?[[:space:]]*[^&|;]*\.github/workflows/'                         # CI 워크플로 리다이렉트 쓰기

  # --- [SEC-01 보강] Bash 우회 쓰기 추가 차단 (W6 Michael 보안감사) ---
  #   여전히 "완전성 미주장": python -c / perl -e / 변수치환(`f=…; >"$f"`) 등 임의 인터프리터
  #   쓰기는 패턴으로 못 잡는다. 위험경로 변경의 진짜 게이트는 Write/Edit + freeze-guard fingerprint.
  'tee[[:space:]][^|;]*\.claude/(settings\.json|hooks/)'             # tee로 훅/설정 덮어쓰기
  'tee[[:space:]][^|;]*_state/manifest\.json'                        # tee로 manifest 덮어쓰기
  'tee[[:space:]][^|;]*\.github/workflows/'                          # tee로 CI 워크플로 덮어쓰기
  'dd[[:space:]][^|;]*of=[^&|;]*\.claude/(settings\.json|hooks/)'    # dd of=로 훅/설정 덮어쓰기
  'patch[[:space:]][^|;]*\.claude/(settings\.json|hooks/)'           # patch로 훅/설정 변경
)

# --------------------------------------------------------------------------
# 3b. 대소문자 구분 패턴 (#39)
# --------------------------------------------------------------------------
# 위 DANGER_PATTERNS 는 SQL(`drop table`)을 잡으려고 -i 로 검사한다. 그런데 그 -i 가
# 배열 전체에 걸려, 대소문자로 위험도가 갈리는 git 플래그까지 싸잡아 차단했다:
#   git checkout -b (새 브랜치 생성)      ← -B(강제 덮어쓰기)로 오인
#   git branch  -d (머지된 것만 안전 삭제) ← -D(강제 삭제)로 오인
# `-d` 는 등가 대체가 없어, 안전 삭제를 하려면 더 위험한 `-D` 를 쓰라고 안내하게 된다 —
# 가드 의도와 정반대다. 그래서 이 배열만 grep -Eq(대소문자 구분)로 따로 검사한다.
#   판단 기준: 플래그의 대소문자가 위험도를 가르면 여기, 아니면 위.
DANGER_PATTERNS_CS=(
  'git[[:space:]]+push[[:space:]].*--force'                   # git push --force
  'git[[:space:]]+push[[:space:]].*-f([[:space:]]|$)'         # git push -f
  'git[[:space:]]+push[[:space:]].*-f[[:space:]]'             # git push -f <remote>
  'git[[:space:]]+reset[[:space:]]+--hard'                    # git reset --hard
  'git[[:space:]]+checkout[[:space:]]+-[Bf]'                  # git checkout -B/-f (-b 는 통과)
  'git[[:space:]]+clean[[:space:]]+-f'                        # git clean -f (미추적 파일 삭제)
  'git[[:space:]]+branch[[:space:]]+-D'                       # git branch -D (-d 는 통과)
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

# 4a. 대소문자 구분 검사 (#39) — -i 없음
if [[ -z "$DETECTED_PATTERN" ]]; then
  for PATTERN in "${DANGER_PATTERNS_CS[@]}"; do
    if printf '%s' "$CMD" | grep -Eq "$PATTERN"; then
      DETECTED_PATTERN="$PATTERN"
      break
    fi
  done
fi

# --------------------------------------------------------------------------
# 4b. WHERE 없는 DELETE 2단계 검사 (L-4 보강, 2026-06-30)
# --------------------------------------------------------------------------
# 배경(L-4): ERE(grep -E)는 부정 전방탐색(negative lookahead)을 지원하지 않으므로
#   "DELETE FROM <table>"이면서 WHERE 절이 없는 경우를 단일 패턴으로 표현할 수 없다.
#   구 패턴 'DELETE...;' 은 세미콜론 있는 경우만 탐지해 다음을 놓쳤다:
#     - DELETE FROM users        (세미콜론 없는 나체 DELETE)
#     - DELETE FROM users -- 주석 (주석 후행)
#
# 2단계 전략:
#   1단계: DELETE FROM <식별자> 패턴 감지 (테이블명 = alnum·_·"·`·. 허용)
#   2단계: WHERE 절 미존재 확인 ([[:space:]]WHERE[[:space:]] 없으면 → 전체 삭제)
#
# 균형 원칙 (careful 정책):
#   ✅ 차단: DELETE FROM users            (WHERE 없음 → 전체 삭제)
#   ✅ 차단: DELETE FROM users;           (세미콜론 직결, WHERE 없음)
#   ✅ 차단: DELETE FROM users -- comment (주석 후행, WHERE 없음)
#   ✅ 통과: DELETE FROM users WHERE id=1 (WHERE 절 있음 → 정상 DELETE)
#   ⚠️  통과: DELETE FROM users WHERE 1=1 (의미적 전체삭제지만 WHERE 절 존재 → 정책 상 허용)
#   한계: "SELECT ... WHERE ...; DELETE FROM t" 복합문은 WHERE 존재로 판단해 통과(알려진 한계).
if [[ -z "$DETECTED_PATTERN" ]]; then
  # 1단계: DELETE FROM <테이블> 패턴 존재 여부 (테이블명에 따옴표·점·백틱 포함)
  if printf '%s' "$CMD" | grep -Eiq 'DELETE[[:space:]]+FROM[[:space:]]+[[:alnum:]_"`.]+'; then
    # 2단계: WHERE 절 미존재 → 위험 판정
    if ! printf '%s' "$CMD" | grep -Eiq '[[:space:]]WHERE[[:space:]]'; then
      DETECTED_PATTERN="DELETE FROM ... (WHERE 없는 전체 삭제 — L-4 보강)"
    fi
  fi
fi

# --------------------------------------------------------------------------
# 5. 감사 로그 append 헬퍼 (차단 여부와 무관하게 호출)
# --------------------------------------------------------------------------
_append_audit() {
  local action="$1"   # "block" 또는 "allow"
  local cmd_excerpt
  cmd_excerpt="$(printf '%s' "$CMD" | head -c 200 | tr '"\\\n\r\t' "    ")"

  # B-1 수정(2026-06-30): Rust CLI 경유 단일 writer.
  # 직접 printf 기록 제거 — bash 포맷이 AuditEntry(hash_self 필수)와 비호환이므로
  # CLI(bathos audit append)가 seq·hash_prev·hash_self를 일관 관리(SSOT).
  # 바이너리 없으면 조용히 통과(|| true — 훅 차단/지연 금지).
  "$BATHOS_BIN" --state-dir "$STATE_DIR" audit append \
    --actor "${BATHOS_ROLE:-hook:careful}" \
    --action "$action" \
    --target "$cmd_excerpt" 2>/dev/null || true
}

# --------------------------------------------------------------------------
# 6. 차단 또는 통과
# --------------------------------------------------------------------------
if [[ -n "$DETECTED_PATTERN" ]]; then
  _append_audit "block"

  printf '\n[bathos careful] x 파괴적/위험경로 우회 명령이 감지되어 차단합니다.\n' >&2
  printf '[bathos careful] 명령: %s\n' "$(printf '%s' "$CMD" | head -c 300)" >&2
  printf '[bathos careful] 감지 패턴: %s\n' "$DETECTED_PATTERN" >&2
  printf '[bathos careful] 이 명령을 실행하려면:\n' >&2
  printf '[bathos careful]   1. 의도를 사용자에게 설명하고\n' >&2
  printf '[bathos careful]   2. 영향 범위(대상 파일/DB/저장소)를 명시하고\n' >&2
  printf '[bathos careful]   3. 롤백 방법을 제시한 뒤\n' >&2
  printf '[bathos careful]   4. 사용자의 명시적 승인을 받으십시오.\n' >&2
  printf '[bathos careful] 위험경로(설정/훅/CI/manifest) 변경은 Write/Edit 도구 +\n' >&2
  printf '[bathos careful] `bathos fingerprint approve`로 정식 승인 절차를 거치십시오.\n' >&2
  printf '[bathos careful] 참고: exceptions.md §5 E-DESTRUCTIVE (Bash 경로는 완전 차단 미보장 — AC2)\n' >&2
  exit 2  # ← 하드 차단
fi

# 정상 통과 (감사 로그는 audit-log.sh PostToolUse 훅이 기록)
exit 0
