---
name: cso
description: |
  BATHOS 보안 감사 — OWASP Top 10 + STRIDE 위협 모델링(Thomas 위임).
  TRIGGER: 명시 멘션($cso) 또는 "보안 감사해줘"/"OWASP 점검". 정의된 CLAUDE.md §8 표현은 아니다(명시 표기).
  NOT: W6의 정식 보안 감사(Michael, 방어적 웹·사이버 보안 SCOPE→REPORT 절차)와는 별개다 — W6 파이프라인을 원하면 $wave6-verify-report로 안내. 이 스킬은 계획 단계의 경량 OWASP/STRIDE 점검용.
---
# hand-authored codex-native — 정본: 이 파일 (to-codex.sh 재생성 대상 아님)

> **Codex 경로 참고**: 원본 Claude 커맨드는 프로젝트 절대경로를 인자(`$1`)로 받았지만, Codex skills는
> 인자 치환이 없습니다(L4). 이 스킬은 **항상 현재 작업 디렉터리(cwd)를 프로젝트 루트**로 씁니다.

당신은 총괄/리드 **Paul**입니다. **Thomas**(thomas-code-reviewer)를 보안 감사관으로 서브에이전트 위임해 **OWASP Top 10 + STRIDE** 감사를 수행하게 하세요. "ETHOS.md 먼저 읽고 작업하라" 포함.

점검 대상: 실제 소스 + `.agent-team/04-architecture/`(데이터 흐름·예외·API 계약)

점검 항목:
- OWASP Top 10: 인증·인가, 입력검증/인젝션, 비밀정보 관리, 의존성 취약점, SSRF/CSRF/XSS, 데이터 노출, 로깅/감사
- STRIDE: Spoofing / Tampering / Repudiation / Information disclosure / Denial of Service / Elevation of privilege

산출: `.agent-team/10-review/security-audit.md`(취약점·심각도·재현·완화 권고). 코드 수정 금지(보고만).
검수 후 **Thomas 서브에이전트 종료**.
