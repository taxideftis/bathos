# codex-adapter — BATHOS × OpenAI Codex CLI 게이트/저장 어댑터

> 성격: Claude Code의 `TaskCompleted`(W3 게이트) · `SessionEnd`(종료 시 저장)를
> Codex CLI의 확장점(`PreToolUse` · `Stop`)으로 재설계한 실구현. 설계 원본:
> `.agent-team/04-architecture/w2-runtime-p4-design-kr.md` §B (James, 2026-07-16).
> 왜 `.claude/hooks/`가 아니라 이 디렉터리인가: freeze-guard 경로 충돌을 피하고,
> Codex 전용 런타임 코드를 Claude Code 훅과 분리하기 위해서다.
>
> **P5 하드닝(2026-07-16, Phillip):** Codex CLI **v0.144.5**(macos-x86_64)를 실제
> 설치해 바이너리 임베드 스키마를 실측했다. 문서 예시 기준 가정(`tool_name` =
> `Bash`/`apply_patch`)이 실측과 달라(실제 값 = `shell`/`exec_command`/
> `apply_patch`, **`Bash`는 존재하지 않음**) T1/T2 트리거가 발화하지 않고 W3
> 게이트가 **fail-open**되는 버그가 있었다. 아래 문서·훅·config 예시는 모두
> 이 실측값 기준으로 갱신됐다(당시 버전 고정 v0.144.5 — 이 기록 자체는 갱신하지
> 않는다, 날조 금지).
>
> **타겟 버전 이동(2026-07-23, 리드 결정):** 사용자 확정으로 타겟이
> **v0.144.5 → v0.145.0+**(2026-07-21 stable)로 이동했다(역할별 모델 매핑
> 작동 우선, Stephen 조사 근거). ADR-CX-02(같은 날) 2층 대칭 광폭화가
> matcher/tool_name을 실측 3종+문서 별칭 3종 합집합(6종)으로 이미 넓혀 둬서
> v0.145.0+에서 tool_name/스키마가 바뀌어도 흡수한다 — v0.145.0+ 라이브
> 재실측(D1 훅 스키마 종결 등)은 `probe.sh`(story-03)·story-20 몫으로 남는다.

---

## 무엇이 들어있나

```
codex-adapter/
├── hooks/
│   ├── pretooluse-gate.sh       # W3 Implementation 게이트: FAIL이면 구현 진입 exit 2 차단
│   ├── careful-guard-codex.sh   # 파괴 명령 하드 차단(CT-SAFETY, story-15) — 패턴 정본 .claude/hooks/careful-guard.sh 승계
│   ├── freeze-guard-codex.sh    # 소유 경로 밖 apply_patch/Edit/Write 차단(CT-SAFETY, story-15) — BATHOS_OWNED_PATHS 동일 소스
│   ├── stop-save.sh             # SessionEnd 근사: 턴마다 증분 저장(state show 덤프)
│   ├── session-start.sh         # resume 재개 안내 — 저장분 존재 시 $cold-start 1줄 고지(story-14)
│   └── _test-codex-hooks.sh     # 시뮬레이션 테스트(실제 Codex 설치 불요) — 실행할 때마다 최신 PASS/총계는 스크립트 자체 출력이 정본
├── run-role.sh                  # runtime=codex 역할 위임 러너(ADR-D-0006, §A3.3) — Claude Code 팀원이 아닌 별도 프로세스로 역할 실행
├── _test-run-role.sh            # run-role.sh 스모크 테스트(T8, 10케이스·24 assertion, 스텁 codex로 실제 설치 불요)
├── probe.sh                     # 버전 드리프트 1분 재실측 소품(CT-PROBE, story-03) — 실행마다 PROBE-RESULTS-<버전>.md 생성
└── config.toml.example          # ~/.codex/config.toml 등록 예시(실측 스키마, 보조 지위)
```

배선 정본은 이 디렉터리 밖(`<repo>/.codex/hooks.json`, story-02·CT-WIRE-HOOKS)에
있다 — repo 체크인 파일이라 클론만 하면 존재하고, trust 1회로 활성화된다(§설치).

### `run-role.sh` — Codex 런타임 위임 러너

`_state/model-plan.json`에서 `runtime=codex`로 배정된 역할은 Claude Code 팀원으로
스폰되지 않는다(GLM과 달리 별도 프로세스라 in-process 팀원과 병행 무충돌 —
ADR-D-0006). 웨이브 커맨드가 대신 이 스크립트로 위임한다:

```bash
codex-adapter/run-role.sh <role-slug> <task-file.md> [--project <절대경로>] [--dry-run]
```

- **exit 0**=완료 / **1**=실행 실패(`.codex/agents/<slug>.toml` 부재 포함) /
  **3**=`E-CODEX-ABSENT`(codex CLI 미설치) / **4**=`E-CODEX-AUTH`(미인증 — 선제
  `codex login status` 검사 또는 `codex exec` 실행 결과 양쪽에서 판정 가능).
- 프롬프트 = 역할 base md 본문(`.claude/agents/_base/<n>-<slug>.md`, `slug:`
  프론트매터로 탐색) + `ETHOS.md` 전문 + 웨이브 커맨드가 작성한 task-file. 조립된
  프롬프트를 `codex exec "<프롬프트>"`로 비대화 실행한다(⚠️[추정] — 라이브 인증
  세션 미실측, §정직한 한계 참고). `bathos model resolve <slug> --json`이
  `model`/`reasoning_effort` 오버라이드를 찾으면 `-c` 플래그로 전달한다.
- `.codex/agents/<slug>.toml`이 프로젝트 로컬(`<project>/.codex/agents/`) 또는
  `~/.codex/agents/`에 없으면 **자동 생성하지 않고** `scripts/to-codex.sh --write`
  안내 후 exit 1로 끝난다(홈 디렉터리 쓰기는 사용자 승인 사안).
- 완료/실패는 항상 `_state/panes/inbox/codex-<slug>-<ts>-<pid>.txt`에
  `<DONE|FAIL|DRY-RUN><TAB><요약 1줄>`로 기록된다(bathos-tui `inbox.rs`와 동일
  ts-pid·atomic tmp→mv 관례) — Codex는 Agent Teams 메시징/훅 밖이므로 이 파일이
  Paul/패널이 진행을 감지하는 유일한 경로다(경계 명시, §A3.3).
- 테스트: `bash codex-adapter/_test-run-role.sh` — 스텁 `codex` 바이너리로
  10가지 분기(부재/TOML부재/인증실패 선제·사후/dry-run/정상실행/일반오류/
  잘못된 slug/task-file 부재)를 24개 assertion으로 검증한다.

## 설치

**정본 배선 = `<repo>/.codex/hooks.json`(프로젝트 스코프, story-02·CT-WIRE-HOOKS).**
이 파일은 repo에 체크인돼 있으므로 클론만 하면 배선이 이미 있다 — 유저 레벨
`~/.codex/config.toml`을 손으로 편집할 필요가 없다(US1-AC3).

1. `bathos` 바이너리를 빌드해 둔다(`cargo build --release -p bathos-cli` 또는
   저장소 루트에서 `cargo build --release`). 훅은 다음 순서로 바이너리를 찾는다:
   `$BATHOS_BIN` > `<project>/core/target/release/bathos` >
   `<project>/core/target/debug/bathos` > `PATH`의 `bathos`.
2. Codex를 저장소 루트에서 실행하면 `.codex/hooks.json`을 감지하고 **trust
   프롬프트를 1회** 띄운다(프로젝트 스코프 훅을 신뢰할지 확인 — [문서확정]).
   승인하면 이후 세션마다 재확인 없이 자동 배선된다. 두 훅 스크립트가 실행
   가능한지도 확인해 둔다: `chmod +x codex-adapter/hooks/*.sh`(이미 실행
   권한이 설정돼 있음).
3. `.codex/hooks.json`의 `command` 필드는 **repo 상대경로**(`codex-adapter/hooks/...`)
   로 1차 시도한다 — Codex가 훅 command를 프로젝트 루트 기준 상대경로로
   실행하는지는 ⚠️**미실측**이다(probe.sh, story-03이 실측 확정 대상). 상대
   실행이 안 되는 것으로 판명되면, 설치 스크립트가 `<BATHOS_ROOT>`를 절대경로로
   치환해 `.codex/hooks.json`을 덮어쓰는 폴백을 쓸 것(이번 스코프에는 아직 그
   설치 스크립트가 없다 — 필요해지면 별도 스토리로 추가).
4. (다중 프로젝트 사용자 보조) `codex-adapter/config.toml.example`을 열어
   `<BATHOS_ROOT>`를 실제 절대경로로 치환한 뒤 `~/.codex/config.toml`에
   병합할 수도 있다(기존 `[hooks.*]`가 있으면 배열 항목을 추가) — 단 이 예시는
   **보조 지위**다(CT-WIRE-HOOKS secondary). `.codex/hooks.json`을 이미 쓰고
   있다면 Codex가 둘을 병합하며 경고를 낼 수 있다([문서]) — 한쪽으로 통일 권장.
5. Codex를 재시작하고, 아무 도구 호출이나 실행해 훅이 조용히 통과하는지 확인
   (기본값 = 무해).

## 동작 요약

### `pretooluse-gate.sh` — W3 게이트

- **트리거될 때만** `bathos gate show`를 호출한다(모든 도구 호출마다가 아님).
  tool_name은 **v0.144.5 실측 3종 + 공식 문서 별칭 3종의 합집합(6종, ADR-CX-02,
  2026-07-23)**을 매칭한다 — `shell`/`exec_command`(셸 실행)·`apply_patch`(파일
  편집)가 실측값, `Bash`/`Edit`/`Write`가 문서 별칭이다. P4는 `Bash`만 보고
  가정했다가(문서 예시만 신뢰) 실측으로 폐기됐고(P5), 이후 공식 문서가 이를
  별칭으로 서술하는 드리프트(D2)가 확인돼 **다시 합류**했다 — "한 번 폐기된
  값은 영원히 배제"가 아니라 "실측+문서 양쪽의 합집합을 항상 유지"가 이
  어댑터의 규율이다(story-01):
  - **T1 소스 쓰기**: `apply_patch`/`Edit`/`Write`가 `src/`·`core/crates/`·
    `core/src/`·`codex-adapter/hooks/` 경로를 언급하거나, `shell`/`exec_command`/
    `Bash`가(`sed -i`/`tee`/`cp`/`mv` 등으로) 같은 경로에 직접 쓸 때. `.agent-team/`
    전용 언급은 제외(문서 쓰기는 게이트 대상 아님).
  - **T2 웨이브 진입 명령**: `shell`/`exec_command`/`Bash`의 명령 문자열이
    `bathos wave advance|start|enter`, `wave5`, `wave4-implement`,
    `W5 진입/시작`, `implementation start` 등에 매치. (`apply_patch`/`Edit`/
    `Write`는 명령 실행이 아니므로 T2 대상이 아니다.)
- verdict가 **FAIL**일 때만 `exit 2` + stderr 사유로 차단한다. PASS/CONCERNS/
  verdict 확인 불가(bathos·state·report 모두 없음)는 전부 `exit 0`(fail-safe).
- verdict 조회 우선순위: `bathos gate show` > `manifest.json` 보수적 파싱 >
  `readiness-report-kr.md` 프론트매터(`.claude/hooks/gate-enforce.sh`와 동일
  3단 우선순위·동일 판정 의미론 — ADR-P4-2).

### `stop-save.sh` — SessionEnd 근사

- Codex에는 `SessionEnd`가 없다. 이 훅은 **매 턴 종료(Stop)마다** 다음을
  증분 수행해 근사한다:
  1. `bathos state show` 덤프를 `_state/session-state.json`에 원자적으로
     (`tmp` → `mv`) 교체 저장.
  2. `_state/codex-stop-save.log`에 1줄 append(500줄 롤링, 1행은 항상 마지막
     heavy-save epoch을 자기 기록).
  3. `_state/SESSION-SNAPSHOT.md`가 있으면 그날짜 아카이브로 복사(원본이
     없으면 아무 것도 만들지 않는다 — 훅은 서술을 생성하지 않는다).
  4. **디바운스**(기본 10초, `BATHOS_STOP_SAVE_DEBOUNCE`로 조정, 0=끔): 짧은
     간격의 연속 턴에서는 무거운 저장(1·3)을 건너뛰고 로그만 남긴다.
- **항상 exit 0.** `stop_hook_active=true`면 즉시 통과(루프 가드).

### `session-start.sh` — resume 재개 안내 (CT-HOOK-SESSIONSTART, story-14)

- `source=startup|resume`에서 `_state/SESSION-SNAPSHOT.md`가 있으면 stdout에
  1줄 주입: 저장분 존재·mtime·`$cold-start` 복원 안내 + `$save-session` 권장.
  **stdout이 컨텍스트로 처리된다**(Stop과 정반대 — Stop은 무출력이 계약).
- `source=clear|compact`이거나 스냅샷이 없으면 무주입. 항상 exit 0.
- 저장은 하지 않는다(읽기·안내만) — 저장은 `stop-save.sh`의 몫.

### `careful-guard-codex.sh` · `freeze-guard-codex.sh` — 안전 훅 (CT-SAFETY, story-15)

- **careful**: `shell`/`exec_command`/`Bash` 명령에서 파괴 명령(`rm -rf`·
  `DROP TABLE`·`git push --force` 등)을 감지하면 exit 2 차단. 패턴 목록은
  `.claude/hooks/careful-guard.sh`를 그대로 승계한다(정책 분기 금지).
- **freeze**: `apply_patch`/`Edit`/`Write`가 `BATHOS_OWNED_PATHS`(콜론 구분,
  Claude판과 동일 env — Codex 전용 상태 파일 신설 없음) 밖 경로를 편집하면
  exit 2 차단. `BATHOS_OWNED_PATHS` 미설정이면 freeze 비활성(통과).
  **스코프 한정**: Claude판 freeze-guard.sh의 fingerprint 승인 게이트(§5,
  jq 필수)는 포팅하지 않았다 — 이 어댑터는 jq 금지 규율이라 소유 경로 검사만
  이식했다(adapter-contracts.md §10 CT-SAFETY가 명시하는 스코프 그대로).
- 둘 다 matcher는 게이트 훅과 동일 광폭 6종을 재사용한다 — 4개 지점
  (`config.toml.example`·`.codex/hooks.json`·이 두 스크립트의 헤더 주석)의
  바이트 단위 일치를 `_test-codex-hooks.sh`가 자동 검증한다.
- 오차단 0이 판정 기준(US11-AC3) — 정상 명령/소유 경로 내부 편집을 막으면 FAIL.

### 정직한 한계 (읽어야 함)

- **LLM 서술 스냅샷 생성 불가** — `SESSION-SNAPSHOT.md`의 "★ 현재 상태" 같은
  서술은 훅이 아니라 모델 턴에서만 만들 수 있다. Codex에서도 세션 중
  `/save-session` 상당(프롬프트) 수동 실행을 병행해야 한다.
- **HTML 태스크리포트 생성은 범위 밖** — `session-report.sh` 이식은 P4
  스코프가 아니다.
- **저장 손실 창** — 최대 "1턴 + 디바운스(기본 10초)". SessionEnd 방식보다
  좁지만(세션 단위가 아니라 턴 단위) 0은 아니다.
- **Codex `tool_name` fail-open 리스크 — P5(2026-07-16)에서 해소됨** — P4는
  공식 문서 예시(`"Bash"`·`"apply_patch"`)만 보고 매칭했으나, 실제 설치에서
  `tool_name`이 다른 값(`shell`/`exec_command`)으로 와 T1/T2가 발화하지 않고
  게이트가 무력화되는 버그가 실측으로 확정됐다. `pretooluse-gate.sh`를
  실측 3종 tool_name(`shell`/`exec_command`/`apply_patch`)으로 갱신하고
  `_test-codex-hooks.sh`에 회귀 케이스(B-15~B-18)를 추가해 재발을 감시한다.
  **P5.1(2026-07-17) 후속 수정:** 실제 `apply_patch`는 패치를
  `tool_input.command`에 싣고 대상 파일을 **절대경로**로 지목하는데, 옛
  `SRC_ERE` 경계 `[^A-Za-z0-9_./-]`가 `/`를 경계로 인정하지 않아 절대경로 앞의
  `src/`가 T1에서 미발화(fail-open)했다. 경계에 `/`를 추가해 수정하고
  회귀 케이스 B-19~B-20으로 잠갔다.
  **단, 이 실측은 v0.144.5(macos-x86_64) 기준이다.** 타겟이 이후
  **v0.145.0+**(2026-07-21 stable, 2026-07-23 리드 결정)로 이동했고,
  ADR-CX-02(같은 날)가 matcher/tool_name case를 실측 3종+문서 별칭 3종
  합집합으로 이미 광폭화해 이런 버전 드리프트를 흡수하도록 했다 — 그래도
  `codex features list`·PreToolUse stdin의 v0.145.0+ 재실측은 하지 않은
  채로 완료를 주장하지 않는다(`probe.sh`, story-03·story-20이 그 절차).
- **라이브 인증 세션 미실행(남은 미실증)** — 이번 실측은 로컬 API 키 없이
  진행되어 `codex` 바이너리의 스키마·계약(이벤트명·필드·tool_name·exit 코드
  의미론)만 확인했다. 실제 인증된 세션에서 훅이 배선대로 호출되는지(config
  등록 반영·타이밍 등)는 아직 라이브로 실행해 보지 못했다 — 다음 실사용
  시 최우선 확인 항목으로 남긴다.
- **Windows 네이티브 미지원** — macOS/Linux/WSL만 지원(bash 3.2+ 호환 작성).
  `.ps1` 포트는 이번 스코프 밖이나, `commandWindows` 필드가 실측 스키마에
  존재함을 확인했다(Windows 네이티브 경로가 실제로 있다는 뜻 — 포트 시
  참고). Windows 사용자는 현재로선 WSL에서 Codex 구동을 권장
  (`scripts/wsl-setup.sh`).
- **네이티브 마이그레이션 대안(미검토)** — Codex는 외부 config(AGENTS_MD/
  HOOKS/COMMANDS/SUBAGENTS/MCP)의 네이티브 import를 지원한다. `to-codex.sh`
  스캐폴드 변환 대신 이 경로를 쓰는 방안은 아직 검토하지 않았다(후속 과제).

## 테스트

```bash
bash codex-adapter/hooks/_test-codex-hooks.sh
```

실제 Codex 설치나 실제 `bathos` 빌드 없이도 동작한다(스텁 `bathos`를
`mktemp` 디렉터리에 생성해 `gate show`/`state show` 출력을 재생). 20개
설계 테스트 케이스(게이트 B-1~B-10·B-15~B-20, 저장 B-11~B-14)를 세분화한
40개 assertion으로 검증하며, 전부 통과 시 `전체 통과` + exit 0으로 끝난다.
B-15~B-18은 P5(2026-07-16) 실측 회귀 케이스로, (a) `exec_command`의 웨이브
진입 명령 차단, (b) `shell`의 소스 직접쓰기(`sed -i`) 차단, (c) 폐기된
`Bash` 가정이 여전히 무해함(비트리거·bathos 미호출), (d) 무관 tool_name
통과를 계약화한다. B-19~B-20은 P5.1(2026-07-17) 절대경로 회귀로, 실제
`apply_patch`가 `tool_input.command`에 싣는 **절대경로**(`/…/src/…`)가
소스쓰기(T1)로 발화하는지(FAIL→exit 2)와, 넓어진 경계가 게이트 판정을
넘어 과차단하지 않는지(PASS→exit 0)를 계약화한다.

추가로 실제 `bathos` 바이너리(`core/target/release/bathos`)를 빌드해 두면
두 훅을 실제 프로젝트 state 사본에 대해 수동으로 돌려 통합 확인도 가능하다
(위 §동작 요약의 verdict 우선순위·원자적 저장이 실물로 동작함을 확인 완료
— 구현 노트 참고).

## 버전 드리프트 재검증 — `probe.sh` (CT-PROBE, story-03)

Codex CLI를 업그레이드할 때마다(또는 정기적으로) 다음을 실행해 D1(훅 스키마
평탄/중첩 병존)·tool_name 커버리지·훅 컨텍스트 env 실키·`.codex/hooks.json`
발화 여부를 재확인한다:

```bash
bash codex-adapter/probe.sh
```

- 정적 항목(`codex --version`·`codex features list`·hooks.json JSON 파싱)은
  자동으로 리포트에 기록된다(`codex-adapter/PROBE-RESULTS-<버전>.md`).
- 라이브 1턴이 필요한 항목(에코 훅 발화 관찰·tool_name 실측·훅 컨텍스트 env
  키·hooks.json 무편집 발화)은 스크립트가 준비만 하고, 사람이 인증 세션에서
  수동 절차(리포트 본문 §②·⑤에 기록됨)를 따른 뒤 리포트를 갱신한다 — 인증
  세션이 없으면 `[미실측 — 인증 세션 필요]`로 정직 기록한다(날조 금지).
- codex CLI가 PATH에 없으면 `PROBE-RESULTS-unknown.md`가 생성되고 정적 항목도
  "미실측"으로 기록된다 — 스택트레이스 없이 정상 종료(exit 0).
- 관측된 tool_name이 story-01 정본 matcher(6종: `Bash shell exec_command
  apply_patch Edit Write`) 밖이면 `E-CODEX-SCHEMA-DRIFT`로 취급하고, matcher/
  방출물을 갱신하기 전까지 업그레이드를 보류할 것을 권고한다(exceptions.md §5).
- 에코 훅은 임시 디렉터리(`mktemp -d`)에만 준비되며 `~/.codex/config.toml`을
  자동 편집하지 않는다 — 등록·해제는 사람이 수동으로 한다(홈 디렉터리 쓰기는
  사용자 승인 사안).

## 환경변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `BATHOS_BIN` | (자동 탐지) | `bathos` 바이너리 절대경로 강제 지정 |
| `BATHOS_STATE_DIR` | `<project>/.agent-team/_state` | state 디렉터리 강제 지정 |
| `BATHOS_PROJECT_DIR` | stdin의 `cwd` | 프로젝트 루트 강제 지정 |
| `BATHOS_GATE_SRC_ERE` | (§B2 기본 ERE) | pretooluse-gate.sh T1 소스 경로 패턴 오버라이드 |
| `BATHOS_STOP_SAVE_DEBOUNCE` | `10` | stop-save.sh 디바운스 초(0=끔) |

## 출처·근거

- 설계: `.agent-team/04-architecture/w2-runtime-p4-design-kr.md`
- 상위 포팅 판단: `docs/PORTABILITY-kr.md`, `docs/codex-adapter-kr.md`
- 스타일 정본: `.claude/hooks/{gate-enforce,careful-guard,session-start}.sh`
- Codex hooks 공식 문서(2026-07-16 확인): https://developers.openai.com/codex/hooks ,
  https://learn.chatgpt.com/docs/hooks
- **실측 SSOT(2026-07-16, P5, Phillip)**: Codex CLI **v0.144.5**
  (macos-x86_64) 실제 설치 바이너리에서 `codex features list` + PreToolUse
  훅 stdin/config 스키마를 직접 확인. 이 문서·훅·config 예시의 이벤트명·
  필드명·tool_name 값은 모두 이 실측에 근거한다(문서 예시만 보고 추정한
  것이 아님). 라이브 인증 세션은 미실행(auth 부재) — §정직한 한계 참고.
