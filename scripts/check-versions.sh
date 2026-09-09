#!/usr/bin/env bash
# =============================================================================
# BATHOS Dynamis — check-versions.sh
# CF-B3 / US7 AC2 — 전 배포 매니페스트가 단일 semver에 핀 되었는지 검사한다.
# ponytail 교훈: 무언 버전 노후화를 changelog 각주가 아니라 CI 실패로 만든다.
# =============================================================================
#
# 검사 대상: dist/**/plugin.json , dist/**/manifest.json
#   (marketplace.json은 검사 제외 — 자체 버전 필드를 갖지 않는 설계, plugin.json을
#    포인터로만 참조하므로 version 드리프트 대상이 아니다.)
#
# 기준(SSOT): dist/VERSION 1줄(semver). 이 파일이 축 B 배포 레이어의 단일 버전
#   핀이다. (주의: core/crates의 Rust 엔진 버전(Phillip 소유, VERSION 파일 별도)과
#   *의도적으로 분리*된 축이다 — 배포 패키징 버전과 엔진 크레이트 버전은 다른 축.
#   통합이 필요하면 Paul 확인 후 재설계.)
#
# 부가: git 태그가 존재하면(예: v0.2.0) 태그-버전 정합도 검사(US7 AC2 후단).
#
# exit: 0=전부 정합, 1=불일치 발견(어떤 파일의 어떤 값이 다른지 명시 + 다음 행동)
# =============================================================================
set -uo pipefail

# --- 경로 해석 (기존 훅 관례 ① 계승: SCRIPT_DIR -> BATHOS_ROOT) --------------
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

# --- jq 유무에 따른 필드 추출 (기존 훅 관례 ②: jq 있으면 파싱, 없으면 grep 폴백) --
extract_version() {
  local file="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r '.version // empty' "$file" 2>/dev/null
  else
    # 보수적 grep 폴백: "version": "x.y.z" 패턴만 인식
    grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "$file" | head -1 | sed -E 's/.*"([^"]+)"$/\1/'
  fi
}

# --- 검사 대상 수집 ----------------------------------------------------------
# 주의: mapfile/readarray는 bash4+ 전용 — 기존 훅과 동일하게 bash 3.2(macOS 기본)
# 호환을 위해 while-read + process substitution 패턴을 쓴다.
TARGETS=()
while IFS= read -r -d '' f; do
  TARGETS+=("$f")
done < <(find "$DIST_DIR" -type f \( -name 'plugin.json' -o -name 'manifest.json' \) -print0 2>/dev/null)

if [[ "${#TARGETS[@]}" -eq 0 ]]; then
  # B3 CONCERNS 명시 처리: 검사 대상 0건 = 통과 + 안내(실패로 오인 금지)
  ok "검사 대상 0건 (dist/**/{plugin,manifest}.json 없음) — 통과. 다음 행동: 매니페스트 추가 시 자동으로 검사됩니다."
  exit 0
fi

CHECKED=0
for f in "${TARGETS[@]}"; do
  rel="${f#"$BATHOS_ROOT"/}"

  # 폐지(deprecated) 매니페스트는 버전 핀 검사에서 제외한다 — #35 에서
  # dist/tests/test-manifests.sh 에 넣은 것과 같은 관례. 스스로
  # `"deprecated": true` 를 선언하고 후속 정본을 가리키며 삭제 계획(`_removal`)까지
  # 적어 둔 스켈레톤에 버전 핀을 요구하면 오탐이 된다.
  # 암묵 제외 금지 — 건너뛴 사실을 로그로 남긴다(조용히 통과시키지 않음).
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

# --- git 태그 정합(태그가 있을 때만, 없으면 스킵 — fail-open) -------------------
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
