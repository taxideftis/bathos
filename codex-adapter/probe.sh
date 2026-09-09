#!/usr/bin/env bash
# =============================================================================
# BATHOS  codex-adapter/probe.sh  —  Codex 버전 드리프트 1분 재실측 소품 (CT-PROBE)
#
# 게이트 fail-open 3연(P4/P5/P5.1)의 공통 원인은 "문서 가정"이었다. probe는
# 그 반대 — 실측을 제품에 내장한다. Codex CLI를 업그레이드할 때마다 이 스크립트
# 1회 실행으로 D1(훅 스키마 평탄/중첩 병존)·hooks.json JSON 스키마·R-RT1(훅
# 컨텍스트 env 주입)이 여전히 유효한지 재현 가능하게 재검증한다.
#
# 설계 원본: .agent-team/04-architecture/adapter-contracts.md §6 (CT-PROBE)
#
# 타겟 버전(2026-07-23, 리드 결정): v0.144.5 → v0.145.0+(2026-07-21 stable)로
# 이동 — 이 스크립트가 정확히 이 상황(버전 드리프트)을 위한 소품이다. 버전
# 문자열을 하드코딩하지 않는다: `codex --version` 실측값을 그대로 사용해
# 파일명(`PROBE-RESULTS-<실측버전>.md`)을 짓는다(2026-07-23 이 저장소 실행
# 환경 실측: codex-cli 0.145.0 — 정적 항목 ①·⑤ 일부는 이미 이 버전으로 확인됨,
# 라이브 1턴 필요 항목은 여전히 미실측).
#
# 무엇을 하는가(5항목, 순서대로 리포트에 기록):
#   ① codex --version + codex features list(hooks stable 여부)
#   ② 평탄형/중첩형 에코 훅 등록 안내 — 라이브 1턴은 사람이 수행(자동화 불가,
#      아래 "라이브 1턴이 필요한 판정" 참고). 이 스크립트는 준비·수거·판정만.
#   ③ 관측 tool_name 목록 vs 광폭 matcher(story-01, 6종) 커버리지 대조
#   ④ 훅 컨텍스트 env 중 PLUGIN*/CLAUDE_* "키 존재 여부"만(값은 절대 기록하지
#      않는다 — R-RT1 해소, 보안 설계)
#   ⑤ .codex/hooks.json 단독 발화 여부·trust 절차 기록(수동 관찰 항목)
#
# 무엇을 하지 않는가: `~/.codex/config.toml`을 자동으로 편집하지 않는다(홈
# 디렉터리 쓰기는 사용자 승인 사안 — E-CODEX-TOML-ABSENT와 동일 철학). 에코
# 훅 등록은 임시 프로젝트 디렉터리(§2)에서만 안내한다.
#
# 실측 없는 값은 리포트에 절대 기입하지 않는다(날조 금지) — 라이브 1턴이
# 필요한 항목(②·⑤)은 인증 세션이 없으면 `[미실측 — 인증 세션 필요]`로 정직
# 기록한다. 리포트가 곧 실측 정본이므로 오염되면 CT-PROBE 체제 전체가 무너진다.
#
# 실행: bash codex-adapter/probe.sh
# 출력: codex-adapter/PROBE-RESULTS-<codex_version>.md (codex 부재 시 -unknown)
#
# 이식성: bash 3.2 호환. jq 금지는 아니나(개발 도구라 §C0의 엄격 적용 대상은
# 아니다) 이식성을 위해 grep/sed만 사용한다.
# =============================================================================
set -uo pipefail

PROG="probe.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

say()  { printf '[%s] %s\n' "$PROG" "$*"; }
warn() { printf '[%s] ⚠ %s\n' "$PROG" "$*" >&2; }

# --------------------------------------------------------------------------
# 0. codex CLI 탐지 — 부재는 오류가 아니라 정직한 리포트 대상이다(AC#... 비-Codex
#    환경에서 스택트레이스 없이 명확한 안내로 정상 종료해야 한다).
# --------------------------------------------------------------------------
CODEX_BIN="${CODEX_BIN:-}"
if [ -z "$CODEX_BIN" ] && command -v codex >/dev/null 2>&1; then
  CODEX_BIN="$(command -v codex)"
fi

CODEX_VERSION="unknown"
CODEX_FEATURES_OUT="[미실측 — codex CLI 없음]"
if [ -n "$CODEX_BIN" ]; then
  RAW_VERSION="$("$CODEX_BIN" --version 2>/dev/null || true)"
  if [ -n "$RAW_VERSION" ]; then
    # 흔한 형식 "codex-cli 0.145.0"·"codex 0.145.0" 등에서 버전 토큰만 추출.
    # 실패해도 안전측(원문을 그대로 보존)으로 폴백한다.
    PARSED="$(printf '%s' "$RAW_VERSION" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    CODEX_VERSION="${PARSED:-$(printf '%s' "$RAW_VERSION" | tr -d '\n' | tr ' /' '--')}"
  fi
  CODEX_FEATURES_OUT="$("$CODEX_BIN" features list 2>&1 || true)"
  [ -z "$CODEX_FEATURES_OUT" ] && CODEX_FEATURES_OUT="[미실측 — 'codex features list' 출력 없음]"
fi

REPORT="$SCRIPT_DIR/PROBE-RESULTS-${CODEX_VERSION}.md"

# --------------------------------------------------------------------------
# 1. 관측 tool_name vs matcher 커버리지 대조 (③) — 함수 분리(픽스처 입력으로
#    단위 테스트 가능하게, testing_requirements 요구사항).
# --------------------------------------------------------------------------
# story-01 정본 6종(config.toml.example의 matcher와 바이트 단위 동일해야 함 —
# _test-codex-hooks.sh의 별도 assertion이 그 동일성을 감시한다. 여기서는 이미
# 확정된 정본 목록만 정적으로 인용한다, 날조 금지).
MATCHER_TOOL_NAMES="Bash shell exec_command apply_patch Edit Write"

# check_tool_name_coverage <observed_name> -> "covered" | "drift"
check_tool_name_coverage() {
  local observed="$1" name
  for name in $MATCHER_TOOL_NAMES; do
    [ "$name" = "$observed" ] && { printf 'covered'; return 0; }
  done
  printf 'drift'
}

# --------------------------------------------------------------------------
# 2. 에코 훅 페어 준비 (②) — 임시 프로젝트에만 등록 안내, 홈 config 자동 편집 금지.
# --------------------------------------------------------------------------
ECHO_HOOK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bathos-probe-echo.XXXXXX" 2>/dev/null || mktemp -d)"
cat > "$ECHO_HOOK_DIR/echo-flat.sh" <<'EOF'
#!/usr/bin/env bash
# probe.sh 에코 훅(평탄형 스키마 실측용) — stdin 원문 + PLUGIN*/CLAUDE_* 키
# 이름만(값 제외) stderr에 찍고 exit 0으로 통과한다. 사람이 라이브 1턴에서
# 이 훅을 등록해 실제로 발화하는지 관찰한다(자동화 불가 — 인증 세션 필요).
cat >&2
printf 'env-keys: ' >&2
env | grep -E '^(PLUGIN|CLAUDE_)' | sed -E 's/=.*$//' | tr '\n' ' ' >&2
printf '\n' >&2
exit 0
EOF
cp "$ECHO_HOOK_DIR/echo-flat.sh" "$ECHO_HOOK_DIR/echo-nested.sh"
chmod +x "$ECHO_HOOK_DIR"/*.sh

# --------------------------------------------------------------------------
# 3. 훅 컨텍스트 env 키 존재 여부 (④) — 이 프로세스 자체의 env를 스캔한다.
#    probe.sh를 직접 셸에서 실행하면 훅 컨텍스트가 아니므로 대개 비어 있는
#    것이 정상이다(runtime-abstraction-design.md §4 "감지의 유효 컨텍스트").
#    값은 기록하지 않는다 — 키 이름만.
# --------------------------------------------------------------------------
OBSERVED_ENV_KEYS="$(env | grep -E '^(PLUGIN|CLAUDE_)' | sed -E 's/=.*$//' | sort | tr '\n' ' ')"
[ -z "$OBSERVED_ENV_KEYS" ] && OBSERVED_ENV_KEYS="(없음 — 이 실행은 훅 컨텍스트 밖. 정상 — 훅 등록 후 echo-flat.sh/echo-nested.sh 출력을 참고)"

# --------------------------------------------------------------------------
# 4. .codex/hooks.json 존재·JSON 파스 확인 (⑤ 일부 — 발화 자체는 라이브 필요)
# --------------------------------------------------------------------------
HOOKS_JSON="$REPO_ROOT/.codex/hooks.json"
HOOKS_JSON_STATUS="[미실측 — .codex/hooks.json 없음]"
if [ -f "$HOOKS_JSON" ]; then
  if command -v python3 >/dev/null 2>&1; then
    if python3 -m json.tool < "$HOOKS_JSON" >/dev/null 2>&1; then
      HOOKS_JSON_STATUS="존재·유효 JSON"
    else
      HOOKS_JSON_STATUS="존재하나 JSON 파싱 실패(E-PLUGIN-MANIFEST-INVALID류 — 확인 필요)"
    fi
  else
    HOOKS_JSON_STATUS="존재(python3 없어 파싱 검증 생략)"
  fi
fi

# --------------------------------------------------------------------------
# 5. E-CODEX-SCHEMA-DRIFT 판정 — 이 실행만으로는 실제 발화 tool_name을 수집할
#    수 없으므로(라이브 1턴 필요) 정적 판정은 "확인 불가"로 정직 기록한다.
#    라이브 실측(story-20) 시 사람이 관찰한 tool_name을 이 스크립트의
#    check_tool_name_coverage에 통과시켜 리포트를 갱신하는 절차로 이어진다.
# --------------------------------------------------------------------------
DRIFT_LINE="[미실측 — 라이브 1턴에서 관측된 tool_name을 check_tool_name_coverage로 대조 필요]"

# --------------------------------------------------------------------------
# 리포트 작성
# --------------------------------------------------------------------------
{
  printf '# PROBE-RESULTS — Codex CLI %s\n\n' "$CODEX_VERSION"
  printf '> 생성: %s · %s (CT-PROBE, story-03)\n' "$(date '+%Y-%m-%d %H:%M:%S %z' 2>/dev/null || echo unknown)" "$PROG"
  printf '> 이 리포트는 재현 가능한 실측 기록이다 — 미실측 항목은 날조하지 않고 정직 표기한다.\n\n'

  printf '## ① codex --version / features list\n\n'
  if [ -n "$CODEX_BIN" ]; then
    printf -- '- codex 바이너리: `%s`\n' "$CODEX_BIN"
    printf -- '- --version 원문: `%s`\n' "$RAW_VERSION"
  else
    printf -- '- codex CLI를 PATH에서 찾지 못함(비-Codex 환경 — 정상일 수 있음)\n'
  fi
  printf '\n```\n%s\n```\n\n' "$CODEX_FEATURES_OUT"

  printf '## ② 평탄형/중첩형 훅 스키마 라이브 재실측 (D1 종결 절차)\n\n'
  printf '에코 훅 준비 완료: `%s`\n\n' "$ECHO_HOOK_DIR"
  printf '수동 절차(자동화 불가 — 인증 세션 필요, 라이브 1턴 요구):\n'
  printf '1. 임시 프로젝트(또는 이 저장소 사본)에서 평탄형 스키마로 `echo-flat.sh`를,\n'
  printf '   중첩형 스키마로 `echo-nested.sh`를 각각 PreToolUse에 등록한다.\n'
  printf '2. 아무 도구나 1회 호출해 어느 쪽이 stderr에 stdin을 찍는지 관찰한다.\n'
  printf '3. 발화한 쪽의 스키마(평탄형=timeoutSec 낱개 필드 / 중첩형=hooks.<E>.hooks[]+timeout)로\n'
  printf '   방출물(config.toml.example·.codex/hooks.json)을 그 스키마로 고정한다(D1 종결).\n\n'
  printf '결과: [미실측 — 인증 세션 필요]\n\n'

  printf '## ③ 관측 tool_name vs matcher 커버리지\n\n'
  printf -- '- matcher 정본(story-01, 6종): `%s`\n' "$MATCHER_TOOL_NAMES"
  printf -- '- 관측된 tool_name: [미실측 — 라이브 1턴 필요, ②와 동시 수행 권장]\n'
  printf -- '- 판정: %s\n\n' "$DRIFT_LINE"

  printf '## ④ 훅 컨텍스트 env 키 존재 여부 (PLUGIN*/CLAUDE_*, 값 비기록)\n\n'
  printf -- '- 이 실행(비-훅 컨텍스트)에서 관측: `%s`\n' "$OBSERVED_ENV_KEYS"
  printf -- '- R-RT1 해소는 실제 훅 실행 컨텍스트에서 관찰해야 한다 — echo-flat.sh/echo-nested.sh가\n'
  printf '  등록 상태에서 발화할 때 함께 출력하는 `env-keys:` 줄을 여기 옮겨 적을 것.\n\n'

  printf '## ⑤ .codex/hooks.json 단독 발화 · trust 절차\n\n'
  printf -- '- 파일 상태: %s\n' "$HOOKS_JSON_STATUS"
  printf -- '- 발화 여부(유저 config 무편집 상태에서): [미실측 — 인증 세션 필요, US1-AC3]\n'
  printf -- '- trust 프롬프트 절차: [미실측 — 관찰 기록 필요]\n\n'

  printf '## 종합 판정\n\n'
  if [ -z "$CODEX_BIN" ]; then
    printf -- '- codex CLI가 없어 라이브 항목은 전부 미실측이다. 설치 후 재실행할 것.\n'
  else
    printf -- '- 정적 확인 항목(①·hooks.json 파스)은 위 기록대로. 라이브 1턴이 필요한 항목(②·③·④·⑤)은\n'
    printf '  이 스크립트 단독으로 종결되지 않는다 — 인증 세션에서 수동 절차를 따른 뒤 이 파일을\n'
    printf '  직접 갱신하거나 재실행 결과로 대체할 것(리포트가 정본 — 오염 시 CT-PROBE 체제 붕괴).\n'
  fi
} > "$REPORT"

say "리포트 생성: $REPORT"
say "에코 훅 임시 디렉터리(수동 정리 필요, TTL 없음): $ECHO_HOOK_DIR"

exit 0
