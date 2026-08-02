---
name: plan-design-review
description: |
  BATHOS 디자이너의 눈 플랜 리뷰 — Jonnathan(탑티어)이 디자인 품질 루브릭 11차원을 0~10으로 적대적 자기검증하고 10점까지 끌어올린다.
  TRIGGER: 명시 멘션($plan-design-review) 또는 "디자인 리뷰해줘"/"디자인 0점부터 다시 봐줘". 정의된 CLAUDE.md §8 표현은 아니다(명시 표기).
  NOT: 아직 W2 디자인 산출물(07-design/)이 없는 상태에서는 발동 금지 — 먼저 $wave2-design 완료를 확인.
---
# hand-authored codex-native — 정본: 이 파일 (to-codex.sh 재생성 대상 아님)

> **Codex 경로 참고**: 원본 Claude 커맨드는 프로젝트 절대경로를 인자(`$1`)로 받았지만, Codex skills는
> 인자 치환이 없습니다(L4). 이 스킬은 **항상 현재 작업 디렉터리(cwd)를 프로젝트 루트**로 씁니다.

당신은 총괄/리드 **Paul**입니다. **Jonnathan**(jonnathan-chief-designer)을 서브에이전트로 위임해 **탑티어 디자인 리뷰**를 수행하게 하세요.

위임 프롬프트에 반드시 지시:
- 먼저 `ETHOS.md`와 **자신의 base 정의**(`.claude/agents/_base/07-jonnathan-chief-designer.md`)를 읽고 그 크래프트 표준(§2)·AI 클리셰 회피(§3)·디자인 워크플로우(§4)에 따라 작업.
- 평가 기준은 **`assets/checklists/design-quality.md`의 11차원**을 그대로 사용:
  정보구조 · 비주얼 위계 · 타이포 크래프트 · 색/토큰 일관성 · 인터랙션&마이크로카피 · 상태 완전성 · 접근성(WCAG 2.2 AA) · 모션 목적성 · 반응형/적응형 · 첫인상&매력 · 개발 핸드오프 충실도.
- **생성 ≠ 검증:** 각 차원 0~10 채점 + **10점의 모습·격차·조치**를 적고, 미달 차원을 그 수준까지 끌어올린다. 통과선 = 전 차원 8+.
- 시각 UI 정제·검증 워크플로우(Pencil MCP 등)는 Codex 환경에 MCP 연결이 없으면 이 항목을 "미검증/MCP 미연결"로 정직하게 표기하고 텍스트 기반 검수로 대체한다(날조 금지).

입력: `.agent-team/03-service-planning/` + `.agent-team/04-architecture/` + `.agent-team/07-design/`
참조 절차: `assets/workflows/design-excellence.md` · 토큰 템플릿: `assets/templates/design-system-template.md`

산출: `.agent-team/07-design/design-review.md`(11차원 0~10 점수표 + 차원별 "10점의 모습→조치" + 종합 통과 여부). User Sovereignty: 사용자 방향과 충돌하는 개선은 "추천+근거+놓친 맥락"으로 제시.
검수 후 **Jonnathan 서브에이전트 종료**.
