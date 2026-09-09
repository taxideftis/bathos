#!/usr/bin/env bash
# =============================================================================
# BATHOS P5 — codex-adapter/hooks/_test-codex-hooks.sh
# 시뮬레이션 테스트 하네스: pretooluse-gate.sh · stop-save.sh를 실제 Codex
# 설치 없이 검증한다. 가짜 stdin JSON을 파이프하고, 스텁 bathos로 verdict를
# 재생해 exit code·stderr·부수효과(파일)를 단정(assert)한다.
#
# 설계 원본: .agent-team/04-architecture/w2-runtime-p4-design-kr.md §B5 (James)
# 자리매김: .claude/hooks/_test-hooks.sh와 동일(수동 실행 검증 스크립트).
# bash 3.2 호환(카운터 변수 + 함수, 연관배열 금지).
#
# P5 갱신(2026-07-16, Codex v0.144.5 macos-x86_64 실측 반영):
# 픽스처 stdin의 tool_name을 실측값(shell/exec_command/apply_patch)으로
# 교체하고, B-15~B-18을 추가해 "Bash는 존재하지 않는다"는 실측 사실이
# 회귀하지 않음을 계약화한다(B-3은 이제 실측 tool_name인 shell로 웨이브
# 진입 명령을 검증하고, B-15는 옛 P4 가정이던 Bash가 더 이상 필요/유효하지
# 않음 — 오지 않는 값이므로 무해 통과만 확인 — 을 별도로 남겨 둔다).
#
# P5.1 갱신(2026-07-17): B-19~B-20을 추가해 절대경로 apply_patch 회귀를
# 계약화한다 — 실제 Codex는 패치를 tool_input.command에 싣고 파일을 절대경로로
# 지목하는데, 옛 SRC_ERE 경계가 '/'를 인정하지 않아 T1이 미발화(fail-open)했다.
# 경계에 '/'를 추가한 수정을 B-19(FAIL->exit2)·B-20(PASS->exit0)으로 잠근다.
#
# story-01(2026-07-23) 갱신: ADR-CX-02 2층 대칭 광폭화 — matcher뿐 아니라
# 스크립트 내부 T1/T2 case도 별칭 tool_name(Bash/Edit/Write)을 대칭으로
# 넓혔다. B-17을 "Bash 무해" 전제에서 "Bash도 발화" 전제로 갱신하고
# B-21~B-25로 나머지 별칭 조합을 계약화한다.
#
# story-02(2026-07-23) 갱신: stop-save stdout 무출력 봉인(B-11~B-14 보강) +
# matcher 정본 바이트단위 일치 검증(config.toml.example ↔ .codex/hooks.json).
#
# story-13(2026-07-23) 갱신: bash(dist/lib/host-detect.sh) ↔ Rust
# (bathos-state::runtime_host::detect, `bathos runtime`) 교차 검증 5행 —
# 한쪽만 고치면 이 절이 깨진다(D-RT5 드리프트 방지).
#
# 타겟 버전 이동(2026-07-23, 리드 결정): v0.144.5 → v0.145.0+(2026-07-21
# stable). 위 P5/P5.1 실측 기록(2026-07-16/17)은 v0.144.5 설치본 결과이므로
# 고쳐 쓰지 않는다 — 픽스처가 실측 3종+별칭 3종 합집합을 쓰는 이유가 바로
# 이 버전 이동 같은 드리프트를 흡수하기 위해서다. v0.145.0+ 라이브 재실측은
# probe.sh(story-03)·story-20 몫.
#
# 실행: bash codex-adapter/hooks/_test-codex-hooks.sh
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$SCRIPT_DIR"
BASH_BIN="$(command -v bash)"

TMPDIR_BASE="$(mktemp -d)"
cleanup() { rm -rf "$TMPDIR_BASE"; }
trap cleanup EXIT

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASS_COUNT=0
FAIL_COUNT=0

assert_exit() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" -eq "$expected" ] 2>/dev/null; then
    printf "${GREEN}[PASS]${NC} %s (exit=%d)\n" "$desc" "$actual"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    printf "${RED}[FAIL]${NC} %s — 예상 exit=%d, 실제 exit=%d\n" "$desc" "$expected" "$actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

assert_true() {
  # $1=desc $2=condition(0/1, already-evaluated as shell truthiness via [ ] outside)
  local desc="$1" ok="$2"
  if [ "$ok" = "1" ]; then
    printf "${GREEN}[PASS]${NC} %s\n" "$desc"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    printf "${RED}[FAIL]${NC} %s\n" "$desc"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# --------------------------------------------------------------------------
# 스텁 bathos 생성 헬퍼 — $1=STUB_DIR $2=verdict("PASS"|"CONCERNS"|"FAIL"|"EMPTY")
# --------------------------------------------------------------------------
make_stub_bathos() {
  local stub_dir="$1" verdict="$2"
  mkdir -p "$stub_dir"
  printf '%s' "$verdict" > "$stub_dir/verdict"
  cat > "$stub_dir/bathos" <<'STUB_EOF'
#!/usr/bin/env bash
# 스텁 bathos — 호출 기록 + verdict 재생 (실제 Codex/BATHOS 빌드 불요)
STUB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "$*" >> "$STUB_DIR/calls.log"
case "$*" in
  *"gate show"*)
     V="$(cat "$STUB_DIR/verdict" 2>/dev/null)"
     if [ "$V" = "EMPTY" ]; then exit 0; fi
     printf '{"decided":"2026-07-16T00:00:00Z","facilitator":"Paul","gate_type":"Implementation","issues_critical":0,"issues_total":1,"verdict":"%s","wave_id":"W3"}\n' "$V"
     ;;
  *"state show"*)
     printf '{"project_id":"stub","stub":true}\n'
     ;;
  *"audit append"*)
     exit 0
     ;;
esac
exit 0
STUB_EOF
  chmod +x "$stub_dir/bathos"
}

# --------------------------------------------------------------------------
# 픽스처 프로젝트 디렉터리 생성 — $1=이름 -> stdout에 절대경로
# --------------------------------------------------------------------------
make_fixture_project() {
  local name="$1"
  local dir="$TMPDIR_BASE/proj-$name"
  mkdir -p "$dir/.agent-team/_state"
  printf '# seed\n' > "$dir/.agent-team/_state/SESSION-SNAPSHOT.md"
  printf '%s' "$dir"
}

# --------------------------------------------------------------------------
# 훅 실행 헬퍼 — $1=hook_script $2=stdin_json (env는 호출부에서 export)
# 표준출력에 "EXIT<tab>STDERR_B64" 형태로 반환(멀티라인 stderr 보존 위해 base64).
# --------------------------------------------------------------------------
run_hook() {
  local hook="$1" stdin_json="$2"
  local out ec
  out="$(printf '%s' "$stdin_json" | bash "$hook" 2>&1 1>/dev/null)"
  ec=$?
  printf '%d\t%s' "$ec" "$(printf '%s' "$out" | base64 | tr -d '\n')"
}

get_exit() { printf '%s' "$1" | cut -f1; }
get_stderr() { printf '%s' "$1" | cut -f2- | base64 -d 2>/dev/null; }

# ==========================================================================
# 픽스처 stdin JSON (하네스 내 printf 상수, <TMP_PROJ>를 실경로로 치환)
# tool_name은 Codex v0.144.5(macos-x86_64) 실측값만 사용한다: shell,
# exec_command, apply_patch. `Bash`는 존재하지 않는 값이며(P5에서 확정),
# 그 사실 자체를 검증하는 픽스처는 별도로 json_legacy_bash_wave()에 둔다.
# ==========================================================================
json_write_src() {
  printf '{"session_id":"s1","turn_id":"t1","hook_event_name":"PreToolUse","tool_name":"apply_patch","cwd":"%s","tool_input":{"patch":"*** Update File: core/crates/bathos-cli/src/main.rs"}}' "$1"
}
json_shell_wave() {
  # T2: 실측 tool_name "shell"의 tool_input.command가 웨이브 진입 명령.
  printf '{"session_id":"s1","turn_id":"t1","hook_event_name":"PreToolUse","tool_name":"shell","cwd":"%s","tool_input":{"command":"bathos wave advance --to W5"}}' "$1"
}
json_exec_command_wave() {
  # T2: 실측 tool_name "exec_command"(shell과 별개 값)로도 동일하게 발화해야 한다.
  printf '{"session_id":"s1","turn_id":"t1","hook_event_name":"PreToolUse","tool_name":"exec_command","cwd":"%s","tool_input":{"command":"bathos wave advance --to W5"}}' "$1"
}
json_bash_benign() {
  printf '{"session_id":"s1","turn_id":"t1","hook_event_name":"PreToolUse","tool_name":"shell","cwd":"%s","tool_input":{"command":"ls -la"}}' "$1"
}
json_write_docs() {
  printf '{"session_id":"s1","turn_id":"t1","hook_event_name":"PreToolUse","tool_name":"apply_patch","cwd":"%s","tool_input":{"patch":"*** Update File: .agent-team/08-impl-notes/backend.md"}}' "$1"
}
json_shell_write_src() {
  # T1: apply_patch가 아니라 shell 도구가 sed -i로 소스 경로를 직접 쓰는 경우
  # (§4 T1 케이스가 apply_patch 외 shell/exec_command도 포함하는지 검증).
  printf '{"session_id":"s1","turn_id":"t1","hook_event_name":"PreToolUse","tool_name":"shell","cwd":"%s","tool_input":{"command":"sed -i \\"\\" \\"s/x/y/\\" core/crates/bathos-cli/src/main.rs"}}' "$1"
}
json_bash_wave() {
  # ADR-CX-02(2026-07-23) 2층 대칭 광폭화: tool_name "Bash"(문서 별칭 — P4가
  # 가정했으나 v0.144.5 실측에는 없던 값)로 웨이브 진입 명령을 보낸다. story-01
  # 이전에는 케이스문에 Bash가 없어 무해(비트리거)했으나, 지금은 T2 case에
  # Bash가 추가돼 있으므로 발화해야 한다(P5의 "Bash 무해" 전제는 ADR-CX-02로
  # 대체됨 — 구 json_legacy_bash_wave()의 옛 주석·함수명 승계 아님, 의도된 변경).
  printf '{"session_id":"s1","turn_id":"t1","hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"%s","tool_input":{"command":"bathos wave advance --to W5"}}' "$1"
}
json_edit_write_src() {
  # ADR-CX-02 별칭: tool_name "Edit"(문서 별칭, apply_patch에 대응)로 소스
  # 경로를 편집 — T1이 발화해야 한다. Claude Code Edit 도구의 file_path 필드
  # 관례를 그대로 사용(freeze-guard.sh와 동일 스키마 가정).
  printf '{"session_id":"s1","turn_id":"t1","hook_event_name":"PreToolUse","tool_name":"Edit","cwd":"%s","tool_input":{"file_path":"%s/src/main.rs"}}' "$1" "$1"
}
json_write_tool_src() {
  # ADR-CX-02 별칭: tool_name "Write"(문서 별칭, apply_patch에 대응)로 소스
  # 경로에 신규 파일을 작성 — T1이 발화해야 한다.
  printf '{"session_id":"s1","turn_id":"t1","hook_event_name":"PreToolUse","tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s/src/new_file.rs"}}' "$1" "$1"
}
json_unrelated_tool() {
  # 게이트 트리거와 무관한 tool_name(가상의 read 계열 도구) -> 항상 통과.
  printf '{"session_id":"s1","turn_id":"t1","hook_event_name":"PreToolUse","tool_name":"read_file","cwd":"%s","tool_input":{"path":"README.md"}}' "$1"
}
json_apply_patch_abspath() {
  # T1 절대경로 회귀: 실제 Codex apply_patch는 패치를 tool_input.command에 싣고
  # `*** Update File:` 헤더는 파일을 **절대경로**로 지목한다(/Users/.../src/...).
  # $1 = 픽스처 프로젝트 절대경로. src/ 앞이 '/'인 절대경로가 SRC_ERE 경계에
  # 걸려 source-write로 발화하는지(= 옛 ERE의 fail-open 재발 방지)를 계약화한다.
  printf '{"session_id":"s1","turn_id":"t1","hook_event_name":"PreToolUse","tool_name":"apply_patch","cwd":"%s","tool_input":{"command":"*** Begin Patch *** Update File: %s/src/main.rs @@ -BASELINE +MODIFIED *** End Patch"}}' "$1" "$1"
}
json_careful_rm_rf() {
  printf '{"session_id":"s1","turn_id":"t1","hook_event_name":"PreToolUse","tool_name":"shell","cwd":"%s","tool_input":{"command":"rm -rf /tmp/some-target"}}' "$1"
}
json_careful_benign() {
  printf '{"session_id":"s1","turn_id":"t1","hook_event_name":"PreToolUse","tool_name":"shell","cwd":"%s","tool_input":{"command":"ls -la"}}' "$1"
}
json_freeze_apply_patch_path() {
  # $1=cwd(픽스처 프로젝트 절대경로) $2=cwd 기준 상대경로(예: src/main.rs)
  printf '{"session_id":"s1","turn_id":"t1","hook_event_name":"PreToolUse","tool_name":"apply_patch","cwd":"%s","tool_input":{"command":"*** Begin Patch *** Update File: %s/%s @@ -BASELINE +MODIFIED *** End Patch"}}' "$1" "$1" "$2"
}
json_session_start_resume() {
  printf '{"hook_event_name":"SessionStart","source":"resume","cwd":"%s"}' "$1"
}
json_session_start_clear() {
  printf '{"hook_event_name":"SessionStart","source":"clear","cwd":"%s"}' "$1"
}
json_stop() {
  printf '{"session_id":"s1","turn_id":"t9","hook_event_name":"Stop","stop_hook_active":false,"cwd":"%s","last_assistant_message":"done"}' "$1"
}
json_stop_active() {
  printf '{"session_id":"s1","turn_id":"t9","hook_event_name":"Stop","stop_hook_active":true,"cwd":"%s","last_assistant_message":"done"}' "$1"
}
JSON_GARBAGE='not json at all'

# ==========================================================================
# B-1 ~ B-10: pretooluse-gate.sh
# ==========================================================================
printf '\n=== pretooluse-gate.sh (B-1 ~ B-10) ===\n'

# --- B-1: J_WRITE_SRC, verdict=PASS -> exit 0, stderr에 BLOCKED 없음 ---
P1="$(make_fixture_project b1)"
STUB1="$TMPDIR_BASE/stub-b1"; make_stub_bathos "$STUB1" "PASS"
RES="$(BATHOS_BIN="$STUB1/bathos" run_hook "$HOOKS_DIR/pretooluse-gate.sh" "$(json_write_src "$P1")")"
EC="$(get_exit "$RES")"; ERR="$(get_stderr "$RES")"
assert_exit "B-1 소스쓰기 + PASS -> 통과" 0 "$EC"
if printf '%s' "$ERR" | grep -q 'BLOCKED'; then
  assert_true "B-1 stderr에 BLOCKED 없음" 0
else
  assert_true "B-1 stderr에 BLOCKED 없음" 1
fi

# --- B-2: J_WRITE_SRC, verdict=FAIL -> exit 2, stderr에 BLOCKED·FAIL ---
P2="$(make_fixture_project b2)"
STUB2="$TMPDIR_BASE/stub-b2"; make_stub_bathos "$STUB2" "FAIL"
RES="$(BATHOS_BIN="$STUB2/bathos" run_hook "$HOOKS_DIR/pretooluse-gate.sh" "$(json_write_src "$P2")")"
EC="$(get_exit "$RES")"; ERR="$(get_stderr "$RES")"
assert_exit "B-2 소스쓰기 + FAIL -> 차단(exit 2)" 2 "$EC"
if printf '%s' "$ERR" | grep -q 'BLOCKED' && printf '%s' "$ERR" | grep -q 'FAIL'; then
  assert_true "B-2 stderr에 BLOCKED·FAIL 포함" 1
else
  assert_true "B-2 stderr에 BLOCKED·FAIL 포함" 0
fi

# --- B-3: J_SHELL_WAVE(tool_name=shell, 실측), verdict=FAIL -> exit 2, stderr에 wave-entry-command ---
P3="$(make_fixture_project b3)"
STUB3="$TMPDIR_BASE/stub-b3"; make_stub_bathos "$STUB3" "FAIL"
RES="$(BATHOS_BIN="$STUB3/bathos" run_hook "$HOOKS_DIR/pretooluse-gate.sh" "$(json_shell_wave "$P3")")"
EC="$(get_exit "$RES")"; ERR="$(get_stderr "$RES")"
assert_exit "B-3 웨이브진입명령(tool_name=shell) + FAIL -> 차단(exit 2)" 2 "$EC"
if printf '%s' "$ERR" | grep -q 'wave-entry-command'; then
  assert_true "B-3 stderr에 wave-entry-command 포함" 1
else
  assert_true "B-3 stderr에 wave-entry-command 포함" 0
fi

# --- B-4: J_WRITE_SRC, verdict=CONCERNS -> exit 0, stderr에 CONCERNS ---
P4="$(make_fixture_project b4)"
STUB4="$TMPDIR_BASE/stub-b4"; make_stub_bathos "$STUB4" "CONCERNS"
RES="$(BATHOS_BIN="$STUB4/bathos" run_hook "$HOOKS_DIR/pretooluse-gate.sh" "$(json_write_src "$P4")")"
EC="$(get_exit "$RES")"; ERR="$(get_stderr "$RES")"
assert_exit "B-4 소스쓰기 + CONCERNS -> 통과" 0 "$EC"
if printf '%s' "$ERR" | grep -q 'CONCERNS'; then
  assert_true "B-4 stderr에 CONCERNS 포함" 1
else
  assert_true "B-4 stderr에 CONCERNS 포함" 0
fi

# --- B-5: J_BASH_BENIGN(tool_name=shell, 무해 명령), verdict=FAIL(스텁) -> exit 0, calls.log 비어있음(비트리거는 bathos 미호출) ---
P5="$(make_fixture_project b5)"
STUB5="$TMPDIR_BASE/stub-b5"; make_stub_bathos "$STUB5" "FAIL"
RES="$(BATHOS_BIN="$STUB5/bathos" run_hook "$HOOKS_DIR/pretooluse-gate.sh" "$(json_bash_benign "$P5")")"
EC="$(get_exit "$RES")"
assert_exit "B-5 무해 shell 명령 -> 통과" 0 "$EC"
if [ ! -s "$STUB5/calls.log" ]; then
  assert_true "B-5 calls.log 비어있음(bathos 미호출)" 1
else
  assert_true "B-5 calls.log 비어있음(bathos 미호출)" 0
fi

# --- B-6: J_WRITE_SRC, BATHOS_BIN=/nonexistent + manifest/report도 없음 -> exit 0, fail-safe 경고 ---
P6="$(make_fixture_project b6)"
RES="$(BATHOS_BIN=/nonexistent run_hook "$HOOKS_DIR/pretooluse-gate.sh" "$(json_write_src "$P6")")"
EC="$(get_exit "$RES")"; ERR="$(get_stderr "$RES")"
assert_exit "B-6 bathos 없음 -> fail-safe 통과" 0 "$EC"
if printf '%s' "$ERR" | grep -q '확인 불가'; then
  assert_true "B-6 stderr에 fail-safe 경고" 1
else
  assert_true "B-6 stderr에 fail-safe 경고" 0
fi

# --- B-7: J_WRITE_SRC, verdict=EMPTY(게이트 미존재) -> exit 0, stderr에 "verdict 확인 불가" ---
P7="$(make_fixture_project b7)"
STUB7="$TMPDIR_BASE/stub-b7"; make_stub_bathos "$STUB7" "EMPTY"
RES="$(BATHOS_BIN="$STUB7/bathos" run_hook "$HOOKS_DIR/pretooluse-gate.sh" "$(json_write_src "$P7")")"
EC="$(get_exit "$RES")"; ERR="$(get_stderr "$RES")"
assert_exit "B-7 게이트 미존재(EMPTY) -> 통과" 0 "$EC"
if printf '%s' "$ERR" | grep -q '확인 불가'; then
  assert_true "B-7 stderr에 verdict 확인 불가" 1
else
  assert_true "B-7 stderr에 verdict 확인 불가" 0
fi

# --- B-8: J_WRITE_DOCS, verdict=FAIL -> exit 0, .agent-team/ 전용 쓰기는 비트리거 ---
P8="$(make_fixture_project b8)"
STUB8="$TMPDIR_BASE/stub-b8"; make_stub_bathos "$STUB8" "FAIL"
RES="$(BATHOS_BIN="$STUB8/bathos" run_hook "$HOOKS_DIR/pretooluse-gate.sh" "$(json_write_docs "$P8")")"
EC="$(get_exit "$RES")"
assert_exit "B-8 .agent-team/ 전용 쓰기 -> 비트리거 통과" 0 "$EC"

# --- B-9: J_GARBAGE, verdict=FAIL -> exit 0, 파싱 실패 fail-safe ---
STUB9="$TMPDIR_BASE/stub-b9"; make_stub_bathos "$STUB9" "FAIL"
RES="$(BATHOS_BIN="$STUB9/bathos" run_hook "$HOOKS_DIR/pretooluse-gate.sh" "$JSON_GARBAGE")"
EC="$(get_exit "$RES")"
assert_exit "B-9 비-JSON 입력 -> fail-safe 통과" 0 "$EC"

# --- B-10: J_WRITE_SRC, _state 없는 cwd -> exit 0, 비-BATHOS 프로젝트 통과 ---
NO_STATE_DIR="$TMPDIR_BASE/proj-b10-no-state"
mkdir -p "$NO_STATE_DIR"
STUB10="$TMPDIR_BASE/stub-b10"; make_stub_bathos "$STUB10" "FAIL"
RES="$(BATHOS_BIN="$STUB10/bathos" run_hook "$HOOKS_DIR/pretooluse-gate.sh" "$(json_write_src "$NO_STATE_DIR")")"
EC="$(get_exit "$RES")"
assert_exit "B-10 _state 없는 cwd -> 비-BATHOS 프로젝트 통과" 0 "$EC"

# --------------------------------------------------------------------------
# B-15 ~ B-18: P5 실측 회귀(Codex v0.144.5) — tool_name 하드닝 계약화
# --------------------------------------------------------------------------

# --- B-15: J_EXEC_COMMAND_WAVE(tool_name=exec_command), verdict=FAIL -> exit 2 ---
# (a) 웨이브 진입 명령이 exec_command로 와도 shell과 동일하게 차단되어야 한다.
P15="$(make_fixture_project b15)"
STUB15="$TMPDIR_BASE/stub-b15"; make_stub_bathos "$STUB15" "FAIL"
RES="$(BATHOS_BIN="$STUB15/bathos" run_hook "$HOOKS_DIR/pretooluse-gate.sh" "$(json_exec_command_wave "$P15")")"
EC="$(get_exit "$RES")"; ERR="$(get_stderr "$RES")"
assert_exit "B-15 웨이브진입명령(tool_name=exec_command) + FAIL -> 차단(exit 2)" 2 "$EC"
if printf '%s' "$ERR" | grep -q 'wave-entry-command'; then
  assert_true "B-15 stderr에 wave-entry-command 포함" 1
else
  assert_true "B-15 stderr에 wave-entry-command 포함" 0
fi

# --- B-16: J_SHELL_WRITE_SRC(tool_name=shell, sed -i 로 src/ 직접 쓰기), verdict=FAIL -> exit 2 ---
# (b) apply_patch가 아니어도 shell이 소스 경로를 직접 쓰면 T1(source-write)로
# 차단되어야 한다(§4 T1 케이스가 apply_patch 외 shell/exec_command도 포함).
P16="$(make_fixture_project b16)"
STUB16="$TMPDIR_BASE/stub-b16"; make_stub_bathos "$STUB16" "FAIL"
RES="$(BATHOS_BIN="$STUB16/bathos" run_hook "$HOOKS_DIR/pretooluse-gate.sh" "$(json_shell_write_src "$P16")")"
EC="$(get_exit "$RES")"; ERR="$(get_stderr "$RES")"
assert_exit "B-16 shell의 소스직접쓰기(sed -i) + FAIL -> 차단(exit 2)" 2 "$EC"
if printf '%s' "$ERR" | grep -q 'source-write'; then
  assert_true "B-16 stderr에 source-write 포함" 1
else
  assert_true "B-16 stderr에 source-write 포함" 0
fi

# --- B-17: J_BASH_WAVE(tool_name="Bash", ADR-CX-02 별칭), verdict=FAIL -> exit 2 ---
# (c) ADR-CX-02(2026-07-23)의 2층 대칭 광폭화 이후 "Bash"는 T2(웨이브 진입
# 명령) case에 포함된 별칭 tool_name이다 — P5 시절엔 (실측에 없어) 무해했지만
# 지금은 matcher가 넓어졌으니 내부 case도 대칭으로 넓어져야 하고, 발화해야
# 한다. story-01의 핵심 교훈("두 층 모두 넓혀야 한다")을 정확히 이 케이스가
# 계약화한다 — 옛 B-17(비트리거 기대)을 그대로 두면 회귀를 놓친다.
P17="$(make_fixture_project b17)"
STUB17="$TMPDIR_BASE/stub-b17"; make_stub_bathos "$STUB17" "FAIL"
RES="$(BATHOS_BIN="$STUB17/bathos" run_hook "$HOOKS_DIR/pretooluse-gate.sh" "$(json_bash_wave "$P17")")"
EC="$(get_exit "$RES")"; ERR="$(get_stderr "$RES")"
assert_exit "B-17 별칭 tool_name=Bash 웨이브진입 + FAIL -> 차단(exit 2)" 2 "$EC"
if printf '%s' "$ERR" | grep -q 'wave-entry-command'; then
  assert_true "B-17 stderr에 wave-entry-command 포함" 1
else
  assert_true "B-17 stderr에 wave-entry-command 포함" 0
fi

# --------------------------------------------------------------------------
# B-21 ~ B-25: ADR-CX-02 2층 대칭 광폭화 — 별칭 tool_name 회귀(story-01 AC#3)
# --------------------------------------------------------------------------
# matcher 광폭화만으로는 불충분하다는 게 ADR-CX-02의 결론이었다(§2.1) — 아래는
# Bash(T2)·Edit/Write(T1) 각각의 FAIL→exit2 / PASS→exit0 쌍을 계약화한다.
# (B-17이 Bash+FAIL을 이미 담당하므로 여기서는 Bash+PASS부터.)

# --- B-21: J_BASH_WAVE, verdict=PASS -> exit 0 ---
P21="$(make_fixture_project b21)"
STUB21="$TMPDIR_BASE/stub-b21"; make_stub_bathos "$STUB21" "PASS"
RES="$(BATHOS_BIN="$STUB21/bathos" run_hook "$HOOKS_DIR/pretooluse-gate.sh" "$(json_bash_wave "$P21")")"
EC="$(get_exit "$RES")"
assert_exit "B-21 별칭 tool_name=Bash 웨이브진입 + PASS -> 통과(exit 0)" 0 "$EC"

# --- B-22: J_EDIT_WRITE_SRC(tool_name=Edit), verdict=FAIL -> exit 2 ---
P22="$(make_fixture_project b22)"
STUB22="$TMPDIR_BASE/stub-b22"; make_stub_bathos "$STUB22" "FAIL"
RES="$(BATHOS_BIN="$STUB22/bathos" run_hook "$HOOKS_DIR/pretooluse-gate.sh" "$(json_edit_write_src "$P22")")"
EC="$(get_exit "$RES")"; ERR="$(get_stderr "$RES")"
assert_exit "B-22 별칭 tool_name=Edit 소스편집 + FAIL -> 차단(exit 2)" 2 "$EC"
if printf '%s' "$ERR" | grep -q 'source-write'; then
  assert_true "B-22 stderr에 source-write 포함" 1
else
  assert_true "B-22 stderr에 source-write 포함" 0
fi

# --- B-23: J_EDIT_WRITE_SRC(tool_name=Edit), verdict=PASS -> exit 0 ---
P23="$(make_fixture_project b23)"
STUB23="$TMPDIR_BASE/stub-b23"; make_stub_bathos "$STUB23" "PASS"
RES="$(BATHOS_BIN="$STUB23/bathos" run_hook "$HOOKS_DIR/pretooluse-gate.sh" "$(json_edit_write_src "$P23")")"
EC="$(get_exit "$RES")"
assert_exit "B-23 별칭 tool_name=Edit 소스편집 + PASS -> 통과(exit 0)" 0 "$EC"

# --- B-24: J_WRITE_TOOL_SRC(tool_name=Write), verdict=FAIL -> exit 2 ---
P24="$(make_fixture_project b24)"
STUB24="$TMPDIR_BASE/stub-b24"; make_stub_bathos "$STUB24" "FAIL"
RES="$(BATHOS_BIN="$STUB24/bathos" run_hook "$HOOKS_DIR/pretooluse-gate.sh" "$(json_write_tool_src "$P24")")"
EC="$(get_exit "$RES")"; ERR="$(get_stderr "$RES")"
assert_exit "B-24 별칭 tool_name=Write 소스작성 + FAIL -> 차단(exit 2)" 2 "$EC"
if printf '%s' "$ERR" | grep -q 'source-write'; then
  assert_true "B-24 stderr에 source-write 포함" 1
else
  assert_true "B-24 stderr에 source-write 포함" 0
fi

# --- B-25: J_WRITE_TOOL_SRC(tool_name=Write), verdict=PASS -> exit 0 ---
P25="$(make_fixture_project b25)"
STUB25="$TMPDIR_BASE/stub-b25"; make_stub_bathos "$STUB25" "PASS"
RES="$(BATHOS_BIN="$STUB25/bathos" run_hook "$HOOKS_DIR/pretooluse-gate.sh" "$(json_write_tool_src "$P25")")"
EC="$(get_exit "$RES")"
assert_exit "B-25 별칭 tool_name=Write 소스작성 + PASS -> 통과(exit 0)" 0 "$EC"

# --- B-18: J_UNRELATED_TOOL(tool_name=read_file), verdict=FAIL -> exit 0 ---
# (d) 게이트 트리거와 무관한 tool_name은 verdict와 무관하게 항상 통과.
P18="$(make_fixture_project b18)"
STUB18="$TMPDIR_BASE/stub-b18"; make_stub_bathos "$STUB18" "FAIL"
RES="$(BATHOS_BIN="$STUB18/bathos" run_hook "$HOOKS_DIR/pretooluse-gate.sh" "$(json_unrelated_tool "$P18")")"
EC="$(get_exit "$RES")"
assert_exit "B-18 무관 tool_name(read_file) -> 통과(exit 0)" 0 "$EC"
if [ ! -s "$STUB18/calls.log" ]; then
  assert_true "B-18 calls.log 비어있음(비트리거 -> bathos 미호출)" 1
else
  assert_true "B-18 calls.log 비어있음(비트리거 -> bathos 미호출)" 0
fi

# --------------------------------------------------------------------------
# B-19 ~ B-20: 절대경로 apply_patch 회귀(2026-07-17) — SRC_ERE '/' 경계
# --------------------------------------------------------------------------
# 실제 Codex apply_patch는 패치를 tool_input.command에 싣고 대상 파일을
# **절대경로**(/Users/.../src/...)로 지목한다. 옛 SRC_ERE 경계 [^A-Za-z0-9_./-]는
# '/'를 경계로 인정하지 않아 절대경로 앞의 src/가 매치되지 않았고(T1 미발화),
# FAIL 게이트에서도 소스 편집이 exit 0으로 통과하는 fail-open 버그였다. 경계에
# '/'를 추가한 수정을 계약화한다 — B-19는 옛 ERE에서 반드시 red가 되는 케이스다.

# --- B-19: apply_patch + 절대경로 src/, verdict=FAIL -> exit 2, stderr에 source-write ---
P19="$(make_fixture_project b19)"
STUB19="$TMPDIR_BASE/stub-b19"; make_stub_bathos "$STUB19" "FAIL"
RES="$(BATHOS_BIN="$STUB19/bathos" run_hook "$HOOKS_DIR/pretooluse-gate.sh" "$(json_apply_patch_abspath "$P19")")"
EC="$(get_exit "$RES")"; ERR="$(get_stderr "$RES")"
assert_exit "B-19 apply_patch 절대경로 src/ + FAIL -> 차단(exit 2)" 2 "$EC"
if printf '%s' "$ERR" | grep -q 'source-write'; then
  assert_true "B-19 stderr에 source-write 포함" 1
else
  assert_true "B-19 stderr에 source-write 포함" 0
fi

# --- B-20: apply_patch + 절대경로 src/, verdict=PASS -> exit 0 (넓어진 경계가 게이트 판정을 넘어서 과차단하지 않음) ---
P20="$(make_fixture_project b20)"
STUB20="$TMPDIR_BASE/stub-b20"; make_stub_bathos "$STUB20" "PASS"
RES="$(BATHOS_BIN="$STUB20/bathos" run_hook "$HOOKS_DIR/pretooluse-gate.sh" "$(json_apply_patch_abspath "$P20")")"
EC="$(get_exit "$RES")"
assert_exit "B-20 apply_patch 절대경로 src/ + PASS -> 통과(exit 0)" 0 "$EC"

# ==========================================================================
# B-11 ~ B-14: stop-save.sh
# ==========================================================================
printf '\n=== stop-save.sh (B-11 ~ B-14) ===\n'

# --- B-11: J_STOP -> session-state.json 존재·유효 JSON, 로그 dump=ok, 스냅샷 아카이브 생성 ---
# story-02 AC#4 봉인 겸용: 1회 실행으로 exit·stdout을 함께 확인한다(run_hook()은
# stdout을 버리므로 여기만 파이프 직접 조합 — stdout 1바이트도 없어야 한다,
# CT-HOOK-STOP "decision:block 의미 반전" 회피 계약).
P11="$(make_fixture_project b11)"
STUB11="$TMPDIR_BASE/stub-b11"; make_stub_bathos "$STUB11" "PASS"
STDOUT_B11="$(printf '%s' "$(json_stop "$P11")" | BATHOS_BIN="$STUB11/bathos" bash "$HOOKS_DIR/stop-save.sh")"
EC=$?
assert_exit "B-11 Stop 저장 -> exit 0" 0 "$EC"
if [ -z "$STDOUT_B11" ]; then
  assert_true "B-11 stdout 무출력(0바이트) 봉인" 1
else
  assert_true "B-11 stdout 무출력(0바이트) 봉인" 0
fi

STATE_DIR_11="$P11/.agent-team/_state"
if [ -f "$STATE_DIR_11/session-state.json" ] && head -c1 "$STATE_DIR_11/session-state.json" | grep -q '{'; then
  assert_true "B-11 session-state.json 존재·유효 JSON({로 시작)" 1
else
  assert_true "B-11 session-state.json 존재·유효 JSON({로 시작)" 0
fi
if grep -q 'dump=ok' "$STATE_DIR_11/codex-stop-save.log" 2>/dev/null; then
  assert_true "B-11 codex-stop-save.log에 dump=ok" 1
else
  assert_true "B-11 codex-stop-save.log에 dump=ok" 0
fi
TODAY="$(date '+%Y-%m-%d')"
if [ -f "$STATE_DIR_11/SESSION-SNAPSHOT-$TODAY.md" ]; then
  assert_true "B-11 스냅샷 날짜 아카이브 생성" 1
else
  assert_true "B-11 스냅샷 날짜 아카이브 생성" 0
fi

# --- B-12: J_STOP, BATHOS_BIN=/nonexistent -> 로그 dump=no-bathos, session-state.json 미생성(기존본 미파괴) ---
P12="$(make_fixture_project b12)"
STDOUT_B12="$(printf '%s' "$(json_stop "$P12")" | BATHOS_BIN=/nonexistent bash "$HOOKS_DIR/stop-save.sh")"
EC=$?
assert_exit "B-12 bathos 없음 -> exit 0" 0 "$EC"
if [ -z "$STDOUT_B12" ]; then
  assert_true "B-12 stdout 무출력(0바이트) 봉인" 1
else
  assert_true "B-12 stdout 무출력(0바이트) 봉인" 0
fi
STATE_DIR_12="$P12/.agent-team/_state"
if grep -q 'dump=no-bathos' "$STATE_DIR_12/codex-stop-save.log" 2>/dev/null; then
  assert_true "B-12 로그에 dump=no-bathos" 1
else
  assert_true "B-12 로그에 dump=no-bathos" 0
fi
if [ ! -f "$STATE_DIR_12/session-state.json" ]; then
  assert_true "B-12 session-state.json 미생성(기존본 미파괴)" 1
else
  assert_true "B-12 session-state.json 미생성(기존본 미파괴)" 0
fi

# --- B-13: J_STOP 2회 연속(디바운스 10s) -> 0,0 / 2회차 로그 dump=skip ---
P13="$(make_fixture_project b13)"
STUB13="$TMPDIR_BASE/stub-b13"; make_stub_bathos "$STUB13" "PASS"
RES1="$(BATHOS_BIN="$STUB13/bathos" run_hook "$HOOKS_DIR/stop-save.sh" "$(json_stop "$P13")")"
EC1="$(get_exit "$RES1")"
RES2="$(BATHOS_BIN="$STUB13/bathos" run_hook "$HOOKS_DIR/stop-save.sh" "$(json_stop "$P13")")"
EC2="$(get_exit "$RES2")"
assert_exit "B-13 1회차 -> exit 0" 0 "$EC1"
assert_exit "B-13 2회차(디바운스 내) -> exit 0" 0 "$EC2"
STATE_DIR_13="$P13/.agent-team/_state"
LAST_LINE="$(tail -1 "$STATE_DIR_13/codex-stop-save.log" 2>/dev/null)"
if printf '%s' "$LAST_LINE" | grep -q 'dump=skip'; then
  assert_true "B-13 2회차 로그 dump=skip" 1
else
  assert_true "B-13 2회차 로그 dump=skip (실제: $LAST_LINE)" 0
fi

# --- B-14: J_STOP_ACTIVE -> exit 0, 아무 파일도 변경 없음(루프 가드) ---
P14="$(make_fixture_project b14)"
STUB14="$TMPDIR_BASE/stub-b14"; make_stub_bathos "$STUB14" "PASS"
STATE_DIR_14="$P14/.agent-team/_state"
BEFORE_LISTING="$(ls -la "$STATE_DIR_14" 2>/dev/null)"
STDOUT_B14="$(printf '%s' "$(json_stop_active "$P14")" | BATHOS_BIN="$STUB14/bathos" bash "$HOOKS_DIR/stop-save.sh")"
EC=$?
AFTER_LISTING="$(ls -la "$STATE_DIR_14" 2>/dev/null)"
assert_exit "B-14 stop_hook_active=true -> exit 0" 0 "$EC"
if [ -z "$STDOUT_B14" ]; then
  assert_true "B-14 stdout 무출력(0바이트) 봉인" 1
else
  assert_true "B-14 stdout 무출력(0바이트) 봉인" 0
fi
if [ "$BEFORE_LISTING" = "$AFTER_LISTING" ]; then
  assert_true "B-14 아무 파일도 변경 없음(루프 가드)" 1
else
  assert_true "B-14 아무 파일도 변경 없음(루프 가드)" 0
fi

# ==========================================================================
# C-1 ~ C-4: session-start.sh (story-14, CT-HOOK-SESSIONSTART)
# ==========================================================================
printf '\n=== session-start.sh (C-1 ~ C-4) ===\n'

# --- C-1: resume + 스냅샷 존재(make_fixture_project 기본 seed) -> exit 0, 안내 주입 ---
PC1="$(make_fixture_project c1)"
RC1_OUT="$(printf '%s' "$(json_session_start_resume "$PC1")" | bash "$HOOKS_DIR/session-start.sh")"
EC=$?
assert_exit "C-1 resume+스냅샷 존재 -> exit 0" 0 "$EC"
if printf '%s' "$RC1_OUT" | grep -q '\[bathos\] 이전 세션 저장분 있음' && printf '%s' "$RC1_OUT" | grep -q 'cold-start'; then
  assert_true "C-1 stdout에 저장분 안내 + \$cold-start 언급 포함" 1
else
  assert_true "C-1 stdout에 저장분 안내 + \$cold-start 언급 포함(실제: $RC1_OUT)" 0
fi

# --- C-2: resume + 스냅샷 부재 -> exit 0, 무주입(빈 stdout) ---
PC2="$TMPDIR_BASE/proj-c2"
mkdir -p "$PC2/.agent-team/_state"
RC2_OUT="$(printf '%s' "$(json_session_start_resume "$PC2")" | bash "$HOOKS_DIR/session-start.sh")"
EC=$?
assert_exit "C-2 resume+스냅샷 부재 -> exit 0" 0 "$EC"
if [ -z "$RC2_OUT" ]; then
  assert_true "C-2 stdout 무주입(스냅샷 부재)" 1
else
  assert_true "C-2 stdout 무주입(스냅샷 부재, 실제: $RC2_OUT)" 0
fi

# --- C-3: _state 없는 cwd(비-BATHOS 프로젝트) -> exit 0, 무주입 ---
PC3="$TMPDIR_BASE/proj-c3-no-state"
mkdir -p "$PC3"
RC3_OUT="$(printf '%s' "$(json_session_start_resume "$PC3")" | bash "$HOOKS_DIR/session-start.sh")"
EC=$?
assert_exit "C-3 비-BATHOS cwd -> exit 0" 0 "$EC"
if [ -z "$RC3_OUT" ]; then
  assert_true "C-3 stdout 무주입(비-BATHOS 프로젝트)" 1
else
  assert_true "C-3 stdout 무주입(비-BATHOS 프로젝트, 실제: $RC3_OUT)" 0
fi

# --- C-4: source=clear + 스냅샷 존재 -> exit 0, 무주입(clear/compact는 안내 대상 아님) ---
PC4="$(make_fixture_project c4)"
RC4_OUT="$(printf '%s' "$(json_session_start_clear "$PC4")" | bash "$HOOKS_DIR/session-start.sh")"
EC=$?
assert_exit "C-4 source=clear -> exit 0" 0 "$EC"
if [ -z "$RC4_OUT" ]; then
  assert_true "C-4 stdout 무주입(source=clear)" 1
else
  assert_true "C-4 stdout 무주입(source=clear, 실제: $RC4_OUT)" 0
fi

# ==========================================================================
# D-1 ~ D-5: careful-guard-codex.sh · freeze-guard-codex.sh (story-15, CT-SAFETY)
# 차단 2종(rm -rf·소유 밖 apply_patch) + 통과 3종(정상 명령·비활성·비-BATHOS)
# ==========================================================================
printf '\n=== careful-guard-codex.sh · freeze-guard-codex.sh (D-1 ~ D-5) ===\n'

# --- D-1(차단): careful — rm -rf -> exit 2 ---
PD1="$(make_fixture_project d1)"
RES="$(run_hook "$HOOKS_DIR/careful-guard-codex.sh" "$(json_careful_rm_rf "$PD1")")"
EC="$(get_exit "$RES")"; ERR="$(get_stderr "$RES")"
assert_exit "D-1 careful: rm -rf -> 차단(exit 2)" 2 "$EC"
if printf '%s' "$ERR" | grep -q 'BLOCKED'; then
  assert_true "D-1 stderr에 BLOCKED 포함" 1
else
  assert_true "D-1 stderr에 BLOCKED 포함" 0
fi

# --- D-2(차단): freeze — BATHOS_OWNED_PATHS="src/**" 활성 상태에서 소유 밖 apply_patch -> exit 2 ---
PD2="$(make_fixture_project d2)"
RES="$(BATHOS_OWNED_PATHS="src/**" run_hook "$HOOKS_DIR/freeze-guard-codex.sh" "$(json_freeze_apply_patch_path "$PD2" "outside/secret.txt")")"
EC="$(get_exit "$RES")"; ERR="$(get_stderr "$RES")"
assert_exit "D-2 freeze: 소유 밖 apply_patch -> 차단(exit 2)" 2 "$EC"
if printf '%s' "$ERR" | grep -q 'BLOCKED'; then
  assert_true "D-2 stderr에 BLOCKED 포함" 1
else
  assert_true "D-2 stderr에 BLOCKED 포함" 0
fi

# --- D-3(통과): careful — 정상 명령(ls -la) -> exit 0 ---
PD3="$(make_fixture_project d3)"
RES="$(run_hook "$HOOKS_DIR/careful-guard-codex.sh" "$(json_careful_benign "$PD3")")"
EC="$(get_exit "$RES")"
assert_exit "D-3 careful: 정상 명령 -> 통과(exit 0)" 0 "$EC"

# --- D-4(통과): freeze — BATHOS_OWNED_PATHS 미설정(비활성) -> 소유 밖이어도 통과 ---
PD4="$(make_fixture_project d4)"
RES="$(run_hook "$HOOKS_DIR/freeze-guard-codex.sh" "$(json_freeze_apply_patch_path "$PD4" "outside/secret.txt")")"
EC="$(get_exit "$RES")"
assert_exit "D-4 freeze: BATHOS_OWNED_PATHS 미설정(비활성) -> 통과(exit 0)" 0 "$EC"

# --- D-5(통과): 비-BATHOS cwd(_state 없음) -> 둘 다 통과(exit 0), rm -rf여도 ---
D5_NO_STATE="$TMPDIR_BASE/proj-d5-no-state"
mkdir -p "$D5_NO_STATE"
RES="$(run_hook "$HOOKS_DIR/careful-guard-codex.sh" "$(json_careful_rm_rf "$D5_NO_STATE")")"
EC="$(get_exit "$RES")"
assert_exit "D-5a 비-BATHOS cwd(careful, rm -rf여도) -> 통과(exit 0)" 0 "$EC"
RES="$(BATHOS_OWNED_PATHS="src/**" run_hook "$HOOKS_DIR/freeze-guard-codex.sh" "$(json_freeze_apply_patch_path "$D5_NO_STATE" "outside/secret.txt")")"
EC="$(get_exit "$RES")"
assert_exit "D-5b 비-BATHOS cwd(freeze, 소유 밖이어도) -> 통과(exit 0)" 0 "$EC"

# --- 소유 경로 내부는 정상 통과(회귀 확인 — freeze가 owned 경로까지 오차단하지 않음) ---
PD6="$(make_fixture_project d6)"
RES="$(BATHOS_OWNED_PATHS="src/**" run_hook "$HOOKS_DIR/freeze-guard-codex.sh" "$(json_freeze_apply_patch_path "$PD6" "src/main.rs")")"
EC="$(get_exit "$RES")"
assert_exit "D-6 freeze: 소유 경로 내부 apply_patch -> 통과(exit 0, 오차단 0 확인)" 0 "$EC"

# ==========================================================================
# matcher 정본 바이트단위 일치 검증 (story-02 AC#5 + story-15 AC#8 최종 봉인)
# ==========================================================================
# matcher 드리프트로 게이트가 fail-open된 전례가 3회다(P4/P5/P5.1). 수기로
# 같은 문자열을 여러 파일에 복제하는 4개 지점(config.toml.example ·
# .codex/hooks.json · careful-guard-codex.sh · freeze-guard-codex.sh 헤더 주석)
# 마다 assertion 없이는 4차 재발을 못 막는다 — 이 절이 그 자동 검증이다
# (불일치 1건 = FAIL, story-15 AC#8 — 훅 체인 마지막에서 4점 전부 대조).
printf '\n=== matcher 정본 바이트단위 일치 검증 (story-02 AC#5 + story-15 AC#8) ===\n'
CONFIG_TOML="$SCRIPT_DIR/../config.toml.example"
HOOKS_JSON="$SCRIPT_DIR/../../.codex/hooks.json"
CAREFUL_SH="$SCRIPT_DIR/careful-guard-codex.sh"
FREEZE_SH="$SCRIPT_DIR/freeze-guard-codex.sh"
MATCHER_TOML="$(grep -m1 '^matcher = ' "$CONFIG_TOML" | sed -E 's/^matcher = "(.*)"$/\1/')"
MATCHER_JSON="$(grep -m1 '"matcher"' "$HOOKS_JSON" | sed -E 's/.*"matcher"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')"
MATCHER_CAREFUL="$(grep -m1 '^#   \^(' "$CAREFUL_SH" | sed -E 's/^#[[:space:]]*//')"
MATCHER_FREEZE="$(grep -m1 '^#   \^(' "$FREEZE_SH" | sed -E 's/^#[[:space:]]*//')"
if [ -n "$MATCHER_TOML" ] \
  && [ "$MATCHER_TOML" = "$MATCHER_JSON" ] \
  && [ "$MATCHER_TOML" = "$MATCHER_CAREFUL" ] \
  && [ "$MATCHER_TOML" = "$MATCHER_FREEZE" ]; then
  assert_true "matcher 정본 4점 일치: toml/hooks.json/careful/freeze ($MATCHER_TOML)" 1
else
  assert_true "matcher 정본 불일치! toml='$MATCHER_TOML' json='$MATCHER_JSON' careful='$MATCHER_CAREFUL' freeze='$MATCHER_FREEZE'" 0
fi

# ==========================================================================
# bash↔Rust 교차 검증 (story-13 AC#4, D-RT5) — 동일 5행 픽스처에 대해
# `bathos_detect_host`(bash, dist/lib/host-detect.sh)와 `bathos runtime`
# (Rust, bathos-state::runtime_host::detect)가 같은 판정을 내는지 확인한다.
# 한쪽 진리표만 고치면 이 절이 red가 된다 — 그것이 목적이다.
# ==========================================================================
printf '\n=== bash<->Rust 교차 검증: bathos_detect_host vs bathos runtime (story-13 AC#4) ===\n'
HOST_DETECT_SH="$SCRIPT_DIR/../../dist/lib/host-detect.sh"
BATHOS_BIN_REAL=""
for cand in "$SCRIPT_DIR/../../core/target/release/bathos" "$SCRIPT_DIR/../../core/target/debug/bathos"; do
  if [ -x "$cand" ]; then BATHOS_BIN_REAL="$cand"; break; fi
done

if [ -z "$BATHOS_BIN_REAL" ]; then
  printf "${YELLOW}[SKIP]${NC} bash<->Rust 교차 검증 5행 — bathos 릴리스/디버그 바이너리 없음(cargo build 먼저 필요, PASS/FAIL 카운트에 반영 안 함)\n"
else
  # cross_check_row <설명> [KEY=VALUE ...] — env -i로 완전 격리한 뒤 주어진
  # 키만 주입해 양쪽 구현을 같은 조건에서 호출한다("이 키가 켜져 있는가"만
  # 보는 판정이므로 격리가 곧 정확한 재현이다). Rust 쪽은 텍스트 출력(1단어),
  # bash 쪽은 함수 반환값을 그대로 비교한다.
  cross_check_row() {
    local desc="$1"; shift
    local rust_out bash_out
    rust_out="$(env -i "$@" "$BATHOS_BIN_REAL" runtime 2>/dev/null)"
    bash_out="$(env -i "$@" "$BASH_BIN" -c "source '$HOST_DETECT_SH'; bathos_detect_host" 2>/dev/null)"
    if [ "$rust_out" = "$bash_out" ]; then
      assert_true "교차검증[$desc]: bathos runtime == bathos_detect_host ($rust_out)" 1
    else
      assert_true "교차검증[$desc]: 불일치! rust=$rust_out bash=$bash_out" 0
    fi
  }

  cross_check_row "forced"               BATHOS_FORCE_HOST=codex
  cross_check_row "codex"                PLUGIN_ROOT=/some/plugin
  cross_check_row "claude-hook"          CLAUDE_PROJECT_DIR=/some/project
  cross_check_row "claude-plugin-legacy" CLAUDE_PLUGIN_ROOT=/some/plugin
  cross_check_row "none"
fi

# ==========================================================================
# 요약
# ==========================================================================
printf '\n=== 요약 ===\n'
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'PASS %d/%d\n' "$PASS_COUNT" "$TOTAL"
if [ "$FAIL_COUNT" -gt 0 ]; then
  printf "${RED}FAIL 있음: %d건${NC}\n" "$FAIL_COUNT"
  exit 1
fi
printf "${GREEN}전체 통과${NC}\n"
exit 0
