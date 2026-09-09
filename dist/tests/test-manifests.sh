#!/usr/bin/env bash
# =============================================================================
# BATHOS Dynamis — dist/tests/test-manifests.sh
# Implements Story B1/B2 §5 "test approach": manifest schema self-check + pointer validity.
#
#   1) Required fields (name/version/sources/capability_tier) exist, and no prose fields
#      (checks that behavior text isn't embedded wholesale — a rough field-length test)
#   2) The relative paths under sources.* point at directories that actually exist
#      (a broken pointer fails). LD-5 gap handling (before final assembly): if the target
#      isn't in the product tree yet, fall back to the same relative path under the original
#      bathos/ and mark it "awaiting assembly".
#   3) capability_tier is inside the closed vocabulary (full-hook/instruction-only/mcp)
#
# For marketplace.json, having no sources/capability_tier is the correct schema, so only
# plugin.json/manifest.json are checked (same target convention as check-versions.sh).
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATHOS_ROOT="${BATHOS_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
DIST_DIR="$BATHOS_ROOT/dist"

FAIL=0
PASS_COUNT=0
info()  { printf '[test-manifests] %s\n' "$*"; }
error() { printf '[test-manifests] ✗ %s\n' "$*"; FAIL=1; }
ok()    { printf '[test-manifests] ✓ %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  info "jq 없음 — 스키마 검사는 스킵(fail-open, 비차단). 다음 행동: jq 설치 후 재실행."
  exit 0
fi

VALID_TIERS="full-hook instruction-only mcp"

TARGETS=()
while IFS= read -r -d '' f; do
  TARGETS+=("$f")
done < <(find "$DIST_DIR" -type f \( -name 'plugin.json' -o -name 'manifest.json' \) -print0 2>/dev/null)

if [[ "${#TARGETS[@]}" -eq 0 ]]; then
  info "검사 대상 0건 — 통과(안내)"
  exit 0
fi

for f in "${TARGETS[@]}"; do
  rel="${f#"$BATHOS_ROOT"/}"
  fdir="$(cd "$(dirname "$f")" && pwd)"

  # --- 0) Deprecated manifests are excluded from the schema check --------------------
  # Demanding today's required fields from a skeleton that declares `"deprecated": true`
  # and points at its replacement produces a false positive (#35). Example:
  # dist/manifests/codex/plugin.json uses `_note` to state that it is slated for removal
  # (its schema does not match the real host) and that the canonical file is
  # dist/codex-plugin/.codex-plugin/plugin.json, and records a `_removal` plan — there is
  # no reason to require version/sources of it.
  # Per the no-implicit-exclusions rule, the skip is logged (never a silent pass).
  if [[ "$(jq -r '.deprecated // false' "$f")" == "true" ]]; then
    info "$rel — deprecated=true → 스키마 검사 제외(정본으로 대체된 스켈레톤, #35). 파일 삭제는 각 매니페스트의 _removal 계획을 따른다"
    continue
  fi

  # --- 0-b) Host detection — required fields differ per host -------------------------
  # The Codex plugin schema has **no** `sources` or `capability_tier` field (measured in
  # PR #27 — see the scripts/build-codex-plugin.sh header, codex-mechanisms.md §4.3).
  # Instead of relative pointers, Codex bundles `skills`/`hooks` directly. So applying the
  # Claude plugin convention (`sources` pointers) to a Codex manifest fails a correct file
  # (#35). Branch the required fields per host.
  case "$rel" in
    *.codex-plugin/*|*/codex-plugin/*|*/manifests/codex/*) host="codex" ;;
    *)                                                     host="claude" ;;
  esac

  # --- 1) Required fields exist ----------------------------------------------------
  name="$(jq -r '.name // empty' "$f")"
  version="$(jq -r '.version // empty' "$f")"
  tier="$(jq -r '.capability_tier // empty' "$f")"
  has_sources="$(jq -r 'has("sources")' "$f")"

  [[ -n "$name" ]] && ok "$rel — name 존재" || error "$rel — name 필드 없음"
  [[ -n "$version" ]] && ok "$rel — version 존재" || error "$rel — version 필드 없음"

  if [[ "$host" == "codex" ]]; then
    # Codex: the `skills` bundle takes the place of pointers; a missing `sources` is normal.
    if [[ "$(jq -r 'has("skills")' "$f")" == "true" ]]; then
      ok "$rel — (codex) skills 번들 존재 — sources 포인터는 이 호스트 스키마에 없음(정상)"
    else
      error "$rel — (codex) skills 필드 없음(Codex 플러그인은 skills 번들로 스킬을 노출한다)"
    fi
  elif [[ "$has_sources" != "true" ]]; then
    error "$rel — sources 필드 없음(포인터 규약 위반, CF-B1 AC1)"
  else
    ok "$rel — sources 필드 존재"
  fi

  # --- 2) No prose fields (rough check: no string field longer than 200 chars, description
  #        aside) — behavior text must not be embedded (CF-B1 AC1 "<20 lines" goal)
  long_field="$(jq -r '
    to_entries
    | map(select(.key != "sources" and .key != "_skeleton_note"))
    | map(select(.value | type == "string" and (length > 200)))
    | length
  ' "$f")"
  if [[ "$long_field" -gt 0 ]]; then
    error "$rel — 200자 초과 문자열 필드 발견(behavior 산문 임베드 의심)"
  else
    ok "$rel — 산문 임베드 없음(필드 길이 검사 통과)"
  fi

  # --- 3) capability_tier closed-vocabulary check ------------------------------------
  if [[ -n "$tier" ]]; then
    if [[ " $VALID_TIERS " == *" $tier "* ]]; then
      ok "$rel — capability_tier=$tier (폐쇄 어휘 내)"
    else
      error "$rel — capability_tier='$tier' 는 폐쇄 어휘(full-hook/instruction-only/mcp) 밖"
    fi
  fi

  # --- 4) Pointer validity ----------------------------------------------------------
  if [[ "$has_sources" == "true" ]]; then
    for key in roles skills commands hooks; do
      ptr="$(jq -r ".sources.${key} // empty" "$f")"
      [[ -z "$ptr" ]] && continue
      target="$fdir/$ptr"
      if [[ -d "$target" ]]; then
        ok "$rel — sources.$key -> $ptr (존재)"
        continue
      fi
      # LD-5 fallback: while the product tree is unassembled, check the same relative
      # location under the original bathos/. (fdir is dist/..., so take only the
      # .claude/xxx suffix of "target" and compare it against the original.)
      suffix="${ptr##*.claude/}"
      orig_target="$BATHOS_ROOT/../../bathos/.claude/$suffix"
      if [[ -d "$orig_target" ]]; then
        info "$rel — sources.$key -> $ptr : 제품 트리 미존재(LD-5 조립 대기), 원본 bathos/.claude/$suffix 로 확인됨(통과)"
        PASS_COUNT=$((PASS_COUNT + 1))
      else
        error "$rel — sources.$key -> $ptr : 대상 디렉터리 없음(제품 트리·원본 모두 부재 — 깨진 포인터)"
      fi
    done
  fi
done

info "총 ${PASS_COUNT}건 통과"
if [[ "$FAIL" -eq 0 ]]; then
  info "전체 통과"
  exit 0
else
  error "실패 항목 존재 — 위 목록을 확인하세요."
  exit 1
fi
