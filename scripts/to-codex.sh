#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# BATHOS  scripts/to-codex.sh  —  Claude Code assets -> OpenAI Codex CLI dual-emit
#
# What & why (intro):
#   The canonical sources are always `.claude/commands/*.md` and `.claude/agents/_base/*.md`, and this
#   script **only reads** them (project-context-kr.md#2.6 "zero regression on the Claude path" — W5 freeze).
#   The output splits into four targets:
#     1) legacy scaffold (backwards compat, story-05 AC#6): <dest>/prompts/*.md, <dest>/agents/*.toml
#        — behaviour unchanged (default dest=./.codex-out); only the TOML gets the literal `'''` + spawnable filter (§3).
#        here the model field stays a `# TODO` comment (legacy is only a preview scaffold, not a release path).
#     2) canonical skills (D6 — NOT `.codex/skills`): $REPO_ROOT/.agents/skills/<name>/SKILL.md
#        emitted automatically on `--write` (an in-repo path, so no extra consent is needed).
#     3) transitional prompts: ~/.codex/prompts/<name>.md — only with an explicit `--emit-prompts` (writing to
#        the home directory is a matter of user consent — story-05, subtask 1).
#     4) canonical agents (CT-SUBAGENT, story-11 — Stephen's request §8): <repo>/.codex/agents/<slug>.toml
#        emitted automatically on `--write` (in-repo). Same D6-style dual-path pattern as the canonical skills (legacy+canonical) —
#        unlike legacy (1), this one **writes a real value into the model field** (stephen-model-mapping.md §1 lookup,
#        the lead's confirmed v0.145.0+ adoption) plus the story-09 standard orchestration text (blocks A+B, stephen-orchestration.md
#        §"TOML/skills insertion points" specifies A+B only), appended at the end of developer_instructions. Both texts are
#        constants copied verbatim from the canonical documents (do not rewrite — wording drift is canon collapse; both
#        documents state this explicitly).
#
#   Three emission classes (rationale: .agent-team/08-impl-notes/andrew-command-classification.md, story-04 SS5):
#     - the 15 team-spawning ones (they use the Task tool) -> this script does not create them. story-10 writes their
#       SKILL.md by hand (hand-authored) and registers them in scripts/codex-skills-drift-exclusions.json, out of regeneration.
#       (Careful: `scripts/drift-exclusions.json` is a separate file that **already exists** — the docs i18n drift-guard
#       `check-rule-copies.sh` owns and consumes it, so a new filename avoids the clash. Detailed rationale in
#       andrew-command-classification.md#8.)
#     - the 4 aliases (save/resume/context-save/context-restore) -> in the skills target they merge into the canonical
#       names (save-session/cold-start) so no duplicate skill is exposed (US8-AC1). In the prompts target (both legacy
#       and transitional) they are kept — a deterministic fallback only means something if the aliases live too.
#     - remote-dev (1) -> it is a guide to a Claude-only feature (Remote Control), which Codex has no counterpart for.
#       Excluded from the skills target (no overclaiming, project-context-kr.md#2.5); included in prompts per AC#1's wording.
#     -> final number of exposed skills = 15 (hand-authored) + 15 (generated here) = 30 (the classification table's §5 figure).
#
#   The 3-part description (summary/TRIGGER/NOT, CT-SKILL §7) is synthesised **deterministically** by this script
#   without touching `.claude/commands` (the trigger_for/not_for tables, below). Unsourced natural-language triggers are
#   never invented — without a CLAUDE.md §8/§8.1 entry or the command's own "natural-language trigger" footnote, we
#   honestly write "explicit mention only" (project-context-kr.md#2.5). Since the synthesis emits the same output every
#   run (nothing nondeterministic), it keeps the "generated" status — idempotence (AC#4) is not "byte-equal to canon" but "re-run this script, same result".
#
#   Handling the project-path argument: most original commands accept `$1` (the project's absolute path, usually
#   optional), but Codex skills have no argument substitution (L4, issue #15316). So every skill body gets the same
#   banner prepended, stating that any `$1` token left in the body must be read as "always the current working
#   directory (cwd)" (F1: the base assumption is that Codex runs from the repo root). Why `$1` is not substituted
#   sentence by sentence: rewriting Korean prose (with its particles and endings) by regex risks breaking the meaning more than it gains — one banner notice is more honest.
#
# Usage:
#   bash scripts/to-codex.sh                              # dry-run (preview, everything)
#   bash scripts/to-codex.sh --write                       # really create the legacy scaffold + canonical skills
#   bash scripts/to-codex.sh --write --emit-prompts        # + transitional ~/.codex/prompts emission (consent to write to home)
#   bash scripts/to-codex.sh --write --dest ~/.codex-out2  # choose where the legacy scaffold goes
#   bash scripts/to-codex.sh --write --skills-root <dir>   # redirect the skills output (mainly for the drift check)
#   bash scripts/to-codex.sh --write --agents-root <dir>   # redirect the canonical agents output (default .codex/agents)
#
# Hard rule: no fabrication. The model field preserves the original (claude-*) as a comment, and the
#       Codex model is left blank for the user to fill in (never insert an arbitrary model name — blank until the SS10 mapping table is settled).
#       Idempotence: two `--write` runs back to back yield a zero diff (US13-AC1 — no timestamps or other nondeterminism).
#       bash 3.2 compatible (the macOS default) — no jq, native grep/sed/awk parsing only (project-context-kr.md#1).
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "$SCRIPT_DIR/.." && pwd)"
WRITE=0
EMIT_PROMPTS=0
DEST="$PROJ/.codex-out"
SKILLS_ROOT="$PROJ/.agents/skills"
AGENTS_ROOT="$PROJ/.codex/agents"

while [ $# -gt 0 ]; do
  case "$1" in
    --write) WRITE=1 ;;
    --dest) shift; DEST="$1" ;;
    --skills-root) shift; SKILLS_ROOT="$1" ;;
    --agents-root) shift; AGENTS_ROOT="$1" ;;
    --emit-prompts) EMIT_PROMPTS=1 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "알 수 없는 인자: $1" >&2; exit 2 ;;
  esac
  shift
done

CMD_SRC="$PROJ/.claude/commands"
AGT_SRC="$PROJ/.claude/agents/_base"
LEGACY_PROMPT_DST="$DEST/prompts"
LEGACY_AGENT_DST="$DEST/agents"
HOME_PROMPTS_DST="$HOME/.codex/prompts"

say(){ printf '%s\n' "$*"; }
[ "$WRITE" = "1" ] && say "== 실제 생성 → $DEST (+ skills: $SKILLS_ROOT) ==" || say "== DRY-RUN(미리보기) — 실제 생성하려면 --write =="

# ---------------------------------------------------------------------------
# §1. frontmatter/body parser (reuse the existing helpers — do not reinvent)
# ---------------------------------------------------------------------------
# Extract a frontmatter value (key: value from the first --- block, inline comments stripped)
fm_val(){ # $1=file $2=key
  awk -v k="$2" '
    NR==1 && $0 ~ /^---[[:space:]]*$/ {inf=1; next}
    inf && $0 ~ /^---[[:space:]]*$/ {exit}
    inf {
      line=$0; sub(/#.*/,"",line)                       # strip the inline comment
      if (line ~ "^[[:space:]]*" k "[[:space:]]*:") {
        sub("^[[:space:]]*" k "[[:space:]]*:[[:space:]]*","",line)
        gsub(/^[[:space:]]+|[[:space:]]+$/,"",line)
        gsub(/^"|"$/,"",line)
        print line; exit
      }
    }' "$1"
}
# Extract the body (everything after the second ---)
body_after_fm(){ awk 'p{print} /^---[[:space:]]*$/{c++; if(c==2)p=1}' "$1"; }
first_body_description(){
  awk '
    /^---[[:space:]]*$/ && c < 2 { c++; next }
    c >= 2 && $0 !~ /^[[:space:]]*$/ && $0 !~ /^#/ { print; exit }
  ' "$1"
}

# ---------------------------------------------------------------------------
# §2. classification data (andrew-command-classification.md §1~4 verbatim — .claude untouched)
# ---------------------------------------------------------------------------
TEAM_SPAWN="autoplan cso investigate lecture plan-design-review plan-devex-review plan-eng-review review wave0-analysis wave1-discovery wave2-design wave3-story-gate wave4-ip-research wave5-implement wave6-verify-report"
ARG_SKILLS="route recall guard team-kickoff"
CODEX_INAPPLICABLE="remote-dev"

is_in(){ # $1=needle $2=space-separated haystack
  case " $2 " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# Alias -> canonical mapping (for merging in the skills target). Empty string when it does not apply.
alias_canonical(){
  case "$1" in
    save|context-save) printf 'save-session' ;;
    resume|context-restore) printf 'cold-start' ;;
    *) printf '' ;;
  esac
}

# Is this an emission target for skills? (= the other 20: not team-spawning, not an alias, not remote-dev)
is_skill_target(){
  is_in "$1" "$TEAM_SPAWN" && return 1
  [ -n "$(alias_canonical "$1")" ] && return 1
  is_in "$1" "$CODEX_INAPPLICABLE" && return 1
  return 0
}

# ---------------------------------------------------------------------------
# §3. synthesise the 3-part TRIGGER/NOT description (no fabrication — only sourced wording)
# ---------------------------------------------------------------------------
trigger_for(){
  case "$1" in
    save-session) printf '명시 멘션($save-session) 또는 자연어(CLAUDE.md §8): "세션 저장", "전체 저장", "저장", "세이브", "체크포인트", "save session", "save" — 짧은 별칭 $save, gstack 별칭 $context-save도 동일 취급(스킬 병합, andrew-command-classification.md#2)' ;;
    cold-start) printf '명시 멘션($cold-start) 또는 자연어(CLAUDE.md §8): "콜드스타트", "이어서", "이어서 하자", "이어서 시작하자", "이어서 시작", "이전 작업 불러와", "이전 세션 불러와", "재개", "cold start", "resume", "continue" — 짧은 별칭 $resume, gstack 별칭 $context-restore도 동일 취급(스킬 병합)' ;;
    project-handoff) printf '명시 멘션($project-handoff) 또는 자연어(커맨드 자체 각주): "핸드오프", "프로젝트 기억", "전역 저장", "project handoff"' ;;
    recall) printf '명시 멘션($recall) 또는 자연어(커맨드 자체 각주): "이전 프로젝트 참고", "예전에 어떻게 했지", "회상", "recall", "다른 프로젝트에서"' ;;
    taskreport) printf '명시 멘션($taskreport) 또는 자연어(커맨드 자체 각주): "작업 리포트", "리포트 생성", "task report", "세션 리포트 만들어"' ;;
    *) printf '명시 멘션($%s)만 — CLAUDE.md §8·커맨드 자체 각주에 자연어 별칭 정의 없음(날조 금지, 미정 상태 정직 표기). 자연어 확장은 실사용 관측 후 사용자 확정을 거쳐 추가한다.' "$1" ;;
  esac
}

not_for(){
  case "$1" in
    save-session) printf 'git commit 등 다른 "저장" 의미, 코드 파일 저장(Write/Edit) 같은 일반 저장 요청에는 발동 금지.' ;;
    cold-start) printf '파일 수정·새 기능 시작 요청에는 발동 금지(읽기 전용 브리핑 전용). "저장해줘"는 save-session 몫.' ;;
    project-handoff) printf '프로젝트 내부 세션 저장(→save-session)이나 다른 프로젝트 참고(→recall)에는 발동 금지 — 이 스킬은 현재 프로젝트를 전역 레지스트리로 내보내는 것만.' ;;
    recall) printf '현재 프로젝트 내부 상태 복원(→cold-start)에는 발동 금지 — 이 스킬은 다른 프로젝트의 지식을 끌어오는 것만.' ;;
    taskreport) printf '세션을 마무리·저장하려는 의도("저장해줘")에는 save-session을 우선 안내(리포트도 함께 만들어짐 — 중복 호출 유의). 이 스킬은 세션 도중 리포트만 즉시 원할 때.' ;;
    guard) printf '이미 guard 활성 상태에서 안전 조치와 무관한 일반 편집 요청에는 발동 금지. freeze 해제는 unfreeze 몫.' ;;
    unfreeze) printf 'freeze를 걸려는 요청(→guard)에는 발동 금지 — 이 스킬은 해제 전용.' ;;
    route) printf '이미 레벨이 확정된 상태에서 재라우팅 의도가 없는 일반 작업 요청에는 발동 금지 — 레벨 변경은 명시적 재라우팅 발화에서만.' ;;
    team-kickoff) printf '이미 킥오프된 프로젝트에서 재킥오프 의도가 없는 요청에는 발동 금지(charter.md 존재 여부로 먼저 확인 권장).' ;;
    team-status) printf '완전 복원 브리핑 의도(→cold-start)에는 발동 금지 — 이 스킬은 경량 점검, cold-start는 3자 교차 완전 복원.' ;;
    team-confirm) printf '중간 진행 점검(→team-status)에는 발동 금지 — 이 스킬은 웨이브 종료 후 최종 사후 컨펌 전용.' ;;
    team-cleanup) printf '팀원 shutdown과 무관한 일반 파일 정리 요청에는 발동 금지.' ;;
    health) printf '특정 버그 조사 요청(→investigate, 팀 스폰형)에는 발동 금지 — 이 스킬은 정적 품질 대시보드만.' ;;
    plan-ceo-review) printf '코드 리뷰(→review)나 설계 리뷰(→plan-design-review, 모두 팀 스폰형) 요청에는 발동 금지 — 이 스킬은 리드 단독 CEO 모드 플랜 리뷰만.' ;;
    retro) printf '진행 중 상태 점검(→team-status)에는 발동 금지 — 이 스킬은 사이클 종료 후 회고 전용.' ;;
    *) printf '이 스킬과 무관한 일반 코딩/대화 요청에는 발동 금지.' ;;
  esac
}

# For the 4 argument-taking skills only — the prose argument-convention block (CT-SKILL argument_convention, story-07)
arg_prose_for(){
  case "$1" in
    route)
      cat <<'BLOCK'
**인자 해석**: 멘션($route) 뒤 텍스트를 원하는 Scale-Adaptive 레벨 후보(Lv0~4) 또는 그 근거(범위/신규성/규제/팀규모)로 해석한다. 없으면 본문 "1단계 — Stakes 수집"의 4가지 질문을 순서대로 한다.

**모호하면 반드시 사용자에게 되묻는다**(자의 해석 금지 — E-SKILL-ARG-AMBIGUOUS).

**User Sovereignty 최종 방어선**: 이 스킬이 유도하는 판단은 항상 "추천 제시 → 사용자 확정 발화" 2단이다. 스킬이 자동으로 레벨을 확정하지 않는다(F2 흐름).

**결정론 폴백**: 해석이 어긋나면 `/prompts:route <레벨>`를 쓰세요(과도기 prompts 방출본, `$1..$9` 인자 치환 결정론 — L4 고지).
BLOCK
      ;;
    recall)
      cat <<'BLOCK'
**인자 해석**: 멘션($recall) 뒤 텍스트를 관심 주제/기술/도메인으로 해석한다. 없으면 본문 "1. 관련성 판단"대로 현재 프로젝트 컨셉(manifest.json·charter·SESSION-SNAPSHOT에서 추정) 기준으로 자동 진행한다(질문 불필요 — 원본 폴백 그대로).

**모호하면 되묻기보다 위 자동 폴백을 우선**(이 스킬은 읽기 전용·비파괴적이라 자의 해석의 피해가 낮다 — route/team-kickoff와의 차이).

**결정론 폴백**: `/prompts:recall <주제>`.
BLOCK
      ;;
    guard)
      cat <<'BLOCK'
**인자 해석**: 멘션($guard) 뒤 텍스트(공백 구분)를 허용 편집 경로 목록으로 해석한다. 없으면 "각 팀원의 소유 경로만"이 기본값(원본 `${ARGUMENTS:-...}` 폴백 그대로).

**모호하면 반드시 사용자에게 되묻는다**(freeze 범위는 파괴적 결정이므로 자의 해석 금지 — E-SKILL-ARG-AMBIGUOUS).

**결정론 폴백**: `/prompts:guard <경로1> <경로2> ...`.
BLOCK
      ;;
    team-kickoff)
      cat <<'BLOCK'
**인자 해석**: 멘션($team-kickoff) 뒤 텍스트를 서비스 컨셉/목표 한 줄로 해석한다.

**컨셉 없이는 진행 금지 — 반드시 되묻는다**(E-SKILL-ARG-AMBIGUOUS 강제 케이스): charter.md 작성에 컨셉이 필수 입력이라 자동 해석·추정으로 채우면 이후 전 웨이브가 틀린 전제 위에서 진행된다.

**결정론 폴백**: `/prompts:team-kickoff <컨셉>`.
BLOCK
      ;;
  esac
}

# ---------------------------------------------------------------------------
# §4. path banner + generated header (common to every emitted skill, AC#2)
# ---------------------------------------------------------------------------
GENERATED_HEADER_SKILL(){ printf '# generated by scripts/to-codex.sh — 정본: .claude/commands/%s.md (직접 수정 금지)\n' "$1"; }
GENERATED_HEADER_TOML(){ printf '# generated by scripts/to-codex.sh — 정본: .claude/agents/_base/%s (직접 수정 금지)\n' "$1"; }

PATH_BANNER(){
  cat <<'BANNER'
> **Codex 경로 참고**: 원본 Claude 커맨드는 프로젝트 절대경로를 인자(`$1`)로 받았지만, Codex skills는
> 인자 치환이 없습니다(L4 — 이슈 #15316). 이 스킬은 **항상 현재 작업 디렉터리(cwd)를 프로젝트 루트**로
> 씁니다 — 다른 프로젝트를 다루려면 그 디렉터리에서 Codex를 실행하세요. 아래 본문에 원본 표기 `$1`이
> 남아 있으면 전부 **현재 작업 디렉터리**로 읽으세요(치환되지 않습니다 — 지침일 뿐 실제 인자가 아닙니다).
BANNER
}

# story-16 L1/L2 disclosure — only for save-session/cold-start/taskreport (ux-parity-limits.md §3)
codex_notice_for(){
  case "$1" in
    save-session)
      cat <<'BLOCK'
> **L1 고지(종료 훅 부재)**: Codex에는 SessionEnd 훅이 없습니다 — 세션을 끝내기 전에 이 스킬($save-session
> 또는 "저장해줘")을 직접 실행하세요. 자동 저장은 Stop 훅(매 턴 종료 시 `session-state.json` 증분 갱신,
> 유실 창 ≤ 1턴+10s)뿐이며, 서술 스냅샷(`SESSION-SNAPSHOT.md`)은 이 스킬을 실행해야만 갱신됩니다.
BLOCK
      ;;
    cold-start)
      cat <<'BLOCK'
> **L1/L2 고지**: 이번 세션도 종료 전 $save-session 실행을 권장합니다(Codex에는 종료 훅이 없어 자동
> 저장·자동 리포트가 없습니다 — 수동 실행이 설계된 최선입니다).
BLOCK
      ;;
    taskreport)
      cat <<'BLOCK'
> **L2 고지(자동 리포트 부재)**: Codex에는 세션 종료 시 리포트를 자동 생성하는 훅이 없습니다. 세션을
> 마무리할 때는 $save-session이 이 스킬과 동일한 리포트를 함께 생성하므로(L2 완화 — "저장과 리포트를
> 한 번으로"), 종료 직전이라면 이 스킬 대신 $save-session을 우선 고려하세요. 이 스킬은 세션 도중
> 온디맨드로 리포트만 원할 때 씁니다.
BLOCK
      ;;
  esac
}

# ---------------------------------------------------------------------------
# §5. emit the canonical skills (.agents/skills/<name>/SKILL.md — D6)
# ---------------------------------------------------------------------------
nskill=0
if [ -d "$CMD_SRC" ]; then
  for f in "$CMD_SRC"/*.md; do
    [ -e "$f" ] || continue
    name="$(basename "${f%.md}")"
    is_skill_target "$name" || continue
    nskill=$((nskill+1))

    summary="$(fm_val "$f" description)"
    [ -z "$summary" ] && summary="BATHOS $name"
    trig="$(trigger_for "$name")"
    nott="$(not_for "$name")"

    if [ "$WRITE" = "1" ]; then
      mkdir -p "$SKILLS_ROOT/$name"
      {
        printf -- '---\n'
        printf 'name: %s\n' "$name"
        printf 'description: |\n'
        printf '  %s\n' "$summary"
        printf '  TRIGGER: %s\n' "$trig"
        printf '  NOT: %s\n' "$nott"
        printf -- '---\n'
        GENERATED_HEADER_SKILL "$name"
        printf '\n'
        PATH_BANNER
        printf '\n'
        if is_in "$name" "$ARG_SKILLS"; then
          arg_prose_for "$name"
          printf '\n'
        fi
        cn="$(codex_notice_for "$name")"
        [ -n "$cn" ] && { printf '%s\n\n' "$cn"; }
        body_after_fm "$f"
      } > "$SKILLS_ROOT/$name/SKILL.md"

      if is_in "$name" "$ARG_SKILLS"; then
        mkdir -p "$SKILLS_ROOT/$name/agents"
        {
          GENERATED_HEADER_SKILL "$name"
          printf '# interface.default_prompt 프리필 — $1..$9 인자 치환 부재(#15316)의 공식 우회책.\n'
          printf '# Codex가 이 skill을 호출할 때 입력창에 아래 문구를 미리 채운다(L4 완화, CT-SKILL prefill).\n'
          printf 'interface:\n'
          printf '  default_prompt: "$%s "\n' "$name"
        } > "$SKILLS_ROOT/$name/agents/openai.yaml"
      fi
    else
      kind="무인자형"; is_in "$name" "$ARG_SKILLS" && kind="인자형(+openai.yaml)"
      say "  [skill]  $name/SKILL.md  ($kind)"
    fi
  done
fi

# ---------------------------------------------------------------------------
# §6. legacy scaffold (backwards compat, AC#6) — <dest>/prompts, <dest>/agents
#     + transitional ~/.codex/prompts (--emit-prompts, story-05 AC#1: only the 15 team-spawning ones excluded)
# ---------------------------------------------------------------------------
ncmd=0
if [ -d "$CMD_SRC" ]; then
  [ "$WRITE" = "1" ] && mkdir -p "$LEGACY_PROMPT_DST"
  [ "$WRITE" = "1" ] && [ "$EMIT_PROMPTS" = "1" ] && mkdir -p "$HOME_PROMPTS_DST"
  for f in "$CMD_SRC"/*.md; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"; name="${base%.md}"; ncmd=$((ncmd+1))
    if [ "$WRITE" = "1" ]; then
      { GENERATED_HEADER_SKILL "$name"; printf '\n'; cat "$f"; } > "$LEGACY_PROMPT_DST/$base"
      if [ "$EMIT_PROMPTS" = "1" ] && ! is_in "$name" "$TEAM_SPAWN"; then
        { GENERATED_HEADER_SKILL "$name"; printf '\n'; cat "$f"; } > "$HOME_PROMPTS_DST/$base"
      fi
    else
      say "  [prompt] $base  (/prompts:${name})"
    fi
  done
fi

# ---------------------------------------------------------------------------
# §7. agents -> agents/*.toml (legacy scaffold) — literal ''' + spawnable filter (AC#3)
# ---------------------------------------------------------------------------
nagt=0
nagt_skipped=0
if [ -d "$AGT_SRC" ]; then
  [ "$WRITE" = "1" ] && mkdir -p "$LEGACY_AGENT_DST"
  for f in "$AGT_SRC"/*.md; do
    [ -e "$f" ] || continue
    slug="$(fm_val "$f" slug)"; [ -z "$slug" ] && slug="$(fm_val "$f" name)"
    [ -z "$slug" ] && slug="$(basename "${f%.md}")"
    model="$(fm_val "$f" model)"
    spawnable="$(fm_val "$f" spawnable)"

    # spawnable:false (currently one file, 00-paul-team-lead.md) -> excluded from TOML emission (story-05 AC#3 — fixes
    # the 18-file emission bug: Paul is never spawned as a teammate, so a subagent TOML makes no sense for him).
    if [ "$spawnable" = "false" ]; then
      nagt_skipped=$((nagt_skipped+1))
      [ "$WRITE" != "1" ] && say "  [agent]  $slug.toml  SKIP(spawnable:false)"
      continue
    fi

    # description = the body's first non-empty, non-heading line
    desc="$(first_body_description "$f")"
    [ -z "$desc" ] && desc="BATHOS role $slug"
    nagt=$((nagt+1))

    if [ "$WRITE" = "1" ]; then
      body="$(body_after_fm "$f")"
      # AC#3: if a literal ''' appears in the developer_instructions body, TOML cannot express it safely
      # (TOML has no string-concatenation operator, so "splitting" is effectively impossible — stop with an honest error).
      if printf '%s' "$body" | grep -qF "'''"; then
        echo "오류: $slug — developer_instructions 본문에 literal ''' 등장, TOML 리터럴 문자열로 안전 표현 불가(AC#3 정직 오류)" >&2
        exit 1
      fi
      {
        GENERATED_HEADER_TOML "$(basename "$f")"
        printf '# source model: %s   (Codex 모델은 아래 model 을 직접 지정하세요 — 임의 삽입 금지)\n' "${model:-미지정}"
        printf '# spawnable: %s\n\n' "${spawnable:-미지정}"
        printf 'name = "%s"\n' "$slug"
        printf 'description = "%s"\n' "$(printf '%s' "$desc" | sed 's/"/\\"/g')"
        printf '# model = "gpt-5-codex"   # TODO: 사용자 지정(SS10 매핑표 확정 후 — 그 전까지 생략)\n'
        printf '# model_reasoning_effort = "high"\n\n'
        printf "developer_instructions = '''\n"
        printf '%s\n' "$body"
        printf "'''\n"
      } > "$LEGACY_AGENT_DST/$slug.toml"
    else
      say "  [agent]  $slug.toml  (src model: ${model:-미지정}, spawnable: ${spawnable:-미지정})"
    fi
  done
fi

# ---------------------------------------------------------------------------
# §8. agents -> .codex/agents/*.toml (canonical, CT-SUBAGENT — story-11/Stephen's request)
#     Same source, same spawnable filter and same literal ''' discipline as legacy (§7), but this is the release
#     canon, so the model field gets a real value and the standard orchestration text is appended. Why the two
#     sections repeat an almost identical loop: §7 is a "preview scaffold" (legacy --dest backwards compat, story-05
#     AC#6) while §8 is the "story-11 release canon" — different purposes, and force-merging them would entangle each section's reason to change (single responsibility kept).
# ---------------------------------------------------------------------------

# The model mapping (story-11/SS10 canon — stephen-model-mapping.md §1, reflecting the lead's confirmed v0.145.0+ adoption).
# Only these two functions are lookups; every other text (comments, orchestration wording) is a constant copied verbatim from the canonical documents.
model_for(){ # $1 = the base frontmatter model value (claude-fable-5|claude-sonnet-5)
  case "$1" in
    claude-fable-5) printf 'gpt-5.6-sol' ;;
    claude-sonnet-5) printf 'gpt-5.5' ;;
    *) printf '' ;;
  esac
}
effort_for(){
  case "$1" in
    claude-fable-5) printf 'high' ;;
    claude-sonnet-5) printf 'medium' ;;
    *) printf '' ;;
  esac
}

# Residual-constraint note — stephen-model-mapping.md §4 canonical text verbatim (no rewriting; avoids fabrication/overclaiming risk).
MODEL_CONSTRAINT_NOTE(){
  cat <<'BLOCK'
# ⚠️ 잔존 제약(2026-07-23 확인, [실측]/[문서확정] 아님 — 커뮤니티 재현 수준, 상세: stephen-model-mapping.md#3):
#   1) v0.145.0+ 전제(리드 확정 채택)에서 model/model_reasoning_effort 오버라이드 자체는 PR #32749로
#      복원됨. 그러나 gpt-5.6-sol 부모가 "이 TOML을 이름으로 골라 쓰는지"(agent_type 자동 선택)는
#      별도 후속 PR 대기 중(2026-07-23 기준 머지 미확인) — 완전 동작은 사용자 ~/.codex/config.toml에
#      [features.multi_agent_v2] hide_spawn_agent_metadata=false 수동 설정이 필요할 수 있음.
#   2) 위 전부 [LIVE] 미검증 — story-20에서 재확인 예정. 그때까지 "동작 예상, 미검증"으로 취급할 것.
BLOCK
}

# Standard orchestration blocks A+B — stephen-orchestration.md canonical text verbatim (no rewriting).
# As the "TOML/skills insertion points" section specifies: A+B only in an individual role TOML (C and D carry
# session-global/spawn semantics, unnecessary in a persona file — they are for AGENTS.md and the wave skills).
ORCH_BLOCK_AB(){
  cat <<'BLOCK'

[BATHOS 오케스트레이션 규칙 — 중첩 금지]
당신은 서브에이전트로 스폰되었습니다. 이 세션에서 추가로 서브에이전트를 스폰하지 마세요
(중첩 스폰 금지). 필요한 작업이 있으면 직접 수행하거나, 완료 후 반환 요약에 "이런 후속 작업이
필요하다"고 적어 리드(Paul)가 재스폰하도록 넘기세요. 이 규칙은 config 강제가 아니라 지침
강제입니다(물리 차단 아님) — SubagentStart 로그로 사후 검증됩니다.

[BATHOS 오케스트레이션 규칙 — 디스크 SSOT]
당신의 작업 결과는 스폰한 쪽(리드)에게 요약으로만 반환됩니다. 요약은 포인터일 뿐 신뢰할 원본이
아닙니다. 그러므로 산출물의 전문은 반드시 소유 경로의 디스크 파일로 남기세요(코드·문서·리포트
전부). 반환 요약에는 "무엇을 어느 파일에 썼는지" 경로를 명시하세요.
BLOCK
}

nagt_canon=0
nagt_canon_skipped=0
nagt_canon_unmapped=0
if [ -d "$AGT_SRC" ]; then
  [ "$WRITE" = "1" ] && mkdir -p "$AGENTS_ROOT"
  for f in "$AGT_SRC"/*.md; do
    [ -e "$f" ] || continue
    slug="$(fm_val "$f" slug)"; [ -z "$slug" ] && slug="$(fm_val "$f" name)"
    [ -z "$slug" ] && slug="$(basename "${f%.md}")"
    model="$(fm_val "$f" model)"
    spawnable="$(fm_val "$f" spawnable)"

    if [ "$spawnable" = "false" ]; then
      nagt_canon_skipped=$((nagt_canon_skipped+1))
      [ "$WRITE" != "1" ] && say "  [agent*] $slug.toml  SKIP(spawnable:false)"
      continue
    fi

    desc="$(first_body_description "$f")"
    [ -z "$desc" ] && desc="BATHOS role $slug"
    cm="$(model_for "$model")"
    ce="$(effort_for "$model")"
    [ -z "$cm" ] && nagt_canon_unmapped=$((nagt_canon_unmapped+1))
    nagt_canon=$((nagt_canon+1))

    if [ "$WRITE" = "1" ]; then
      body="$(body_after_fm "$f")"
      if printf '%s' "$body" | grep -qF "'''"; then
        echo "오류: $slug — developer_instructions 본문에 literal ''' 등장, TOML 리터럴 문자열로 안전 표현 불가(AC#3 정직 오류)" >&2
        exit 1
      fi
      {
        GENERATED_HEADER_TOML "$(basename "$f")"
        printf '# source model(base frontmatter): %s\n\n' "${model:-미지정}"
        printf 'name = "%s"\n' "$slug"
        printf 'description = "%s"\n' "$(printf '%s' "$desc" | sed 's/"/\\"/g')"
        if [ -n "$cm" ]; then
          MODEL_CONSTRAINT_NOTE
          printf 'model = "%s"\n' "$cm"
          printf 'model_reasoning_effort = "%s"\n\n' "$ce"
        else
          printf '# model 매핑 없음(base model=\"%s\" 미인식) — stephen-model-mapping.md §1 갱신 필요, 임의 값 삽입 금지\n' "${model:-미지정}"
          printf '# model = "gpt-5-codex"   # TODO\n\n'
        fi
        printf "developer_instructions = '''\n"
        printf '%s\n' "$body"
        ORCH_BLOCK_AB
        printf "'''\n"
      } > "$AGENTS_ROOT/$slug.toml"
    else
      say "  [agent*] $slug.toml  (canonical, model: ${cm:-미매핑} $ce)"
    fi
  done
fi

say ""
say "요약: 커맨드 $ncmd 개 → 레거시 prompts, 에이전트 $nagt 개 → agents/*.toml($nagt_skipped 개 spawnable:false 제외), skills $nskill 개 → .agents/skills/**"
say "      agents 정본(story-11) $nagt_canon 개 → .codex/agents/*.toml($nagt_canon_skipped 개 spawnable:false 제외, $nagt_canon_unmapped 개 model 미매핑)"
if [ "$WRITE" = "1" ]; then
  say "생성 위치: $DEST (레거시) / $SKILLS_ROOT (skills 정본) / $AGENTS_ROOT (agents 정본)"
  [ "$EMIT_PROMPTS" = "1" ] && say "prompts 과도기: $HOME_PROMPTS_DST"
  say "다음(수기): 팀 스폰형 15개 skills(story-10) — 이 스크립트가 만들지 않음, codex-skills-drift-exclusions.json 확인"
else
  say "실제 생성: bash scripts/to-codex.sh --write [--dest <경로>] [--emit-prompts] [--skills-root <dir>]"
fi
