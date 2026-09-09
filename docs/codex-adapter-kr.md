# BATHOS × Codex CLI — 어댑터 설계 (포팅 가이드)

> **성격: 런타임 포팅.** Claude Code 접착층(Agent Teams·훅·커맨드)을 OpenAI Codex CLI의 확장점으로 옮긴다. `bathos` 엔진은 그대로 CLI로 호출.
> 상위 판단·단계 계획: `docs/PORTABILITY-kr.md`. 이 문서는 Codex 매핑 상세 + 재설계 지점 + 변환 스캐폴드(`scripts/to-codex.sh`) 사용법.
> **W5 갱신(2026-07-23~31)**: 타겟 기준선은 Codex CLI **v0.145.0+**로 이동했다.
> 저장소는 prompts 중심 스캐폴드가 아니라 **skills + project hooks + subagents +
> plugin bundle** 경로를 정본으로 방출한다. v0.145.0 로컬에서 `hooks stable true`
> 는 확인했지만, 인증된 Codex 세션의 end-to-end hook 발화와 plugin/skill/subagent
> 동작은 `story-20` live walkthrough로 남아 있다. 또한 2026-07-31 현재 공식 Hooks
> 문서가 `SessionEnd`를 노출하므로, 과거 v0.144.5 기준의 "SessionEnd 부재" 단정은
> **문서 드리프트 후보**로 보고 `probe.sh`로 재실측해야 한다.

---

## 1. 매핑 매트릭스

| BATHOS(Claude Code) | Codex CLI 대응 | 변환 |
|---------------------|----------------|------|
| `.claude/agents/<r>.md` (frontmatter `model`) | `.codex/agents/<r>.toml` (`name`·`description`·`developer_instructions`·`model`·`model_reasoning_effort`) | `to-codex.sh` + 모델 매핑 |
| `.claude/commands/<c>.md` | `.agents/skills/<c>/SKILL.md` (`$<c>` explicit/implicit skills) | generated + hand-authored Codex-native skills |
| `.claude/commands/<c>.md` | `.codex-out/prompts/<c>.md` / 선택적 `~/.codex/prompts/<c>.md` | legacy deterministic fallback only |
| `AGENTS.md` | 네이티브(Codex가 읽음) | 그대로 |
| MCP 서버 | `~/.codex/config.toml` `[mcp_servers.x]` | 수동/후속 |
| 훅(settings.json) | `.codex/hooks.json` project hooks + 보조 `config.toml.example` | §3 재설계 |
| 모델 ID `claude-*` | Codex `model` + `[model_providers.x]` | §4 |

**중첩 규칙:** `max_depth`류 물리 차단은 현재 정본으로 삼지 않는다. AGENTS.md와
각 TOML `developer_instructions`에 "서브에이전트는 다시 스폰하지 않는다"를 중복
명기하고, SubagentStart 로그로 사후 검증한다.

---

## 2. 커맨드·에이전트 변환 (기계적 80%)

```bash
bash scripts/to-codex.sh            # 미리보기(dry-run): 무엇이 생성될지 출력만
bash scripts/to-codex.sh --write    # 실제 생성: .agents/skills/** 와 .codex/agents/**, .codex-out/**
bash scripts/to-codex.sh --write --dest /경로   # 출력 위치 지정
```
- 커맨드: generated skills와 hand-authored Codex-native skills로 나눈다. 팀 스폰형
  커맨드는 자동 변환하지 않고 스폰 순서·디스크 SSOT·중첩 금지 규칙을 수기 명시한다.
- 에이전트: `.claude/agents/_base/*.md` frontmatter/body를 읽어 `.codex/agents/*.toml`
  로 방출한다. `spawnable:false`인 Paul은 제외한다.
- prompts: `.codex-out/prompts/**`는 legacy scaffold이고, `--emit-prompts`를 명시할
  때만 홈의 `~/.codex/prompts`에도 과도기 폴백을 쓴다.
- ⚠️ **자동 변환이 못 하는 것**(수동): live hook trust, plugin marketplace E2E,
  인증 세션에서의 `agent_type`/model override 동작, `SessionEnd` 실제 발화 여부.

---

## 3. 재설계 지점 — Codex 이식의 진짜 비용

### (a) `TaskCompleted` 게이트 → `PreToolUse` exit-2 게이트
BATHOS는 W3 등 핵심 게이트를 "태스크 완료 차단"(TaskCompleted 훅)으로 하드 강제했다. Codex엔 등가 이벤트가 없다.
- **대안:** 다음 단계 진입 트리거(예: 구현 파일 쓰기, `wave5` 커맨드 실행)를 `PreToolUse` 훅으로 가로채 `bathos gate show`가 PASS/CONCERNS 아니면 **exit 2 + stderr 사유**로 차단. Codex에서 exit 2 = `"decision":"block"`.
- **실측 정정(P5)**: 트리거 매칭의 `tool_name`은 실제로 `shell`/`exec_command`
  (셸 실행)/`apply_patch`(파일 편집)이며, **`Bash`는 존재하지 않는다.** P4는
  공식 문서 예시만 보고 `Bash`를 가정했고, 이 때문에 T1/T2가 결코 발화하지
  않아 게이트가 **fail-open**되는 버그가 있었다(2026-07-16 실측으로 확정·
  `codex-adapter/hooks/pretooluse-gate.sh`에서 수정 완료 — 상세는
  `codex-adapter/README.md` §정직한 한계).

### (b) 종료 저장: `Stop` 근사 + `SessionEnd` 재실측 필요
CLAUDE.md §9(종료 시 저장→리포트→종료 강제)는 v0.144.5 실측 당시 Codex에
`SessionEnd`가 없어 물리적으로 동일 구현 불가라고 판단했다. 그러나 2026-07-31
현재 공식 Hooks 문서가 `SessionEnd`를 노출하므로, 이 전제는 W6에서 재실측해야 한다.
- **대안:** `Stop`(턴 종료) 훅에서 스냅샷/리포트를 **증분 저장**(세션 종료 ≠ 턴 종료이므로 매 턴 갱신 방식). 완전한 "종료 시 1회"는 포기하고 "자주 저장"으로 대체. `/save-session` 수동 저장 병행 권장.
- **현재 방침:** 구현은 `Stop` + `SessionStart`를 유지한다. `SessionEnd`가 실제로
  발화하는지 `probe.sh`/인증 세션으로 확인한 뒤, 종료 리포트 자동화를 이번 릴리스에
  넣을지 다음 스코프로 둘지 사용자에게 묻는다(User Sovereignty).

### (c) 훅 stable·Windows 공백
- **실측 정정(P5)**: Codex 훅은 더 이상 실험적이 아니다 — `codex features
  list`에서 `hooks  stable  true`로 확인됨(2026-07-16, v0.144.5). 다만
  BATHOS의 Windows/WSL 지원과의 관계는 여전히 유의할 것: hook config
  스키마에 **`commandWindows`**(Windows 전용 명령) 필드가 실측으로 존재함을
  확인했다 — Windows 네이티브 경로가 실제로 있다는 뜻이나, 이번 스코프에서
  `.ps1` 포트는 하지 않았다(§5). Windows 사용자는 당분간 WSL에서 Codex
  구동을 권장(`scripts/wsl-setup.sh`).

---

## 4. 모델 프로바이더 — responses-only 함정

- Codex는 `~/.codex/config.toml` `[model_providers.x]`로 커스텀 백엔드를 붙이되 **`wire_api="responses"`만 지원**(2026-02 chat 제거).
- **Codex + GLM**: GLM은 Chat Completions 계열 → **직접 연결 시 깨짐**(issue #9612). Responses↔Chat **번역 프록시**(codex-relay, codex-glm-proxy 등) 경유 필요. 즉 "Codex 위에서 GLM"은 어댑터 2겹.
- `model_provider(s)`는 **유저 레벨 `~/.codex/config.toml`에서만** 유효(프로젝트 로컬 무시).

---

## 5. 남은 단계 (후속)
- **P4: 완료(2026-07-16, Phillip)** — (a)(b) 훅 재설계가 `codex-adapter/`에
  실구현되었다: `hooks/pretooluse-gate.sh`(W3 게이트 exit-2) ·
  `hooks/stop-save.sh`(Stop 증분 저장) · `hooks/_test-codex-hooks.sh`(14케이스
  시뮬레이션, 실 Codex 불요 — 전부 통과) · `config.toml.example`. 당시
  미해소: `tool_name` 실측값 미확인(문서 예시 `Bash`·`apply_patch` 기준
  ⚠️[추정] — fail-open 리스크).
- **P5: 완료(2026-07-16, Phillip)** — 리드가 Codex CLI **v0.144.5**
  (macos-x86_64)를 실제로 설치해 바이너리 임베드 스키마를 실측, P4의
  `tool_name=Bash` 가정이 실제로는 항상 미스매치라 게이트가 fail-open되는
  버그를 확정하고 수정했다. 실측 tool_name(`shell`/`exec_command`/
  `apply_patch`)으로 `pretooluse-gate.sh`를 하드닝, `config.toml.example`을
  실측 스키마(`matcher`/`command`/`commandWindows`/`timeoutSec`)로 정정,
  `_test-codex-hooks.sh`에 회귀 케이스(B-15~B-18) 4건을 추가해 18케이스·
  37 assertion 전부 실행·통과시켰다. hooks=stable·기본 활성, `SessionEnd`
  부재(확정), `Stop` 유효도 이번에 재확인됨. **남은 미실증**: 라이브 인증
  세션(auth 부재로 미실행) — 스키마·계약까지만 실측했고, 실제 인증 세션에서
  config 등록이 배선대로 동작하는지는 다음 실사용 시 확인 필요. 또한 이
  해소는 **v0.144.5 버전 고정**이므로 업그레이드 시 재확인 필요.
- **W5: 구현 완료(2026-07-23, story-20 제외)** — 타겟을 **v0.145.0+**로 이동하고,
  `.agents/skills/**`, `.codex/agents/*.toml`, `.codex/hooks.json`,
  `dist/codex-plugin/**`, `bathos runtime`, `probe.sh`, Codex careful/freeze,
  SessionStart 안내, drift check, run-role CI를 추가했다. 로컬 하네스 기준 구현은
  닫혔지만, 인증 Codex 세션에서의 E2E(`story-20`)는 W6 검증 항목이다.
- **P5.1: 완료(2026-07-17)** — 라이브 인증 Codex 세션에서 실제
  `apply_patch` PreToolUse 입력을 확인한 결과, 패치는 `tool_input.command`에
  실리고 대상 파일은 **절대경로**(`/Users/…/project/src/…`)로 온다. 옛
  `SRC_ERE` 경계 `[^A-Za-z0-9_./-]`가 `/`를 경계로 인정하지 않아 절대경로
  앞의 `src/`가 T1 소스쓰기로 발화하지 못하고 FAIL 게이트에서도 편집이
  통과(fail-open)했다. 경계에 `/`를 추가해 수정하고, `_test-codex-hooks.sh`에
  회귀 케이스 B-19~B-20 2건을 추가(→ 20케이스·40 assertion)했으며, 이
  하네스를 **CI(`ci.yml` hooks job)에 연결**해 재발을 CI에서 강제한다.
- P6: Codex+GLM 프록시 연동, 커맨드→skills 마이그레이션(공식 방향), 네이티브
  마이그레이션(AGENTS_MD/HOOKS/COMMANDS/SUBAGENTS/MCP import)을 `to-codex.sh`
  스캐폴드 변환의 대안으로 검토.
- P7: `bathos runtime` 추상화(런타임 감지→어댑터 자동 선택).

## 출처
- prompts/slash: developers.openai.com/codex/custom-prompts · /guides/slash-commands
- hooks(이벤트·exit2·실험적·Windows): learn.chatgpt.com/docs/hooks · codex.danielvaughan.com(2026-04)
- subagents(TOML·max_depth): learn.chatgpt.com/docs/agent-configuration/subagents
- config/MCP/AGENTS.md: developers.openai.com/codex/config-reference
- responses-only·프로바이더: learn.chatgpt.com/docs/config-file/config-reference · github.com/openai/codex/discussions/7782
- Codex+GLM 프록시: github.com/openai/codex/issues/9612 · KevinSHH/codex-glm-proxy · MetaFARS/codex-relay
