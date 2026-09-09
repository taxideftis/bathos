---
name: bathos-debt
description: .agent-team/ 산출물의 "CONCERNS:" 앵커와 소스코드의 "ponytail:" 마커를 한 번에 수집해 부채 ledger로 보여준다. 게이트 판정 CONCERNS(조건부 통과)와 W5 의도적 단순화의 후속 해소 여부를 놓치지 않기 위함. "부채 확인", "/bathos-debt", "CONCERNS 목록", "ponytail 부채", "ponytail 마커 모아줘", "남은 리스크 뭐 있어", "부채 ledger" 요청 시 사용.
---

# bathos-debt — CONCERNS 부채 ledger (CF-A6 · US15 · Should)

> 근거: `_recon/ponytail-analysis.md` #8(companion 스킬 패밀리, `/ponytail-debt`),
> `04-architecture/hook-and-gate-design-kr.md §6`, `story-a6-debt-ledger-kr.md`.
> **앵커 2종(2026-09-09 확장, User 결정):** 최초 설계는 BATHOS 산출물이 마크다운이라는 이유로
> 앵커를 `CONCERNS:` 하나로 재정의했으나, W5에 구현 규율(사다리)이 도입되면서 **소스코드**에도
> 의도적 단순화 마커가 생겼다. 이제 두 앵커를 **매체별로 분리 수집**한다 — 중복이 아니라 분업이다:
>
> | 매체 | 앵커 | 규약 정본 |
> |------|------|----------|
> | 마크다운 산출물·게이트 리스크 | `CONCERNS:` | `CLAUDE.md` §2.1 |
> | 소스코드 | `ponytail: <ceiling>, <upgrade path>` | `.claude/agents/_preamble/ponytail-inject-kr.md` §5 |
>
> 같은 항목을 두 앵커로 중복 기록하지 않는다(규율 §5 "앵커 분리 원칙").
> 읽기 전용 — 아무것도 변경하지 않는다.

## 목적

게이트 판정 **CONCERNS**(조건부 통과, 비차단 리스크)는 문서 곳곳(`04-architecture/`,
`_state/risk-log.md`, `manifest.json`의 `risks[]` 등)에 흩어져 남는다. 시간이 지나면
"나중에 해소하겠다"던 항목이 조용히 잊힌다(ponytail의 "later means never" 문제와 동형).
이 스킬은 흩어진 `CONCERNS:` 앵커를 **한 번에 조회 가능한 ledger**로 모은다.

## 스캔 절차 (에이전트가 직접 수행 — 별도 스크립트 불요)

1. **대상 범위**: `.agent-team/**/*.md`(전 하위 디렉터리) + `.agent-team/_state/risk-log.md`
   (있다면) + `bathos state show`(또는 `bathos --state-dir <dir> state show`)로 조회한
   `manifest.json`의 `risks[]` 배열. `node_modules`·`.git`·`core/target`은 제외.
2. **앵커 탐지**: 각 파일에서 `CONCERNS:` 리터럴이 포함된 행을 찾는다.
   ```bash
   grep -rn 'CONCERNS:' .agent-team --include='*.md'
   ```
   표기가 파일마다 미세하게 다를 수 있다(볼드 `**CONCERNS:**`, 인용 블록 안 등) —
   **관대하게** "행 내 `CONCERNS:` 리터럴 포함"만 조건으로 삼는다. 오탐이 의심돼도
   note로 강등하지 말고 그대로 노출한다(사용자가 최종 판단).
2-B. **`ponytail:` 마커 탐지(소스코드)**: 프로젝트 소스 트리에서 의도적 단순화 마커를 찾는다.
   ```bash
   grep -rnE '(#|//|--) ?ponytail:' . \
     --include='*.rs' --include='*.ts' --include='*.tsx' --include='*.js' --include='*.py' \
     --include='*.sh' --include='*.ps1' --include='*.go' --include='*.java' --include='*.kt' \
     --exclude-dir=target --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=.agent-team
   ```
   - 주석 기호(`#`·`//`·`--`)와 선택적 공백을 허용한다. 마커 뒤 본문 전체를 캡처한다.
   - **파싱**: 본문을 첫 쉼표에서 나눠 `ceiling`(앞) / `upgrade path`(뒤)로 본다.
     쉼표가 없거나 뒤쪽이 비면 **업그레이드 경로 없음**으로 판정한다.
   - **`no-trigger` 판정**: 업그레이드 경로가 없거나, 있어도 되돌아볼 **트리거**(조건·측정·임계)를
     담지 않은 마커는 `no-trigger`로 표시한다. 규율 정본 §5: *조용히 썩는 건 바로 그것들이다.*
     판정이 애매하면 `no-trigger`를 **붙이지 않는다**(과탐지보다 미탐지 — 사용자가 최종 판단).
   - `.agent-team/`은 제외한다(그쪽은 `CONCERNS:` 담당 — 앵커 분리 원칙).
3. **웨이브 추론**: 파일 경로의 최상위 디렉터리(`00-plan`~`12-report`, `_state`)로
   웨이브를 역추론한다. 프론트매터에 `wave:` 필드가 있으면 그것을 우선한다.
   `_state/risk-log.md`·`manifest.json risks[]` 항목은 `owner_wave` 필드를 사용한다.
   **소스코드의 `ponytail:` 마커는 `W5`로 귀속한다** — 구현 규율은 W5 전용이고 마커는 구현 중에만
   생긴다(규율 정본 §8 "적용 웨이브 = W5만"). 파일 경로로 추론하지 않는다.
4. **심각도 폐쇄 어휘 판정** — 아래 3값 외 임의 태그 금지:
   | 표기 | 의미 | 판정 근거 |
   |------|------|-----------|
   | `[x]` | blocker | 문맥에 "차단"/"blocker"/"FAIL" 동반 |
   | `[!]` | concerns | 기본값(대부분의 게이트 CONCERNS 항목) |
   | `[·]` | note | 문맥에 "참고"/"note"/"비차단" 명시 동반 |

   **`ponytail:` 마커의 심각도** — 같은 폐쇄 어휘를 재사용한다(신규 태그 금지):
   | 표기 | 조건 |
   |------|------|
   | `[!]` | 기본값 — 천장·업그레이드 경로가 모두 있는 정상 마커 |
   | `[x]` | `no-trigger` 판정 — 업그레이드 경로/트리거 없음(조용히 썩는 부채) |
   | `[·]` | 마커 본문에 "note"/"참고"가 명시된 경우 |

   `no-trigger` 항목은 SUMMARY 맨 앞에 `no-trigger — ` 접두를 붙여 노출한다.
5. **요약 추출**: `CONCERNS:` 뒤 첫 문장을 80자로 절단한다(그 이상은 `…`).
6. **정렬**: 웨이브 순(W0→W6, `_state`는 맨 뒤) → 그 안에서 심각도(`blocker`→`concerns`→`note`) 순.
7. **ID 부여**: 이번 실행 내에서만 안정적인 순번 `D-01`, `D-02`, … (정렬 후 부여 —
   재실행해도 같은 스캔 결과면 같은 ID가 나오도록 정렬을 먼저 확정한 뒤 채번한다).

## 출력 형식 (인수: `--wave <W0..W6>` 필터 선택, `--format table|md|json`, 기본 `table`)

### table (기본, 터미널/채팅 출력 — surface-formats-kr.md §a-1 정본 형식)

```
BATHOS DEBT LEDGER  ·  scanned 37 files  ·  2026-07-08 14:20
────────────────────────────────────────────────────────────
  ID    WAVE   SEV    SOURCE                         SUMMARY
────────────────────────────────────────────────────────────
  D-01  W3     [!]    _state/risk-log.md:42            fingerprint diff 정규화 경로 (추정)
  D-02  W4     [·]    04-architecture/schema-ext:72    콜드스타트 데이터 부족
────────────────────────────────────────────────────────────
  총 2건 · CONCERNS 1 · note 1 · 미해결 2 / 해결 0
  다음: 각 SOURCE 경로로 이동해 해소 후 라인에서 'CONCERNS:' 제거
```

### md (문서에 그대로 붙여넣기)

동일 내용을 마크다운 표(`| ID | WAVE | SEV | SOURCE | SUMMARY |`)로 출력하고,
표 아래에 위와 동일한 푸터 문단을 둔다.

### json (도구 연계 — surface-formats-kr.md §a-3 정본 스키마)

```json
{
  "scanned_at": "2026-07-08T14:20:00Z",
  "scanned_files": 37,
  "items": [
    { "id": "D-01", "wave": "W3", "severity": "concerns", "anchor": "concerns",
      "source": "_state/risk-log.md", "line": 42,
      "summary": "fingerprint diff 정규화 경로 (추정)", "status": "open" },
    { "id": "D-03", "wave": "W5", "severity": "blocker", "anchor": "ponytail",
      "source": "core/crates/bathos-state/src/model_plan.rs", "line": 88,
      "summary": "no-trigger — single global lock",
      "ceiling": "single global lock", "upgrade": null, "no_trigger": true,
      "status": "open" }
  ],
  "summary": { "total": 2, "concerns": 1, "note": 1, "open": 2, "resolved": 0 }
}
```
`status`는 `open`(기본) 또는 항목 텍스트에 "해소됨"/"resolved" 등이 동반되면 `resolved`.
`summary`에 `blocker` 카운트가 1건 이상이면 필드를 추가한다(0건이면 생략 가능 —
정본 예시가 concerns/note 사례만 다루므로 blocker 발생 시 임의 확장 아님을 명시).

## 상태별 출력 (막다른 골목 금지 — 항상 "다음 행동" 포함)

| 상태 | 출력 |
|------|------|
| 로딩(파일 많을 때) | `scanning .agent-team/ … (k/N)` 진행 로그 |
| 빈(0건) | `✓ 미해결 CONCERNS·ponytail 마커 없음 — 부채 0건 (scanned N files)` — **성공 톤**(문제 없음을 긍정적으로) |
| 에러(`.agent-team/` 미탐지) | `✗ .agent-team/ 미탐지. 프로젝트 루트에서 실행하세요. (탐색: <cwd>)` |
| 부분(일부 파일 파싱/읽기 실패) | 정상 항목은 그대로 출력 + 푸터에 `주의: k개 파일 건너뜀(파싱 실패)` 추가(개별 실패로 전체를 죽이지 않음) |

## 디자인 규약 (project-context-kr.md §9 그대로 적용)

- 무컬러이모지 — 흑백 기호만: `✓ ✗ ! · [ ]`. `✅⚠️⛔` 등 컬러 이모지 금지.
- 로그 접두: `[bathos debt] <기호> <메시지>`.
- 미측정/미확인 값은 `—`로 표기(날조 금지).

## Boundaries (스코프 밖 — D1·D2 규약 최초 적용 사례)

- **쓰기 없음**: 이 스킬은 순수 조회다. `.agent-team/` 문서를 수정·"해소됨" 자동
  표기하지 않는다(사용자가 직접 해소 후 표기).
- **CONCERNS 앵커 재정의 강제 없음**: 기존 문서의 `CONCERNS:` 표기 스타일을 통일
  시도하지 않는다(그대로 수집만).
- **`manifest.json risks[]` 스키마 변경 없음**: 기존 `bathos state show` 읽기 전용
  조회만 사용, 신규 CLI 서브커맨드를 만들지 않는다.
- **HTML/대시보드 렌더링 없음**: table/md/json 3형태까지만(Martin W6 HTML 리포트는
  범위 밖 — 이 스킬의 json 출력을 소스로 삼을 수는 있음).
- **범위 밖 이관 추적 없음**: `_state/risk-log.md`의 "후속(범위 밖)" 섹션 항목(예:
  US12-AC2 실반영, npm 퍼블리시)은 이 ledger가 아니라 risk-log 자체가 SSOT다 —
  이 스킬은 그 섹션도 `CONCERNS:` 리터럴이 있으면 그대로 수집하되 별도 가공은 하지 않는다.

## 테스트 (체크리스트형 — 스킬이므로 결정성 유닛테스트 대신 시나리오 검증)

가장 싼 검증은 **본 프로젝트의 실제 `.agent-team/`에 대해 실행**해 기존
`_state/risk-log.md`(§A~§C)의 CONCERNS 항목들이 정확히 잡히는지 확인하는 것이다.
추가로 임시 픽스처로 아래를 확인한다:
1. `CONCERNS:` 앵커 3건(웨이브·심각도 상이) 포함 임시 `.agent-team/`을 만들어 스캔 →
   3건이 웨이브→심각도 순으로 정렬돼 출력되는지.
2. `--format json` 출력이 위 스키마와 정확히 일치하는지(필드 누락 없음).
3. `CONCERNS:` 앵커가 0건인 픽스처 → 빈(성공 톤) 상태 문구가 정확히 출력되는지.
4. `.agent-team/` 자체가 없는 디렉터리에서 실행 → 에러 상태 문구(`탐색: <cwd>` 포함)가
   출력되는지.
5. 읽기 권한이 없는 파일 1개를 섞은 픽스처 → 나머지 항목은 정상 출력 + `주의: 1개
   파일 건너뜀` 푸터가 붙는지(부분 성공 우선 원칙).
