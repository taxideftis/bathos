#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# BATHOS  scripts/check-codex-drift.sh  —  Codex 방출물 drift 검사(US13-AC2)
#
# 무엇을·왜: `.agents/skills/**`의 generated 파일(scripts/to-codex.sh 산출)이 정본
# (`.claude/commands/*.md`)과 어긋나 있지 않은지 — 즉 "누군가 방출물을 직접 손으로 고쳐서
# 재방출과 달라지지 않았는지"를 검사한다(E-EMIT-DRIFT, exceptions.md#5 "정본 수정 후 재방출이
# 유일 경로"). 검사 방법은 to-codex.sh를 임시 디렉터리(`--skills-root`)에 다시 돌려 실물과
# diff하는 것뿐이다 — 이 스크립트 자체는 별도 렌더링 로직을 갖지 않는다(멱등 파이프라인의
# 유일 진실원은 to-codex.sh, 재발명 금지).
#
# 검사 대상: generated 헤더 파일만(15개 — story-04 §4). hand-authored 15개(팀 스폰형)는
# scripts/codex-skills-drift-exclusions.json에 등재된 이름이라 자동 제외한다(파일명 충돌 경위는
# andrew-command-classification.md#8 참고 — story 원문의 "drift-exclusions.json"이 아니다).
#
# 사용:
#   bash scripts/check-codex-drift.sh            # 검사만(비파괴), 그린이면 exit 0
#   bash scripts/check-codex-drift.sh --verbose   # diff 상세 출력
#
# CI 배선은 Phillip 소유(.github/workflows/ci.yml, build-plan.md#1) — 이 스크립트는 "호출되는 쪽"만.
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "$SCRIPT_DIR/.." && pwd)"
VERBOSE=0
[ "${1:-}" = "--verbose" ] && VERBOSE=1

REAL_SKILLS="$PROJ/.agents/skills"
EXCLUSIONS_FILE="$SCRIPT_DIR/codex-skills-drift-exclusions.json"
TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/bathos-codex-drift.XXXXXX")"
trap 'rm -rf "$TMPROOT"' EXIT

# hand-authored 제외 목록 추출(jq 금지 — awk/grep만, project-context-kr.md#1)
hand_authored(){
  awk '/"hand_authored_skills"[[:space:]]*:[[:space:]]*\[/{f=1;next} f&&/\]/{f=0} f' "$EXCLUSIONS_FILE" \
    | grep -oE '"[a-zA-Z0-9_-]+"' | tr -d '"'
}

is_excluded(){ # $1=name
  local n
  for n in $(hand_authored); do [ "$n" = "$1" ] && return 0; done
  return 1
}

echo "== check-codex-drift: $EXCLUSIONS_FILE 기준 재생성 비교 =="
[ -f "$EXCLUSIONS_FILE" ] || { echo "오류: $EXCLUSIONS_FILE 없음" >&2; exit 1; }
[ -d "$REAL_SKILLS" ] || { echo "오류: $REAL_SKILLS 없음 — 먼저 'bash scripts/to-codex.sh --write' 실행" >&2; exit 1; }

# to-codex.sh를 임시 root로 재실행(실물은 건드리지 않음 — 순수 비교용 사본 생성).
# to-codex.sh는 skills 외에도 agents를 방출하므로 agents-root도 tmp로 격리한다.
bash "$SCRIPT_DIR/to-codex.sh" --write --skills-root "$TMPROOT/skills" --agents-root "$TMPROOT/agents" >/dev/null

fail=0
checked=0
skipped=0
for d in "$REAL_SKILLS"/*/; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"
  if is_excluded "$name"; then
    skipped=$((skipped+1))
    continue
  fi
  checked=$((checked+1))
  real="$REAL_SKILLS/$name/SKILL.md"
  regen="$TMPROOT/skills/$name/SKILL.md"
  if [ ! -f "$regen" ]; then
    echo "DRIFT: $name — to-codex.sh가 이 skill을 더 이상 생성하지 않음(분류 변경? codex-skills-drift-exclusions.json 갱신 필요?)" >&2
    fail=$((fail+1))
    continue
  fi
  if ! cmp -s "$real" "$regen"; then
    echo "DRIFT: $name/SKILL.md — 방출물이 재생성 결과와 다름(수동 편집 의심, E-EMIT-DRIFT)" >&2
    [ "$VERBOSE" = "1" ] && diff -u "$regen" "$real" >&2
    fail=$((fail+1))
  fi
  # openai.yaml도 있으면 동일 비교(인자형 4개)
  if [ -f "$REAL_SKILLS/$name/agents/openai.yaml" ]; then
    real_y="$REAL_SKILLS/$name/agents/openai.yaml"
    regen_y="$TMPROOT/skills/$name/agents/openai.yaml"
    if [ ! -f "$regen_y" ] || ! cmp -s "$real_y" "$regen_y"; then
      echo "DRIFT: $name/agents/openai.yaml — 방출물이 재생성 결과와 다름" >&2
      fail=$((fail+1))
    fi
  fi
done

echo "검사: $checked 개 generated(제외 $skipped 개 hand-authored) — drift $fail 건"
if [ "$fail" -gt 0 ]; then
  echo "실패: 정본(.claude/commands)을 수정한 뒤 'bash scripts/to-codex.sh --write'로 재방출하세요(방출물 직접 수정 금지)." >&2
  exit 1
fi
echo "OK: drift 0건"
exit 0
