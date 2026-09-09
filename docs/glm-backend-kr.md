# BATHOS × GLM — GLM 백엔드로 구동하기

> **성격: 이식이 아니라 "모델 스왑".** Claude Code 런타임을 그대로 두고 백엔드 모델만 GLM(Zhipu/Z.ai)으로 바꾼다. Agent Teams·훅·슬래시 커맨드·MCP·`bathos` 엔진이 **100% 그대로** 동작한다.
> 전제: Z.ai의 **Anthropic 호환 엔드포인트**. (공식 Anthropic이 아니라 Z.ai 호환 레이어 — 내부에서 Claude 모델명을 GLM으로 매핑.)
> ⚠️ 엔드포인트·모델 매핑·플랜 정책은 버전에 따라 변함 → 실사용 전 `docs.z.ai/scenario-example/develop-tools/claude` 재확인.

---

## 1. 3분 셋업

1. **Z.ai API 키 발급** — Z.ai(z.ai) GLM Coding Plan 가입 후 API 키 생성.
2. **환경변수 설정** (아래 둘 필수):
   ```bash
   export ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic"
   export ANTHROPIC_AUTH_TOKEN="<발급받은 Z.ai 키>"
   export API_TIMEOUT_MS="3000000"   # 선택: 긴 에이전트 턴 대비
   ```
   또는 저장소 헬퍼: `source scripts/glm-env.sh`(키는 `Z_AI_API_KEY` 환경변수로 주입 — 파일에 키를 넣지 말 것).
3. **Claude Code 실행** — 평소처럼 `claude` 실행. 이제 모델 호출이 GLM으로 나간다.
4. **확인** — 아무 프롬프트나 던져 응답이 오면 연결 성공. `/status`(또는 `/config`)에서 엔드포인트 확인.

---

## 2. BATHOS 특이점 — 모델 필드 매핑 (유일한 적응 포인트)

BATHOS 에이전트 정의(`.claude/agents/_base/*.md`)의 `model` 필드는 **`claude-fable-5`·`claude-sonnet-5`**(비표준 ID)를 씁니다. Z.ai 호환 레이어는 표준 Claude **별칭**(opus/sonnet/haiku)을 GLM으로 매핑하므로, 다음 중 하나를 권장:

- **(권장·무변경) `/config`의 Default teammate model** 을 지정 → 팀원 스폰 시 그 모델 사용. 저장소 파일 수정 불필요.
- **(대안) 별칭으로 매핑** — teammate 모델을 `opus`/`sonnet`/`haiku` 별칭으로 두면 Z.ai가 GLM으로 매핑.
- Z.ai 별칭 매핑 예시(**2026-07 시점 문서 기준 — 현재 매핑은 재확인하지 않았음**): **Opus/Sonnet → GLM-4.7**, **Haiku → GLM-4.5-Air**. → 기본 매핑을 유지하면 플랜이 최신 모델로 자동 갱신된다.
- **현재 모델 라인업(2026-09-09 `docs.z.ai` pricing 페이지 확인):** 플래그십 **`glm-5.3`**, fast 티어 `glm-5.3-flash`. 이전 세대 `glm-5.2`·`glm-5.1`·`glm-5`·`glm-4.7`, 경량 `glm-4.5-air`, 무료 티어 `glm-4.7-flash`·`glm-4.5-flash`. 전체 목록·검증 상태는 [`assets/model-catalog.json`](../assets/model-catalog.json).

> 원칙: 저장소의 정본 `model` 필드(`claude-*`)는 **Claude 실행용 기본값으로 보존**하고, GLM 구동은 **환경변수 + `/config`** 로만 전환하는 것을 권장(코드 무변경·가역).

---

## 3. 무엇이 되고 무엇을 주의하나

| 항목 | GLM 백엔드에서 |
|------|----------------|
| Agent Teams(웨이브 팀 스폰) | ✅ 그대로 |
| 훅(careful/freeze/gate/SessionStart/SessionEnd) | ✅ 그대로(`bathos` 바이너리 로컬 존재 전제) |
| 슬래시 커맨드 40+ | ✅ 그대로 |
| MCP(pencil 등) | ✅ 그대로 |
| `bathos` 엔진(게이트·감사·상태) | ✅ 그대로 |
| 도구 호출/긴 컨텍스트 | ◐ GLM-4.6/5.2 실사용 가능 수준(멀티턴 실무에서 Sonnet과 사실상 대등하다는 자체보고). 정밀 head-to-head는 근거 제한 |
| 품질/판정 일관성 | ⚠️ 모델이 다르므로 게이트 판정·리뷰 톤이 Claude와 다를 수 있음 → 중요한 게이트는 결과 재검토 권장 |
| 비용/할당량 | ⚠️ Z.ai 티어(Lite/Pro/Max)별 할당량 |

---

## 4. 되돌리기

환경변수만 제거(또는 새 셸)하면 즉시 Claude(Anthropic)로 복귀. 저장소 변경이 없으므로 완전 가역.
```bash
unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN API_TIMEOUT_MS
```

## 5. 역할별 모델 혼합 제약 — `bathos model validate` (ADR-D-0005)

이 문서의 "모델 스왑" 성격에는 **물리적 한계**가 하나 있다: 위 §1의 `ANTHROPIC_BASE_URL`은
**프로세스 전역**이다 — 같은 Claude Code 프로세스 안에서 팀원 A는 GLM, 팀원 B는 Claude로
나가게 하는 것은 불가능하다(env가 하나뿐이라 전 팀원+Paul 자신이 같은 백엔드를 공유).
`_state/model-plan.json`(§A1, `bathos model`)으로 역할별 `runtime`을 지정할 수 있게 된
뒤에도 이 제약은 사라지지 않으므로, `bathos model validate --wave <W>`가 웨이브 스폰
전에 이를 강제한다:

- **R1(불변식)**: 한 세션의 모든 인프로세스 팀원은 같은 백엔드를 쓴다 — "이 역할만 GLM"은
  물리적으로 불가하며 이 사실을 UI/문서에서 숨기지 않는다.
- **R2(충족 조건)**: `runtime=glm` 역할이 스폰 가능하려면 `session_backend=glm`이어야
  한다(= 위 §1처럼 `source scripts/glm-env.sh` 후 `claude`를 띄운 세션). 이때 같은 배치의
  `runtime=claude` 역할도 **사실상 GLM으로 구동**되므로 `validate`가 `E-MODEL-MIX`(exit 2)로
  차단한다.
- **R3(해소 선택지, `validate`가 출력)**: ① 배치 전체 GLM로 통일 ② GLM 희망 역할을
  `claude`/`codex`로 재배정 ③ `mixed_policy=sequential` — claude 배치를 현 세션에서 먼저
  끝내고 shutdown → 사용자가 `source scripts/glm-env.sh && claude`로 재기동한 새 세션에서
  GLM 배치를 이어감(세션 재기동은 사람의 행동이라 자동화 불가 — 정직한 한계).
- **R4(mismatch)**: `session_backend=glm`인 세션에서 `runtime=claude`를 명시한 역할이
  있으면 `E-MODEL-BACKEND-MISMATCH` — "이 세션에서 claude 지정은 이행 불가(전부 GLM으로
  나감)"를 알리고 사용자 확인 후 표기를 정정한다(침묵 오차단·침묵 오표기 둘 다 금지).

Codex(`runtime=codex`)는 **별도 프로세스**라 이 제약에서 예외다 — GLM처럼 env를 공유하지
않으므로 같은 배치의 Claude/GLM 팀원과 병행 무충돌(`codex-adapter/run-role.sh`로 위임,
`docs/codex-adapter-kr.md` 참고).

상세 설계·엣지케이스 전수: `.agent-team/04-architecture/w2-panes-model-design-kr.md`
§A3.2(R1~R4 원문)·§B6(E1~E14)·ADR-D-0005. CLI 레퍼런스: `docs/COMMANDS-kr.md` §10.1.

## 상태 — 실연결 검증 하네스 (2026-07-16, Phillip)

`scripts/glm-smoke-test.sh`가 이 문서의 "환경변수 2개면 GLM으로 구동된다"는
주장을 curl로 직접 검증하는 스모크 테스트다(`--dry-run`으로 키 없이 요청
구성만 볼 수도 있음). 실키 없이 실증한 범위:

- **인증 재시도 경로(ADR-P4-3) 실서버 확인:** 가짜 키로 `https://api.z.ai/api/anthropic/v1/messages`에
  요청 시 `Authorization: Bearer` 헤더가 401을 받고, `x-api-key` 헤더로
  1회 재시도해도 401(`"token expired or incorrect"`)이 옴을 실측했다 —
  즉 엔드포인트 자체는 살아있고 두 인증 방식 모두 서버가 인지한다.
- **✅ 유효 키 라이브 실증 완료 (2026-07-16, Paul):** GLM Coding Plan 키(API명 `βατηοσ-γλμ`)로
  `Z_AI_API_KEY=<키> bash scripts/glm-smoke-test.sh` 1회 실행 → **RESULT: PASS**.
  - **HTTP 200**, 정상 응답 본문, text 블록 존재(V1~V4 통과).
  - **성공 auth 방식 = `Authorization: Bearer`**(1차 시도 성공, `x-api-key` 폴백 미발생).
  - **model echo = `glm-4.7 → glm-4.7`**(요청·응답 모델 일치).
  - 응답 텍스트 = 지시 토큰 `BATHOS-GLM-OK` 정확 반환(참고용).
  - 즉 이 문서의 "환경변수 2개면 GLM으로 구동" 주장이 **실서버·유효키로 봉인됨**. (키는 문서·저장소에 기록하지 않음.)
  - 남은 선택 검증: `--tool-use`(툴콜 라이브)·장기 에이전트 워크플로우 품질은 실사용에서 계측 권장.
  - ℹ️ **위 `glm-4.7`은 그 시점의 측정값이므로 고치지 않는다**(측정 기록 보존). 이후 2026-09-09에
    `glm-smoke-test.sh`의 **기본 모델을 `glm-5.3`으로 갱신**했으므로, 지금 재실행하면 echo 값은
    `glm-5.3 → glm-5.3`이 된다. 옛 모델로 재현하려면 `GLM_SMOKE_MODEL=glm-4.7` 또는 `--model glm-4.7`.
    ⚠️ `glm-5.3`에 대한 라이브 재실증은 **아직 수행하지 않았다**(기본값만 갱신 — 날조 금지).

## 출처
- Z.ai × Claude Code 공식 가이드: https://docs.z.ai/scenario-example/develop-tools/claude
- GLM Coding Plan × Claude Code: https://codingplan.run/guides/claude-code-with-glm
- GLM-5.2(1M ctx): https://www.marktechpost.com/2026/06/14/z-ai-launches-glm-5-2-... · GLM-4.6(200K): https://docs.z.ai/guides/llm/glm-4.6
- 현재 모델·가격 목록(2026-09-09 확인 — `glm-5.3` 플래그십): https://docs.z.ai (pricing)
