#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# BATHOS  scripts/build-codex-plugin.sh  —  assembles the dist/codex-plugin/ bundle (story-17)
#
# What and why: assembles the payload behind the one-line `codex plugin marketplace add`
# install path (F1-b). Every file this script produces is a **copy** — the canonical sources
# are `.agents/skills/**` (canonical skills: to-codex.sh output + story-10 hand-authored) and
# `.codex/hooks.json` (owned by Phillip, the canonical CT-WIRE-HOOKS wiring). This script only
# rearranges them into the CT-PLUGIN layout (adapter-contracts.md §9); it creates no new
# content (never a second canonical copy).
#
# plugin.json is the only "new content" this script writes itself. To avoid repeating the old
# skeleton's mistake (dist/manifests/codex/plugin.json was judged FAIL on a three-way mismatch
# — codex-mechanisms.md §4.3: it ignored the `.codex-plugin/` convention, carried the
# non-existent `sources`/`capability_tier` fields, and used a different relative-pointer
# scheme), it writes only manifest_schema's three required fields (name/version/description)
# plus optional fields we have evidence for.
#
# Usage:
#   bash scripts/build-codex-plugin.sh            # assemble (idempotent — a re-run diffs to 0)
#
# Prerequisites: `.agents/skills/**` (kept current by scripts/to-codex.sh --write) and
# `.codex/hooks.json` (Phillip's output; if absent this warns and skips — fail-safe, this
# script never creates a file Phillip owns).
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
# 1) Empty the existing bundle and reassemble (idempotent — always a clean rebuild, so no
#    leftovers from a previous run survive)
# ---------------------------------------------------------------------------
rm -rf "$DST"
mkdir -p "$DST/.codex-plugin" "$DST/skills" "$DST/hooks"

# ---------------------------------------------------------------------------
# 2) plugin.json — CT-PLUGIN manifest_schema (3 required fields + evidence-backed optionals)
#
# story-20's live verification (SS18, measured) confirmed that without the "skills"/"hooks"
# component pointers, `codex plugin marketplace add` registers fine but the plugin never shows
# up in `codex plugin list` — so the optional fields (skills/hooks) of adapter-contracts.md §9
# manifest_schema are filled in with explicit pointers (reference: Codex's built-in visualize
# plugin uses "skills": "./skills/").
# ---------------------------------------------------------------------------
# The version is read from dist/VERSION (the single version pin of the axis-B distribution
# layer). It used to be hardcoded here as "0.1.0", so every build rewrote the stale value even
# after dist/VERSION had moved to 0.2.0 — check-versions.sh catches exactly that, but the check
# lived inside drift-guard and that workflow was dead from a parse error (#32), which masked
# the drift (#33). Fixing only the JSON would regress on the next build, so the generator is
# fixed instead (the root cause).
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
# 3) skills bundle — copies all of .agents/skills/** (generated 15 + hand-authored 15 = 30;
#    only the discovery path differs, the content is identical to the canonical files —
#    story-17 Dev Notes, "never a second canonical copy").
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
# 4) hooks bundle — fixes story-20's live exit-127 defect (SS18, third round).
#
# What was wrong: .codex/hooks.json (owned by Phillip, repo-scoped) references its commands by
# the relative path `codex-adapter/hooks/*.sh`. For repo-scoped wiring that is fine, since cwd
# is always the repo root — but the older version that shipped those values into the plugin
# **verbatim** broke after installation, because cwd is then the user's project (not the
# plugin's install location), so `codex-adapter/hooks/*.sh` was nowhere to be found and every
# hook exited 127 (measured live: `~/.codex/plugins/cache/.../bathos/0.1.0/` contains no
# codex-adapter/ at all — story-20 SS18).
#
# How it was fixed: (a) bundle the five hook scripts themselves into the same directory as
# hooks.json, removing the relative-path problem entirely, and (b) rewrite each command as an
# absolute reference based on the plugin install root. The policy (matcher/timeout/event order)
# is still read straight from Phillip's SSOT (.codex/hooks.json) — the only value changed here
# is the path expression inside command (still no second canonical copy; see the header).
#
# The absolute-reference scheme (⚠️ not confirmed live — the best evidence-backed option):
# per Caleb's research (02-market-analysis/codex-mechanisms.md §4.1, official docs checked
# 2026-07-23), Codex injects the **environment variables** `PLUGIN_ROOT` (plus the legacy
# `CLAUDE_PLUGIN_ROOT`) into the hook process. Whether that value is expanded inside the
# command string (i.e. run through a shell) is unconfirmed, so rather than relying on that
# assumption we wrap the command in `/bin/bash -c '...'` ourselves and use **bash's own**
# variable expansion — that way, whether the outer runner executes this command through a
# shell or straight via execve (as long as the quotes survive), the inner
# `${PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}` is always expanded at `bash -c` time from that
# process's real environment, so no assumption about the outer execution model is needed.
# If the assumption is wrong (a different env var name, or docs diverging from reality), a
# live retest by the user will reveal it; then the name can be pinned by a probe.sh-style
# measurement and only this script needs changing (its body stays untouched).
# ---------------------------------------------------------------------------
if [ -f "$SRC_HOOKS" ]; then
  nhook=0
  for h in "$SRC_HOOK_SCRIPTS"/*.sh; do
    [ -f "$h" ] || continue
    base="$(basename "$h")"
    case "$base" in
      _test-*) continue ;;  # test scripts are not distribution assets (codex-adapter internal)
    esac
    cp -p "$h" "$DST/hooks/$base"
    chmod +x "$DST/hooks/$base"
    nhook=$((nhook+1))
  done
  say "[hooks/*.sh] $nhook 개 → $DST/hooks/**(실행권한 유지)"

  # hooks.json is parsed structurally and only its command fields are rewritten (python3 — the
  # same tool already used to validate this file's plugin.json; the no-jq-dependency rule does
  # not apply here because this script is build-time only, so python3 is harmless).
  # matcher/timeout/event order are preserved exactly as they appear in SRC_HOOKS.
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
