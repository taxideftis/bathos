#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# BATHOS  scripts/build-codex-plugin.sh  —  dist/codex-plugin/ 정식 플러그인 번들 조립(story-17)
#
# 무엇을·왜: `codex plugin marketplace add` 1줄 설치 경로(F1-b)의 내용물을 조립한다. 이 스크립트가
# 만드는 파일은 전부 **복사 생성물**이다 — 정본은 `.agents/skills/**`(skills 정본, to-codex.sh 산출 +
# story-10 수기)과 `.codex/hooks.json`(Phillip 소유, CT-WIRE-HOOKS 배선 정본)이며, 이 스크립트는 그것을
# CT-PLUGIN 레이아웃(adapter-contracts.md §9)으로 재배치할 뿐 새 내용을 만들지 않는다(이중 정본화 금지).
#
# plugin.json은 이 스크립트가 직접 쓰는 유일한 "신규 내용"이다 — 구 스켈레톤(dist/manifests/codex/
# plugin.json)이 3중 불일치로 FAIL 판정을 받은 반면교사(codex-mechanisms.md §4.3: `.codex-plugin/` 규약
# 미준수·`sources`/`capability_tier` 비실재 필드·상대 포인터 방식 상이)를 반복하지 않도록, CT-PLUGIN
# manifest_schema의 필수 3필드(name/version/description)와 근거 있는 선택 필드만 쓴다.
#
# 사용:
#   bash scripts/build-codex-plugin.sh            # 조립(멱등 — 재실행 시 diff 0)
#
# 전제: `.agents/skills/**`(scripts/to-codex.sh --write 로 최신화됨) · `.codex/hooks.json`(Phillip 산출,
# 없으면 스킵하고 경고만 — fail-safe, 이 스크립트가 Phillip 소유 파일을 만들지 않는다).
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "$SCRIPT_DIR/.." && pwd)"

SRC_SKILLS="$PROJ/.agents/skills"
SRC_HOOKS="$PROJ/.codex/hooks.json"
SRC_HOOK_SCRIPTS="$PROJ/codex-adapter/hooks"
DST="$PROJ/dist/codex-plugin"

say(){ printf '%s\n' "$*"; }

[ -d "$SRC_SKILLS" ] || { echo "오류: $SRC_SKILLS 없음 — 먼저 'bash scripts/to-codex.sh --write' 실행" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1) 기존 번들 비우고 재조립(멱등 — 이전 실행의 잔여 파일이 남지 않도록 항상 클린 리빌드)
# ---------------------------------------------------------------------------
rm -rf "$DST"
mkdir -p "$DST/.codex-plugin" "$DST/skills" "$DST/hooks"

# ---------------------------------------------------------------------------
# 2) plugin.json — CT-PLUGIN manifest_schema(필수 3필드 + 근거 있는 선택 필드만)
#
# story-20 라이브 검증(SS18 실측)에서 "skills"/"hooks" 컴포넌트 포인터 누락 시
# `codex plugin marketplace add` 등록은 성공해도 `codex plugin list`에 노출되지 않음이
# 확인됨 — adapter-contracts.md §9 manifest_schema의 optional 필드(skills/hooks)를
# 명시 포인터로 채운다(레퍼런스: Codex 내장 visualize 플러그인의 "skills": "./skills/").
# ---------------------------------------------------------------------------
# version 은 dist/VERSION(축 B 배포 레이어의 단일 버전 핀)에서 읽는다.
# 이전에는 여기에 "0.1.0" 이 하드코딩돼 있어, dist/VERSION 이 0.2.0 으로 올라간 뒤에도
# 빌드마다 낡은 값을 다시 써 넣었다 — check-versions.sh 가 이를 잡아내지만 그 검사가
# drift-guard 안에 있었고 워크플로가 파싱 오류로 죽어 있어(#32) 드리프트가 가려졌다(#33).
# JSON 만 손으로 고치면 다음 빌드에서 되돌아가므로 생성기 쪽을 고친다(근본 원인).
_PLUGIN_VERSION="$(tr -d '[:space:]' < "$PROJ/dist/VERSION" 2>/dev/null || true)"
if [[ -z "$_PLUGIN_VERSION" ]]; then
  printf '[build-codex-plugin] ✗ dist/VERSION 을 읽을 수 없습니다 — 버전 핀 없이 번들을 만들지 않습니다.\n' >&2
  exit 1
fi

cat > "$DST/.codex-plugin/plugin.json" <<JSONEOF
{
  "name": "bathos",
  "version": "$_PLUGIN_VERSION",
  "description": "BATHOS — 17역할 7웨이브 AI Workflow Agent 메서드 패키지 (Codex CLI 네이티브 플러그인: skills + hooks)",
  "author": {
    "name": "BATHOS project"
  },
  "keywords": ["orchestration", "multi-agent", "workflow", "bathos"],
  "skills": "./skills/",
  "hooks": "./hooks/hooks.json"
}
JSONEOF
say "[plugin.json] $DST/.codex-plugin/plugin.json"

# ---------------------------------------------------------------------------
# 3) skills 번들 — .agents/skills/** 전량 복사(generated 15 + hand-authored 15 = 30, 발견 경로만
#    다를 뿐 내용은 정본과 동일 — story-17 Dev Notes "이중 정본화 금지").
# ---------------------------------------------------------------------------
nskill=0
for d in "$SRC_SKILLS"/*/; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"
  mkdir -p "$DST/skills/$name"
  cp -R "$d." "$DST/skills/$name/"
  nskill=$((nskill+1))
done
say "[skills] $nskill 개 → $DST/skills/**"

# ---------------------------------------------------------------------------
# 4) hooks 번들 — story-20 라이브 127 결함(SS18 3차) 수정.
#
# 무엇이 문제였나: .codex/hooks.json(Phillip 소유, repo-스코프)은 command를
# 상대경로 `codex-adapter/hooks/*.sh`로 참조한다 — repo-스코프 배선은 cwd가
# 항상 repo 루트라 문제없지만, 이 값을 **그대로 복사**해 플러그인에 실었던
# 구버전은 설치 후 cwd가 사용자 프로젝트(플러그인 설치 위치가 아님)가 되므로
# `codex-adapter/hooks/*.sh`가 어디서도 발견되지 않아 전 훅이 exit 127이었다
# (라이브 실측: `~/.codex/plugins/cache/.../bathos/0.1.0/`엔 codex-adapter/가
# 아예 없음 — story-20 SS18).
#
# 고친 방법: (a) 훅 스크립트 5종 실물을 hooks.json과 같은 디렉터리로 번들해
# 상대경로 문제 자체를 없애고, (b) command를 플러그인 설치 루트 기준 절대
# 참조로 재작성한다. 정책(matcher/timeout/이벤트 순서)은 여전히 Phillip의
# SSOT(.codex/hooks.json)에서 그대로 읽어온다 — 여기서 바꾸는 값은 command의
# 경로 표현 하나뿐(이중 정본화 금지 유지, script §머리말 참고).
#
# 절대 참조 방식(⚠️ 라이브 미확정 — 근거 있는 최선안): Caleb 조사
# (02-market-analysis/codex-mechanisms.md §4.1, 2026-07-23 공식 문서 확인)에
# 따르면 Codex는 훅 프로세스에 **환경변수** `PLUGIN_ROOT`(+ 레거시 호환
# `CLAUDE_PLUGIN_ROOT`)를 주입한다. 이 값이 command 문자열 안에서 자동
# 치환(셸 경유 실행)되는지는 미확정이므로, 그 가정에 기대지 않고 우리가 직접
# `/bin/bash -c '...'`로 감싸 **bash 자신의 환경변수 치환**을 쓴다 — 이렇게
# 하면 바깥 실행기가 이 command를 셸로 돌리든 execve로 바로 돌리든(따옴표만
# 보존하면) 안쪽 `${PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}`는 항상 bash -c 시점에
# 그 프로세스의 실제 환경변수로 치환된다 — 바깥 실행 방식에 대한 가정이 필요
# 없다. 이 가정이 틀렸다면(env var 이름이 다르거나 문서와 실제가 다르면)
# 사용자 라이브 재테스트로 드러나며, 그 경우 probe.sh류 실측으로 이름을
# 확정한 뒤 이 스크립트만 고치면 된다(스크립트 본체는 무수정).
# ---------------------------------------------------------------------------
if [ -f "$SRC_HOOKS" ]; then
  nhook=0
  for h in "$SRC_HOOK_SCRIPTS"/*.sh; do
    [ -f "$h" ] || continue
    base="$(basename "$h")"
    case "$base" in
      _test-*) continue ;;  # 테스트 스크립트는 배포 자산이 아님(codex-adapter 내부 전용)
    esac
    cp -p "$h" "$DST/hooks/$base"
    chmod +x "$DST/hooks/$base"
    nhook=$((nhook+1))
  done
  say "[hooks/*.sh] $nhook 개 → $DST/hooks/**(실행권한 유지)"

  # hooks.json은 구조적으로 읽어 command 필드만 재작성(python3 — 이 파일의
  # plugin.json 검증에도 이미 쓰는 도구, jq 비의존 원칙과 무관하게 이 스크립트는
  # 빌드타임 전용이라 python3 사용이 무해함). matcher/timeout/이벤트 순서는
  # SRC_HOOKS 그대로 보존된다.
  python3 - "$SRC_HOOKS" "$DST/hooks/hooks.json" <<'PYEOF'
import json, re, sys

src, dst = sys.argv[1], sys.argv[2]
with open(src, encoding="utf-8") as f:
    data = json.load(f)

pat = re.compile(r"codex-adapter/hooks/([\w.-]+\.sh)")
n = 0
for entries in data.get("hooks", {}).values():
    for entry in entries:
        for hook in entry.get("hooks", []):
            m = pat.search(hook.get("command", ""))
            if not m:
                continue
            name = m.group(1)
            hook["command"] = (
                "/bin/bash -c '/bin/bash \"${PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}/hooks/%s\"'" % name
            )
            n += 1

with open(dst, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
print(f"[hooks.json] command {n} 건 재작성(PLUGIN_ROOT 절대 참조)")
PYEOF
  say "[hooks.json] $SRC_HOOKS → $DST/hooks/hooks.json (command 재작성)"
else
  say "[hooks] 경고: $SRC_HOOKS 없음 — hooks 번들 생략(Phillip SS2 완료 후 재실행하면 채워짐, fail-safe)"
fi

say ""
say "요약: 플러그인 번들 조립 완료 → $DST"
say "검증: python3 -c \"import json; json.load(open('$DST/.codex-plugin/plugin.json'))\""
