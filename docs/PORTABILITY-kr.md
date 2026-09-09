# BATHOS 멀티 런타임 포터빌리티 — 판단 & 제안 (Codex · GLM)

> 질문: "이 프레임워크를 **Codex 기반**·**GLM 기반**으로도 쓸 수 있게 하고 싶다. 구현 가능한가?"
> 결론 한 줄: **GLM = 쉬움(모델 백엔드 스왑, 프레임워크 100% 보존) · Codex = 어려움(런타임 포팅, 오케스트레이션 재구현 필요)** — 둘은 성격이 다른 별개 결정.
> 근거: 2026-07 리서치(하단 출처). 불확실 항목은 "⚠️ 확인 필요"로 표기. 수치·엔드포인트는 실측/문서 기반(날조 없음).

---

## 0. 무엇이 런타임에 묶여 있나 (결합도 지도)

| 계층 | 구성요소 | 런타임 결합도 | 이식성 |
|------|----------|---------------|--------|
| **코어 엔진** | `bathos` Rust 바이너리(router·wave·gate·story·state·audit·plug) | **독립** — CLI 호출만 | ✅ 그대로 재사용 |
| 오케스트레이션 | Agent Teams(팀 스폰·병렬), 훅(exit-code 게이트 강제), 슬래시 커맨드 | **Claude Code 강결합** | ⚠️ 런타임별 재매핑 |
| 정의·자산 | `.claude/agents/*.md`(model 필드), `.claude/commands/*.md`, `AGENTS.md`, 마크다운 규약 | 규약 결합 | ◐ 변환 가능 |
| 모델 | `claude-fable-5`/`claude-sonnet-5` 지정 | 모델 결합 | ◐ 매핑 필요 |

> **핵심 자산은 `bathos` 엔진** — 게이트/웨이브/상태/감사 로직이 런타임 밖 독립 바이너리라, 어느 런타임이든 훅/커맨드가 `bathos <subcmd>`만 호출하면 동일 로직이 돈다. 포팅 대상은 "엔진"이 아니라 "엔진을 부르는 오케스트레이션 접착층"이다.

---

## 1. GLM 경로 — 모델 백엔드 스왑 (쉬움, 즉시 가능)

**성격:** 이식이 아니라 **모델 스왑**. Claude Code 런타임을 그대로 두고 백엔드만 GLM으로 지정.

- **방법:** Z.ai가 **Anthropic 호환 엔드포인트**를 제공 → 환경변수 2개로 Claude Code(=BATHOS)를 GLM 위에서 구동.
  ```
  ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic
  ANTHROPIC_AUTH_TOKEN=<Z.ai 키>
  ```
- **보존되는 것:** Agent Teams · 훅(SessionEnd 포함) · 슬래시 커맨드 · MCP · 에이전트 정의 · `bathos` 엔진 = **100%**.
- **적응 필요 1가지(BATHOS 특이점):** 에이전트 `model` 필드가 `claude-fable-5`/`claude-sonnet-5`(비표준 ID). Z.ai 호환 레이어는 표준 Claude 별칭(opus/sonnet/haiku)을 GLM으로 매핑하므로, **teammate 모델을 별칭으로 두거나 `/config` 기본 모델을 지정**하는 편이 안전. (별칭 매핑 예 — **2026-07 시점 문서 기준, 현재 매핑 미재확인**: Opus/Sonnet→GLM-4.7, Haiku→GLM-4.5-Air — 플랜이 자동 최신화되도록 기본 매핑 유지 권장. **현재 플래그십 = `glm-5.3`**, fast 티어 `glm-5.3-flash`(2026-09-09 `docs.z.ai` pricing 확인). 전체 목록: [`assets/model-catalog.json`](../assets/model-catalog.json).)
- **한계/주의:** 공식 Anthropic이 아니라 Z.ai 호환 레이어(내부 모델명 재매핑)·자체보고 벤치마크 위주(외부 재현 근거 제한)·티어별 할당량.
- **실행물:** `docs/glm-backend-kr.md`(설정 가이드) + `scripts/glm-env.sh`(env 헬퍼).

**판정: 구현 가능 · 난이도 낮음 · 코드 변경 최소(선택적 모델 필드 매핑).**

---

## 2. Codex 경로 — 런타임 포팅 (어려움, 단계적)

**성격:** 프레임워크 전체를 다른 패러다임(OpenAI Codex CLI)으로 포팅. 접착층 재구현 필요.

### 대응 양호 (그대로/변환)
| Claude Code | Codex CLI | 비고 |
|-------------|-----------|------|
| `.claude/agents/*.md` (model 지정) | `~/.codex/agents/*.toml` (name/description/instructions, **model·reasoning_effort 오버라이드**, 병렬) | 변환 가능. `max_depth=1` 기본 → "팀원 중첩 금지" 규칙과 **부합** |
| MCP 서버 | `[mcp_servers.x]` (소비) + `codex mcp-server`(노출) | 양방향 지원 |
| `AGENTS.md` | 네이티브(원래 Codex 규약) | 그대로 |
| 슬래시 커맨드 | `~/.codex/prompts/*.md` (`/prompts:이름`, `$1..$9`·`$ARGUMENTS`·front matter) | 거의 1:1 변환. ⚠️ 단 custom prompts는 **deprecated → skills 권장** |

### 핵심 공백 (재설계 필요) — Codex 이식의 진짜 비용
1. **`SessionEnd` 훅 없음** → CLAUDE.md §9(종료 시 저장→리포트→종료 강제)가 물리적으로 불가. `Stop`으로 근사만 가능(세션 종료 ≠ 턴 종료).
2. **`TaskCompleted` 등가물 없음** → W3 게이트를 "태스크 완료 차단"으로 걸던 방식을 **`PreToolUse` exit-2 게이트로 재설계** 해야 함.
3. **훅이 실험적 · Windows 미지원 가능성** ⚠️ → 프로젝트의 Windows/WSL 지원과 충돌 가능.
4. **모델 프로바이더 responses-only** → Codex는 `wire_api="responses"`만 지원(2026-02 chat 제거). **GLM을 Codex에 직접 붙이면 깨짐** → 번역 프록시(codex-relay 등) 필요. (즉 "Codex+GLM"은 두 겹의 어댑터.)
5. 슬래시 커맨드가 **skills로 이동 중** → 40여 개 커맨드를 prompts/skills로 재작성.

### 제안하는 Codex 어댑터 범위 (이번 산출)
- **설계 문서** `docs/codex-adapter-kr.md`: 매핑 매트릭스 + 게이트 재설계(PreToolUse exit-2) + SessionEnd 공백 대응.
- **변환 스캐폴드** `scripts/to-codex.sh`: 기계적 80% 변환(`.claude/commands/*.md` → `~/.codex/prompts/`, `.claude/agents/*.md` frontmatter → `.codex/agents/*.toml`). 게이트·SessionEnd는 수동 적응 필요라고 명시.

**판정: 부분 구현 가능 · 난이도 높음 · 이번엔 "설계 + 기계적 변환 스캐폴드"까지. 완전 포팅(게이트 재설계·SessionEnd 대체·커맨드→skills)은 후속 단계.**

---

## 3. 단계별 실행 계획

| 단계 | 내용 | 상태 |
|------|------|------|
| **P1** | 포터빌리티 설계 문서(본 문서) + 결합도 지도 | ✅ 이번 |
| **P2** | GLM 백엔드 가이드 + env 헬퍼 → 즉시 사용 가능 | ✅ 이번 |
| **P3** | Codex 어댑터 설계 문서 + 기계적 변환 스캐폴드 | ✅ 이번 |
| P4 | (후속) Codex 게이트 재설계(PreToolUse exit-2) + SessionEnd 근사(Stop) 구현·검증 | ⏳ 별도 |
| P5 | (후속) Codex+GLM 번역 프록시 연동, 커맨드→skills 마이그레이션 | ⏳ 별도 |
| P6 | (후속) `bathos runtime` 추상화 — 런타임 감지 후 어댑터 자동 선택 | ⏳ 별도 |

> 권장 순서: **GLM(P2) 먼저 — 최소 노력·최대 효용**(BATHOS 그대로 GLM에서 구동). Codex(P3~)는 설계 확정 후 단계적.

---

## 출처 (2026-07 리서치)
- Codex custom prompts/slash: developers.openai.com/codex/custom-prompts · /guides/slash-commands
- Codex hooks(이벤트·exit2·실험적): learn.chatgpt.com/docs/hooks · codex.danielvaughan.com(2026-04 hooks guide)
- Codex subagents(TOML·병렬·max_depth): learn.chatgpt.com/docs/agent-configuration/subagents
- Codex MCP·AGENTS.md·config: developers.openai.com/codex/config-reference
- Codex model providers responses-only: learn.chatgpt.com/docs/config-file/config-reference · github.com/openai/codex/discussions/7782
- GLM×Claude Code(Anthropic 호환): docs.z.ai/scenario-example/develop-tools/claude
- GLM×Codex 프록시: github.com/openai/codex/issues/9612 · KevinSHH/codex-glm-proxy · MetaFARS/codex-relay
- GLM-5.2(1M ctx): marktechpost.com(2026-06 GLM-5.2) · GLM-4.6 200K: docs.z.ai/guides/llm/glm-4.6
- 현재 모델·가격 목록(2026-09-09 확인 — `glm-5.3` 플래그십): docs.z.ai (pricing)

> ⚠️ Codex 훅 기본 활성/Windows 지원, GLM 모델 매핑 세부는 버전에 따라 변함 — 실사용 전 각 출처 재확인.
