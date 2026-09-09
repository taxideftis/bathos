# AGENTS — 역할 & 커맨드 인덱스 (17역할 · 7웨이브 · BATHOS, gstack 보강판)

> **BATHOS**(그리스어 βάθος = '깊이·심연') — 표층 지식과 대비되는 압도적 깊이의 AI Workflow Agent. BMAD-METHOD v6 리버스 흡수로 14역할·5웨이브 → 17역할·7웨이브 진화.
> 운영 규칙 상세는 `CLAUDE.md`, 운영 철학은 `ETHOS.md`(gstack 적응), 출처는 `CREDITS.md`. 모든 팀원은 스폰 시 ETHOS를 숙지합니다. "BMAD/BMad" 상표 사용 금지.
> **전체 슬래시 커맨드(35개) 카테고리별 레퍼런스: [`docs/COMMANDS-kr.md`](docs/COMMANDS-kr.md).** 아래는 핵심 요약.
> **멀티 런타임(Codex·GLM) 포터빌리티:** 판단·계획 [`docs/PORTABILITY-kr.md`] · GLM 백엔드 [`docs/glm-backend-kr.md`] · Codex 어댑터 [`docs/codex-adapter-kr.md`]. 요약 — GLM=모델 스왑(쉬움, `scripts/glm-env.sh`), Codex=런타임 포팅(어려움, `scripts/to-codex.sh` 변환 스캐폴드). `bathos` 엔진은 런타임 독립.

## 역할(서브에이전트) — `.claude/agents/`
Paul(0·리드/CEO렌즈) · John(1·리버스) · Caleb(2·시장분석 +W0 Analyst 겸임) · Joshua(3·기획) · James(4·아키텍트) · Mark(5·IP) · Nathanael(6·논문) · Jonnathan(7·디자인) · Phillip(8·백엔드) · Andrew(9·프론트) · Stephen(10·ML) · Timothy(11·문서) · Thomas(12·리뷰) · **Michael(13·보안, 방어적 웹·사이버 보안 감사·하드닝, 신규)** · Hananiah(14·리팩토링, 동작보존) · Matthias(15·QA) · Martin(16·리포트) · **Matthew(17·Story Engineer, 스토리파일+W3 게이트)**.
- 모델: opus=Opus 4.8(Paul·John·Caleb·Joshua·James·Mark·Jonnathan·**Matthew**), sonnet=Sonnet 5(나머지, **Michael 포함**).
- **#17 Matthew(Story Engineer)는 평시 비가동**, W3 활성 시에만 스폰.
- **#13 Michael(Security Specialist)은 W6에서 Thomas 리뷰 이후** 스폰 — 방어적 보안 감사·하드닝(무해성·승인 경계·인간 승인 게이트).

## 웨이브 커맨드 — `.claude/commands/`
| 커맨드 | 웨이브 | 설명 | 게이트 |
|--------|--------|------|--------|
| `/team-kickoff` | (사전) | 계획/charter/.agent-team 골격 | — |
| `/wave0-analysis` | **W0** | Analysis(선택·전단) — Caleb(Analyst 겸임) brainstorm/forge/brief | Brief Readiness |
| `/wave1-discovery` | W1 | John+Caleb (리버스·시장) | USP Readiness |
| `/wave2-design` | W2 | Joshua→James,Jonnathan (기획·아키·디자인) | Plan Readiness |
| `/wave3-story-gate` | **W3** | Matthew(Story Engineer) 스토리파일 응축 + Thomas·Matthias 독립리뷰 | **Implementation Readiness (이중)** |
| `/wave3-ip-research` | W4 | Mark+Nathanael (IP·논문, 선택·비본류 플러그) | — |
| `/wave4-implement` | W5 | Phillip+Andrew+Stephen (구현) | 스토리 완료검증 |
| `/wave5-verify-report` | W6 | Thomas+Timothy+Matthias→Michael(보안)→Hananiah(리팩토링)→Martin (검증·문서·리포트) | Release Readiness |
| `/team-confirm` | (사후) | 최종 confirm + cleanup | — |
| `/team-status` `/team-cleanup` | — | 현황 점검 / 정리 | — |

> **명령어 정합 메모:** 기존 스킬 파일명(`/wave3-ip-research`,`/wave4-implement`,`/wave5-verify-report`)은 구 5웨이브 번호 유지 — 위 표대로 W4/W5/W6에 매핑됩니다. 차기 정리에서 신규 번호로 리네임 예정.

## W5 구현 규율 — 사다리(Ladder)
W5 구현자(Phillip·Andrew·Stephen)는 스폰 시 **구현 규율**을 함께 주입받는다. 7단 사다리(①존재해야 하는가 →②이미 있는가 →③표준 라이브러리 →④플랫폼 네이티브 →⑤설치된 의존성 →⑥한 줄 →⑦최소 코드)가 **무엇을 만들지**를, ETHOS *Boil the Ocean*이 **정한 범위의 완전성**을 지배한다 — 검증·에러 처리·보안·접근성·테스트는 사다리로 자르지 않는다. 천장 있는 단순화는 `ponytail: <ceiling>, <upgrade path>`(영어) 마커를 남기고 `/bathos-debt`가 문서의 `CONCERNS:`와 함께 수집한다. 강도: `/bathos intensity <lite|full|ultra|off>`(기본 `full`).
정본 `.claude/agents/_preamble/ponytail-inject-kr.md` (보조 번역 `-en`·`-ja`·`-es`) · 출처 고지 `CREDITS.md`.

## 게이트 용어 (통일)
**PASS**(즉시 진입) / **CONCERNS**(리스크 로그 후 진행) / **FAIL**(차단·재게이트). 게이트는 FACILITATOR — 근거 없는 자동 PASS 금지. 핵심 게이트(W3)는 훅으로 하드 강제.

## Scale-Adaptive (Lv0~4)
작업 규모로 가동 웨이브 조절: Lv0=W5만 / Lv1=경량 W2+W3축약+W5+W6 / Lv2=W1~W3+W5+W6 / Lv3=W0~W6 / Lv4=전체+W4 풀. 현재 Lv는 `_state/manifest.json`. 상세: `CLAUDE.md` §2.5.

## plan-mode 리뷰 게이트 (gstack)
`/plan-ceo-review` · `/plan-design-review` · `/plan-eng-review` · `/plan-devex-review` · `/autoplan`(넷을 순차).

## 구현·리뷰·운영 (gstack)
`/review`(랜딩 전 리뷰) · `/investigate`(근본원인) · `/cso`(보안 감사) · `/retro`(회고) · `/health`(품질 대시보드) · `/context-save` · `/context-restore`.

## 안전·스코핑 (gstack)
`/guard`(careful+freeze 활성) · `/unfreeze`(잠금 해제). careful는 `PreToolUse` 훅으로 파괴적 명령을 차단.

## 세션·메모리·원격 (BATHOS)
- **세션 저장/복원:** `/save-session`(정본, 별칭 `/save`) → 다음 세션 `/cold-start`(정본, 별칭 `/resume`)로 무손실 복원. gstack 레거시 `/context-save`·`/context-restore` 동일 `_state`.
- **크로스-프로젝트 메모리:** `/project-handoff`(전역 레지스트리 upsert) · `/recall`(이전 프로젝트 warm-start).
- **리포트:** `/taskreport`(온디맨드 HTML) · 세션별 정식 리포트는 `result_report/generate-task-report.sh`(session_no 자동 증가·6항목).
- **라우팅/현황:** `/route`(Lv0~4 확정) · `/team-status` · `/team-cleanup`.
- **원격 개발:** `/remote-dev`(Remote Control 셋업·가이드 — 내 머신 세션을 폰/웹에서 조종, `_state`·안전훅 유지). ⚠️ 클라우드형(Web/Routines)은 fresh clone이라 BATHOS 상태·훅 부재 → 파이프라인 부적합. 상세 비교: `docs/COMMANDS-kr.md`.
- **교육:** `/lecture`(David 튜터 강의안 생성).

## Codex 팀 실행 오케스트레이션 (Codex CLI 전용 — Claude Code Agent Teams에는 미적용)

> Codex에는 Claude Code의 Agent Teams 같은 별도 오케스트레이터 프로세스가 없습니다 — **이 절 자체가
> 오케스트레이터**입니다(ADR-CX-04 결정 2항). Codex가 루트 지침으로 이 파일을 읽으므로, 여기 적힌
> 규칙이 곧 팀 실행 런타임 규칙입니다. 표준 문구 정본: `.agent-team/08-impl-notes/stephen-orchestration.md`
> (각 `.codex/agents/*.toml`의 `developer_instructions`도 동일 문구를 중복 인용합니다 — 이중 방어).

- **W2 순차 게이트(스폰 분할 패턴)**: Joshua 단독 스폰 → 산출 파일 확인(`.agent-team/03-service-planning/*` 존재·비어있지 않음 확인) → James∥Jonnathan 병렬 스폰. 다른 웨이브도 이 패턴(게이트 역할 단독 선행 → 산출 확인 → 병렬)을 따르세요.
- **동시 활성 ≤3**: `[agents] max_concurrent_threads_per_session = 3`([문서확정] — Codex 공식 subagents 문서 `[agents]` 전역 설정 테이블. 라이브 효력 자체는 ⚠️미검증)로 설정하세요. 이 상한은 상류 기술 한계 추종이 아니라 **BATHOS의 토큰 비용 정책**(CLAUDE.md §0)입니다 — 상류가 더 높은 동시성을 허용하더라도 BATHOS 웨이브 운영은 3을 넘기지 않습니다.
- **중첩 스폰 금지(물리 차단 아님 — 정직 표기)**: 서브에이전트로 스폰된 팀원은 추가로 서브에이전트를 스폰하지 마세요. `max_depth` 류 config 강제 상한이 현재 Codex 공식 문서에서 확인되지 않아(D3), 남은 방어선은 **이 절 + 각 TOML의 developer_instructions 이중 명기**뿐입니다(지침 강제 — 위반을 코드로 막지 않습니다). 준수 여부는 SubagentStart 로그로 사후 검증하세요. (향후 실측에서 `max_depth`가 복원되면 config 3중 방어로 승격 — 재검토 트리거.)
- **산출물 = 디스크 파일 강제**: 서브에이전트의 반환값은 리드에게 오는 **요약뿐**입니다 — 요약을 원본으로 신뢰하지 말고, 항상 소유 경로의 디스크 파일을 산출물의 SSOT로 삼으세요. 스폰 지침에 "결과는 파일로 남기고, 반환 요약에는 그 경로를 적을 것"을 포함하세요.
- **모델 지정(Codex custom agent file 계약)**: 공식 subagents 문서 기준, custom agent TOML이 `model`/`model_reasoning_effort`를 지정하면 그 값이 spawn 시점 값보다 우선합니다. BATHOS 역할별 매핑은 `.agent-team/08-impl-notes/stephen-model-mapping.md`가 정본입니다. **런타임 버전(리드 확정)**: Codex CLI **v0.145.0 이상**을 전제로 합니다(PR #32749로 model/reasoning_effort 오버라이드가 기본 복원된 릴리스). **알려진 잔존 제약(⚠️커뮤니티 재현·비[LIVE])**: 상위 그룹 모델(`gpt-5.6-sol`)이 부모일 때는 v0.145.0+에서도 자식 서브에이전트가 named custom-agent 파일(`agent_type` 선택)을 자동으로 고르지 못하고 부모 설정을 상속할 수 있습니다(OpenAI Codex GitHub Issue #31814 계열의 후속 PR 미확인, 2026-07). 완전 해소하려면 사용자가 직접 `~/.codex/config.toml`에 `[features.multi_agent_v2] hide_spawn_agent_metadata = false`를 설정해야 합니다(저장소가 자동 편집하지 않음 — 설치 안내는 W6 `docs/codex-adapter-kr.md`). 회피책·근거 전문은 `stephen-model-mapping.md` §3~§4를 참조하세요.

### 운영 수칙 L1/L2/L3 (UX 패리티 격차 고지 — `ux-parity-limits.md`)

- **L3(중간 지시 불가)**: Codex 팀원에게는 중간 지시를 보낼 수 없습니다. 지시는 스폰 시 완결하고, 수정은 재스폰으로 하세요(스폰 프롬프트 자족성 — W3 Matthew의 스토리 응축이 Codex에서 더 중요해지는 구조적 이유입니다).
- **L1/L2(자동 종료 절차 부재)**: Codex에는 SessionEnd 훅 3단 종료(저장→리포트→종료)가 없습니다. 작업 마무리 전 `$save-session` 실행을 권장합니다.

## 권장 흐름
`/team-kickoff` → `/wave0-analysis`(선택) → `/wave1-discovery` → `/wave2-design` *(필요 시 `/autoplan`로 락인)* → **`/wave3-story-gate`**(PASS/CONCERNS면 진입) → `/wave3-ip-research`(W4·선택) → `/wave4-implement`(W5) → `/wave5-verify-report`(W6) → `/team-confirm`. 위험 작업 전 `/guard`. (규모에 따라 scale-adaptive로 일부 웨이브 생략.)
