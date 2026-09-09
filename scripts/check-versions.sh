#!/usr/bin/env bash
# =============================================================================
# BATHOS Dynamis — check-versions.sh
# CF-B3 / US7 AC2 — verifies that every distribution manifest is pinned to a single semver.
# ponytail lesson: turn silent version rot into a CI failure, not a changelog footnote.
# =============================================================================
#
# Targets: dist/**/plugin.json , dist/**/manifest.json
#   (marketplace.json is excluded — by design it carries no version field of its own and
#    references plugin.json only as a pointer, so it cannot drift.)
#
# Reference (SSOT): dist/VERSION, a single semver line. This file is the one version pin for
#   the axis-B distribution layer. (Note: it is *deliberately separate* from the Rust engine
#   version under core/crates (owned by Phillip, its own VERSION file) — packaging version and
#   engine crate version are different axes. Unifying them needs Paul's sign-off and a redesign.)
#
# Extra: when a git tag exists (e.g. v0.2.0), tag/version consistency is checked too
#   (US7 AC2, latter half).
#
# exit: 0=all consistent, 1=mismatch found (names the file, the differing value, next action)
# =============================================================================
set -uo pipefail

# --- Path resolution (inherits hook convention (1): SCRIPT_DIR -> BATHOS_ROOT) ------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATHOS_ROOT="${BATHOS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
DIST_DIR="$BATHOS_ROOT/dist"
VERSION_FILE="$DIST_DIR/VERSION"

FAIL=0

info()  { printf '[bathos check-versions] %s\n' "$*"; }
warn()  { printf '[bathos check-versions] ! %s\n' "$*"; }
error() { printf '[bathos check-versions] ✗ %s\n' "$*"; FAIL=1; }
ok()    { printf '[bathos check-versions] ✓ %s\n' "$*"; }

if [[ ! -f "$VERSION_FILE" ]]; then
  error "기준 파일 없음: $VERSION_FILE — 다음 행동: dist/VERSION을 생성하고 semver 한 줄을 기록하세요."
  exit 1
fi

CANON_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
if [[ -z "$CANON_VERSION" ]]; then
  error "dist/VERSION이 비어 있음 — 다음 행동: semver 값을 기록하세요."
  exit 1
fi
info "기준 버전(dist/VERSION): $CANON_VERSION"

# --- Field extraction, jq-aware (hook convention (2): parse with jq, else grep fallback) --
extract_version() {
  local file="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r '.version // empty' "$file" 2>/dev/null
  else
    # Conservative grep fallback: recognizes only the "version": "x.y.z" pattern
    grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "$file" | head -1 | sed -E 's/.*"([^"]+)"$/\1/'
  fi
}

# --- Collect targets ---------------------------------------------------------
# Note: mapfile/readarray are bash 4+ only — like the existing hooks, this uses the
# while-read + process-substitution pattern to stay compatible with bash 3.2 (macOS default).
TARGETS=()
while IFS= read -r -d '' f; do
  TARGETS+=("$f")
done < <(find "$DIST_DIR" -type f \( -name 'plugin.json' -o -name 'manifest.json' \) -print0 2>/dev/null)

if [[ "${#TARGETS[@]}" -eq 0 ]]; then
  # B3 CONCERNS, handled explicitly: zero targets = pass + notice (must not read as a failure)
  ok "검사 대상 0건 (dist/**/{plugin,manifest}.json 없음) — 통과. 다음 행동: 매니페스트 추가 시 자동으로 검사됩니다."
  exit 0
fi

CHECKED=0
for f in "${TARGETS[@]}"; do
  rel="${f#"$BATHOS_ROOT"/}"

  # Deprecated manifests are excluded from the version-pin check — the same convention added
  # to dist/tests/test-manifests.sh in #35. Demanding a version pin from a skeleton that
  # declares `"deprecated": true`, points at its replacement, and even records a removal
  # plan (`_removal`) produces a false positive.
  # No implicit exclusions — the skip is logged (never a silent pass).
  if command -v jq >/dev/null 2>&1 && [[ "$(jq -r '.deprecated // false' "$f" 2>/dev/null)" == "true" ]]; then
    info "$rel — deprecated=true → 버전 핀 검사 제외(정본으로 대체된 스켈레톤). 파일 삭제는 해당 매니페스트의 _removal 계획을 따른다"
    continue
  fi

  v="$(extract_version "$f")"
  CHECKED=$((CHECKED + 1))
  if [[ -z "$v" ]]; then
    error "$rel — version 필드 없음. 다음 행동: \"version\": \"$CANON_VERSION\"을 추가하세요."
    continue
  fi
  if [[ "$v" != "$CANON_VERSION" ]]; then
    error "$rel — version=$v (기대: $CANON_VERSION). 다음 행동: dist/VERSION과 동일하게 맞추세요."
  fi
done

# --- git tag consistency (only when a tag exists; otherwise skipped — fail-open) ----------
if command -v git >/dev/null 2>&1 && git -C "$BATHOS_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  LATEST_TAG="$(git -C "$BATHOS_ROOT" tag --points-at HEAD 2>/dev/null | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)"
  if [[ -n "$LATEST_TAG" ]]; then
    TAG_VERSION="${LATEST_TAG#v}"
    if [[ "$TAG_VERSION" != "$CANON_VERSION" ]]; then
      error "git 태그($LATEST_TAG) != dist/VERSION($CANON_VERSION). 다음 행동: 태그 재발행 또는 VERSION 갱신."
    else
      ok "git 태그($LATEST_TAG) 정합"
    fi
  fi
else
  warn "git 저장소 아님 또는 git 없음 — 태그 정합 검사 스킵(fail-open, 비차단)."
fi

if [[ "$FAIL" -eq 0 ]]; then
  ok "${CHECKED}개 매니페스트 전부 ${CANON_VERSION}로 정합"
  exit 0
else
  printf '[bathos check-versions] ✗ 버전 불일치 발견 — 위 항목을 수정한 뒤 재실행하세요.\n'
  exit 1
fi
