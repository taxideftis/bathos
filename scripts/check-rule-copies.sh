#!/usr/bin/env bash
# =============================================================================
# BATHOS Dynamis — check-rule-copies.sh
#
# Supports two modes (both back CF-B1/B3):
#
#   --dup-scan      (default) risk-log A-4 required action — verifies B1/B2 AC1 "no
#                    duplication" on the spot. greps whether meaningful lines of the
#                    canonical sources (role/skill/command prose) have been re-copied
#                    wholesale into dist/** or docs/**. Introduced now so it can be run
#                    by hand before the B3 CI promotion (per A-4).
#
#   --check-copies          The body of CF-B3 AC1 — checks drift in rule text that was
#                    *deliberately* copied into the instruction-only layer (only entries
#                    registered in dist/copies-manifest.json). Short copies=byte diff,
#                    long bodies=invariant substrings. Zero registered copies means
#                    pass + notice (not a failure — B3 CONCERNS, handled explicitly).
#
# Shared conventions: inherits (1)(2)(3) of the five hook rules (project-context-kr.md §4-2)
#   (1) SCRIPT_DIR -> BATHOS_ROOT path resolution
#   (2) parse with jq when available, else a conservative grep fallback
#   (3) fail-safe: when there is nothing to check at all (missing directory, etc.), pass +
#       notice (never over-block)
#
# exit: 0=no problem, 1=drift/duplication found (says what was found where + the next action)
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATHOS_ROOT="${BATHOS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# The exclusions file both modes use — kept outside the mode blocks (shared).
# Note: this used to be defined only inside the --check-copies block. Once --dup-scan began
# referencing it, that placement left it empty and silently disabled the exclusions (a silent
# failure that `set -u` does not catch either). Shared here so a new mode cannot fall into
# the same trap.
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

# --- Canonical source root (product tree first, else fall back to the original bathos/) ---
# LD-5: before Paul's final assembly the product tree may not have .claude/agents yet
# (implementers commit only their diffs). In that case fall back to the original bathos/ as a
# read-only reference, to verify "what the pointers will ultimately resolve to".
# This fallback is temporary; after final assembly the product-tree path automatically wins.
resolve_canon_root() {
  if [[ -d "$BATHOS_ROOT/.claude/agents" ]]; then
    printf '%s\n' "$BATHOS_ROOT/.claude"
    return
  fi
  local orig="$BATHOS_ROOT/../../bathos/.claude"
  if [[ -d "$orig" ]]; then
    # Note: this function is called via $(...), so stdout must carry exactly one line — the
    # path. Diagnostics must go to stderr (polluting stdout corrupts the path).
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

  # Prose files to scan: roles (agents), skills (skills/*/SKILL.md), commands (commands).
  # None of the three is guaranteed to exist (e.g. the original bathos/.claude has no skills/
  # yet — bathos-debt and friends are new in Dynamis). Only existing directories are checked.
  # Note: mapfile is bash 4+ only (hook-compat convention keeps bash 3.2/macOS working).
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

  # Surfaces to check: dist/, docs/ (short quotations in manifest JSON or in the tables
  # themselves are out — only lines at or above MIN_LEN below are compared, so "short
  # quotes / symbol glossaries" fall out naturally)
  SEARCH_DIRS=()
  [[ -d "$BATHOS_ROOT/dist" ]] && SEARCH_DIRS+=("$BATHOS_ROOT/dist")
  [[ -d "$BATHOS_ROOT/docs" ]] && SEARCH_DIRS+=("$BATHOS_ROOT/docs")

  if [[ "${#SEARCH_DIRS[@]}" -eq 0 ]]; then
    ok "dist/·docs/ 없음 — 검사 대상 없음(통과)"
    exit 0
  fi

  MIN_LEN=60   # Shorter lines match by coincidence too easily — excluded (avoids false positives)
  LINES_SCANNED=0
  DUPES_FOUND=0

  # --- Load excluded directories (no implicit exclusions — declared in a file, reason required)
  # `dup_scan_excluded_dirs[]` in drift-exclusions.json holds "directory prefixes to drop
  # from the search surface entirely" (a different meaning from `exclusions[]` in the same
  # file — those are the 'registered copy' file paths used by --check-copies).
  # Why it is needed: a distribution bundle for a host that cannot follow pointers (Codex)
  # has to carry the prose itself, so CF-B1's "distribution surfaces hold pointers only"
  # premise does not hold (#33).
  # Without jq no exclusions are applied — that only makes the check stricter, so it is safe.
  DUP_EXCLUDED_DIRS=()
  if [[ -f "$EXCLUSIONS_FILE" ]] && command -v jq >/dev/null 2>&1; then
    while IFS= read -r p; do
      [[ -n "$p" ]] && DUP_EXCLUDED_DIRS+=("$p")
    done < <(jq -r '.dup_scan_excluded_dirs[]?.path // empty' "$EXCLUSIONS_FILE" 2>/dev/null || true)
  fi
  if [[ "${#DUP_EXCLUDED_DIRS[@]}" -gt 0 ]]; then
    info "제외 디렉터리 ${#DUP_EXCLUDED_DIRS[@]}건 적용(사유는 $(basename "$EXCLUSIONS_FILE") 참조): ${DUP_EXCLUDED_DIRS[*]}"
  fi

  # Decides whether a hit path sits under an excluded prefix (compared BATHOS_ROOT-relative).
  _hit_excluded() {
    local hit_rel="${1#"$BATHOS_ROOT"/}"
    local d
    for d in "${DUP_EXCLUDED_DIRS[@]}"; do
      [[ "$hit_rel" == "$d"/* || "$hit_rel" == "$d" ]] && return 0
    done
    return 1
  }

  for f in "${CANON_FILES[@]}"; do
    # Skips frontmatter (---), headings (#), table rules and blank lines; only lines at or
    # above MIN_LEN become candidates.
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      [[ "$line" =~ ^#+[[:space:]] ]] && continue
      [[ "$line" == "---" ]] && continue
      [[ "${#line}" -lt "$MIN_LEN" ]] && continue
      LINES_SCANNED=$((LINES_SCANNED + 1))
      for d in "${SEARCH_DIRS[@]}"; do
        # -F (fixed string) -r (recursive) -l (names only): looks only for a prose block
        # embedded verbatim from the canonical file into a distribution surface (partial
        # quotes/paraphrases are ignored to avoid false positives).
        hit="$(grep -F -r -l -- "$line" "$d" 2>/dev/null || true)"
        # Hits under an excluded directory are dropped — if none remain, it is no violation.
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
  # EXCLUSIONS_FILE is defined once at the top of the script (shared by both modes).

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

  # Load the exclusions list (no implicit exclusions — declared in a file)
  is_excluded() {
    local rel="$1"
    [[ -f "$EXCLUSIONS_FILE" ]] || return 1
    jq -e --arg p "$rel" '.exclusions[] | select(.path == $p)' "$EXCLUSIONS_FILE" >/dev/null 2>&1
  }

  norm() {
    # fingerprint normalization (simplified): strip trailing whitespace + CRLF->LF.
    # Note (CONCERNS): a separate implementation from bathos-state's single normalization
    # function (Rust, owned by Phillip) — not reusable across the language boundary. Only
    # the rules are kept identical.
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
