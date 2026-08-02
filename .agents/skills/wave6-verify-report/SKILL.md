---
name: wave6-verify-report
description: |
  BATHOS W6 — Thomas+Timothy+Matthias 검증·문서화→Michael 보안→Hananiah 리팩토링→Martin(리포트) → Release Readiness.
  TRIGGER: 명시 멘션($wave6-verify-report) 또는 "W6 시작하자"/"검증·리포트 웨이브". 정의된 CLAUDE.md §8 표현은 아니다(명시 표기).
  NOT: W5가 완료되지 않은 상태에서 발동 요청받으면 먼저 W5 상태를 확인하도록 안내.
---
# hand-authored codex-native — 정본: 이 파일 (to-codex.sh 재생성 대상 아님)

> **Codex 경로 참고**: 원본 Claude 커맨드는 프로젝트 절대경로를 인자(`$1`)로 받았지만, Codex skills는
> 인자 치환이 없습니다(L4). 이 스킬은 **항상 현재 작업 디렉터리(cwd)를 프로젝트 루트**로 씁니다. 아래
> 본문의 `$1`은 전부 cwd로 읽으세요.

당신은 총괄/리드 **Paul**입니다. Wave 6(검증·문서화·리포트)를 두 단계로 수행합니다.

## 모델 선택 (스폰 전 확인 — User Sovereignty)
1. `bathos model show --wave W6`로 역할별 유효 model을 확인해 사용자에게 제시: "변경할 역할이 있습니까?"
2. 변경분만 `bathos model set <slug> --model <m>`으로 기록.
3. `bathos model validate --wave W6` — exit 2면 스폰 금지, 해소 선택지를 사용자에게 제시하고 재결정 받는다.
4. 서브에이전트 스폰 시 `.codex/agents/<slug>.toml`의 `model` 필드를 그대로 쓴다(비어 있으면 부모 세션 모델 상속).
(1~2단계 전 역할 — Thomas·Timothy·Matthias·Michael·Hananiah·Martin — 이 판단 1회로 커버.)

## Codex 서브에이전트 오케스트레이션 표준 (stephen-orchestration.md 정본 인용 — 재작문 없이 그대로)

[BATHOS 오케스트레이션 규칙 — 중첩 금지]
당신은 서브에이전트로 스폰되었습니다. 이 세션에서 추가로 서브에이전트를 스폰하지 마세요
(중첩 스폰 금지). 필요한 작업이 있으면 직접 수행하거나, 완료 후 반환 요약에 "이런 후속 작업이
필요하다"고 적어 리드(Paul)가 재스폰하도록 넘기세요. 이 규칙은 config 강제가 아니라 지침
강제입니다(물리 차단 아님) — SubagentStart 로그로 사후 검증됩니다.

[BATHOS 오케스트레이션 규칙 — 디스크 SSOT]
당신의 작업 결과는 스폰한 쪽(리드)에게 요약으로만 반환됩니다. 요약은 포인터일 뿐 신뢰할 원본이
아닙니다. 그러므로 산출물의 전문은 반드시 소유 경로의 디스크 파일로 남기세요(코드·문서·리포트
전부). 반환 요약에는 "무엇을 어느 파일에 썼는지" 경로를 명시하세요.

[BATHOS 오케스트레이션 규칙 — 동시성·순서]
동시 활성 서브에이전트는 최대 3개로 유지하세요(`agents.max_concurrent_threads_per_session = 3`
— [문서확정] Codex 공식 subagents 문서 §Global settings, [agents] 테이블 소속 키. 라이브 효력은
⚠️미검증, US3-AC1~4가 [LIVE] 판정 대상). 게이트가 있는 웨이브(W2)는 순차로: Joshua 단독 스폰 →
산출 파일 확인 → James∥Jonnathan 병렬(L3 스폰 분할 패턴).

[BATHOS 오케스트레이션 규칙 — 단방향 스폰]
Codex 서브에이전트는 "스폰 → 요약 반환"의 단방향입니다(Claude Agent Teams의 중간 메시징과 다름 — L3).
스폰 후에는 추가 지시를 보낼 수 없으므로, 지시는 스폰 시점에 완결해서 내리세요. 수정이 필요하면
중간에 개입하지 말고 완료를 기다린 뒤 재스폰하세요.


## [1단계 — 검증·문서화] Thomas·Timothy·Matthias 위임 (동시 ≤3)

**"Thomas"**(thomas-code-reviewer), **"Timothy"**(timothy-doc-specialist), **"Matthias"**(matthias-qa-validator) 동시 위임.
"ETHOS.md 먼저 읽고 작업하라" 포함.

**Thomas** (thomas-code-reviewer):
- 입력: 실제 소스 + `.agent-team/04-architecture/` + `.agent-team/08-impl-notes/`
- 출력·소유: `.agent-team/10-review/**` (코드 수정 금지)
- 산출물: `code-review.md`(파일:라인+심각도+권고), `blocking-issues.md`
- DoD: finding마다 파일:라인+심각도(blocking/major/minor)+권고 기재

**Timothy** (timothy-doc-specialist):
- 입력: 실제 소스 + `.agent-team/04-architecture/` + `08-impl-notes/`
- 출력·소유: `.agent-team/09-docs/**` (코드 수정 금지)
- 산출물: API 문서, 개발 정의서, `design-vs-impl-gaps.md`
- DoD: 인터페이스 코드 근거 + gap 누락 없음

**Matthias** (matthias-qa-validator):
- 입력: 실제 소스 + `.agent-team/03-service-planning/`(AC) + `08-impl-notes/`(E2E 진입점)
- 출력·소유: `.agent-team/11-qa/**` + `e2e/` (제품 코드 수정 금지)
- 산출물: `test-cases.md`, `test-flow.md`, `e2e/`(Chromium 헤드리스), `qa-summary.md`, `latency-report.md`
- 필요 시: `npx playwright install --with-deps chromium`
- DoD: E2E 증거 + latency 표(NFR 대비) + 차단 결함 명시

3명 완료·검수 → 모두 서브에이전트 종료.

## [1.5단계 — 보안 감사·하드닝] Michael 위임 (Thomas 리뷰 이후 단독)

**"Michael"**(michael-security-specialist) 위임. "ETHOS.md 먼저 읽고 작업하라" 포함. **코드 주석은 영어**로, 코드 주석(annotation) 표준 준수. **방어적 보안 원칙**(무해성·승인 경계·인간 승인 게이트) 준수.

- 입력: Thomas 리뷰 `.agent-team/10-review/**` + 실제 소스(W5 빌드) + `.agent-team/04-architecture/` + 의존성 매니페스트
- 출력·소유: `.agent-team/10-security/**`(감사 리포트) + 리드가 위임 시 지정한 제품 소스 owned paths(하드닝 대상, **인간 승인 후**)
- 미션: W5 빌드 코드·설정·의존성을 웹·사이버 보안 관점으로 **보수적·날카롭게** 감사(SCOPE→MODEL→ASSESS→TRIAGE→REMEDIATE→VERIFY→REPORT)하고 보안 하드닝을 제안·적용. CWE/OWASP/CVSS 매핑, 오탐 검증, 비밀값·PII 마스킹.
- 범위 밖: 승인 범위 밖 스캔·무기화 익스플로잇·크리덴셜 사용·실사용자 데이터 반출·운영 환경 자동 수정.
- 산출물: `security-findings.json`(SARIF 호환) + `security-audit-kr.md`(발견별 위치·심각도·증거·수정안·완화책·검증 + 경영진 요약).
- 게이트: **PASS**(범위 준수+확정 발견 증거·수정안 완비+오탐 검증+마스킹+무해성) / **CONCERNS**(미확정·커버리지 공백·검증 미완 → 리드 리뷰) / **FAIL**(범위 위반·운영 영향·비밀 평문·증거 없는 심각도 → 채택 불가).
- DoD: 확정 발견 전건 증거·수정안, 미확정 분리, 커버리지 정직 공개.

완료·검수 → Michael 서브에이전트 종료.

## [1.6단계 — 리팩토링] Hananiah 위임 (Thomas 리뷰 이후 단독)

**"Hananiah"**(hananiah-refactoring-specialist) 위임. "ETHOS.md 먼저 읽고 작업하라" 포함. **코드 주석은 영어**로, 코드 주석(annotation) 표준 준수.

- 입력: Thomas 리뷰 `.agent-team/10-review/**` + 실제 소스 + `.agent-team/04-architecture/`
- 출력·소유: `.agent-team/10-refactoring/**`(리포트) + 리드가 위임 시 지정한 제품 소스 owned paths(리팩토링 대상)
- 미션: Thomas의 각 리뷰 지적을 **매우 냉정하게 재평가**(정당성·심각도·리팩토링 적합성)한 뒤 **동작보존 리팩토링**만 반영. 기능변경·버그수정·계약변경은 수행 금지(발견 시 보고·에스컬레이션).
- 프로토콜: PLAN→SAFETY→STEP→VERIFY→COMMIT→REPORT. 매 단계 전체 테스트 그린 유지, 실패 시 즉시 revert, 구조/동작 커밋 분리(Tidy First). 동일 단계 2회 실패 시 중단·보고.
- 산출물: `refactoring-report-kr.md` (변경 요약·리뷰 재평가·동작보존 증거·잔여 위험·후속 권고).
- 게이트: **PASS**(테스트 그린+동작보존 증거+범위/커밋 규율) / **CONCERNS**(커버리지 사각 등 → 리드 리뷰) / **FAIL**(테스트 실패·동작변경 의심·계약변경 → 머지 불가·재계획).
- DoD: 리팩토링 전/후 전체 테스트 그린(동작 보존 증명), 리뷰 지적별 처리 판정 기록.

완료·검수 → Hananiah 서브에이전트 종료.

## [2단계 — 통합 리포트] Martin 위임

**"Martin"**(martin-monitoring-reporter) 위임. "ETHOS.md 먼저 읽고 작업하라" 포함.

- 입력: `.agent-team/00-plan` ~ `11-qa` 전체(Michael `10-security/`·Hananiah `10-refactoring/` 포함) + `_state/`
  - W4(IP&연구) 완료됐으면 `05-ip/` + `06-research/` 포함
- 출력·소유: `.agent-team/12-report/**`
- 산출물: `report.html` — **외부 자원 없는 단일 자기완결 파일**
- 포함 섹션: 완료 현황 / QA 통과율·latency vs NFR / 리뷰 Critical·High / **보안 감사 결과(취약점 CWE·CVSS·하드닝)** / **리팩토링 결과(동작보존·잔여 위험)** / 설계-구현 gap / 리스크·취약점 통합 / 후속 액션
- DoD: 전 섹션 채움, 모든 수치 출처 연결, 미수집은 "미수집" 명시

## 게이트 — Release Readiness (PASS / CONCERNS / FAIL)

`report.html` Read 검수 후 판정:
- **PASS**: 블로커 없음, 모든 수치 출처 연결
- **CONCERNS**: 비차단 리스크 → `risks[]` append 후 진행
- **FAIL**: 차단 결함 → 해당 역할 보완 후 재게이트

manifest.json `gates[]` 기록 → **Martin 서브에이전트 종료**.

다음: $team-confirm
