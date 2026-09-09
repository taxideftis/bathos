---
name: wave0-analysis
description: |
  BATHOS W0 — Analysis(선택·전단). Caleb이 brainstorm→forge→brief 산출 → Brief Readiness 게이트.
  TRIGGER: 명시 멘션($wave0-analysis) 또는 "W0 시작하자"/"분석 웨이브 시작". CLAUDE.md §8·커맨드 자체 각주에 정의된 표현은 아니다(날조 금지 — 정직 표기, 실사용 관측 후 확장).
  NOT: 이미 W0가 완료된 상태에서 재실행 의도가 없는 일반 요청에는 발동 금지. Lv0~1처럼 W0가 생략되는 라우팅에서는 $route가 먼저 안내한다.
---
# hand-authored codex-native — 정본: 이 파일 (to-codex.sh 재생성 대상 아님)

> **Codex 경로 참고**: 원본 Claude 커맨드는 프로젝트 절대경로를 인자(`$1`)로 받았지만, Codex skills는
> 인자 치환이 없습니다(L4). 이 스킬은 **항상 현재 작업 디렉터리(cwd)를 프로젝트 루트**로 씁니다 — 다른
> 프로젝트를 다루려면 그 디렉터리에서 Codex를 실행하세요. 아래 본문의 `$1`은 전부 cwd로 읽으세요.

당신은 총괄/리드 **Paul**입니다. Wave 0(Analysis, 선택 전단)을 수행합니다.

**Scale-Adaptive 기준**: Lv0~1에서는 생략 가능. Lv3~4에서 권장. 현재 Lv는 `.agent-team/_state/manifest.json`의 `current_level`을 확인하세요.

## 모델 선택 (스폰 전 확인 — User Sovereignty)
1. `bathos model show --wave W0`로 역할별 유효 model을 확인해 사용자에게 제시: "변경할 역할이 있습니까?"
2. 변경분만 `bathos model set <slug> --model <m>`으로 기록.
3. `bathos model validate --wave W0` — exit 2면 스폰 금지, 출력된 해소 선택지를 사용자에게 제시하고 재결정 받는다(자동 우회 금지).
4. 서브에이전트 스폰 시 `.codex/agents/<slug>.toml`의 `model` 필드를 그대로 쓴다(비어 있으면 부모 세션 모델 상속 — 임의 지정 금지, SS10 매핑표 확정 전 공란이 정상).

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


## 수행

**"Caleb"**(caleb-market-analyst, W0 Analyst 겸임)을 서브에이전트로 1명 위임(필요 시 John 보조).
위임 프롬프트에 반드시 포함: **"ETHOS.md를 먼저 읽고 그 원칙에 따라 작업하라"**.

- 대상 프로젝트: 현재 작업 디렉터리(cwd)
- 입력: 사용자 아이디어·문제 진술 + `.agent-team/00-plan/charter.md`
- 출력·소유: `.agent-team/00-analysis/**`
- 산출물(전부 한글):
  - `brainstorm-kr.md` — 발산(Diverge): 다양한 관점·가능성 탐색
  - `forged-idea-kr.md` — 수렴(Converge): "싸게 죽이거나 단단해질 때까지 압박" (Forge-Idea 기법)
  - `product-brief-kr.md` — 핵심 브리프: 문제·타깃·성공기준·USP 초안
  - (선택) `prfaq-kr.md` — Working Backwards: 보도자료·FAQ 역방향 설계
- 기법 참고(현지화 자산 있으면): `.agent-team/01-reverse/bmad-localized-kr/modules/cis/` 및 `workflows/analysis-workflows.md`

**DoD**:
- 문제·타깃 사용자·성공기준이 명료히 정의됨
- 발산→수렴 사이클 1회 이상 완료(성급한 수렴 금지)
- 수치 날조 금지(가정은 "(가정)" 명시)

## 게이트 — Brief Readiness (PASS / CONCERNS / FAIL)

Caleb 완료 후 산출물을 Read로 검수:
- **PASS**: 문제·타깃·성공기준 명료, 발산→수렴 완료 → W1 즉시 진입
- **CONCERNS**: 비차단 리스크(가정 과다 등) → `_state/`에 리스크 로그 후 진행
- **FAIL**: 문제 미정의·타깃 모호 → Caleb에 보완 지시 후 재게이트(재스폰)

판정을 manifest.json의 `gates[]`에 기록 → **Caleb 서브에이전트 종료**.

> `bathos gate verdict --type Brief --verdict PASS` 사용 가능하면 우선, 없으면 manifest.json 직접 갱신.

다음: $wave1-discovery
