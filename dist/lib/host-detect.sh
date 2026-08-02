#!/usr/bin/env bash
# =============================================================================
# BATHOS — dist/lib/host-detect.sh
# CF-B5 / SS9 → story-13(실키 구현) — 런타임 host-detection + 출력분기 단일 모듈.
#
# claude/codex/unknown 축은 실키로 구현됐다(story-13, ADR-CX-01/CT-ENGINE-5의
# bash 판) — copilot 분기는 여전히 스텁이다(LD-2: Claude Code/Codex 외 런타임
# 미타깃, 손대지 않음).
#
# **의도적 이중 구현(D-RT5)**: 이 함수는 `bathos runtime`(Rust,
# `bathos-state::runtime_host::detect`)과 **동일 진리표**를 bash로 구현한다.
# 정본은 하나뿐이다 — `.agent-team/04-architecture/runtime-abstraction-design.md`
# §4. 이 파일은 bathos 바이너리 없이도 동작해야 하는 독립 배포 자산(설치 전
# 진단에도 쓰인다)이라 엔진을 호출하지 않고 진리표를 그대로 재구현한다. 양쪽이
# 갈라지면 조용히 드리프트하므로, 교차 검증 테스트(같은 5행 픽스처를 bash/Rust
# 양쪽에 통과시키는 `_test-codex-hooks.sh`의 테이블 테스트)가 한쪽만 고치는
# 실수를 CI에서 잡는다.
#
# 진리표(순위 상단이 이긴다, 값 존재 여부만 본다 — 값은 로그·출력에 남기지 않음):
#   1. BATHOS_FORCE_HOST(claude|codex|unknown 중 하나만 유효) — 무효값이면
#      경고 후 무시하고 2순위로 진행(W-RUNTIME-FORCE-INVALID).
#   2. PLUGIN_ROOT 또는 PLUGIN_DATA 존재 → codex.
#   3. (copilot, 스코프 밖 — 원 위치 유지) COPILOT_PLUGIN_DATA 존재 → copilot.
#   4. CLAUDE_PROJECT_DIR 존재 → claude.
#   5. CLAUDE_PLUGIN_ROOT/CLAUDE_PLUGIN_DATA만 존재(2의 unprefixed 키 부재 확인
#      후) → claude. Codex가 레거시 호환으로 이 키들도 함께 세팅하므로 2번이
#      먼저 실행돼야 오판정을 피한다.
#   6. 전부 부재 → unknown(과거엔 "기본값 claude"였다 — story-13 AC#1로 갱신.
#      맨 셸에서 직접 실행하면 unknown이 정답이며 버그가 아니다).
#
# 규약(US8 AC2): 호스트 판별·출력분기 로직은 이 모듈 하나에만 존재해야 한다.
# 다른 스크립트(uninstall.sh, check-*.sh 등)에서 동일 로직을 복제하지 않는다
# (복제 시 CF-B5 AC2 위반).
#
# 사용법:
#   source dist/lib/host-detect.sh
#   host="$(bathos_detect_host)"
#   bathos_write_hook_output "$host" '{"decision":"allow"}'
# =============================================================================

# bathos_detect_host — 현재 실행 호스트를 판별해 소문자 문자열로 반환.
#   반환값: "claude" | "codex" | "copilot" | "unknown"
bathos_detect_host() {
  # 1순위: 강제 오버라이드 — 유효값(claude|codex|unknown)만 신뢰한다. 무효값
  # (오타 등)을 그대로 믿으면 오판정을 부르므로 경고 후 실감지로 넘어간다.
  if [[ -n "${BATHOS_FORCE_HOST:-}" ]]; then
    case "$BATHOS_FORCE_HOST" in
      claude|codex|unknown)
        printf '%s\n' "$BATHOS_FORCE_HOST"
        return 0
        ;;
      *)
        printf '[bathos host-detect] ⚠ BATHOS_FORCE_HOST=%s 무효(claude|codex|unknown만 허용) — 무시하고 실감지 진행\n' "$BATHOS_FORCE_HOST" >&2
        ;;
    esac
  fi

  # 2순위: Codex 플러그인/훅 컨텍스트 실키 [문서확정 2026-07-23] — PLUGIN_ROOT
  # 추가, PLUGIN_DATA는 ⚠️추정에서 문서확정으로 승격(story-13).
  if [[ -n "${PLUGIN_ROOT:-}" || -n "${PLUGIN_DATA:-}" ]]; then
    printf 'codex\n'
    return 0
  fi

  # (스코프 밖 — 손대지 않음) copilot: 원래 있던 자리(codex 다음)를 그대로 유지.
  if [[ -n "${COPILOT_PLUGIN_DATA:-}" ]]; then
    printf 'copilot\n'
    return 0
  fi

  # 3순위: Claude Code 훅 컨텍스트 실키 [실측] — .claude/hooks 전 스크립트가 사용.
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    printf 'claude\n'
    return 0
  fi

  # 4순위: CLAUDE_PLUGIN_ROOT/CLAUDE_PLUGIN_DATA만 존재(2순위에서 unprefixed
  # 부재가 이미 확인된 상태) → 레거시 Claude Code 플러그인 컨텍스트.
  if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" || -n "${CLAUDE_PLUGIN_DATA:-}" ]]; then
    printf 'claude\n'
    return 0
  fi

  # 5순위: 전부 부재 → unknown(정직 보고 — 오류 아님).
  printf 'unknown\n'
  return 0
}

# bathos_write_hook_output <host> <json_payload>
#   호스트별 훅 출력 형태로 분기해 stdout에 쓴다.
#   claude/codex/unknown은 같은 형태로 통과시킨다(story-13 §5: "판정은 정직하게
#   unknown을 보고하되, 출력형 선택은 claude-형 기본을 유지" — 이 모듈이
#   실제로 서로 다른 출력 포맷을 구현한 적이 없으므로, "포맷 차이 없음"이
#   현재 사실이다. 별도 codex 포맷이 확정되면(probe.sh 실측 이후) 그때 이
#   분기를 갈라낼 것 — 지금 갈라놓는 것은 "지원하는 척"의 반대 방향 날조다).
#   copilot만 여전히 미구현을 명시적으로 알리고 실패 종료(2) — 조용히 잘못된
#   형태를 출력하지 않는다(날조 금지 원칙 유지).
bathos_write_hook_output() {
  local host="$1"
  local payload="$2"
  case "$host" in
    claude|codex|unknown)
      printf '%s\n' "$payload"
      return 0
      ;;
    copilot)
      printf '[bathos host-detect] ! %s 출력 분기는 미구현(스텁, Could 범위 밖). ' "$host" >&2
      printf '참조: docs/agent-portability-kr.md §2\n' >&2
      return 2
      ;;
    *)
      printf '[bathos host-detect] ✗ 알 수 없는 host: %s\n' "$host" >&2
      return 2
      ;;
  esac
}

# 직접 실행 시(source가 아니라 실행) 자가진단만 수행 — 부작용 없음.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  detected="$(bathos_detect_host)"
  printf '[bathos host-detect] 감지된 host: %s\n' "$detected"
fi
