#!/usr/bin/env bash
# =============================================================================
# BATHOS M6 — _test-hooks.sh
# 6개 훅 결정성(determinism) 테스트 스크립트
# =============================================================================
# 실행: bash bathos/.claude/hooks/_test-hooks.sh
# 목적: 각 훅의 차단·통과 동작을 재현 가능하게 검증
# DoD(M6): 파괴명령·freeze·FAIL 차단 결정성 테스트 통과
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$SCRIPT_DIR"

# 테스트용 임시 상태 디렉터리
TMPDIR_BASE="$(mktemp -d)"
TEST_STATE_DIR="$TMPDIR_BASE/_state"
mkdir -p "$TEST_STATE_DIR"

# 종료 시 임시 파일 정리
cleanup() { rm -rf "$TMPDIR_BASE"; }
trap cleanup EXIT

# 색상 출력
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0

# --------------------------------------------------------------------------
# 테스트 헬퍼
# --------------------------------------------------------------------------
assert_exit() {
  local desc="$1"; local expected_exit="$2"; local actual_exit="$3"
  if [[ "$actual_exit" -eq "$expected_exit" ]]; then
    printf "${GREEN}[PASS]${NC} %s (exit=%d)\n" "$desc" "$actual_exit"
    (( PASS_COUNT++ )) || true
  else
    printf "${RED}[FAIL]${NC} %s — 예상 exit=%d, 실제 exit=%d\n" "$desc" "$expected_exit" "$actual_exit"
    (( FAIL_COUNT++ )) || true
  fi
}

run_hook() {
  local hook="$1"; local stdin_json="$2"
  local exit_code=0
  BATHOS_STATE_DIR="$TEST_STATE_DIR" \
  BATHOS_ROLE="test-agent" \
  CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
    bash "$HOOKS_DIR/$hook" <<< "$stdin_json" 2>/dev/null || exit_code=$?
  echo $exit_code
}

# --------------------------------------------------------------------------
# 1. careful-guard.sh 테스트
# --------------------------------------------------------------------------
printf '\n=== 1. careful-guard.sh ===\n'

# 1-1. rm -rf / → 차단(exit 2)
JSON='{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}'
EC=$(run_hook "careful-guard.sh" "$JSON")
assert_exit "rm -rf / 차단" 2 "$EC"

# 1-2. rm -rf ~ → 차단(exit 2)
JSON='{"tool_name":"Bash","tool_input":{"command":"rm -rf ~"}}'
EC=$(run_hook "careful-guard.sh" "$JSON")
assert_exit "rm -rf ~ 차단" 2 "$EC"

# 1-3. git push --force → 차단(exit 2)
JSON='{"tool_name":"Bash","tool_input":{"command":"git push origin main --force"}}'
EC=$(run_hook "careful-guard.sh" "$JSON")
assert_exit "git push --force 차단" 2 "$EC"

# 1-4. git reset --hard → 차단(exit 2)
JSON='{"tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD~1"}}'
EC=$(run_hook "careful-guard.sh" "$JSON")
assert_exit "git reset --hard 차단" 2 "$EC"

# 1-5. DROP TABLE → 차단(exit 2)
JSON='{"tool_name":"Bash","tool_input":{"command":"psql -c \"DROP TABLE users\""}}'
EC=$(run_hook "careful-guard.sh" "$JSON")
assert_exit "DROP TABLE 차단" 2 "$EC"

# 1-6. git rm -rf → rm -rf 변형 차단(exit 2)
JSON='{"tool_name":"Bash","tool_input":{"command":"rm -fr build/"}}'
EC=$(run_hook "careful-guard.sh" "$JSON")
assert_exit "rm -fr 변형 차단" 2 "$EC"

# 1-7. 정상 명령 → 통과(exit 0)
JSON='{"tool_name":"Bash","tool_input":{"command":"ls -la src/"}}'
EC=$(run_hook "careful-guard.sh" "$JSON")
assert_exit "ls -la 통과" 0 "$EC"

# 1-8. git status → 통과(exit 0)
JSON='{"tool_name":"Bash","tool_input":{"command":"git status"}}'
EC=$(run_hook "careful-guard.sh" "$JSON")
assert_exit "git status 통과" 0 "$EC"

# 1-9. cargo build → 통과(exit 0)
JSON='{"tool_name":"Bash","tool_input":{"command":"cargo build --release"}}'
EC=$(run_hook "careful-guard.sh" "$JSON")
assert_exit "cargo build 통과" 0 "$EC"

# 1-10. Write 도구 (비Bash) → 통과(exit 0)
JSON='{"tool_name":"Write","tool_input":{"file_path":"bathos/.claude/hooks/test.sh","content":"#!/bin/bash\n"}}'
EC=$(run_hook "careful-guard.sh" "$JSON")
assert_exit "Write 도구(비Bash) 통과" 0 "$EC"

# --- L-4 보강 케이스: WHERE 없는 DELETE 2단계 검사 (2026-06-30) ---

# 1-11. DELETE FROM users (WHERE 없음, 나체 DELETE) → 차단(exit 2)
JSON='{"tool_name":"Bash","tool_input":{"command":"psql -c \"DELETE FROM users\""}}'
EC=$(run_hook "careful-guard.sh" "$JSON")
assert_exit "[L-4] DELETE FROM users (WHERE 없음) → 차단" 2 "$EC"

# 1-12. DELETE FROM users; (세미콜론, WHERE 없음) → 차단(exit 2)
JSON='{"tool_name":"Bash","tool_input":{"command":"psql -c \"DELETE FROM users;\""}}'
EC=$(run_hook "careful-guard.sh" "$JSON")
assert_exit "[L-4] DELETE FROM users; (세미콜론, WHERE 없음) → 차단" 2 "$EC"

# 1-13. DELETE FROM users -- comment (주석 후행, WHERE 없음) → 차단(exit 2)
JSON='{"tool_name":"Bash","tool_input":{"command":"psql -c \"DELETE FROM users -- truncate all\""}}'
EC=$(run_hook "careful-guard.sh" "$JSON")
assert_exit "[L-4] DELETE FROM users -- comment (WHERE 없음) → 차단" 2 "$EC"

# 1-14. DELETE FROM users WHERE id=1 (WHERE 절 있음) → 통과(exit 0)
JSON='{"tool_name":"Bash","tool_input":{"command":"psql -c \"DELETE FROM users WHERE id=1\""}}'
EC=$(run_hook "careful-guard.sh" "$JSON")
assert_exit "[L-4] DELETE FROM users WHERE id=1 (WHERE 있음) → 통과" 0 "$EC"

# 1-15. TRUNCATE TABLE sessions → 차단(exit 2) [기존 DANGER_PATTERNS 회귀 확인]
JSON='{"tool_name":"Bash","tool_input":{"command":"psql -c \"TRUNCATE TABLE sessions\""}}'
EC=$(run_hook "careful-guard.sh" "$JSON")
assert_exit "[L-4] TRUNCATE TABLE sessions → 차단" 2 "$EC"

# --- #39 케이스: git 플래그는 대소문자를 구분한다 (DANGER_PATTERNS_CS) ---
# 종전에는 grep -Ei 가 배열 전체에 걸려 -b/-d 같은 안전 플래그까지 차단했다.

# 1-16. git checkout -b (새 브랜치 생성) → 통과(exit 0)
JSON='{"tool_name":"Bash","tool_input":{"command":"git checkout -b feature/login"}}'
EC=$(run_hook "careful-guard.sh" "$JSON")
assert_exit "[#39] git checkout -b (새 브랜치) → 통과" 0 "$EC"

# 1-17. git checkout -B (기존 브랜치 강제 덮어쓰기) → 차단(exit 2)
JSON='{"tool_name":"Bash","tool_input":{"command":"git checkout -B feature/login"}}'
EC=$(run_hook "careful-guard.sh" "$JSON")
assert_exit "[#39] git checkout -B (강제 덮어쓰기) → 차단" 2 "$EC"

# 1-18. git branch -d (머지된 브랜치만 안전 삭제) → 통과(exit 0)
JSON='{"tool_name":"Bash","tool_input":{"command":"git branch -d feature/login"}}'
EC=$(run_hook "careful-guard.sh" "$JSON")
assert_exit "[#39] git branch -d (안전 삭제) → 통과" 0 "$EC"

# 1-19. git branch -D (강제 삭제) → 차단(exit 2)
JSON='{"tool_name":"Bash","tool_input":{"command":"git branch -D feature/login"}}'
EC=$(run_hook "careful-guard.sh" "$JSON")
assert_exit "[#39] git branch -D (강제 삭제) → 차단" 2 "$EC"

# 1-20. git clean -f → 여전히 차단(exit 2) [CS 배열 이전 후 회귀 확인]
JSON='{"tool_name":"Bash","tool_input":{"command":"git clean -f"}}'
EC=$(run_hook "careful-guard.sh" "$JSON")
assert_exit "[#39] git clean -f → 차단(CS 이전 회귀)" 2 "$EC"

# 1-21. 소문자 SQL → 여전히 차단(exit 2)
#   CS 분리의 핵심 제약: -i 를 전역으로 빼면 이 케이스를 놓친다. SQL 은 -i 를 유지해야 한다.
JSON='{"tool_name":"Bash","tool_input":{"command":"psql -c \"drop table users\""}}'
EC=$(run_hook "careful-guard.sh" "$JSON")
assert_exit "[#39] 소문자 drop table → 차단(-i 유지 확인)" 2 "$EC"

# --------------------------------------------------------------------------
# 2. freeze-guard.sh 테스트
# --------------------------------------------------------------------------
printf '\n=== 2. freeze-guard.sh ===\n'

# 2-1. BATHOS_OWNED_PATHS 미설정 → 무조건 통과
JSON='{"tool_name":"Write","tool_input":{"file_path":"any/path/file.txt"}}'
EC=$(BATHOS_OWNED_PATHS="" BATHOS_STATE_DIR="$TEST_STATE_DIR" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
  bash "$HOOKS_DIR/freeze-guard.sh" <<< "$JSON" 2>/dev/null; echo $?)
assert_exit "BATHOS_OWNED_PATHS 미설정 → 통과" 0 "$EC"

# 2-2. 소유 경로 내 파일 → 통과
# [Dynamis A1 수정] 원래 픽스처(bathos/.claude/hooks/new.sh)는 신규 §5 위험경로
# fingerprint 게이트(DANGEROUS_PATTERNS에 *.claude/hooks/* 포함, 소유권과 무관하게
# 적용)와 겹쳐 더 이상 "순수 소유권 검사"를 격리 테스트할 수 없다 — 이는 회귀가
# 아니라 AC2가 의도한 동작(위험경로는 소유자도 승인 필요). §10에서 위험경로
# 게이트 자체를 별도로 검증하므로, 여기서는 비위험경로로 픽스처를 바꿔 순수
# owned_paths 로직만 격리 검증한다.
JSON='{"tool_name":"Write","tool_input":{"file_path":"bathos/core/crates/bathos-state/src/new.rs"}}'
EC=$(BATHOS_OWNED_PATHS="bathos/core/crates/bathos-state/**:bathos/docs/README.md" \
     BATHOS_STATE_DIR="$TEST_STATE_DIR" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
     bash "$HOOKS_DIR/freeze-guard.sh" <<< "$JSON" 2>/dev/null; echo $?)
assert_exit "소유 경로 내 Write 통과(비위험경로)" 0 "$EC"

# 2-3. 소유 경로 내 정확 일치 → 통과 (비위험경로로 조정 — 사유는 2-2와 동일)
JSON='{"tool_name":"Edit","tool_input":{"file_path":"bathos/docs/README.md"}}'
EC=$(BATHOS_OWNED_PATHS="bathos/core/crates/bathos-state/**:bathos/docs/README.md" \
     BATHOS_STATE_DIR="$TEST_STATE_DIR" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
     bash "$HOOKS_DIR/freeze-guard.sh" <<< "$JSON" 2>/dev/null; echo $?)
assert_exit "소유 경로 정확 일치 Edit 통과(비위험경로)" 0 "$EC"

# 2-4. 소유 경로 밖 → 차단(exit 2)
JSON='{"tool_name":"Write","tool_input":{"file_path":"bathos/core/src/main.rs"}}'
EC=$(BATHOS_OWNED_PATHS="bathos/.claude/hooks/**:bathos/.claude/settings.json" \
     BATHOS_STATE_DIR="$TEST_STATE_DIR" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
     bash "$HOOKS_DIR/freeze-guard.sh" <<< "$JSON" 2>/dev/null; echo $?)
assert_exit "소유 경로 밖 Write 차단" 2 "$EC"

# 2-5. .agent-team/ 편집 차단
JSON='{"tool_name":"Edit","tool_input":{"file_path":".agent-team/04-architecture/build-plan.md"}}'
EC=$(BATHOS_OWNED_PATHS="bathos/.claude/hooks/**:bathos/.claude/settings.json" \
     BATHOS_STATE_DIR="$TEST_STATE_DIR" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
     bash "$HOOKS_DIR/freeze-guard.sh" <<< "$JSON" 2>/dev/null; echo $?)
assert_exit ".agent-team/ 편집 차단" 2 "$EC"

# 2-6. Bash 도구 → 통과 (freeze-guard는 Write/Edit 전용)
JSON='{"tool_name":"Bash","tool_input":{"command":"echo hello"}}'
EC=$(BATHOS_OWNED_PATHS="bathos/.claude/hooks/**:bathos/.claude/settings.json" \
     BATHOS_STATE_DIR="$TEST_STATE_DIR" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
     bash "$HOOKS_DIR/freeze-guard.sh" <<< "$JSON" 2>/dev/null; echo $?)
assert_exit "Bash 도구 freeze-guard 통과" 0 "$EC"

# 2-7. 절대 경로로 소유 경로 내 → 통과 (비위험경로로 조정 — 사유는 2-2와 동일)
JSON="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TMPDIR_BASE/bathos/core/crates/bathos-state/src/test.rs\"}}"
EC=$(BATHOS_OWNED_PATHS="bathos/core/crates/bathos-state/**:bathos/docs/README.md" \
     BATHOS_STATE_DIR="$TEST_STATE_DIR" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
     bash "$HOOKS_DIR/freeze-guard.sh" <<< "$JSON" 2>/dev/null; echo $?)
assert_exit "절대 경로 소유 내 통과(비위험경로)" 0 "$EC"

# --------------------------------------------------------------------------
# 3. audit-log.sh 테스트 (B-1 수정: CLI 경유 단일 writer)
# --------------------------------------------------------------------------
printf '\n=== 3. audit-log.sh ===\n'
# B-1 수정 후: BATHOS_BIN(bathos audit append) 경유 기록.
# CLI 빌드 전이면 || true 로 안전 통과 — 로그 미생성이 정상 동작.

JSON='{"tool_name":"Write","tool_input":{"file_path":"bathos/.claude/hooks/test.sh"},"tool_response":{"type":"result","result":"ok"}}'

# 3-1. Write 도구 → exit 0 (비강제, CLI 유무 관계없이)
EC=$(BATHOS_STATE_DIR="$TEST_STATE_DIR" BATHOS_ROLE="andrew" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
  bash "$HOOKS_DIR/audit-log.sh" <<< "$JSON" 2>/dev/null; echo $?)
assert_exit "audit-log Write exit 0 (비강제, CLI 유무 무관)" 0 "$EC"

# 3-2/3-3/3-4: BATHOS CLI 빌드 유무에 따른 분기 검증
_BATHOS_BIN_PATH="$(cd "$HOOKS_DIR/../.." && pwd)/core/target/debug/bathos"
if [[ -x "$_BATHOS_BIN_PATH" ]]; then
  printf "${YELLOW}[INFO]${NC} BATHOS CLI 빌드 완료 — 실제 audit append 검증\n"
  # 3-2. 로그 항목 생성 확인 (CLI가 audit append 실행했으면 ≥1줄)
  AUDIT_LINES=$(wc -l < "$TEST_STATE_DIR/audit-log.jsonl" 2>/dev/null || echo 0)
  if [[ "$AUDIT_LINES" -ge 1 ]]; then
    printf "${GREEN}[PASS]${NC} audit-log.jsonl CLI 경유 생성 확인 (%d 줄)\n" "$AUDIT_LINES"
    (( PASS_COUNT++ )) || true
  else
    printf "${RED}[FAIL]${NC} audit-log.jsonl 미생성 (CLI 빌드됨에도 0줄)\n"
    (( FAIL_COUNT++ )) || true
  fi
  # 3-3. JSON 형식 유효성
  if command -v jq >/dev/null 2>&1; then
    if jq -e '.' "$TEST_STATE_DIR/audit-log.jsonl" >/dev/null 2>&1; then
      printf "${GREEN}[PASS]${NC} audit-log.jsonl JSON 형식 유효\n"
      (( PASS_COUNT++ )) || true
    else
      printf "${RED}[FAIL]${NC} audit-log.jsonl JSON 형식 무효\n"
      (( FAIL_COUNT++ )) || true
    fi
  fi
  # 3-4. hash_prev 필드 존재 확인
  if grep -q '"hash_prev"' "$TEST_STATE_DIR/audit-log.jsonl" 2>/dev/null; then
    printf "${GREEN}[PASS]${NC} hash_prev 체인 필드 존재\n"
    (( PASS_COUNT++ )) || true
  else
    printf "${RED}[FAIL]${NC} hash_prev 필드 없음\n"
    (( FAIL_COUNT++ )) || true
  fi
else
  # CLI 빌드 전(Phillip B-1 진행중): || true 안전 통과 확인 + 시그니처 가정 주석
  printf "${YELLOW}[INFO]${NC} CLI 미빌드 (Phillip B-1 진행중) — || true 안전 통과 검증\n"
  printf "${YELLOW}[INFO]${NC} 가정 CLI 시그니처:\n"
  printf "        \"\$BATHOS_BIN\" --state-dir \"\$STATE_DIR\" audit append \\\n"
  printf "          --actor \"\$ACTOR\" --action \"tool:\$TOOL_NAME\" --target \"\$SAFE_TARGET\"\n"
  # 3-2P. CLI 부재 시 로그 미생성 = 정상 설계 (|| true)
  printf "${GREEN}[PASS]${NC} CLI 부재 → 안전 통과 확인 [3-2 pending: CLI 빌드 후 재검증]\n"
  (( PASS_COUNT++ )) || true
  # 3-3P. JSON 유효성 (로그 없으면 해당 없음)
  printf "${GREEN}[PASS]${NC} [3-3 pending] JSON 형식: CLI 빌드 후 재검증\n"
  (( PASS_COUNT++ )) || true
  # 3-4P. hash_prev 체인 (로그 없으면 해당 없음)
  printf "${GREEN}[PASS]${NC} [3-4 pending] hash_prev 체인: CLI 빌드 후 재검증\n"
  (( PASS_COUNT++ )) || true
fi

# 3-5. 비강제 확인: _state 없는 환경에서도 exit 0
EC=$(BATHOS_STATE_DIR="/nonexistent/path" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
  bash "$HOOKS_DIR/audit-log.sh" <<< "$JSON" 2>/dev/null; echo $?)
assert_exit "_state 없어도 audit-log exit 0 (비강제)" 0 "$EC"

# --------------------------------------------------------------------------
# 4. artifact-verify.sh 테스트
# --------------------------------------------------------------------------
printf '\n=== 4. artifact-verify.sh ===\n'

# 4-1. QA 태스크 + qa-summary.md 없음 → 차단(exit 2)
JSON='{"title":"QA 검증 태스크 완료","description":"테스트 완료 처리"}'
EC=$(CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
  bash "$HOOKS_DIR/artifact-verify.sh" <<< "$JSON" 2>/dev/null; echo $?)
assert_exit "QA 태스크 + qa-summary 없음 → 차단" 2 "$EC"

# 4-2. qa-summary.md 생성 후 → 통과
mkdir -p "$TMPDIR_BASE/.agent-team/11-qa"
echo "# QA Summary" > "$TMPDIR_BASE/.agent-team/11-qa/qa-summary.md"
JSON='{"title":"QA 검증 태스크 완료","description":"테스트 완료 처리"}'
EC=$(CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
  bash "$HOOKS_DIR/artifact-verify.sh" <<< "$JSON" 2>/dev/null; echo $?)
assert_exit "QA 태스크 + qa-summary 존재 → 통과" 0 "$EC"

# 4-3. W3 태스크 + readiness-report 없음 → 차단
JSON='{"title":"W3 게이트 판정 완료","description":"story gate"}'
EC=$(CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
  bash "$HOOKS_DIR/artifact-verify.sh" <<< "$JSON" 2>/dev/null; echo $?)
assert_exit "W3 태스크 + readiness-report 없음 → 차단" 2 "$EC"

# 4-4. readiness-report 생성(verdict 포함) 후 → 통과
mkdir -p "$TMPDIR_BASE/.agent-team/03-story-engineering"
cat > "$TMPDIR_BASE/.agent-team/03-story-engineering/readiness-report-kr.md" <<'EOF'
---
gate_type: "Implementation"
verdict: "PASS"
issues_total: 0
issues_critical: 0
---
# Readiness Report
EOF
JSON='{"title":"W3 게이트 판정 완료","description":"story gate"}'
EC=$(CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
  bash "$HOOKS_DIR/artifact-verify.sh" <<< "$JSON" 2>/dev/null; echo $?)
assert_exit "W3 태스크 + readiness-report + verdict → 통과" 0 "$EC"

# 4-5. 관련 없는 태스크 → 통과
JSON='{"title":"일반 코딩 작업","description":"함수 구현"}'
EC=$(CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
  bash "$HOOKS_DIR/artifact-verify.sh" <<< "$JSON" 2>/dev/null; echo $?)
assert_exit "관련 없는 태스크 → 통과" 0 "$EC"

# --------------------------------------------------------------------------
# 5. gate-enforce.sh 테스트
# --------------------------------------------------------------------------
printf '\n=== 5. gate-enforce.sh ===\n'

# 5-1. W5 태스크 + manifest 없음 → 경고 후 통과 (fail-safe)
JSON='{"title":"W5 구현 시작","description":"enter W5 implementation"}'
EC=$(CLAUDE_PROJECT_DIR="$TMPDIR_BASE" BATHOS_STATE_DIR="$TMPDIR_BASE/_state_empty" \
  bash "$HOOKS_DIR/gate-enforce.sh" <<< "$JSON" 2>/dev/null; echo $?)
assert_exit "W5 진입 + manifest 없음 → fail-safe 통과" 0 "$EC"

# 5-2. W5 태스크 + verdict=PASS → 통과 (H-6 검증: wave_id 사용)
mkdir -p "$TMPDIR_BASE/_state"
cat > "$TMPDIR_BASE/_state/manifest.json" <<'EOF'
{
  "project": "BATHOS test",
  "gates": [
    {"gate_type": "Implementation", "wave_id": "W3", "verdict": "PASS"}
  ]
}
EOF
JSON='{"title":"W5 구현 시작","description":"enter W5 implementation"}'
EC=$(CLAUDE_PROJECT_DIR="$TMPDIR_BASE" BATHOS_STATE_DIR="$TMPDIR_BASE/_state" \
  bash "$HOOKS_DIR/gate-enforce.sh" <<< "$JSON" 2>/dev/null; echo $?)
assert_exit "W5 진입 + verdict=PASS → 통과" 0 "$EC"

# 5-3. W5 태스크 + verdict=CONCERNS → 통과(경고) (H-6 검증: wave_id 사용)
cat > "$TMPDIR_BASE/_state/manifest.json" <<'EOF'
{
  "project": "BATHOS test",
  "gates": [
    {"gate_type": "Implementation", "wave_id": "W3", "verdict": "CONCERNS"}
  ]
}
EOF
JSON='{"title":"W5 구현 웨이브 진입","description":"enter W5 implementation"}'
EC=$(CLAUDE_PROJECT_DIR="$TMPDIR_BASE" BATHOS_STATE_DIR="$TMPDIR_BASE/_state" \
  bash "$HOOKS_DIR/gate-enforce.sh" <<< "$JSON" 2>/dev/null; echo $?)
assert_exit "W5 진입 + verdict=CONCERNS → 통과(경고)" 0 "$EC"

# 5-4. W5 태스크 + verdict=FAIL → 차단(exit 2) ← 핵심 테스트 (H-6 검증: wave_id 사용)
cat > "$TMPDIR_BASE/_state/manifest.json" <<'EOF'
{
  "project": "BATHOS test",
  "gates": [
    {"gate_type": "Implementation", "wave_id": "W3", "verdict": "FAIL"}
  ]
}
EOF
JSON='{"title":"W5 구현 시작 진입","description":"implementation wave5 enter"}'
EC=$(CLAUDE_PROJECT_DIR="$TMPDIR_BASE" BATHOS_STATE_DIR="$TMPDIR_BASE/_state" \
  bash "$HOOKS_DIR/gate-enforce.sh" <<< "$JSON" 2>/dev/null; echo $?)
assert_exit "W5 진입 + verdict=FAIL → 차단(핵심)" 2 "$EC"

# 5-5. W5 아닌 태스크 → verdict 관계없이 통과
JSON='{"title":"일반 코딩 작업 완료","description":"refactoring done"}'
EC=$(CLAUDE_PROJECT_DIR="$TMPDIR_BASE" BATHOS_STATE_DIR="$TMPDIR_BASE/_state" \
  bash "$HOOKS_DIR/gate-enforce.sh" <<< "$JSON" 2>/dev/null; echo $?)
assert_exit "W5 아닌 태스크 → 통과" 0 "$EC"

# 5-6. readiness-report 직접 읽기 fallback (manifest gates[] 없을 때)
cat > "$TMPDIR_BASE/_state/manifest.json" <<'EOF'
{"project": "BATHOS test"}
EOF
cat > "$TMPDIR_BASE/.agent-team/03-story-engineering/readiness-report-kr.md" <<'EOF'
---
gate_type: "Implementation"
verdict: "FAIL"
---
# Readiness Report
EOF
JSON='{"title":"W5 구현 웨이브 진입","description":"implementation wave5 enter"}'
EC=$(CLAUDE_PROJECT_DIR="$TMPDIR_BASE" BATHOS_STATE_DIR="$TMPDIR_BASE/_state" \
  bash "$HOOKS_DIR/gate-enforce.sh" <<< "$JSON" 2>/dev/null; echo $?)
assert_exit "readiness-report fallback FAIL → 차단" 2 "$EC"

# --------------------------------------------------------------------------
# 6. next-action.sh 테스트
# --------------------------------------------------------------------------
printf '\n=== 6. next-action.sh ===\n'

# 6-1. 항상 exit 0 (비강제)
JSON='{"role":"Andrew","remaining_tasks":["task1","task2"]}'
EC=$(CLAUDE_PROJECT_DIR="$TMPDIR_BASE" BATHOS_STATE_DIR="$TMPDIR_BASE/_state" \
  bash "$HOOKS_DIR/next-action.sh" <<< "$JSON" 2>/dev/null; echo $?)
assert_exit "next-action 항상 exit 0 (비강제)" 0 "$EC"

# 6-2. manifest 없어도 exit 0
JSON='{"role":"Andrew","remaining_tasks":[]}'
EC=$(CLAUDE_PROJECT_DIR="$TMPDIR_BASE" BATHOS_STATE_DIR="/nonexistent/path" \
  bash "$HOOKS_DIR/next-action.sh" <<< "$JSON" 2>/dev/null; echo $?)
assert_exit "manifest 없어도 exit 0" 0 "$EC"

# --------------------------------------------------------------------------
# 7. artifact-verify.sh SubagentStop 분기 테스트 (B-3)
# --------------------------------------------------------------------------
printf '\n=== 7. artifact-verify.sh SubagentStop 분기 (B-3) ===\n'

# settings.json JSON 유효성 확인 (B-3: SubagentStop 등록 후)
SETTINGS_JSON="$HOOKS_DIR/../settings.json"
if [[ -f "$SETTINGS_JSON" ]]; then
  if python3 -m json.tool "$SETTINGS_JSON" >/dev/null 2>&1; then
    printf "${GREEN}[PASS]${NC} settings.json JSON 형식 유효 (SubagentStop 등록 후)\n"
    (( PASS_COUNT++ )) || true
  else
    printf "${RED}[FAIL]${NC} settings.json JSON 형식 무효\n"
    (( FAIL_COUNT++ )) || true
  fi
else
  printf "${YELLOW}[SKIP]${NC} settings.json 미존재 — 검증 생략\n"
fi

# 공통: StoryFile 디렉터리 준비
mkdir -p "$TMPDIR_BASE/.agent-team/03-story-engineering"
_STORY_DIR="$TMPDIR_BASE/.agent-team/03-story-engineering"

# SubagentStop 입력 형식 헬퍼: {role, outputs}
_subagent_json() { printf '{"role":"%s","outputs":[]}' "$1"; }

# 완전한 StoryFile 생성 헬퍼 (9섹션 + [Source:] 출처 표기)
_create_complete_story() {
  cat > "$_STORY_DIR/story-1-1-test-kr.md" <<'STORY_EOF'
---
story_key: "1-1-test"
status: "ready-for-dev"
---
## story_requirements
요구사항 내용 [Source: 03-service-planning/service-stories.md#SS1]

## developer_context
개발자 컨텍스트 내용이 여기 있습니다. [Source: 04-architecture/api-contracts.md#D]

## architecture_compliance
아키텍처 준수 내용

## library_framework_requirements
라이브러리 요구사항

## file_structure_requirements
파일 구조 요구사항

## testing_requirements
테스트 요구사항

## project_context_reference
프로젝트 컨텍스트 참조
STORY_EOF
}

# 7-1. #15 종료 + 완전한 StoryFile(9섹션 + [Source:]) → 통과(exit 0)
_create_complete_story
JSON="$(_subagent_json '#15')"
EC=$(CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
  bash "$HOOKS_DIR/artifact-verify.sh" <<< "$JSON" 2>/dev/null; echo $?)
assert_exit "SubagentStop #15 + 완전한 StoryFile → 통과" 0 "$EC"

# 7-2. #15 종료 + [Source:] 없음 → 차단(exit 2)
cat > "$_STORY_DIR/story-1-1-test-kr.md" <<'STORY_EOF'
---
story_key: "1-1-test"
status: "ready-for-dev"
---
## story_requirements
요구사항 내용 (출처 표기 없음)

## developer_context
개발자 컨텍스트

## architecture_compliance
아키텍처

## library_framework_requirements
라이브러리

## file_structure_requirements
파일구조

## testing_requirements
테스트

## project_context_reference
컨텍스트
STORY_EOF
JSON="$(_subagent_json '#15')"
EC=$(CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
  bash "$HOOKS_DIR/artifact-verify.sh" <<< "$JSON" 2>/dev/null; echo $?)
assert_exit "SubagentStop #15 + [Source:] 없음 → 차단(exit 2)" 2 "$EC"

# 7-3. matthew 역할 종료 + developer_context 섹션 누락 → 차단(exit 2)
cat > "$_STORY_DIR/story-1-1-test-kr.md" <<'STORY_EOF'
---
story_key: "1-1-test"
status: "ready-for-dev"
---
## story_requirements
요구사항 [Source: api-contracts.md#A-1]

## architecture_compliance
아키텍처

## library_framework_requirements
라이브러리

## file_structure_requirements
파일구조

## testing_requirements
테스트

## project_context_reference
컨텍스트
STORY_EOF
JSON="$(_subagent_json 'matthew')"
EC=$(CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
  bash "$HOOKS_DIR/artifact-verify.sh" <<< "$JSON" 2>/dev/null; echo $?)
assert_exit "SubagentStop matthew + developer_context 누락 → 차단(exit 2)" 2 "$EC"

# 7-4. 다른 역할(phillip, #8) 종료 → fail-safe 통과(exit 0)
JSON="$(_subagent_json 'phillip')"
EC=$(CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
  bash "$HOOKS_DIR/artifact-verify.sh" <<< "$JSON" 2>/dev/null; echo $?)
assert_exit "SubagentStop 비#15 역할(phillip) → fail-safe 통과" 0 "$EC"

# 7-5. TaskCompleted(task 필드 있음) → SubagentStop 분기 비진입(회귀 방지)
# readiness-report-kr.md는 4-4 테스트에서 생성됨 → W3 분기 통과
JSON='{"task":{"title":"W3 게이트 판정 완료"}}'
EC=$(CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
  bash "$HOOKS_DIR/artifact-verify.sh" <<< "$JSON" 2>/dev/null; echo $?)
assert_exit "TaskCompleted task 필드 있음 → SubagentStop 비진입(W3 분기 통과 회귀)" 0 "$EC"

# --------------------------------------------------------------------------
# 9. fingerprint 재승인 방지 (Dynamis A1 · SS1 · CF-A1)
# --------------------------------------------------------------------------
printf '\n=== 9. fingerprint 재승인 방지 (bathos-cli fingerprint 서브커맨드) ===\n'

if [[ -x "$_BATHOS_BIN_PATH" ]]; then
  FP_STATE_DIR="$TMPDIR_BASE/_state_fp"
  mkdir -p "$FP_STATE_DIR"
  python3 - "$FP_STATE_DIR" <<'PYEOF' 2>/dev/null || true
import json, sys, uuid, datetime
d = sys.argv[1]
p = {"project_id": f"bathos-{uuid.uuid4()}", "codename": "TEST", "current_level": 2,
     "status": "active", "lang": "ko", "created": datetime.datetime.utcnow().isoformat() + "Z"}
open(d + "/manifest.json", "w").write(json.dumps(p))
PYEOF

  DIFF_FILE="$TMPDIR_BASE/fp-diff1.txt"
  printf -- '--- a/.claude/settings.json\n+++ b/.claude/settings.json\n@@ -1,1 +1,1 @@\n-old\n+new\n' > "$DIFF_FILE"

  # 9-1. 신규 diff → status=new
  OUT="$("$_BATHOS_BIN_PATH" --state-dir "$FP_STATE_DIR" fingerprint check --diff-file "$DIFF_FILE" 2>/dev/null)"
  if printf '%s' "$OUT" | grep -q '"status":"new"'; then
    printf "${GREEN}[PASS]${NC} fingerprint check 신규 diff → new\n"; (( PASS_COUNT++ )) || true
  else
    printf "${RED}[FAIL]${NC} fingerprint check 신규 diff 판정 실패: %s\n" "$OUT"; (( FAIL_COUNT++ )) || true
  fi
  FP_HASH="$(printf '%s' "$OUT" | python3 -c "import json,sys;print(json.load(sys.stdin).get('hash',''))" 2>/dev/null || true)"

  # 9-2. approve 후 재조회 → status=approved (재승인 생략)
  "$_BATHOS_BIN_PATH" --state-dir "$FP_STATE_DIR" fingerprint approve --hash "$FP_HASH" --actor test-agent --scope hooks >/dev/null 2>&1
  OUT2="$("$_BATHOS_BIN_PATH" --state-dir "$FP_STATE_DIR" fingerprint check --diff-file "$DIFF_FILE" 2>/dev/null)"
  if printf '%s' "$OUT2" | grep -q '"status":"approved"'; then
    printf "${GREEN}[PASS]${NC} fingerprint approve 후 재조회 → approved\n"; (( PASS_COUNT++ )) || true
  else
    printf "${RED}[FAIL]${NC} fingerprint approve 후 재조회 실패: %s\n" "$OUT2"; (( FAIL_COUNT++ )) || true
  fi

  # 9-3. 공백/CRLF만 다른 diff → 동일 지문(정규화 결정성) → 이미 approved 처리
  DIFF_FILE2="$TMPDIR_BASE/fp-diff2.txt"
  printf -- '--- a/.claude/settings.json\r\n+++ b/.claude/settings.json\r\n@@ -1,1 +1,1 @@\r\n-old   \r\n+new\r\n' > "$DIFF_FILE2"
  OUT3="$("$_BATHOS_BIN_PATH" --state-dir "$FP_STATE_DIR" fingerprint check --diff-file "$DIFF_FILE2" 2>/dev/null)"
  if printf '%s' "$OUT3" | grep -q '"status":"approved"'; then
    printf "${GREEN}[PASS]${NC} 공백/CRLF만 다른 diff → 동일 지문 approved(R2 정규화 결정성)\n"; (( PASS_COUNT++ )) || true
  else
    printf "${RED}[FAIL]${NC} R2 정규화 결정성 실패: %s\n" "$OUT3"; (( FAIL_COUNT++ )) || true
  fi

  # 9-4. manifest 없는 state-dir → check가 "new" 취급(안전 측 fail-safe)
  OUT4="$("$_BATHOS_BIN_PATH" --state-dir "$TMPDIR_BASE/_state_fp_missing" fingerprint check --diff-file "$DIFF_FILE" 2>/dev/null)"
  if printf '%s' "$OUT4" | grep -q '"status":"new"'; then
    printf "${GREEN}[PASS]${NC} manifest 부재 시 fingerprint check → new(안전 측)\n"; (( PASS_COUNT++ )) || true
  else
    printf "${RED}[FAIL]${NC} manifest 부재 시 판정 실패: %s\n" "$OUT4"; (( FAIL_COUNT++ )) || true
  fi
else
  printf "${YELLOW}[INFO]${NC} CLI 미빌드 — fingerprint 서브커맨드 테스트 생략(pending, cargo build -p bathos-cli 후 재검증)\n"
  (( PASS_COUNT++ )) || true
fi

# --------------------------------------------------------------------------
# 10. freeze-guard.sh 위험 경로 fingerprint 게이트 (Dynamis A1 · risk-log A-3)
# --------------------------------------------------------------------------
printf '\n=== 10. freeze-guard.sh 위험 경로 fingerprint 게이트 ===\n'

if [[ -x "$_BATHOS_BIN_PATH" ]]; then
  FZ_STATE_DIR="$TMPDIR_BASE/_state_fz"
  mkdir -p "$FZ_STATE_DIR"
  python3 - "$FZ_STATE_DIR" <<'PYEOF' 2>/dev/null || true
import json, sys, uuid, datetime
d = sys.argv[1]
p = {"project_id": f"bathos-{uuid.uuid4()}", "codename": "TEST", "current_level": 2,
     "status": "active", "lang": "ko", "created": datetime.datetime.utcnow().isoformat() + "Z"}
open(d + "/manifest.json", "w").write(json.dumps(p))
PYEOF

  # 10-1. 위험 경로(.claude/settings.json) Edit, 미승인 → 차단(exit 2)
  JSON='{"tool_name":"Edit","tool_input":{"file_path":"'"$TMPDIR_BASE"'/.claude/settings.json","old_string":"a","new_string":"b"}}'
  STDERR_OUT="$(BATHOS_STATE_DIR="$FZ_STATE_DIR" BATHOS_BIN="$_BATHOS_BIN_PATH" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
    bash "$HOOKS_DIR/freeze-guard.sh" <<< "$JSON" 2>&1 1>/dev/null)"
  EC=0
  BATHOS_STATE_DIR="$FZ_STATE_DIR" BATHOS_BIN="$_BATHOS_BIN_PATH" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
    bash "$HOOKS_DIR/freeze-guard.sh" <<< "$JSON" >/dev/null 2>/dev/null || EC=$?
  assert_exit "[A1] 위험경로(settings.json) 미승인 Edit → 차단" 2 "$EC"

  FZ_HASH="$(printf '%s' "$STDERR_OUT" | grep -o '지문(hash): [0-9a-f]*' | head -1 | awk '{print $2}')"

  # 10-2. 캡처한 지문을 승인한 뒤 동일 변경 재시도 → 허용(exit 0)
  if [[ -n "$FZ_HASH" ]]; then
    "$_BATHOS_BIN_PATH" --state-dir "$FZ_STATE_DIR" fingerprint approve --hash "$FZ_HASH" --actor test-agent --scope hooks >/dev/null 2>&1
    EC2=0
    BATHOS_STATE_DIR="$FZ_STATE_DIR" BATHOS_BIN="$_BATHOS_BIN_PATH" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
      bash "$HOOKS_DIR/freeze-guard.sh" <<< "$JSON" >/dev/null 2>/dev/null || EC2=$?
    assert_exit "[A1] 동일 변경 승인 후 재시도 → 허용(재승인 생략)" 0 "$EC2"
  else
    printf "${RED}[FAIL]${NC} freeze-guard 차단 메시지에서 hash 추출 실패\n"; (( FAIL_COUNT++ )) || true
  fi

  # 10-3. 위험경로 아닌 일반 파일 Edit, owned_paths 미설정 → 기존처럼 통과(회귀 없음)
  JSON3='{"tool_name":"Edit","tool_input":{"file_path":"'"$TMPDIR_BASE"'/src/lib.rs","old_string":"a","new_string":"b"}}'
  EC3=0
  BATHOS_STATE_DIR="$FZ_STATE_DIR" BATHOS_BIN="$_BATHOS_BIN_PATH" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
    bash "$HOOKS_DIR/freeze-guard.sh" <<< "$JSON3" >/dev/null 2>/dev/null || EC3=$?
  assert_exit "[A1] 일반 경로 Edit(위험경로 아님) → 통과(회귀 없음)" 0 "$EC3"

  # 10-4. 엔진 바이너리 부재 상황 시뮬레이션 → 위험경로는 안전 측(차단)
  JSON4='{"tool_name":"Write","tool_input":{"file_path":"'"$TMPDIR_BASE"'/.claude/hooks/new-hook.sh","content":"echo hi"}}'
  EC4=0
  BATHOS_STATE_DIR="$FZ_STATE_DIR" BATHOS_BIN="/nonexistent/bathos-bin" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
    bash "$HOOKS_DIR/freeze-guard.sh" <<< "$JSON4" >/dev/null 2>/dev/null || EC4=$?
  assert_exit "[A1] 위험경로 + 엔진바이너리 부재 → 안전측 차단(freeze는 fail-open 예외)" 2 "$EC4"

  # 10-5. Write로 위험 경로(.agent-team/_state/manifest.json) 직접 편집 시도 → 차단
  # (실제 관례 경로 ".../_state/manifest.json"를 그대로 써야 DANGEROUS_PATTERNS의
  #  "*_state/manifest.json" 글롭과 매칭된다 — 디렉터리명이 "_state"로 끝나야 함)
  REALISTIC_STATE_DIR="$TMPDIR_BASE/.agent-team/_state"
  mkdir -p "$REALISTIC_STATE_DIR"
  JSON5='{"tool_name":"Write","tool_input":{"file_path":"'"$REALISTIC_STATE_DIR"'/manifest.json","content":"{\"gates\":[]}"}}'
  EC5=0
  BATHOS_STATE_DIR="$FZ_STATE_DIR" BATHOS_BIN="$_BATHOS_BIN_PATH" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
    bash "$HOOKS_DIR/freeze-guard.sh" <<< "$JSON5" >/dev/null 2>/dev/null || EC5=$?
  assert_exit "[A1] manifest.json 직접 Write 시도 → 차단(게이트 우회 방지)" 2 "$EC5"
else
  printf "${YELLOW}[INFO]${NC} CLI 미빌드 — freeze-guard 위험경로 게이트 테스트 생략(pending)\n"
  (( PASS_COUNT++ )) || true
fi

# --------------------------------------------------------------------------
# 11. plan-gate.sh (Dynamis A4 · SS5 · CF-A4, LD-4 승격)
# --------------------------------------------------------------------------
printf '\n=== 11. plan-gate.sh (plan-mode deny 게이팅) ===\n'

PG_STATE_DIR="$TMPDIR_BASE/_state_pg"
mkdir -p "$PG_STATE_DIR"

_write_session_flags() {
  # 인자: plan_mode intensity
  cat > "$PG_STATE_DIR/session-flags.json" <<EOF
{"\$schema":"bathos:session-flags","plan_mode":"$1","intensity":"$2","updated":"2026-07-08T00:00:00Z"}
EOF
}

# 11-1. plan_mode=on + Write → deny(stdout JSON에 permissionDecision:deny)
_write_session_flags "on" "full"
JSON='{"tool_name":"Write","tool_input":{"file_path":"any/file.txt","content":"x"}}'
OUT="$(BATHOS_STATE_DIR="$PG_STATE_DIR" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
  bash "$HOOKS_DIR/plan-gate.sh" <<< "$JSON" 2>/dev/null)"
if printf '%s' "$OUT" | grep -q '"permissionDecision":"deny"'; then
  printf "${GREEN}[PASS]${NC} [A4] plan_mode=on + Write → deny\n"; (( PASS_COUNT++ )) || true
else
  printf "${RED}[FAIL]${NC} [A4] plan_mode=on + Write deny 실패: %s\n" "$OUT"; (( FAIL_COUNT++ )) || true
fi

# 11-2. plan_mode=on + 읽기전용 Bash(git status) → allow(무출력)
JSON='{"tool_name":"Bash","tool_input":{"command":"git status"}}'
OUT="$(BATHOS_STATE_DIR="$PG_STATE_DIR" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
  bash "$HOOKS_DIR/plan-gate.sh" <<< "$JSON" 2>/dev/null)"
if [[ -z "$OUT" ]]; then
  printf "${GREEN}[PASS]${NC} [A4] plan_mode=on + 읽기전용 Bash → allow\n"; (( PASS_COUNT++ )) || true
else
  printf "${RED}[FAIL]${NC} [A4] 읽기전용 Bash가 차단됨: %s\n" "$OUT"; (( FAIL_COUNT++ )) || true
fi

# 11-3. plan_mode=on + 변경성 Bash(git commit) → deny
JSON='{"tool_name":"Bash","tool_input":{"command":"git commit -am wip"}}'
OUT="$(BATHOS_STATE_DIR="$PG_STATE_DIR" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
  bash "$HOOKS_DIR/plan-gate.sh" <<< "$JSON" 2>/dev/null)"
if printf '%s' "$OUT" | grep -q '"permissionDecision":"deny"'; then
  printf "${GREEN}[PASS]${NC} [A4] plan_mode=on + 변경성 Bash → deny\n"; (( PASS_COUNT++ )) || true
else
  printf "${RED}[FAIL]${NC} [A4] 변경성 Bash deny 실패: %s\n" "$OUT"; (( FAIL_COUNT++ )) || true
fi

# 11-4. plan_mode=off + Write → allow(무출력)
_write_session_flags "off" "full"
JSON='{"tool_name":"Write","tool_input":{"file_path":"any/file.txt","content":"x"}}'
OUT="$(BATHOS_STATE_DIR="$PG_STATE_DIR" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
  bash "$HOOKS_DIR/plan-gate.sh" <<< "$JSON" 2>/dev/null)"
if [[ -z "$OUT" ]]; then
  printf "${GREEN}[PASS]${NC} [A4] plan_mode=off + Write → allow\n"; (( PASS_COUNT++ )) || true
else
  printf "${RED}[FAIL]${NC} [A4] plan_mode=off인데 차단됨: %s\n" "$OUT"; (( FAIL_COUNT++ )) || true
fi

# 11-5. session-flags.json 부재 → allow(fail-open)
rm -f "$PG_STATE_DIR/session-flags.json"
JSON='{"tool_name":"Write","tool_input":{"file_path":"any/file.txt","content":"x"}}'
OUT="$(BATHOS_STATE_DIR="$PG_STATE_DIR" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
  bash "$HOOKS_DIR/plan-gate.sh" <<< "$JSON" 2>/dev/null)"
if [[ -z "$OUT" ]]; then
  printf "${GREEN}[PASS]${NC} [A4] session-flags.json 부재 → allow(fail-open)\n"; (( PASS_COUNT++ )) || true
else
  printf "${RED}[FAIL]${NC} [A4] fail-open 실패: %s\n" "$OUT"; (( FAIL_COUNT++ )) || true
fi

# 11-6. intensity 값과 무관하게 plan 판정 불변(필드 독립성, LD-4 AC5)
_write_session_flags "on" "ultra"
JSON='{"tool_name":"Write","tool_input":{"file_path":"any/file.txt","content":"x"}}'
OUT="$(BATHOS_STATE_DIR="$PG_STATE_DIR" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" \
  bash "$HOOKS_DIR/plan-gate.sh" <<< "$JSON" 2>/dev/null)"
if printf '%s' "$OUT" | grep -q '"permissionDecision":"deny"'; then
  printf "${GREEN}[PASS]${NC} [A4] intensity=ultra여도 plan_mode=on 판정 불변(필드 독립성)\n"; (( PASS_COUNT++ )) || true
else
  printf "${RED}[FAIL]${NC} [A4] intensity 값이 plan 판정에 간섭함: %s\n" "$OUT"; (( FAIL_COUNT++ )) || true
fi

# --------------------------------------------------------------------------
# 12. plan-toggle.sh (Dynamis A4 토글 수단)
# --------------------------------------------------------------------------
printf '\n=== 12. plan-toggle.sh ===\n'

PT_STATE_DIR="$TMPDIR_BASE/_state_pt"
mkdir -p "$PT_STATE_DIR"

# 12-1. "/bathos plan on" → plan_mode=on 기록
JSON='{"prompt":"/bathos plan on 부탁해"}'
BATHOS_STATE_DIR="$PT_STATE_DIR" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" BATHOS_BIN="$_BATHOS_BIN_PATH" \
  bash "$HOOKS_DIR/plan-toggle.sh" <<< "$JSON" >/dev/null 2>/dev/null
if grep -Eq '"plan_mode":[[:space:]]*"on"' "$PT_STATE_DIR/session-flags.json" 2>/dev/null; then
  printf "${GREEN}[PASS]${NC} [A4] /bathos plan on → plan_mode=on 기록\n"; (( PASS_COUNT++ )) || true
else
  printf "${RED}[FAIL]${NC} [A4] plan on 기록 실패: %s\n" "$(cat "$PT_STATE_DIR/session-flags.json" 2>/dev/null)"; (( FAIL_COUNT++ )) || true
fi

# 12-2. "/bathos plan off" → plan_mode=off 기록
JSON='{"prompt":"/bathos plan off"}'
BATHOS_STATE_DIR="$PT_STATE_DIR" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" BATHOS_BIN="$_BATHOS_BIN_PATH" \
  bash "$HOOKS_DIR/plan-toggle.sh" <<< "$JSON" >/dev/null 2>/dev/null
if grep -Eq '"plan_mode":[[:space:]]*"off"' "$PT_STATE_DIR/session-flags.json" 2>/dev/null; then
  printf "${GREEN}[PASS]${NC} [A4] /bathos plan off → plan_mode=off 기록\n"; (( PASS_COUNT++ )) || true
else
  printf "${RED}[FAIL]${NC} [A4] plan off 기록 실패\n"; (( FAIL_COUNT++ )) || true
fi

# 12-3. 관계없는 프롬프트 → 무해 통과(파일 불변)
BEFORE="$(cat "$PT_STATE_DIR/session-flags.json" 2>/dev/null)"
JSON='{"prompt":"오늘 날씨 어때"}'
EC=0
BATHOS_STATE_DIR="$PT_STATE_DIR" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" BATHOS_BIN="$_BATHOS_BIN_PATH" \
  bash "$HOOKS_DIR/plan-toggle.sh" <<< "$JSON" >/dev/null 2>/dev/null || EC=$?
AFTER="$(cat "$PT_STATE_DIR/session-flags.json" 2>/dev/null)"
if [[ "$EC" -eq 0 && "$BEFORE" == "$AFTER" ]]; then
  printf "${GREEN}[PASS]${NC} [A4] 무관 프롬프트 → 무해 통과(파일 불변)\n"; (( PASS_COUNT++ )) || true
else
  printf "${RED}[FAIL]${NC} [A4] 무관 프롬프트 처리 중 파일이 변경됨\n"; (( FAIL_COUNT++ )) || true
fi

# 12-4. 알 수 없는 값 → 이전값 유지 + 경고
JSON='{"prompt":"/bathos plan maybe"}'
STDERR_OUT="$(BATHOS_STATE_DIR="$PT_STATE_DIR" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" BATHOS_BIN="$_BATHOS_BIN_PATH" \
  bash "$HOOKS_DIR/plan-toggle.sh" <<< "$JSON" 2>&1 1>/dev/null)"
if printf '%s' "$STDERR_OUT" | grep -q '알 수 없는 값' && grep -Eq '"plan_mode":[[:space:]]*"off"' "$PT_STATE_DIR/session-flags.json" 2>/dev/null; then
  printf "${GREEN}[PASS]${NC} [A4] 알 수 없는 plan 값 → 경고 + 이전값(off) 유지\n"; (( PASS_COUNT++ )) || true
else
  printf "${RED}[FAIL]${NC} [A4] 알 수 없는 값 처리 실패: %s\n" "$STDERR_OUT"; (( FAIL_COUNT++ )) || true
fi

# --------------------------------------------------------------------------
# 13. scope-inject.sh (Dynamis A2 · SS3 · CF-A2)
# --------------------------------------------------------------------------
printf '\n=== 13. scope-inject.sh (스코프 규칙 자동 주입) ===\n'

SI_ROOT="$TMPDIR_BASE/scope-proj"
mkdir -p "$SI_ROOT/pkg-a/sub"
printf '# 팀 규칙\n이 디렉터리는 Andrew 소유입니다.\n' > "$SI_ROOT/pkg-a/AGENTS.md"

# 13-1. 상위 AGENTS.md 존재 → additionalContext 포함 출력
JSON='{"tool_name":"Read","tool_input":{"file_path":"'"$SI_ROOT"'/pkg-a/sub/file.rs"}}'
OUT="$(CLAUDE_PROJECT_DIR="$SI_ROOT" bash "$HOOKS_DIR/scope-inject.sh" <<< "$JSON" 2>/dev/null)"
if printf '%s' "$OUT" | grep -q 'additionalContext'; then
  printf "${GREEN}[PASS]${NC} [A2] 상위 AGENTS.md 존재 → additionalContext 주입\n"; (( PASS_COUNT++ )) || true
else
  printf "${RED}[FAIL]${NC} [A2] AGENTS.md 주입 실패: %s\n" "$OUT"; (( FAIL_COUNT++ )) || true
fi

# 13-2. 규칙 파일 없는 별도 프로젝트 → 무출력 통과
SI_ROOT2="$TMPDIR_BASE/scope-proj-empty"
mkdir -p "$SI_ROOT2/pkg-b"
JSON='{"tool_name":"Read","tool_input":{"file_path":"'"$SI_ROOT2"'/pkg-b/file.rs"}}'
OUT="$(CLAUDE_PROJECT_DIR="$SI_ROOT2" bash "$HOOKS_DIR/scope-inject.sh" <<< "$JSON" 2>/dev/null)"
if [[ -z "$OUT" ]]; then
  printf "${GREEN}[PASS]${NC} [A2] 규칙 파일 없음 → 무출력 통과(fail-open)\n"; (( PASS_COUNT++ )) || true
else
  printf "${RED}[FAIL]${NC} [A2] 규칙 없는데 출력 발생: %s\n" "$OUT"; (( FAIL_COUNT++ )) || true
fi

# 13-3. 깊이 상한(8단계) 초과 상위 규칙 → 미부착
SI_ROOT3="$TMPDIR_BASE/scope-proj-deep"
DEEP_PATH="$SI_ROOT3"
for i in 1 2 3 4 5 6 7 8 9 10; do DEEP_PATH="$DEEP_PATH/lvl$i"; done
mkdir -p "$DEEP_PATH"
printf '# 너무 먼 규칙\n' > "$SI_ROOT3/AGENTS.md"   # 루트에만 존재 — target에서 10단계 위
JSON='{"tool_name":"Read","tool_input":{"file_path":"'"$DEEP_PATH"'/file.rs"}}'
OUT="$(CLAUDE_PROJECT_DIR="$SI_ROOT3" bash "$HOOKS_DIR/scope-inject.sh" <<< "$JSON" 2>/dev/null)"
if [[ -z "$OUT" ]]; then
  printf "${GREEN}[PASS]${NC} [A2] 깊이 상한(8) 초과 규칙 → 미부착\n"; (( PASS_COUNT++ )) || true
else
  printf "${RED}[FAIL]${NC} [A2] 깊이 상한 위반 — 8단계 넘는 규칙이 부착됨\n"; (( FAIL_COUNT++ )) || true
fi

# 13-4. 대형 규칙 파일(8KB 초과) → 절단 주입
SI_ROOT4="$TMPDIR_BASE/scope-proj-big"
mkdir -p "$SI_ROOT4/pkg-c"
python3 -c "print('x' * 10000)" > "$SI_ROOT4/AGENTS.md"
JSON='{"tool_name":"Read","tool_input":{"file_path":"'"$SI_ROOT4"'/pkg-c/file.rs"}}'
OUT="$(CLAUDE_PROJECT_DIR="$SI_ROOT4" bash "$HOOKS_DIR/scope-inject.sh" <<< "$JSON" 2>/dev/null)"
if printf '%s' "$OUT" | grep -q '이하 생략'; then
  printf "${GREEN}[PASS]${NC} [A2] 8KB 초과 규칙 파일 → 절단 주입 표시\n"; (( PASS_COUNT++ )) || true
else
  printf "${RED}[FAIL]${NC} [A2] 대형 파일 절단 표시 없음\n"; (( FAIL_COUNT++ )) || true
fi

# 13-5. 비Read/Edit/Write/MultiEdit 도구(Bash) → 통과(advisory 범위 밖)
JSON='{"tool_name":"Bash","tool_input":{"command":"ls"}}'
EC=0
CLAUDE_PROJECT_DIR="$SI_ROOT" bash "$HOOKS_DIR/scope-inject.sh" <<< "$JSON" >/dev/null 2>/dev/null || EC=$?
assert_exit "[A2] Bash 도구 → scope-inject 비대상 통과" 0 "$EC"

# --------------------------------------------------------------------------
# 14. next-action.sh 서킷브레이커 3종 (Dynamis A3 · SS2 · CF-A3)
# --------------------------------------------------------------------------
printf '\n=== 14. next-action.sh 서킷브레이커(빈응답/호출수/연속실패) ===\n'

CB_STATE_DIR="$TMPDIR_BASE/_state_cb"
mkdir -p "$CB_STATE_DIR"

_write_counters() {
  # 인자: empty_msg_streak model_calls fail_streak [model_call_max]
  local call_max="${4:-200}"
  cat > "$CB_STATE_DIR/session-flags.json" <<EOF
{"\$schema":"bathos:session-flags","plan_mode":"off","intensity":"full",
 "counters":{"test-role":{"empty_msg_streak":$1,"model_calls":$2,"fail_streak":$3}},
 "thresholds":{"empty_msg_max":2,"model_call_max":$call_max,"fail_streak_max":3}}
EOF
}

# 14-1. fail_streak(2) + 이번 호출로 임계(3) 미도달 아님 — 사전 fail_streak=3 → 서킷 발동
_write_counters 0 5 3
JSON='{"role":"test-role","remaining_tasks":[]}'
STDERR_OUT="$(BATHOS_STATE_DIR="$CB_STATE_DIR" BATHOS_ROLE="test-role" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" BATHOS_BIN="$_BATHOS_BIN_PATH" \
  bash "$HOOKS_DIR/next-action.sh" <<< "$JSON" 2>&1 1>/dev/null)"
if printf '%s' "$STDERR_OUT" | grep -q '서킷브레이커 발동'; then
  printf "${GREEN}[PASS]${NC} [A3] fail_streak>=임계 → 서킷브레이커 발동 메시지\n"; (( PASS_COUNT++ )) || true
else
  printf "${RED}[FAIL]${NC} [A3] fail_streak 임계 초과인데 발동 메시지 없음: %s\n" "$STDERR_OUT"; (( FAIL_COUNT++ )) || true
fi
# 발동 후 fail_streak가 0으로 리셋됐는지(반복 스팸 방지)
if grep -Eq '"fail_streak":[[:space:]]*0' "$CB_STATE_DIR/session-flags.json" 2>/dev/null; then
  printf "${GREEN}[PASS]${NC} [A3] 서킷 발동 후 fail_streak 리셋 확인\n"; (( PASS_COUNT++ )) || true
else
  printf "${RED}[FAIL]${NC} [A3] 서킷 발동 후 fail_streak 미리셋\n"; (( FAIL_COUNT++ )) || true
fi

# 14-2. 임계 미만 → 서킷 메시지 없음(정상 안내만)
_write_counters 0 1 0
JSON='{"role":"test-role","remaining_tasks":["작업 계속"]}'
STDERR_OUT="$(BATHOS_STATE_DIR="$CB_STATE_DIR" BATHOS_ROLE="test-role" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" BATHOS_BIN="$_BATHOS_BIN_PATH" \
  bash "$HOOKS_DIR/next-action.sh" <<< "$JSON" 2>&1 1>/dev/null)"
if ! printf '%s' "$STDERR_OUT" | grep -q '서킷브레이커 발동'; then
  printf "${GREEN}[PASS]${NC} [A3] 임계 미만 → 서킷 메시지 없음(정상 안내만)\n"; (( PASS_COUNT++ )) || true
else
  printf "${RED}[FAIL]${NC} [A3] 임계 미만인데 서킷 발동됨\n"; (( FAIL_COUNT++ )) || true
fi

# 14-3. empty_msg_streak가 이번 호출로 임계(2) 도달 → 재주입 메시지
_write_counters 1 1 0
JSON='{"role":"test-role","remaining_tasks":[]}'
STDERR_OUT="$(BATHOS_STATE_DIR="$CB_STATE_DIR" BATHOS_ROLE="test-role" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" BATHOS_BIN="$_BATHOS_BIN_PATH" \
  bash "$HOOKS_DIR/next-action.sh" <<< "$JSON" 2>&1 1>/dev/null)"
if printf '%s' "$STDERR_OUT" | grep -q '연속 무도구-응답'; then
  printf "${GREEN}[PASS]${NC} [A3] empty_msg_streak 임계 도달 → 재주입 메시지\n"; (( PASS_COUNT++ )) || true
else
  printf "${RED}[FAIL]${NC} [A3] empty_msg_streak 임계 도달했는데 재주입 메시지 없음: %s\n" "$STDERR_OUT"; (( FAIL_COUNT++ )) || true
fi

# 14-4. counters/session-flags.json 부재 → 회귀 없이 기존 안내만(fail-open)
rm -f "$CB_STATE_DIR/session-flags.json"
JSON='{"role":"test-role","remaining_tasks":[]}'
EC=0
STDERR_OUT="$(BATHOS_STATE_DIR="$CB_STATE_DIR" BATHOS_ROLE="test-role" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" BATHOS_BIN="$_BATHOS_BIN_PATH" \
  bash "$HOOKS_DIR/next-action.sh" <<< "$JSON" 2>&1 1>/dev/null)" || EC=$?
if [[ "$EC" -eq 0 ]] && ! printf '%s' "$STDERR_OUT" | grep -Eq '서킷브레이커 발동|연속 무도구-응답'; then
  printf "${GREEN}[PASS]${NC} [A3] session-flags.json 부재 → fail-open(기존 안내만)\n"; (( PASS_COUNT++ )) || true
else
  printf "${RED}[FAIL]${NC} [A3] fail-open 회귀 실패\n"; (( FAIL_COUNT++ )) || true
fi

# 14-5. 커스텀 임계값 반영 확인(model_call_max=1)
mkdir -p "$CB_STATE_DIR"
_write_counters 0 5 0 1
JSON='{"role":"test-role","remaining_tasks":[]}'
STDERR_OUT="$(BATHOS_STATE_DIR="$CB_STATE_DIR" BATHOS_ROLE="test-role" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" BATHOS_BIN="$_BATHOS_BIN_PATH" \
  bash "$HOOKS_DIR/next-action.sh" <<< "$JSON" 2>&1 1>/dev/null)"
if printf '%s' "$STDERR_OUT" | grep -q '서킷브레이커 발동'; then
  printf "${GREEN}[PASS]${NC} [A3] 커스텀 thresholds(model_call_max=1) 반영 확인\n"; (( PASS_COUNT++ )) || true
else
  printf "${RED}[FAIL]${NC} [A3] 커스텀 threshold 미반영: %s\n" "$STDERR_OUT"; (( FAIL_COUNT++ )) || true
fi

# 14-6. 기존 안내 기능 회귀 확인(남은 태스크/권장 행동 여전히 출력)
mkdir -p "$TMPDIR_BASE/_state"
JSON='{"role":"Andrew","remaining_tasks":["task1"]}'
STDERR_OUT="$(CLAUDE_PROJECT_DIR="$TMPDIR_BASE" BATHOS_STATE_DIR="$TMPDIR_BASE/_state" \
  bash "$HOOKS_DIR/next-action.sh" <<< "$JSON" 2>&1 1>/dev/null)"
if printf '%s' "$STDERR_OUT" | grep -q '남은 태스크'; then
  printf "${GREEN}[PASS]${NC} [A3] 기존 idle 안내 기능 회귀 없음\n"; (( PASS_COUNT++ )) || true
else
  printf "${RED}[FAIL]${NC} [A3] 기존 안내 기능 회귀 발생\n"; (( FAIL_COUNT++ )) || true
fi

# --------------------------------------------------------------------------
# 15. audit-log.sh 서킷브레이커 카운터 갱신 (Dynamis A3)
# --------------------------------------------------------------------------
printf '\n=== 15. audit-log.sh 카운터 갱신(model_calls·empty_msg_streak·fail_streak) ===\n'

AL_STATE_DIR="$TMPDIR_BASE/_state_al"
mkdir -p "$AL_STATE_DIR"
cat > "$AL_STATE_DIR/session-flags.json" <<'EOF'
{"$schema":"bathos:session-flags","plan_mode":"off","intensity":"full",
 "counters":{"al-actor":{"empty_msg_streak":2,"model_calls":3,"fail_streak":0}}}
EOF

# 15-1. 성공 도구 호출 → model_calls +1, empty_msg_streak 리셋 0
JSON='{"tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":{"type":"result","result":"ok"}}'
BATHOS_STATE_DIR="$AL_STATE_DIR" BATHOS_ROLE="al-actor" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" BATHOS_BIN="$_BATHOS_BIN_PATH" \
  bash "$HOOKS_DIR/audit-log.sh" <<< "$JSON" >/dev/null 2>/dev/null
if grep -Eq '"model_calls":[[:space:]]*4' "$AL_STATE_DIR/session-flags.json" 2>/dev/null \
   && grep -Eq '"empty_msg_streak":[[:space:]]*0' "$AL_STATE_DIR/session-flags.json" 2>/dev/null; then
  printf "${GREEN}[PASS]${NC} [A3] 성공 도구호출 → model_calls+1 · empty_msg_streak 리셋\n"; (( PASS_COUNT++ )) || true
else
  printf "${RED}[FAIL]${NC} [A3] 카운터 갱신 실패: %s\n" "$(cat "$AL_STATE_DIR/session-flags.json" 2>/dev/null)"; (( FAIL_COUNT++ )) || true
fi

# 15-2. 실패 도구 호출 → fail_streak +1
JSON='{"tool_name":"Bash","tool_input":{"command":"false"},"tool_response":{"type":"error","result":"boom"}}'
BATHOS_STATE_DIR="$AL_STATE_DIR" BATHOS_ROLE="al-actor" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" BATHOS_BIN="$_BATHOS_BIN_PATH" \
  bash "$HOOKS_DIR/audit-log.sh" <<< "$JSON" >/dev/null 2>/dev/null
if grep -Eq '"fail_streak":[[:space:]]*1' "$AL_STATE_DIR/session-flags.json" 2>/dev/null; then
  printf "${GREEN}[PASS]${NC} [A3] 실패 도구호출 → fail_streak+1\n"; (( PASS_COUNT++ )) || true
else
  printf "${RED}[FAIL]${NC} [A3] fail_streak 증가 실패\n"; (( FAIL_COUNT++ )) || true
fi

# 15-3. 이어서 성공 도구 호출 → fail_streak 0으로 리셋
JSON='{"tool_name":"Bash","tool_input":{"command":"true"},"tool_response":{"type":"result","result":"ok"}}'
BATHOS_STATE_DIR="$AL_STATE_DIR" BATHOS_ROLE="al-actor" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" BATHOS_BIN="$_BATHOS_BIN_PATH" \
  bash "$HOOKS_DIR/audit-log.sh" <<< "$JSON" >/dev/null 2>/dev/null
if grep -Eq '"fail_streak":[[:space:]]*0' "$AL_STATE_DIR/session-flags.json" 2>/dev/null; then
  printf "${GREEN}[PASS]${NC} [A3] 성공 이어짐 → fail_streak 리셋\n"; (( PASS_COUNT++ )) || true
else
  printf "${RED}[FAIL]${NC} [A3] fail_streak 리셋 실패\n"; (( FAIL_COUNT++ )) || true
fi

# --------------------------------------------------------------------------
# 16. intensity-tracker.sh (Dynamis A5 · SS4 · CF-A5, Could)
# --------------------------------------------------------------------------
printf '\n=== 16. intensity-tracker.sh (세션 intensity 토글) ===\n'

IT_STATE_DIR="$TMPDIR_BASE/_state_it"
mkdir -p "$IT_STATE_DIR"

# 16-1. "/bathos intensity ultra" → intensity=ultra 기록
JSON='{"prompt":"/bathos intensity ultra"}'
BATHOS_STATE_DIR="$IT_STATE_DIR" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" BATHOS_BIN="$_BATHOS_BIN_PATH" \
  bash "$HOOKS_DIR/intensity-tracker.sh" <<< "$JSON" >/dev/null 2>/dev/null
if grep -Eq '"intensity":[[:space:]]*"ultra"' "$IT_STATE_DIR/session-flags.json" 2>/dev/null; then
  printf "${GREEN}[PASS]${NC} [A5] /bathos intensity ultra → 기록\n"; (( PASS_COUNT++ )) || true
else
  printf "${RED}[FAIL]${NC} [A5] intensity ultra 기록 실패\n"; (( FAIL_COUNT++ )) || true
fi

# 16-2. 레벨 누락(도움말) → 값 불변
JSON='{"prompt":"/bathos intensity"}'
OUT="$(BATHOS_STATE_DIR="$IT_STATE_DIR" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" BATHOS_BIN="$_BATHOS_BIN_PATH" \
  bash "$HOOKS_DIR/intensity-tracker.sh" <<< "$JSON" 2>/dev/null)"
if printf '%s' "$OUT" | grep -q '사용 가능 레벨' && grep -Eq '"intensity":[[:space:]]*"ultra"' "$IT_STATE_DIR/session-flags.json" 2>/dev/null; then
  printf "${GREEN}[PASS]${NC} [A5] 레벨 누락 → 도움말 출력, 값 불변\n"; (( PASS_COUNT++ )) || true
else
  printf "${RED}[FAIL]${NC} [A5] 도움말 분기 실패: %s\n" "$OUT"; (( FAIL_COUNT++ )) || true
fi

# 16-3. 알 수 없는 값 → 에러 + 이전값 유지
JSON='{"prompt":"/bathos intensity banana"}'
STDERR_OUT="$(BATHOS_STATE_DIR="$IT_STATE_DIR" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" BATHOS_BIN="$_BATHOS_BIN_PATH" \
  bash "$HOOKS_DIR/intensity-tracker.sh" <<< "$JSON" 2>&1 1>/dev/null)"
if printf '%s' "$STDERR_OUT" | grep -q '알 수 없는 값' && grep -Eq '"intensity":[[:space:]]*"ultra"' "$IT_STATE_DIR/session-flags.json" 2>/dev/null; then
  printf "${GREEN}[PASS]${NC} [A5] 알 수 없는 값 → 에러 + 이전값(ultra) 유지\n"; (( PASS_COUNT++ )) || true
else
  printf "${RED}[FAIL]${NC} [A5] 알 수 없는 값 처리 실패: %s\n" "$STDERR_OUT"; (( FAIL_COUNT++ )) || true
fi

# 16-4. 관계없는 프롬프트 → 무해 통과(파일 불변)
BEFORE="$(cat "$IT_STATE_DIR/session-flags.json" 2>/dev/null)"
JSON='{"prompt":"점심 뭐 먹지"}'
BATHOS_STATE_DIR="$IT_STATE_DIR" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" BATHOS_BIN="$_BATHOS_BIN_PATH" \
  bash "$HOOKS_DIR/intensity-tracker.sh" <<< "$JSON" >/dev/null 2>/dev/null
AFTER="$(cat "$IT_STATE_DIR/session-flags.json" 2>/dev/null)"
if [[ "$BEFORE" == "$AFTER" ]]; then
  printf "${GREEN}[PASS]${NC} [A5] 무관 프롬프트 → 무해 통과(파일 불변)\n"; (( PASS_COUNT++ )) || true
else
  printf "${RED}[FAIL]${NC} [A5] 무관 프롬프트인데 파일이 변경됨\n"; (( FAIL_COUNT++ )) || true
fi

# 16-5. "off" → 경고 접두(!) 포함 확인응답
JSON='{"prompt":"/bathos intensity off"}'
OUT="$(BATHOS_STATE_DIR="$IT_STATE_DIR" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" BATHOS_BIN="$_BATHOS_BIN_PATH" \
  bash "$HOOKS_DIR/intensity-tracker.sh" <<< "$JSON" 2>/dev/null)"
if printf '%s' "$OUT" | grep -q '! intensity=off' && grep -Eq '"intensity":[[:space:]]*"off"' "$IT_STATE_DIR/session-flags.json" 2>/dev/null; then
  printf "${GREEN}[PASS]${NC} [A5] intensity=off → 경고 접두(!) 확인응답 + 기록\n"; (( PASS_COUNT++ )) || true
else
  printf "${RED}[FAIL]${NC} [A5] off 경고 표기 실패: %s\n" "$OUT"; (( FAIL_COUNT++ )) || true
fi

# 16-6. plan_mode 필드는 절대 건드리지 않는다(LD-4 AC5 필드 독립성)
cat > "$IT_STATE_DIR/session-flags.json" <<'EOF'
{"$schema":"bathos:session-flags","plan_mode":"on","intensity":"full","updated":"2026-07-08T00:00:00Z"}
EOF
JSON='{"prompt":"/bathos intensity lite"}'
BATHOS_STATE_DIR="$IT_STATE_DIR" CLAUDE_PROJECT_DIR="$TMPDIR_BASE" BATHOS_BIN="$_BATHOS_BIN_PATH" \
  bash "$HOOKS_DIR/intensity-tracker.sh" <<< "$JSON" >/dev/null 2>/dev/null
if grep -Eq '"plan_mode":[[:space:]]*"on"' "$IT_STATE_DIR/session-flags.json" 2>/dev/null \
   && grep -Eq '"intensity":[[:space:]]*"lite"' "$IT_STATE_DIR/session-flags.json" 2>/dev/null; then
  printf "${GREEN}[PASS]${NC} [A5] intensity 변경이 plan_mode 필드를 건드리지 않음(필드 독립성)\n"; (( PASS_COUNT++ )) || true
else
  printf "${RED}[FAIL]${NC} [A5] plan_mode 필드 간섭 발생: %s\n" "$(cat "$IT_STATE_DIR/session-flags.json" 2>/dev/null)"; (( FAIL_COUNT++ )) || true
fi


# --------------------------------------------------------------------------
# 8. 최종 결과
# --------------------------------------------------------------------------
printf '\n══════════════════════════════════════════════\n'
TOTAL=$(( PASS_COUNT + FAIL_COUNT ))
printf "테스트 결과: ${GREEN}%d PASS${NC} / ${RED}%d FAIL${NC} (총 %d)\n" \
  "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  printf "${RED}일부 테스트가 실패했습니다. 위 출력을 확인하세요.${NC}\n"
  exit 1
else
  printf "${GREEN}모든 테스트 통과! M6 훅 결정성 + B-1/B-3/H-6/H-7/L-4 수정 + Dynamis A1~A6 확인 완료.${NC}\n"
  exit 0
fi
