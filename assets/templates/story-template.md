<!--
출처: .agent-team/01-reverse/bmad-localized-kr/templates/story-template.md
원본: src/bmm-skills/4-implementation/bmad-create-story/template.md
레포: bmad-code-org/BMAD-METHOD @ main (MIT © 2025 BMad Code, LLC)
현지화: John(BATHOS Reverse Specialist) · 2026-06-29
패키지 배치: Timothy(BATHOS Doc Specialist) · 2026-06-29
-->

# 스토리 {{epic_num}}.{{story_num}}: {{story_title}}

Status: ready-for-dev
<!-- 상태값: backlog → ready-for-dev → in-progress → in-review → done -->
<!-- 검증은 선택. dev-story 전 품질 점검을 원하면 story-context-quality 체크리스트 실행. -->

## 스토리(Story)

As a {{role}},
I want {{action}},
so that {{benefit}}.

## 인수 기준(Acceptance Criteria)

1. [에픽/PRD에서 가져온 인수 기준 — BDD 형식 권장]
2. ...

## 작업/하위작업(Tasks / Subtasks)

- [ ] 작업 1 (AC: #1)
  - [ ] 하위작업 1.1
- [ ] 작업 2 (AC: #2)
  - [ ] 하위작업 2.1

---

## Developer Context (개발자 컨텍스트) ← **가장 중요**

<!-- create-story 워크플로우가 채우는 핵심 섹션. 구현자가 이 섹션만 보고도 착수 가능해야 한다. -->

### 이 스토리에서 무엇을 구현하는가
[한 문단 요약]

### 중요한 제약·전제
- [아키텍처·보안·성능 제약]

### 해서는 안 되는 것
- [anti-pattern, 기존 코드 회귀 금지 항목]

---

## Architecture Compliance (아키텍처 준수)

<!-- [Source: .agent-team/04-architecture/XXX.md#Section] 형식으로 출처 명기 -->

- 관련 아키텍처 패턴·결정:
- 준수해야 할 API 계약:
- 데이터 스키마 관련 사항:

---

## Library / Framework Requirements (라이브러리·프레임워크 요구사항)

<!-- 최신 안정버전·breaking change·보안 패치·deprecated 포함 -->

| 라이브러리/프레임워크 | 버전 | 비고 |
|----------------------|------|------|
| [이름] | [버전] | [breaking/보안/deprecated 여부] |

---

## File Structure Requirements (파일 구조 요구사항)

<!-- 프로젝트 구조와의 정합 — 신규/수정 파일 목록 -->

```
[신규 또는 수정할 파일 경로 목록]
```

---

## Testing Requirements (테스트 요구사항)

<!-- 단위/통합/E2E 각각 요구사항 -->

- **단위 테스트**: [대상 함수/모듈]
- **통합 테스트**: [대상 API/플로우]
- **E2E**: [대상 유저 플로우]

---

## Dev Notes (개발 노트)

- 관련 아키텍처 패턴·제약
- 손대야 할 소스 트리 구성요소
- 테스트 표준 요약

### 이전 스토리 인텔리전스 (Previous Story Intelligence)

<!-- story_num > 1 일 때 채움. 직전 스토리에서 배운 패턴·결정·주의사항 -->

- [이전 스토리에서 확립된 패턴]
- [피해야 할 함정]

### Git Intelligence

<!-- 최근 5커밋 기반 패턴·의존성 변화 -->

- [최근 변경 패턴]

### Latest Tech Information

<!-- 웹리서치 결과: breaking change·보안·deprecated -->

- [최신 기술 정보]

### Project Context Reference

<!-- 프로젝트 헌법(project-context-kr.md)의 핵심 참조 -->
- [Source: project-context-kr.md#관련-섹션]

---

## Dev Agent Record (구현 기록)

### 사용 모델(Agent Model Used)

{{agent_model_name_version}}

### 디버그 로그 참조

[링크 또는 없음]

### 완료 노트 목록(Completion Notes List)

- [완료 시 기록]

### 파일 목록(File List)

<!-- ⚠️ 중요: 이 목록은 다음 스토리의 "이전 스토리 인텔리전스" 입력이 됩니다(연속성 D4). -->

| 파일 경로 | 상태 (신규/수정/삭제) |
|-----------|----------------------|
| [경로] | [신규/수정] |
