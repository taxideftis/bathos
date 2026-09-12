#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# BATHOS  scripts/check-codex-drift.sh  —  drift check for the Codex emissions (US13-AC2)
#
# What & why: checks that the generated files under `.agents/skills/**` (emitted by scripts/to-codex.sh) have
# not drifted from the canonical source (`.claude/commands/*.md`) — i.e. "did someone hand-edit an emission so
# that it no longer matches a re-emission?" (E-EMIT-DRIFT, exceptions.md#5 "editing the canonical file and
# re-emitting is the only path"). The only method used is re-running to-codex.sh into a temp directory
# (`--skills-root`) and diffing against the real files — this script has no rendering logic of its own (the sole
# source of truth for the idempotent pipeline is to-codex.sh; do not reinvent it).
#
# Scope: only the generated-header files (15 of them — story-04 §4). The 15 hand-authored ones (team-spawning)
# are auto-excluded because their names are registered in scripts/codex-skills-drift-exclusions.json (for how the
# filename clash came about see andrew-command-classification.md#8 — it is NOT the story's "drift-exclusions.json").
#
# Usage:
#   bash scripts/check-codex-drift.sh            # check only (non-destructive); exit 0 when green
#   bash scripts/check-codex-drift.sh --verbose   # print the diff in full
#
# CI wiring is Phillip's (.github/workflows/ci.yml, build-plan.md#1) — this script is only "the callee".
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

# Extract the hand-authored exclusion list (no jq — awk/grep only, project-context-kr.md#1)
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

# Re-run to-codex.sh into a temp root (the real files stay untouched — the copy is purely for comparison).
# to-codex.sh emits agents as well as skills, so isolate agents-root into tmp too.
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
  # Compare openai.yaml the same way when it exists (the 4 argument-taking skills)
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
