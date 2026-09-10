# BATHOS — 자주 묻는 질문 (FAQ)

> 처음 접했을 때 가장 먼저 떠오르는 질문들에 짧게 답한다. BATHOS가 무엇이고, 실행하려면 뭐가 필요하며, 비용은 얼마나 드는지, 더 깊이 파고들려면 어디를 보면 되는지. 각 답 끝에는 자세히 다루는 문서로 가는 길을 달아 두었다.
>
> **함께 보기:** [사용(USAGE-kr)](USAGE-kr.md) · [특징(FEATURES-kr)](FEATURES-kr.md) · [비용·쿼터(QUOTA-kr)](QUOTA-kr.md) · English: [`FAQ-en.md`](FAQ-en.md) · Español: [`FAQ-es.md`](FAQ-es.md)

### BATHOS가 정확히 뭔가?
Claude Code 위에서 도는 메서드 패키지다. 17개 전문 역할과 7웨이브 파이프라인에 Scale-Adaptive 라우팅과 하드 품질 게이트를 얹고, 그 아래에 작은 Rust 엔진을 둔다. 독립 실행 앱이 아니라, 하나의 Claude Code 세션을 절제된 제품 팀처럼 움직이게 오케스트레이션한다.

### 실행에 뭐가 필요한가?
Claude Code v2.1.32 이상에서 실험 기능 Agent Teams를 켜야 한다(`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`). 여기에 엔진을 한 번 빌드할 Rust 툴체인과, 안전 훅이 쓰는 `jq`가 필요하다. macOS와 Linux를 지원한다.

### 내 프로젝트에 어떻게 넣나?
`./install.sh --into /abs/path/to/your-project`를 실행하면 `.claude/`·`assets/`·`modules/`가 복사되고, `BATHOS_BIN`을 빌드된 엔진 경로로 잡아 준다. 전체 흐름은 [`USECASE-kr.md`](USECASE-kr.md)에 있다. 설치가 끝나면 `bathos doctor`로 배선을 확인한다.

### 팀원이 무출력으로 멈췄다 — 고장인가?
거의 아니다. 대개는 코드 버그가 아니라 계정 사용량(session) 한도에 걸린 것이다. 한도가 리셋된 뒤 다시 스폰하면 `.agent-team/`에 남은 디스크 산출물 덕분에 잃는 것 없이 이어간다. 자세히는 [`QUOTA-kr.md`](QUOTA-kr.md).

### 서브에이전트가 시작 시 멈춘다.
`.claude/settings.json`을 열어 보자. `hooks` 블록에 주석키(가령 `_note`)가 들어가 있으면 서브에이전트가 시작하지 못하고 무한정 기다린다. 유효한 이벤트명만 남겨야 한다. `bathos doctor`가 이 문제를 정확히 짚어낸다.

### 실행 비용은? 아끼려면?
토큰 비용은 활성 팀원 수와 레벨을 따라간다. 작업에 맞는 가장 낮은 레벨을 고르고, 동시 팀원은 셋 이하로 두며, 필요한 역할만 스폰하고, W4는 뒤로 미루면 된다. 상세는 [`QUOTA-kr.md`](QUOTA-kr.md).

### "tamper-evident 감사 체인"은 실제인가, 주장인가?
실제이고 직접 검증할 수 있다. `bathos audit verify`가 sha256 체인을 끝까지 훑어 확인한다(`hash_prev[n] == hash_self[n-1]`, genesis 앵커, 단조 seq). 체인이 끊기면 `E-AUDIT-TAMPER`와 함께 exit 1을 낸다.

### 작업을 저장하고 새 세션에서 이어갈 수 있나?
있다. `/save-session`이 모든 것을 `_state/`에 스냅샷으로 남기고(머신 SSOT와 서술본을 함께), `/cold-start`가 새 세션에서 그대로 복원한다. 짧게는 `/save`·`/resume`으로 쓴다. [`USAGE-kr.md`](USAGE-kr.md) §12.1 참고.

### 왜 독립 리뷰가 테스트가 놓친 버그를 찾았나?
바로 그게 핵심이다. 생성과 검증은 다르다. 테스트는 검사한 것만 증명하지만, 독립 리뷰어(Thomas)는 저자가 미처 보지 못한 불변식과 통합 지점을 파고든다. BATHOS는 애초에 저자와 검증자를 설계로 갈라 둔다.

### 새 기능(예: 보안 감사)을 어떻게 추가하나?
도메인 팩이라면 플러그로 붙인다 — [`MODULE-GUIDE-kr.md`](MODULE-GUIDE-kr.md). 역할이 내 프로젝트에서 어떻게 행동할지를 바꾸고 싶다면 team이나 user 오버라이드를 쓴다 — [`ROLE-GUIDE-kr.md`](ROLE-GUIDE-kr.md). 코어 자체는 슬림하게 둔다(불변식 A9).

### 프로덕션 준비됐나?
아직이다. v0.4.0은 초기 단계이지만 실제로 동작하고 dogfooding으로 검증됐다(628 테스트와 86 훅 그린, 완전 독립 인증). 1.0 전까지는 API·스키마·커맨드명이 바뀔 수 있다. 지금까지는 자기 자신에 대해서만 검증됐고, 실제 외부 파일럿이 다음 마일스톤이다.

### 라이선스는? 이거 BMAD인가?
MIT다. BATHOS는 [BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD)(MIT © 2025 BMad Code, LLC)를 정밀 역분석한 뒤 제1원리에서 독립 구현한 것으로, 그 근간이 된 선행 작업에 진심 어린 경의를 표한다. BMAD 상표는 쓰지 않는다.

---

<div align="center"><a href="FAQ-en.md">FAQ-en</a> · <a href="FAQ-es.md">FAQ-es</a></div>
