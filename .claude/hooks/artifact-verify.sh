#!/usr/bin/env bash
# =============================================================================
# BATHOS M6 — artifact-verify.sh
# TaskCompleted: 산출물 존재 및 게이트 기준 충족 검증
# =============================================================================
# 계약:  api-contracts.md §D (TaskCompleted artifact-verify), §A-1 StoryFile 계약
# 예외:  exceptions.md §2 E-CTX-LOSS (9섹션 누락/developer_context 공란)
# DoD:   산출물 미충족 → exit 2 + 구체 피드백; 충족 또는 비해당 → exit 0
# 검사 대상:
#   - StoryFile: status=ready-for-dev, 9섹션 존재, developer_context 비어있음 금지
#   - QA task: qa-summary.md 존재
#   - W3 task: readiness-report-kr.md 존재, verdict 포함
# =============================================================================
set -uo pipefail

# --------------------------------------------------------------------------
# 1. 경로 해석
# --------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATHOS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$BATHOS_ROOT}"
ART_DIR="${PROJECT_DIR}/.agent-team"

# --------------------------------------------------------------------------
# 2. stdin JSON 파싱: 태스크 제목 추출
# --------------------------------------------------------------------------
INPUT="$(cat || true)"
TASK_TITLE=""
TASK_DESC=""

if command -v jq >/dev/null 2>&1; then
  TASK_TITLE="$(printf '%s' "$INPUT" | jq -r '.task.title // .title // empty' 2>/dev/null || true)"
  TASK_DESC="$(printf '%s' "$INPUT" | jq -r '.task.description // .description // empty' 2>/dev/null || true)"
else
  TASK_TITLE="$(printf '%s' "$INPUT" | grep -o '"title"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null \
    | head -1 | sed 's/.*"\([^"]*\)".*/\1/' || true)"
fi

# --------------------------------------------------------------------------
# 2-b. SubagentStop 컨텍스트 탐지 (B-3 신규 / R-3 강건화 2026-06-30)
# --------------------------------------------------------------------------
# 입력 스키마 구분:
#   SubagentStop  = { role|agent_type|subagent_type|..., outputs, ... } — task 필드 없음
#   TaskCompleted = { task.title, ... }                                 — task/title 필드 있음
# R-3 수정: 페이로드의 역할 필드명이 런타임 버전마다 다를 수 있으므로(.role 단일 의존 시
#   #15 종료를 미탐) 후보 필드를 폭넓게 조회한다. jq 부재 시 grep 폴백도 둔다.
SUBAGENT_ROLE=""
if command -v jq >/dev/null 2>&1; then
  _task_field="$(printf '%s' "$INPUT" | jq -r '.task // empty' 2>/dev/null || true)"
  _role_field="$(printf '%s' "$INPUT" | jq -r '
    .role // .agent_type // .subagent_type // .agentType
    // .agent.type // .agent.name // .agent_name // .name // empty
  ' 2>/dev/null || true)"
  if [[ -z "$_task_field" && -n "$_role_field" ]]; then
    SUBAGENT_ROLE="$_role_field"
  fi
else
  # jq 부재 폴백: task 필드 없고 역할 후보 키가 보이면 원문에서 값 추출(보수적)
  if ! printf '%s' "$INPUT" | grep -q '"task"'; then
    SUBAGENT_ROLE="$(printf '%s' "$INPUT" \
      | grep -oE '"(role|agent_type|subagent_type|agentType|agent_name|name)"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null \
      | head -1 | sed 's/.*:[[:space:]]*"\([^"]*\)".*/\1/' || true)"
  fi
fi

# --------------------------------------------------------------------------
# 3. StoryFile 필수 섹션 검증 함수
# --------------------------------------------------------------------------
# D1 Completeness 필수 섹션 — 정본: bathos-story-engine/src/compiler.rs REQUIRED_SECTIONS (6개).
# (R-1 수정 2026-06-30: project_context_reference는 Rust에서 조건부 섹션이므로 필수 목록에서 제외.
#  `bathos story compile`은 통과하는데 훅만 차단하던 모순 해소 — Rust 검증과 정합.)
REQUIRED_STORY_SECTIONS=(
  "story_requirements"
  "developer_context"
  "architecture_compliance"
  "library_framework_requirements"
  "file_structure_requirements"
  "testing_requirements"
)

verify_story_file() {
  local story_file="$1"
  local errors=()

  if [[ ! -f "$story_file" ]]; then
    errors+=("StoryFile 없음: $story_file")
    printf '%s\n' "${errors[@]}" >&2
    return 1
  fi

  # status 검사: frontmatter에 status: ready-for-dev 필요
  if ! grep -q 'status:[[:space:]]*"*ready-for-dev"*' "$story_file" 2>/dev/null; then
    errors+=("StoryFile status가 ready-for-dev 아님: $story_file")
  fi

  # 9섹션 존재 검사 (## 또는 # 헤딩으로 존재 확인)
  for section in "${REQUIRED_STORY_SECTIONS[@]}"; do
    if ! grep -qi "## .*${section}\|# .*${section}\|${section}" "$story_file" 2>/dev/null; then
      errors+=("필수 섹션 누락: $section")
    fi
  done

  # developer_context 비어있음 금지 (섹션 헤딩 다음에 내용이 있어야 함)
  # 간단한 휴리스틱: developer_context 이후 5줄 내에 비어있지 않은 라인 확인
  local dc_line
  dc_line="$(grep -n -i 'developer_context' "$story_file" 2>/dev/null | head -1 | cut -d: -f1 || true)"
  if [[ -n "$dc_line" ]]; then
    local after_lines
    after_lines="$(tail -n +"$((dc_line + 1))" "$story_file" 2>/dev/null | head -10 | grep -c '[^[:space:]]' || echo 0)"
    if [[ "$after_lines" -lt 1 ]]; then
      errors+=("developer_context 섹션이 비어 있음 (E-CTX-LOSS)")
    fi
  fi

  if [[ ${#errors[@]} -gt 0 ]]; then
    printf '%s\n' "${errors[@]}" >&2
    return 1
  fi
  return 0
}

# --------------------------------------------------------------------------
# 3-b. SubagentStop 분기 — #15 Matthew 종료 시 StoryFile 완전성 검증 (B-3)
# --------------------------------------------------------------------------
# api-contracts §D: SubagentStop(artifact-verify) → StoryFile 스키마 검증
# D1 완전성: 9섹션 + [Source:] 출처 표기(§A-1 계약 불변식 ②)
# 미충족 시 exit 2(재컴파일 유도), 충족 시 exit 0. fail-safe: 다른 역할은 통과.
if [[ -n "$SUBAGENT_ROLE" ]]; then
  if printf '%s' "$SUBAGENT_ROLE" | grep -Eiq '#15|matthew|story[-_]engineer'; then
    _sa_errors=()
    _story_files_found=0

    # 03-story-engineering/ 내 모든 StoryFile 순회
    for _sf in "$ART_DIR"/03-story-engineering/story-*-kr.md; do
      [[ -f "$_sf" ]] || continue
      _story_files_found=$(( _story_files_found + 1 ))

      # 기존 verify_story_file 재사용(9섹션·status·developer_context 검증)
      # stderr를 stdout으로 리디렉션해 오류 메시지 캡처
      if ! _sf_err="$(verify_story_file "$_sf" 2>&1)"; then
        while IFS= read -r _line; do
          [[ -n "$_line" ]] && _sa_errors+=("$_line")
        done <<< "$_sf_err"
      fi

      # [Source:] 출처 표기 검사 — api-contracts §A-1 계약 불변식 ②
      # 모든 기술 세부에 [Source: <path>#section] 출처 표기 필수
      # grep -q 사용: exit 0=발견, exit 1=미발견 (grep -c || echo 0 패턴의 "0\n0" 부작용 회피)
      if ! grep -q '\[Source:' "$_sf" 2>/dev/null; then
        _sa_errors+=("$(basename "$_sf"): [Source:] 출처 표기 없음 (api-contracts §A-1 ② 위반)")
      fi
    done

    # StoryFile 자체가 없는 경우
    if [[ "$_story_files_found" -eq 0 ]]; then
      _sa_errors+=("StoryFile 없음: $ART_DIR/03-story-engineering/story-*-kr.md")
    fi

    if [[ ${#_sa_errors[@]} -gt 0 ]]; then
      printf '\n[BATHOS artifact-verify] ❌ StoryFile 완전성 미충족 — #15 재컴파일 필요\n' >&2
      for _err in "${_sa_errors[@]}"; do
        printf '[BATHOS artifact-verify] • %s\n' "$_err" >&2
      done
      printf '[BATHOS artifact-verify] #15 Matthew: StoryFile 보완 후 재제출하세요 (E-CTX-LOSS 방지)\n' >&2
      printf '[BATHOS artifact-verify] 참고: api-contracts.md §A-1, exceptions.md §2 E-CTX-LOSS\n' >&2
      exit 2
    fi

    printf '[BATHOS artifact-verify] ✅ StoryFile 완전성 검증 통과 (#15 종료)\n' >&2
    exit 0
  fi

  # 다른 역할 종료: fail-safe 통과 (훅은 절대 차단 금지)
  exit 0
fi

# --------------------------------------------------------------------------
# 4. 태스크 컨텍스트 기반 검증 라우팅
# --------------------------------------------------------------------------
ERRORS=()
VERIFIED=false

# 4-1. QA / 검증 태스크
if printf '%s %s' "$TASK_TITLE" "$TASK_DESC" | grep -Eiq 'QA|qa|테스트|검증|verify|test'; then
  QA_SUMMARY="$ART_DIR/11-qa/qa-summary.md"
  if [[ ! -f "$QA_SUMMARY" ]]; then
    ERRORS+=("QA 태스크 완료 조건 미충족: $QA_SUMMARY 가 없습니다.")
    ERRORS+=("QA 요약 파일을 먼저 생성하고 태스크를 완료하세요.")
  fi
  VERIFIED=true
fi

# 4-2. W3 / 스토리 게이트 태스크
if printf '%s %s' "$TASK_TITLE" "$TASK_DESC" | grep -Eiq 'W3|story.gate|readiness|gate|스토리.*게이트|게이트.*판정'; then
  READINESS_REPORT="$ART_DIR/03-story-engineering/readiness-report-kr.md"
  if [[ ! -f "$READINESS_REPORT" ]]; then
    ERRORS+=("W3 게이트 태스크 완료 조건 미충족: $READINESS_REPORT 가 없습니다.")
    ERRORS+=("readiness-report-kr.md를 생성한 뒤 태스크를 완료하세요.")
  else
    # verdict 필드 존재 확인
    if ! grep -qi 'verdict:[[:space:]]*"*\(PASS\|CONCERNS\|FAIL\)"*' "$READINESS_REPORT" 2>/dev/null; then
      ERRORS+=("readiness-report-kr.md에 verdict(PASS/CONCERNS/FAIL)가 없습니다.")
    fi
  fi
  VERIFIED=true
fi

# 4-3. StoryFile 생성/컴파일 태스크
if printf '%s %s' "$TASK_TITLE" "$TASK_DESC" | grep -Eiq 'story.compil|스토리.파일|story[-_].*kr|create.story'; then
  # 가장 최근 StoryFile 검증
  STORY_FILES=("$ART_DIR"/03-story-engineering/story-*-kr.md)
  if [[ ${#STORY_FILES[@]} -eq 0 || ! -f "${STORY_FILES[0]}" ]]; then
    ERRORS+=("StoryFile이 없습니다: $ART_DIR/03-story-engineering/story-*-kr.md")
  else
    for sf in "${STORY_FILES[@]}"; do
      [[ -f "$sf" ]] || continue
      if ! verify_story_file "$sf"; then
        ERRORS+=("StoryFile 검증 실패: $sf")
      fi
    done
  fi
  VERIFIED=true
fi

# 4-4. W5 구현 태스크 완료 확인: 소유 경로 내 파일 생성 여부 기본 확인
# ⚠️ "구현" 단독은 오탐 多 → "W5"를 함께 요구하거나 웨이브 컨텍스트 필수
if printf '%s %s' "$TASK_TITLE" "$TASK_DESC" | grep -Eiq 'W5|wave5|wave.5.*impl|W5.*구현|구현.*W5|[Ww]ave.*5.*구현|backend.eng|frontend.eng|ml.eng'; then
  IMPL_NOTES_DIR="$ART_DIR/08-impl-notes"
  if [[ ! -d "$IMPL_NOTES_DIR" ]]; then
    ERRORS+=("구현 노트 디렉터리 없음: $IMPL_NOTES_DIR")
    ERRORS+=("구현 완료 후 $IMPL_NOTES_DIR/*.md 를 생성하세요.")
  fi
  VERIFIED=true
fi

# --------------------------------------------------------------------------
# 5. 결과 판정
# --------------------------------------------------------------------------
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  printf '\n[BATHOS artifact-verify] ❌ 산출물 검증 실패 — 태스크 완료 조건 미충족\n' >&2
  for err in "${ERRORS[@]}"; do
    printf '[BATHOS artifact-verify] • %s\n' "$err" >&2
  done
  printf '[BATHOS artifact-verify] 산출물을 보완한 뒤 태스크를 다시 완료 처리하세요.\n' >&2
  printf '[BATHOS artifact-verify] 참고: api-contracts.md §A-1, exceptions.md §2 E-CTX-LOSS\n' >&2
  exit 2  # ← 차단
fi

# 검증 항목 없었거나 모두 통과
if [[ "$VERIFIED" == "true" ]]; then
  printf '[BATHOS artifact-verify] ✅ 산출물 검증 통과\n' >&2
fi
exit 0
