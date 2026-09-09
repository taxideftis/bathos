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

## 권장 흐름
`/team-kickoff` → `/wave0-analysis`(선택) → `/wave1-discovery` → `/wave2-design` *(필요 시 `/autoplan`로 락인)* → **`/wave3-story-gate`**(PASS/CONCERNS면 진입) → `/wave3-ip-research`(W4·선택) → `/wave4-implement`(W5) → `/wave5-verify-report`(W6) → `/team-confirm`. 위험 작업 전 `/guard`. (규모에 따라 scale-adaptive로 일부 웨이브 생략.)
