# PROBE-RESULTS — Codex CLI 0.145.0

> 생성: 2026-07-23 16:38:10 +0900 · probe.sh (CT-PROBE, story-03)
> 이 리포트는 재현 가능한 실측 기록이다 — 미실측 항목은 날조하지 않고 정직 표기한다.

## ① codex --version / features list

- codex 바이너리: `/Users/parkjunha/.local/bin/codex`
- --version 원문: `codex-cli 0.145.0`

```
apply_patch_freeform                 removed            false
apply_patch_streaming_events         under development  false
apps                                 stable             true
apps_mcp_path_override               removed            false
artifact                             under development  false
auth_elicitation                     stable             true
browser_use                          stable             true
browser_use_external                 stable             true
browser_use_full_cdp_access          stable             true
chronicle                            under development  false
code_mode                            under development  false
code_mode_buffered_exec              under development  false
code_mode_host                       stable             true
code_mode_only                       under development  false
codex_git_commit                     removed            false
collaboration_modes                  removed            true
computer_use                         stable             true
concurrent_reasoning_summaries       under development  false
current_time_reminder                under development  false
default_mode_request_user_input      under development  false
deferred_executor                    under development  false
elevated_windows_sandbox             removed            false
enable_fanout                        removed            false
enable_mcp_apps                      under development  false
enable_request_compression           stable             true
exec_permission_approvals            under development  false
executor_capability_discovery        under development  false
experimental_windows_sandbox         removed            false
external_agent_memory_import         under development  false
external_migration                   removed            false
fast_mode                            stable             true
goals                                stable             true
guardian_approval                    stable             true
hooks                                stable             true
image_detail_original                removed            false
image_generation                     stable             true
in_app_browser                       stable             true
item_ids                             under development  false
js_repl                              removed            false
js_repl_tools_only                   removed            false
local_thread_store_compression       under development  false
memories                             stable             false
mentions_v2                          stable             true
multi_agent                          stable             true
multi_agent_mode                     removed            false
multi_agent_v2                       stable             false
network_proxy                        experimental       false
non_prefixed_mcp_tool_names          under development  false
personality                          stable             true
plugin_hooks                         removed            false
plugin_sharing                       stable             true
plugins                              stable             true
prevent_idle_sleep                   experimental       false
realtime_conversation                under development  false
remote_compaction_v2                 stable             true
remote_control                       removed            false
remote_models                        removed            false
remote_plugin                        stable             true
request_permissions_tool             under development  false
request_rule                         removed            false
resize_all_images                    removed            true
respect_system_proxy                 under development  false
responses_websockets                 removed            false
responses_websockets_v2              removed            false
rollout_budget                       under development  false
runtime_metrics                      under development  false
search_tool                          removed            false
secret_auth_storage                  stable             false
shell_snapshot                       stable             true
shell_tool                           stable             true
shell_zsh_fork                       under development  false
skill_env_var_dependency_prompt      removed            false
skill_mcp_dependency_install         stable             true
skill_search                         stable             true
sqlite                               removed            true
standalone_web_search                under development  false
steer                                removed            true
terminal_resize_reflow               removed            true
terminal_visualization_instructions  under development  false
token_budget                         under development  false
tool_call_mcp_elicitation            stable             true
tool_search                          removed            false
tool_search_always_defer_mcp_tools   removed            true
tool_suggest                         stable             true
tui_app_server                       removed            true
unavailable_dummy_tools              removed            false
undo                                 removed            false
unified_exec                         stable             true
unified_exec_zsh_fork                under development  false
use_agent_identity                   under development  false
use_legacy_landlock                  deprecated         false
use_linux_sandbox_bwrap              removed            false
web_search_cached                    deprecated         false
web_search_request                   deprecated         false
workspace_dependencies               stable             true
workspace_owner_usage_nudge          removed            false
```

## ② 평탄형/중첩형 훅 스키마 라이브 재실측 (D1 종결 절차)

에코 훅 준비 완료: `/var/folders/03/7nczct994755b2s1_tk_02600000gn/T//bathos-probe-echo.dIb5VI`

수동 절차(자동화 불가 — 인증 세션 필요, 라이브 1턴 요구):
1. 임시 프로젝트(또는 이 저장소 사본)에서 평탄형 스키마로 `echo-flat.sh`를,
   중첩형 스키마로 `echo-nested.sh`를 각각 PreToolUse에 등록한다.
2. 아무 도구나 1회 호출해 어느 쪽이 stderr에 stdin을 찍는지 관찰한다.
3. 발화한 쪽의 스키마(평탄형=timeoutSec 낱개 필드 / 중첩형=hooks.<E>.hooks[]+timeout)로
   방출물(config.toml.example·.codex/hooks.json)을 그 스키마로 고정한다(D1 종결).

결과: [미실측 — 인증 세션 필요]

## ③ 관측 tool_name vs matcher 커버리지

- matcher 정본(story-01, 6종): `Bash shell exec_command apply_patch Edit Write`
- 관측된 tool_name: [미실측 — 라이브 1턴 필요, ②와 동시 수행 권장]
- 판정: [미실측 — 라이브 1턴에서 관측된 tool_name을 check_tool_name_coverage로 대조 필요]

## ④ 훅 컨텍스트 env 키 존재 여부 (PLUGIN*/CLAUDE_*, 값 비기록)

- 이 실행(비-훅 컨텍스트)에서 관측: `CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_EXECPATH CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS CLAUDE_CODE_SESSION_ID CLAUDE_EFFORT `
- R-RT1 해소는 실제 훅 실행 컨텍스트에서 관찰해야 한다 — echo-flat.sh/echo-nested.sh가
  등록 상태에서 발화할 때 함께 출력하는 `env-keys:` 줄을 여기 옮겨 적을 것.

## ⑤ .codex/hooks.json 단독 발화 · trust 절차

- 파일 상태: 존재·유효 JSON
- 발화 여부(유저 config 무편집 상태에서): [미실측 — 인증 세션 필요, US1-AC3]
- trust 프롬프트 절차: [미실측 — 관찰 기록 필요]

## 종합 판정

- 정적 확인 항목(①·hooks.json 파스)은 위 기록대로. 라이브 1턴이 필요한 항목(②·③·④·⑤)은
  이 스크립트 단독으로 종결되지 않는다 — 인증 세션에서 수동 절차를 따른 뒤 이 파일을
  직접 갱신하거나 재실행 결과로 대체할 것(리포트가 정본 — 오염 시 CT-PROBE 체제 붕괴).
