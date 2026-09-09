# BATHOS 자산 레지스트리 인덱스 (M9)

> 작성: Timothy(BATHOS Doc Specialist) · 2026-06-29
> 목적: `bathos/assets/`의 모든 제품용 자산을 카탈로그화. 신규 자산 추가 시 이 인덱스도 갱신.

---

## 개요

`bathos/assets/`는 BATHOS 패키지의 **현지화 자산 레지스트리(M9)**입니다.
원천: `.agent-team/01-reverse/bmad-localized-kr/` (John이 BMAD-METHOD를 역분석·현지화)
제품 배치: Timothy가 핵심 자산을 선별·정합 후 이 경로에 배치.

---

## 자산 목록

### 📄 템플릿 (`templates/`)

| 파일 | 용도 | 주 사용 역할 | 원천 경로 |
|------|------|------------|----------|
| `story-template.md` | W3 자족 스토리파일 형식 | Story Engineer(#15) | `.../bmad-localized-kr/templates/story-template.md` |
| `project-context-template.md` | 프로젝트 헌법(기술 규칙) 초안 | Story Engineer(#15), Timothy(#11) | `.../bmad-localized-kr/templates/project-context-template.md` |
| `readiness-report-template.md` | W3 게이트 판정 리포트 | Story Engineer(#15) | `.../bmad-localized-kr/templates/readiness-report-template.md` |
| `session-snapshot-template.md` | 세션 저장 스냅샷 형식 | Paul(리드) — `/save-session` | (BATHOS 신규) |
| `design-system-template.md` | 디자인 토큰·컴포넌트 계약 | **Jonnathan(#7)** | (BATHOS 신규, 탑티어 디자인) |
| `project-card-template.md` | 크로스-프로젝트 메모리 카드 형식 | Paul(리드) — `/project-handoff`·`/recall` | (BATHOS 신규, `~/.bathos/registry/`) |

### 🔄 워크플로우 (`workflows/`)

| 파일 | 용도 | 주 사용 역할 | 원천 경로 |
|------|------|------------|----------|
| `create-story.md` | 스토리파일 6단계 컴파일 절차 | Story Engineer(#15) | `.../bmad-localized-kr/workflows/create-story.md` |
| `check-implementation-readiness.md` | W3 이중 게이트 절차 (6단계+독립리뷰) | Story Engineer(#15), Thomas(#12), Matthias(#13) | `.../bmad-localized-kr/workflows/check-implementation-readiness.md` |
| `design-excellence.md` | 탑티어 UI/UX 설계 10단계 절차 (+Claude Design) | **Jonnathan(#7)** | (BATHOS 신규) |

### ✅ 체크리스트 (`checklists/`)

| 파일 | 용도 | 주 사용 역할 | 원천 경로 |
|------|------|------------|----------|
| `story-context-quality.md` | 스토리파일 적대적 재검증 (FIX & PREVENT) | Story Engineer(#15), Thomas(#12), Matthias(#13) | `.../bmad-localized-kr/checklists/story-context-quality.md` |
| `design-quality.md` | 디자인 품질 11차원 0~10 적대적 루브릭 | **Jonnathan(#7)**, `/plan-design-review` | (BATHOS 신규) |

### 📚 참조 자산

| 파일 | 용도 |
|------|------|
| `_glossary-kr.md` | BATHOS 한글 용어집 (일관성 기준) |
| `_index.md` | 이 파일 — 자산 카탈로그 |
| `model-catalog.json` | **LLM 프로바이더·모델 카탈로그** — `/model-config`와 각 `/waveN-…`의 모델 선택 UI가 참조하는 선택지 목록. 주 사용: Paul(리드). **제약이 아니라 편의**(`model` 필드에 allowlist 없음 → 카탈로그에 없는 구형·저가 모델 ID도 그대로 동작). 새 모델 출시 시 이 파일만 갱신하면 되고 엔진 재빌드 불필요. 각 항목의 `verified` 플래그가 1차 출처 확인 여부를 표기한다(미확인 = 사용 전 `docs` URL 재확인). |

---

## 원천에서 선별 기준

다음 원천 자산은 **제품 핵심 자산에 선별 포함**하였습니다:
- `story-template.md` ← **필수**: W3 스토리파일의 9섹션 구조 정의
- `project-context-template.md` ← **필수**: 프로젝트 헌법 = 모든 W5 구현자 공통 로드
- `readiness-report-template.md` ← **필수**: 게이트 판정 표준 양식
- `create-story.md` ← **필수**: W3 핵심 워크플로우
- `check-implementation-readiness.md` ← **필수**: W3 게이트 진행 절차
- `story-context-quality.md` ← **필수**: 적대적 재검증, 생성-검증 루프

다음 원천 자산은 **W4 플러그 모듈**로 분리 예정(차기):
- `epics-template.md` → `modules/ip-pack/` 또는 `modules/research-pack/` 이관
- `prd-template.md` → 차기 W2 강화 시 추가
- `architecture-spine-template.md` → James(#4) 직접 사용, 차기 `modules/` 이관
- `good-spine-checklist.md` → 차기 추가
- `prd-quality-rubric.md` → 차기 추가
- `4-phase-overview.md`, `analysis-workflows.md` 등 → 참조용 유지

---

## 자산 추가 규칙

1. 새 자산은 이 인덱스에 즉시 등록.
2. 모든 자산 파일 상단에 **출처 헤더** (원본 경로, 레포, 라이선스, 현지화 일자) 유지.
3. 원천 라이선스(MIT © 2025 BMad Code, LLC) 고지 보존.
4. 소유: Timothy(#11) — 자산 추가/수정 시 Timothy와 합의.

---

## 차기 계획 (미구현, 위임)

| 항목 | 내용 | 담당 |
|------|------|------|
| `modules/ip-pack/` | Mark(#5) 전용 자산 (특허 명세 템플릿/워크플로우) | Mark, Timothy |
| `modules/research-pack/` | Nathanael(#6) 전용 자산 (Abstract/Intro 가이드) | Nathanael, Timothy |
| `templates/epics-template.md` | 에픽 분해 표준 템플릿 | Joshua(#3) 입력 후 Timothy 배치 |
| `templates/prd-template.md` | PRD 표준 템플릿 | Joshua(#3) 입력 후 Timothy 배치 |
| W0 분석 자산 | brainstorm/forge/brief 템플릿 | Caleb(#2) 입력 후 Timothy 배치 |
