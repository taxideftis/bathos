#!/usr/bin/env bash
# =============================================================================
# BATHOS Dynamis — check-rule-copies.sh
#
# 두 가지 모드를 지원한다(둘 다 CF-B1/B3 뒷받침):
#
#   --dup-scan      (기본)  risk-log A-4 필수 조치 — B1/B2 AC1 "무중복" 즉시 검증.
#                    canonical 소스(역할/스킬/커맨드 산문)의 유의미한 줄이
#                    dist/**·docs/** 안에 통째로 재복제되지 않았는지 grep 검사.
#                    B3 CI 승격 전 수동 실행 가능하도록 지금 도입한다(A-4 지시).
#
#   --check-copies          CF-B3 AC1 본체 — instruction-only 계층으로 "의도적으로"
#                    복제된 규칙 텍스트(dist/copies-manifest.json에 등록된 항목만)의
#                    drift를 검사한다. 짧은 복제=byte diff, 긴 본문=invariant 부분문자열.
#                    등록된 복제가 0건이면 통과+안내(실패 아님 — B3 CONCERNS 명시 처리).
#
# 공통 관례: 기존 훅 5칙(project-context-kr.md §4-2) 중 ①②③ 계승
#   ① SCRIPT_DIR -> BATHOS_ROOT 경로 해석
#   ② jq 있으면 파싱, 없으면 보수적 grep 폴백
#   ③ fail-safe: 검사 대상 자체가 없으면(디렉터리 부재 등) 통과 + 안내(과차단 금지)
#
# exit: 0=문제 없음, 1=드리프트/중복 발견(무엇이 어디서 발견됐는지 + 다음 행동 포함)
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATHOS_ROOT="${BATHOS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# 두 모드가 함께 쓰는 제외 목록 파일 — 모드 블록 밖(공용)에 둔다.
# 주의: 이전에는 --check-copies 블록 안에서만 정의돼 있었다. --dup-scan 이 이 값을
# 참조하게 되면서 그 위치로는 빈 값이 되어 제외가 조용히 무력화된다(set -u 로도
# 안 잡히는 침묵 실패). 새 모드가 추가되어도 같은 함정에 빠지지 않도록 공용화한다.
EXCLUSIONS_FILE="${BATHOS_DRIFT_EXCLUSIONS:-$SCRIPT_DIR/drift-exclusions.json}"

MODE="dup-scan"
for arg in "$@"; do
  case "$arg" in
    --dup-scan) MODE="dup-scan" ;;
    --check-copies) MODE="check-copies" ;;
    -h|--help)
      cat <<'EOF'
사용법: check-rule-copies.sh [--dup-scan|--check-copies]
  --dup-scan      (기본) canonical 산문이 dist/·docs/ 안에 재복제되지 않았는지 검사(B1/B2 AC1, A-4)
  --check-copies  등록된 instruction-only 복제본의 drift 검사(B3 AC1)
EOF
      exit 0
      ;;
    *) printf '[bathos check-rule-copies] ! 알 수 없는 인자: %s (무시)\n' "$arg" ;;
  esac
done

FAIL=0
info()  { printf '[bathos check-rule-copies] %s\n' "$*"; }
warn()  { printf '[bathos check-rule-copies] ! %s\n' "$*"; }
error() { printf '[bathos check-rule-copies] ✗ %s\n' "$*"; FAIL=1; }
ok()    { printf '[bathos check-rule-copies] ✓ %s\n' "$*"; }

# --- canonical 소스 루트 해석 (제품 트리 우선, 없으면 원본 bathos/ 폴백) --------
# LD-5: 최종 조립(Paul)이 끝나기 전에는 제품 트리에 .claude/agents 등이 아직
# 존재하지 않을 수 있다(구현자는 변경분만 커밋). 이 경우 원본 bathos/를
# read-only 참조로 폴백해 "포인터가 가리킬 대상이 결국 무엇인지" 검증한다.
# 이 폴백은 임시이며 최종 조립 후에는 자동으로 제품 트리 경로가 우선된다.
resolve_canon_root() {
  if [[ -d "$BATHOS_ROOT/.claude/agents" ]]; then
    printf '%s\n' "$BATHOS_ROOT/.claude"
    return
  fi
  local orig="$BATHOS_ROOT/../../bathos/.claude"
  if [[ -d "$orig" ]]; then
    # 주의: 이 함수는 $(...) 로 호출되므로 stdout은 오직 "경로 한 줄"만 담아야
    # 한다. 진단 메시지는 반드시 stderr로 보낸다(stdout 오염 시 경로가 깨짐).
    printf '[bathos check-rule-copies] ! 제품 트리에 .claude/agents 없음 — 원본 bathos/.claude 폴백 검사 중(LD-5 최종 조립 전 임시 동작)\n' >&2
    printf '%s\n' "$(cd "$orig" && pwd)"
    return
  fi
  printf '\n'
}

if [[ "$MODE" == "dup-scan" ]]; then
  CANON_CLAUDE="$(resolve_canon_root)"
  if [[ -z "$CANON_CLAUDE" ]]; then
    warn "canonical 소스(.claude/agents)를 찾을 수 없음 — 검사 대상 없음(fail-safe 통과). 다음 행동: 최종 조립 후 재실행."
    exit 0
  fi

  # 스캔 대상 산문 파일: 역할(agents) · 스킬(skills/*/SKILL.md) · 커맨드(commands)
  # 셋 다 존재를 보장하지 않는다(예: 원본 bathos/.claude엔 skills/가 아직 없음
  # — bathos-debt 등은 이번 Dynamis에서 신설되는 스킬). 존재하는 디렉터리만 검사.
  # 주의: mapfile은 bash4+ 전용(기존 훅 호환 관례상 bash 3.2/macOS 기본 지원 유지).
  CANON_DIRS=()
  for d in "$CANON_CLAUDE/agents" "$CANON_CLAUDE/skills" "$CANON_CLAUDE/commands"; do
    [[ -d "$d" ]] && CANON_DIRS+=("$d")
  done

  CANON_FILES=()
  if [[ "${#CANON_DIRS[@]}" -gt 0 ]]; then
    while IFS= read -r -d '' f; do
      CANON_FILES+=("$f")
    done < <(find "${CANON_DIRS[@]}" -type f -name '*.md' -print0 2>/dev/null)
  fi

  if [[ "${#CANON_FILES[@]}" -eq 0 ]]; then
    ok "canonical 산문 파일 0건 — 검사 대상 없음(통과)"
    exit 0
  fi

  # 검사 표면: dist/, docs/ (매니페스트 JSON·본 표 자체의 짧은 인용구는 제외 —
  # 아래 MIN_LEN 이상만 비교하므로 "짧은 인용/기호 설명"은 자연히 걸러진다)
  SEARCH_DIRS=()
  [[ -d "$BATHOS_ROOT/dist" ]] && SEARCH_DIRS+=("$BATHOS_ROOT/dist")
  [[ -d "$BATHOS_ROOT/docs" ]] && SEARCH_DIRS+=("$BATHOS_ROOT/docs")

  if [[ "${#SEARCH_DIRS[@]}" -eq 0 ]]; then
    ok "dist/·docs/ 없음 — 검사 대상 없음(통과)"
    exit 0
  fi

  MIN_LEN=60   # 이 길이 미만 줄은 우연 일치 가능성이 높아 비교 제외(오탐 방지)
  LINES_SCANNED=0
  DUPES_FOUND=0

  # --- 제외 디렉터리 로드(암묵 제외 금지 — 파일로 명시, 사유 필수) -------------
  # drift-exclusions.json 의 `dup_scan_excluded_dirs[]` 는 "검색 표면에서 통째로
  # 뺄 디렉터리 접두사"다(같은 파일의 `exclusions[]` 와 의미가 다름 — 그쪽은
  # --check-copies 가 쓰는 '등록된 복제본' 파일 경로다).
  # 왜 필요한가: 포인터를 따라갈 수 없는 호스트(Codex)의 배포 번들은 산문을
  # 자체 보유해야 하므로, CF-B1 의 "배포 표면은 포인터만" 전제가 성립하지 않는다(#33).
  # jq 가 없으면 제외를 적용하지 않는다 — 검사가 더 엄격해지는 방향이므로 안전하다.
  DUP_EXCLUDED_DIRS=()
  if [[ -f "$EXCLUSIONS_FILE" ]] && command -v jq >/dev/null 2>&1; then
    while IFS= read -r p; do
      [[ -n "$p" ]] && DUP_EXCLUDED_DIRS+=("$p")
    done < <(jq -r '.dup_scan_excluded_dirs[]?.path // empty' "$EXCLUSIONS_FILE" 2>/dev/null || true)
  fi
  if [[ "${#DUP_EXCLUDED_DIRS[@]}" -gt 0 ]]; then
    info "제외 디렉터리 ${#DUP_EXCLUDED_DIRS[@]}건 적용(사유는 $(basename "$EXCLUSIONS_FILE") 참조): ${DUP_EXCLUDED_DIRS[*]}"
  fi

  # 히트 경로가 제외 접두사 아래인지 판정(BATHOS_ROOT 상대경로로 비교).
  _hit_excluded() {
    local hit_rel="${1#"$BATHOS_ROOT"/}"
    local d
    for d in "${DUP_EXCLUDED_DIRS[@]}"; do
      [[ "$hit_rel" == "$d"/* || "$hit_rel" == "$d" ]] && return 0
    done
    return 1
  }

  for f in "${CANON_FILES[@]}"; do
    # frontmatter(---)·헤딩(#)·표 구분선·공백줄 제외, MIN_LEN 이상 줄만 후보로.
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      [[ "$line" =~ ^#+[[:space:]] ]] && continue
      [[ "$line" == "---" ]] && continue
      [[ "${#line}" -lt "$MIN_LEN" ]] && continue
      LINES_SCANNED=$((LINES_SCANNED + 1))
      for d in "${SEARCH_DIRS[@]}"; do
        # -F(고정문자열) -r(재귀) -l(파일명만): 정본 그대로의 산문 블록이
        # 배포 표면에 그대로 박혀 있는지만 본다(부분 인용/의역은 오탐 방지 위해 무시).
        hit="$(grep -F -r -l -- "$line" "$d" 2>/dev/null || true)"
        # 제외 디렉터리 아래 히트는 버린다 — 남은 것이 없으면 위반이 아니다.
        if [[ -n "$hit" && "${#DUP_EXCLUDED_DIRS[@]}" -gt 0 ]]; then
          kept=""
          while IFS= read -r h; do
            [[ -z "$h" ]] && continue
            _hit_excluded "$h" && continue
            kept+="${kept:+$'\n'}$h"
          done <<< "$hit"
          hit="$kept"
        fi
        if [[ -n "$hit" ]]; then
          DUPES_FOUND=$((DUPES_FOUND + 1))
          error "산문 재복제 의심: '${f#"$BATHOS_ROOT"/}' 의 한 줄이 다음에 그대로 존재함 -> $hit"
          error "  내용(일부): ${line:0:80}..."
        fi
      done
    done < "$f"
  done

  if [[ "$FAIL" -eq 0 ]]; then
    ok "무중복 확인 — canonical 파일 ${#CANON_FILES[@]}개, 비교 줄 $LINES_SCANNED 개, 재복제 0건"
    exit 0
  else
    error "재복제 ${DUPES_FOUND}건 발견. 다음 행동: 해당 표면을 canonical 경로 포인터 참조로 교체하세요(CF-B1 위반=게이트 FAIL 사유)."
    exit 1
  fi
fi

if [[ "$MODE" == "check-copies" ]]; then
  COPIES_MANIFEST="${BATHOS_COPIES_MANIFEST:-$BATHOS_ROOT/dist/copies-manifest.json}"
  # EXCLUSIONS_FILE 은 스크립트 상단에서 공용으로 정의된다(두 모드가 공유).

  if [[ ! -f "$COPIES_MANIFEST" ]]; then
    ok "copies-manifest.json 없음 — 검사 대상 0건(통과). 다음 행동: instruction-only 어댑터 추가 시 dist/copies-manifest.json에 등록하세요."
    exit 0
  fi

  if ! command -v jq >/dev/null 2>&1; then
    warn "jq 없음 — check-copies는 JSON 파싱이 필수라 이 모드는 스킵합니다(fail-open, 비차단). 다음 행동: jq 설치 후 재실행."
    exit 0
  fi

  COUNT="$(jq '.copies | length' "$COPIES_MANIFEST")"
  if [[ "$COUNT" -eq 0 ]]; then
    ok "등록된 복제본 0건 — 통과(현재 범위는 Claude Code 정본 + MCP 포인터만 구현, B3 CONCERNS 명시 처리)"
    exit 0
  fi

  # 제외 목록 로드(암묵 제외 금지 — 파일로 명시)
  is_excluded() {
    local rel="$1"
    [[ -f "$EXCLUSIONS_FILE" ]] || return 1
    jq -e --arg p "$rel" '.exclusions[] | select(.path == $p)' "$EXCLUSIONS_FILE" >/dev/null 2>&1
  }

  norm() {
    # fingerprint 정규화(간이판): 후행공백 제거 + CRLF->LF.
    # 주의(CONCERNS): bathos-state의 단일 정규화 함수(Rust, Phillip 소유)와
    # 별도 구현이다 — 언어 경계상 재사용 불가. 규칙만 동일하게 맞춤.
    sed -e 's/\r$//' -e 's/[[:space:]]*$//' "$1"
  }

  for i in $(seq 0 $((COUNT - 1))); do
    src_rel="$(jq -r ".copies[$i].source" "$COPIES_MANIFEST")"
    copy_rel="$(jq -r ".copies[$i].copy" "$COPIES_MANIFEST")"
    mode="$(jq -r ".copies[$i].mode" "$COPIES_MANIFEST")"

    if is_excluded "$copy_rel"; then
      info "제외됨(exclusions): $copy_rel"
      continue
    fi

    src="$BATHOS_ROOT/$src_rel"
    copy="$BATHOS_ROOT/$copy_rel"

    if [[ ! -f "$src" || ! -f "$copy" ]]; then
      error "$copy_rel — 소스 또는 복제본 파일 부재(source=$src_rel). 다음 행동: 경로를 확인하세요."
      continue
    fi

    if [[ "$mode" == "byte" ]]; then
      if ! diff -q <(norm "$src") <(norm "$copy") >/dev/null; then
        error "$copy_rel — canonical($src_rel)과 drift 발견(byte 모드). 다음 행동: 복제본을 정본과 동기화하세요."
      fi
    elif [[ "$mode" == "invariant" ]]; then
      inv_count="$(jq ".copies[$i].invariant | length" "$COPIES_MANIFEST")"
      for j in $(seq 0 $((inv_count - 1))); do
        needle="$(jq -r ".copies[$i].invariant[$j]" "$COPIES_MANIFEST")"
        if ! grep -qF -- "$needle" "$copy"; then
          error "$copy_rel — invariant 문구 누락: \"$needle\". 다음 행동: 복제본에 해당 문구를 복원하세요."
        fi
      done
    else
      error "$copy_rel — 알 수 없는 mode: $mode (byte|invariant만 지원)"
    fi
  done

  if [[ "$FAIL" -eq 0 ]]; then
    ok "등록된 복제본 $COUNT 건 전부 drift 없음"
    exit 0
  else
    exit 1
  fi
fi
