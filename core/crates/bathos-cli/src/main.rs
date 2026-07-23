//! # bathos — BATHOS orchestration CLI
//!
//! Single static binary entry point invoked by Claude Code hooks and commands.
//! ADR-0006: `cargo build --release` → `target/release/bathos`
//!
//! ## Subcommand structure
//! ```text
//! bathos state init       # Create a schema-valid manifest.json seed
//! bathos state validate   # Validate manifest.json schema (B1)
//! bathos state show       # Print current manifest.json state (B1)
//! bathos gate verdict     # Record gate verdict (B3 implementation)
//! bathos gate show        # Print latest Implementation gate JSON (B3 implementation)
//! bathos story compile    # Storyfile staleness + validation (B3 implementation)
//! bathos story check-stale# Staleness check (B3 implementation)
//! bathos wave init        # Initialize wave set (D1 fix)
//! bathos wave activate    # Activate a wave (B2)
//! bathos wave show        # Print wave state (B2)
//! bathos route decide     # Recommend level (B2)
//! bathos route show       # Print level history (B2)
//! bathos plug list        # List plug modules + enabled state (B4)
//! bathos plug enable <id> # Enable a module (B4)
//! bathos plug disable <id># Disable a module (B4)
//! bathos audit append     # Append an audit log entry (B-1 fix: single Rust writer)
//! ```
//!
//! ## Exit code convention (hook integration)
//! - 0: success
//! - 1: general error
//! - 2: gate FAIL — gate-enforce.sh uses this code to block W5 entry
//!
//! ## gate-enforce.sh integration (api-contracts.md §C-1/C-2)
//! `bathos gate show` output format (gate-enforce.sh 4-a block):
//! ```json
//! {"gate_type":"Implementation","verdict":"PASS","issues_total":0,"issues_critical":0}
//! ```

use anyhow::{Context, Result};
use bathos_gate_engine::{GateEngine, GateIssue, VerdictAggregator};
use bathos_plug::{ModuleRegistry, PlugManager};
use bathos_state::{
    model::{GateType, Project},
    model_plan::{self, ModelPlan, Runtime, SessionBackend},
    schema::validate_manifest,
    store::StateStore,
    Verdict,
};
use bathos_story_engine::StoryEngine;
use clap::{Parser, Subcommand};
use std::path::{Path, PathBuf};

// ─────────────────────────────────────────────────────────────────────────────
// CLI structure definition (clap derive)
// ─────────────────────────────────────────────────────────────────────────────

#[derive(Parser)]
#[command(
    name = "bathos",
    version = env!("CARGO_PKG_VERSION"),
    about = "BATHOS 오케스트레이션 엔진 CLI",
    long_about = "BATHOS 17역할×7웨이브 오케스트레이션 엔진.\n\
                  Claude Code 훅·커맨드에서 호출하는 단일 바이너리."
)]
struct Cli {
    /// 상태 디렉터리 경로 (기본값: ./_state)
    #[arg(long, short, default_value = "./_state", global = true)]
    state_dir: PathBuf,

    /// 플러그 모듈 디렉터리 경로 (기본값: ./modules)
    #[arg(long, default_value = "./modules", global = true)]
    modules_dir: PathBuf,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// 상태 저장소 조작 (B1 구현 완료)
    State {
        #[command(subcommand)]
        action: StateAction,
    },
    /// 게이트 판정 기록/조회 (B3 구현)
    Gate {
        #[command(subcommand)]
        action: GateAction,
    },
    /// 웨이브 전이 (B2 구현 완료 — WaveEngine 직접 사용 권장)
    Wave {
        #[command(subcommand)]
        action: WaveAction,
    },
    /// Scale-Adaptive 라우팅 (B2 구현 완료 — Router 직접 사용 권장)
    Route {
        #[command(subcommand)]
        action: RouteAction,
    },
    /// 스토리 컴파일/staleness 검사 (B3 구현)
    Story {
        #[command(subcommand)]
        action: StoryAction,
    },
    /// 플러그 모듈 on/off·조회 (B4 구현 — IP팩·연구팩 등 W4 확장)
    Plug {
        #[command(subcommand)]
        action: PlugAction,
    },
    /// 감사 로그 조작 (B-1 수정: 단일 Rust writer로 bash 훅 통합)
    ///
    /// bash 훅이 직접 audit-log.jsonl에 쓰면 형식 불호환으로 체인이 깨진다.
    /// 이 서브커맨드를 경유하면 단일 Rust append_audit_entry 구현을 공유해
    /// verify_chain이 항상 통과한다.
    Audit {
        #[command(subcommand)]
        action: AuditAction,
    },
    /// 역할별 모델/런타임 선택 (W2 panes/model 설계, ADR-D-0005/0006)
    ///
    /// `_state/model-plan.json`(schema `bathos/model-plan@1`)을 단일 SSOT로 삼아
    /// Claude(fable5/sonnet5/haiku)·GLM·Codex 런타임을 역할별로 배선한다. plan
    /// 부재/미등재 역할은 항상 agent frontmatter `model:`로 폴백(100% 하위호환).
    Model {
        /// `.claude/agents/_base/` 탐색 기준 프로젝트 루트 (기본값: 현재 디렉터리)
        #[arg(long, default_value = ".")]
        root: PathBuf,
        #[command(subcommand)]
        action: ModelAction,
    },
    /// 위험 변경 diff 지문(fingerprint) 조회·승인 (Dynamis 신규, SS1 · CF-A1)
    ///
    /// `freeze-guard.sh`(위험 경로 Write/Edit/MultiEdit)가 재승인 방지를 위해 호출한다.
    /// 지문은 `bathos-state::fingerprint::normalize_diff`로 정규화한 unified diff의
    /// sha256이며, `manifest.json`의 `approved_fingerprints[]`에 캐시된다.
    Fingerprint {
        #[command(subcommand)]
        action: FingerprintAction,
    },
    /// 설치·배선 프리플라이트 진단 (온보딩 함정 차단)
    ///
    /// BATHOS_BIN·jq·Agent Teams 플래그·settings.json hooks 블록(주석키 무한대기 함정)·
    /// 훅 실행권한·manifest 스키마·감사 체인 무결성을 한 번에 점검한다.
    /// 오류 0건이면 exit 0, 하나라도 있으면 exit 1.
    Doctor {
        /// 프로젝트 루트 (기본값: 현재 디렉터리) — `.claude/` 탐색 기준
        #[arg(long, default_value = ".")]
        root: PathBuf,
    },
    /// BATHOS DevTools 파일럿 — 상태 관측·스토리 린트·산출물 doctor(read-only).
    ///
    /// `bathos-inspect`(read-only 크레이트)로 얇게 위임한다(ADR-P-0001=A).
    /// **네이밍 주의(ADR-P-0002):** bare `bathos doctor`(위 변형, 설치·배선
    /// 프리플라이트)와는 별개다 — 이 변형은 alias를 걸지 않고 오직
    /// `bathos inspect doctor`로만 노출된다.
    Inspect {
        #[command(flatten)]
        common: bathos_inspect::CommonArgs,
        #[command(subcommand)]
        action: bathos_inspect::InspectCommand,
    },
    /// Wave 패널 — tmux 실시간 분할 또는 bathos 대화식 TUI (B3/B4, ADR-D-0007~0009).
    ///
    /// 공유 데이터원은 `bathos inspect vm`과 동일한 `DashboardVM`(ADR-D-0007) — 이 서브커맨드는
    /// 새 상태 계층을 만들지 않고 프론트엔드 선택·위임만 한다.
    Panes {
        /// tui(대화식 TUI) | tmux(scripts/bathos-panes.sh 위임) | dump(비대화 1프레임 스냅샷).
        /// 미지정 + TTY: 대화형 선택(tmux/TUI) 후 `_state/panes/prefs`에 1줄 기억.
        #[arg(long, value_enum)]
        mode: Option<PanesMode>,
        /// 대상 `.agent-team` 디렉터리. 미지정 시 cwd에서 상향 탐색(bathos-inspect와 동일 규약).
        #[arg(long)]
        path: Option<PathBuf>,
        /// 표시할 웨이브(예: W5). 미지정 시 전체.
        #[arg(long)]
        wave: Option<String>,
        /// 렌더 주기(초) — tmux 위임 시 그대로 전달, TUI는 tick 간격으로 사용.
        #[arg(long, default_value_t = 2)]
        interval: u64,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, clap::ValueEnum)]
enum PanesMode {
    Tui,
    Tmux,
    Dump,
}

// ── plug subcommands (B4 implementation) ─────────────────────────────────────

#[derive(Subcommand)]
enum PlugAction {
    /// 모듈 목록 + 활성 상태를 JSON으로 출력한다 (modules/ 레지스트리 ⨉ manifest 상태).
    List,
    /// 모듈을 활성화한다.
    Enable {
        /// 모듈 id (예: ip | research)
        module_id: String,
    },
    /// 모듈을 비활성화한다.
    Disable {
        /// 모듈 id (예: ip | research)
        module_id: String,
    },
}

// ── state subcommands ─────────────────────────────────────────────────────────

#[derive(Subcommand)]
enum StateAction {
    /// manifest.json을 JSON Schema로 검증한다.
    ///
    /// 성공: exit 0 + "VALID" 출력
    /// 실패: exit 1 + 위반 목록 출력
    Validate,
    /// manifest.json의 현재 상태를 JSON으로 출력한다.
    Show,
    /// 스키마 유효 manifest.json seed를 생성한다 (kickoff 부트스트랩).
    ///
    /// `Project::new` + `StateStore::create`(쓰기 전 스키마 검증)로 항상 유효한 seed를 만든다.
    /// 기존 manifest가 있으면 `--force` 없이는 덮어쓰지 않는다.
    Init {
        /// 제품 코드명 (codename, 예: BATHOS).
        #[arg(long)]
        codename: String,
        /// Scale-Adaptive 레벨 (0~4). 미지정 시 0 (잠정 — /route에서 확정).
        #[arg(long, default_value_t = 0)]
        level: u8,
        /// 주 언어 코드 (기본 ko).
        #[arg(long, default_value = "ko")]
        lang: String,
        /// 프로젝트 ID (미지정 시 bathos-<uuid> 자동생성; 지정 시 'bathos-' 접두 필수).
        #[arg(long)]
        project_id: Option<String>,
        /// 기존 manifest.json을 덮어쓴다.
        #[arg(long)]
        force: bool,
    },
}

// ── gate subcommands (B3 implementation) ─────────────────────────────────────

#[derive(Subcommand)]
enum GateAction {
    /// 게이트 판정을 StateStore에 기록한다.
    ///
    /// # 종료 코드
    /// - 0: PASS 또는 CONCERNS 판정
    /// - 2: FAIL 판정 (gate-enforce.sh가 W5 진입 차단에 사용)
    ///
    /// # H-4 수정
    /// `--wave-id` 옵션 추가. 미지정 시 gate_type에서 자동 추론 (W3 하드코딩 제거).
    Verdict {
        /// 게이트 종류 (Brief|Usp|Plan|Implementation|Release)
        gate_type: String,
        /// 판정 (PASS|CONCERNS|FAIL)
        verdict: String,
        /// 판정 주체 역할명 (FACILITATOR 불변식 — 비어있음 금지)
        facilitator: String,
        /// 리포트 경로 (선택, 예: 03-story-engineering/readiness-report-kr.md)
        #[arg(long)]
        report: Option<String>,
        /// 대상 스토리 키 (선택, 예: 1-2-payment-auth)
        #[arg(long)]
        story_key: Option<String>,
        /// 이슈 목록 JSON 문자열 (선택, 예: '[{"level":"critical","description":"...","source":"..."}]')
        #[arg(long)]
        issues_json: Option<String>,
        /// 게이트를 기록할 웨이브 ID (미지정 시 gate_type에서 자동 추론).
        /// 예: W3(Implementation), W1(Usp), W2(Plan), W6(Release), W0(Brief)
        #[arg(long)]
        wave_id: Option<String>,
    },
    /// 가장 최신 Implementation 게이트 상태를 JSON으로 출력한다.
    ///
    /// gate-enforce.sh 4-a 블록이 호출하는 서브커맨드.
    /// 출력 형식: {"gate_type":"Implementation","verdict":"PASS|CONCERNS|FAIL",...}
    /// 게이트 없음: 빈 stdout (exit 0)
    Show,
}

// ── wave subcommands (B2 wrapper) ────────────────────────────────────────────

#[derive(Subcommand)]
enum WaveAction {
    /// 웨이브 셋을 초기화한다 (WaveEngine::initialize_waves 호출).
    ///
    /// D1 수정: 이 서브커맨드가 없어 `bathos wave activate`가 항상 E-WAVE-NOT-FOUND 였다.
    ///
    /// 사용 예: `bathos wave init --wave-set W0,W1,W2,W3,W5,W6`
    Init {
        /// 초기화할 웨이브 ID 목록 (쉼표 구분, 예: "W0,W1,W2,W3,W5,W6")
        /// 목록에 없는 W0~W6 웨이브는 Skipped로 초기화된다.
        #[arg(long = "wave-set")]
        wave_set: String,
    },
    /// 웨이브를 active로 전이한다
    Activate {
        /// 웨이브 ID (W0~W6)
        wave_id: String,
    },
    /// 모든 웨이브 상태를 JSON으로 출력한다
    Show,
}

// ── route subcommands (B2 wrapper) ───────────────────────────────────────────

#[derive(Subcommand)]
enum RouteAction {
    /// 현재 레벨 결정 이력을 출력한다
    Show,
    /// Stakes(JSON)를 분석해 추천 레벨을 계산한다. stdin 또는 --stakes-json.
    ///
    /// Stakes JSON 형식:
    ///   {"scope":"feature","novelty":true,"regulation_ip":false,"team_size":"medium"}
    ///   - scope: bug|feature|module|product 등 (불명확 시 medium 취급)
    ///   - novelty: 신규성(bool) / regulation_ip: 규제·IP(bool) / team_size: solo|medium|large
    ///
    /// 기본은 **추천만** 출력(커밋 안 함). --confirm <0-4> 지정 시에만 manifest에 확정 기록.
    Decide {
        /// Stakes JSON (미지정 시 stdin에서 읽음)
        #[arg(long)]
        stakes_json: Option<String>,
        /// 추천을 수용해 이 레벨로 확정·기록한다 (User Sovereignty: 명시적 확정). 0~4
        #[arg(long)]
        confirm: Option<u8>,
    },
}

// ── story subcommands (B3 implementation) ────────────────────────────────────

#[derive(Subcommand)]
enum StoryAction {
    /// 스토리파일의 D1 완전성·D2 출처 추적을 검증한다.
    ///
    /// 스토리파일 마크다운 내용을 stdin으로 받아 검증한다.
    /// 성공(valid): exit 0 + JSON 결과 출력
    /// 실패(E-CTX-LOSS): exit 1 + 에러 메시지
    Compile {
        /// 스토리 슬러그 (예: "1-1-init")
        slug: String,
        /// 스토리파일 경로 (stdin 대신 파일에서 읽기)
        #[arg(long)]
        file: Option<PathBuf>,
    },
    /// 스토리파일의 staleness를 검사한다 (D3 신선도).
    ///
    /// --stored-hash와 --upstream-file들을 비교해 staleness를 판정한다.
    /// stale: exit 1 + E-STALE 메시지
    /// fresh: exit 0 + "FRESH" 출력
    CheckStale {
        /// 스토리 슬러그 (예: "1-1-init")
        slug: String,
        /// 저장된 source_hash (StoryFile 프론트매터 값)
        #[arg(long)]
        stored_hash: String,
        /// 상류 파일 경로들 (여러 개 가능)
        #[arg(long = "upstream")]
        upstream_files: Vec<PathBuf>,
    },
}

// ── model subcommands (W2 panes/model design §A1.4) ──────────────────────────

#[derive(Subcommand)]
enum ModelAction {
    /// 역할별 유효 runtime/model 표를 출력한다 (source: plan|default|frontmatter|runtime-default).
    Show {
        /// 표시 대상을 이 웨이브의 역할군으로 제한 (예: W5). 미지정 시 plan에 등재된
        /// 역할 + agents-dir에서 발견한 전 역할의 합집합을 표시.
        #[arg(long)]
        wave: Option<String>,
        #[arg(long)]
        json: bool,
    },
    /// 역할의 runtime/model을 plan에 기록한다 (변경분만 — 리드 세션 전용 단일 쓰기 경로).
    Set {
        /// agent 정의 slug (예: phillip-backend-engineer)
        slug: String,
        #[arg(long)]
        runtime: String,
        #[arg(long)]
        model: Option<String>,
        #[arg(long = "reasoning-effort")]
        reasoning_effort: Option<String>,
    },
    /// plan에서 역할 항목을 제거한다 (→ frontmatter 폴백으로 복귀).
    Unset { slug: String },
    /// 현재 세션의 실제 백엔드(session_backend)를 판별해 plan에 기록한다
    /// (env `ANTHROPIC_BASE_URL`에 `api.z.ai` 포함 → glm, 그 외 → claude).
    Detect,
    /// GLM/Codex 혼합 배치 규칙(R1~R4)을 검증한다. PASS=exit 0 / 위반=exit 2 + 해소 선택지.
    Validate {
        /// 검증 대상 웨이브 (예: W5). 미지정 시 plan에 등재된 모든 역할을 대상으로 검증.
        #[arg(long)]
        wave: Option<String>,
    },
    /// 한 역할의 유효 runtime/model/적용채널을 1줄 출력한다 (스크립트 소비용).
    Resolve {
        slug: String,
        #[arg(long)]
        json: bool,
    },
}

/// `waves.<W?>` 역할군(role↔wave 배정). BATHOS의 정본은 프로젝트 `CLAUDE.md` §1/§2의
/// 역할·모델 표다 — 여기서는 그 표를 `bathos model show/validate --wave`가 참조할 수
/// 있는 정적 상수로 옮겨 적었을 뿐, 새로운 정책을 만들어내지 않는다(날조 금지).
/// W3/W6의 겸직 보조 역할(Timothy)·독립 리뷰어(Thomas/Matthias)도 CLAUDE.md 표기 그대로 포함.
fn wave_role_slugs(wave_id: &str) -> Option<&'static [&'static str]> {
    match wave_id.to_ascii_uppercase().as_str() {
        "W0" => Some(&["caleb-market-analyst", "john-reverse-specialist"]),
        "W1" => Some(&["john-reverse-specialist", "caleb-market-analyst"]),
        "W2" => Some(&[
            "joshua-service-planner",
            "james-architect",
            "jonnathan-chief-designer",
        ]),
        "W3" => Some(&[
            "matthew-story-engineer",
            "thomas-code-reviewer",
            "matthias-qa-validator",
            "timothy-doc-specialist",
        ]),
        "W4" => Some(&["mark-ip-specialist", "nathanael-research-writer"]),
        "W5" => Some(&[
            "phillip-backend-engineer",
            "andrew-frontend-engineer",
            "stephen-ml-engineer",
        ]),
        "W6" => Some(&[
            "thomas-code-reviewer",
            "timothy-doc-specialist",
            "matthias-qa-validator",
            "mishael-security-specialist",
            "hananiah-refactoring-specialist",
            "martin-monitoring-reporter",
        ]),
        _ => None,
    }
}

// ── audit subcommands (B-1 fix) ──────────────────────────────────────────────

#[derive(Subcommand)]
enum AuditAction {
    /// 감사 로그에 항목 1건을 append한다.
    ///
    /// **B-1 수정:** bash 훅이 직접 audit-log.jsonl에 쓰면 hash_self 누락·genesis 형식 불일치로
    /// verify_chain이 항상 AuditChainBroken을 반환했다. 이 CLI를 경유하면 Rust의 단일
    /// append_audit_entry 구현을 사용해 체인 무결성이 항상 유지된다.
    ///
    /// **fail-safe:** state/audit 파일이 없어도 조용히 생성하거나 exit 0. 훅을 절대 차단하지 않는다.
    ///
    /// Andrew의 훅이 호출하는 시그니처:
    ///   `bathos --state-dir <dir> audit append --actor <STR> --action <STR> --target <STR>`
    Append {
        /// 행위자 (예: hook | User | Paul | WaveEngine)
        #[arg(long)]
        actor: String,
        /// 액션 (예: tool.bash_called | wave.activated | gate.pass)
        #[arg(long = "action")]
        audit_action: String,
        /// 대상 (예: manifest.json | W3 | rm -rf /)
        #[arg(long)]
        target: String,
    },
    /// 감사 해시체인 무결성을 검증한다 (E-AUDIT-TAMPER 탐지).
    ///
    /// tamper-evident 약속을 사용자가 직접 확인하는 경로.
    /// 체인 무결 → exit 0, 단절/변조 → exit 1.
    Verify,
    /// (SEC-02) 레거시 무열쇠 체인을 키드 HMAC-SHA256으로 1회 재봉인한다.
    ///
    /// 마이그레이션 절차: ①레거시 sha256으로 기존 체인 검증(변조 세탁 방지) →
    /// ②`<log>.presealbak`로 백업 → ③전 항목을 키로 재계산 → ④키드 검증.
    /// 성공 → exit 0(재봉인 건수 출력), 기존 체인 손상/변조 → exit 1.
    /// 키 소스: `BATHOS_AUDIT_KEY` 환경변수(권장·out-of-band) → 없으면 `<log>.audit-key`(0600, 자동생성).
    Reseal,
}

// ── fingerprint subcommands (Dynamis new, SS1 · CF-A1) ───────────────────────

#[derive(Subcommand)]
enum FingerprintAction {
    /// diff 파일을 정규화·해싱해 승인 캐시와 대조한다.
    ///
    /// 출력: `{"status":"approved|new","hash":"<sha256>"}` (항상 exit 0 — fail-safe).
    /// `freeze-guard.sh`가 위험 경로 변경 시도마다 호출한다.
    Check {
        /// unified diff 텍스트가 담긴 파일 경로 (훅이 old_string/new_string으로 재구성해 씀)
        #[arg(long)]
        diff_file: PathBuf,
    },
    /// 지문을 캐시에 승인 등록한다 (manifest.json 갱신 + audit append 동반).
    Approve {
        /// sha256 지문 (64자 소문자 hex) — 보통 `check`의 출력값을 그대로 전달
        #[arg(long)]
        hash: String,
        /// 승인 주체 (역할명 또는 "hook:<name>")
        #[arg(long)]
        actor: String,
        /// 대상 경로/행위 분류 (예: hooks, ci, w5-entry). 미지정 시 "unspecified".
        #[arg(long, default_value = "unspecified")]
        scope: String,
    },
    /// 현재 승인 캐시 전체를 JSON 배열로 출력한다.
    List,
}

// ─────────────────────────────────────────────────────────────────────────────
// Execution entry point
// ─────────────────────────────────────────────────────────────────────────────

fn main() {
    let cli = Cli::parse();
    let result = run(cli);
    match result {
        Ok(exit_code) => std::process::exit(exit_code),
        Err(e) => {
            eprintln!("[bathos] 오류: {:#}", e);
            std::process::exit(1);
        }
    }
}

/// CLI routing — delegates each subcommand to its handler.
/// Return value is the exit code (0=success, 1=error, 2=gate FAIL).
fn run(cli: Cli) -> Result<i32> {
    match cli.command {
        Commands::State { action } => handle_state(action, &cli.state_dir),
        Commands::Gate { action } => handle_gate(action, &cli.state_dir),
        Commands::Wave { action } => handle_wave(action, &cli.state_dir),
        Commands::Route { action } => handle_route(action, &cli.state_dir),
        Commands::Story { action } => handle_story(action, &cli.state_dir),
        Commands::Plug { action } => handle_plug(action, &cli.state_dir, &cli.modules_dir),
        Commands::Model { root, action } => handle_model(action, &cli.state_dir, &root),
        Commands::Audit { action } => handle_audit(action, &cli.state_dir),
        Commands::Fingerprint { action } => handle_fingerprint(action, &cli.state_dir),
        Commands::Doctor { root } => handle_doctor(&root, &cli.state_dir, &cli.modules_dir),
        Commands::Inspect { common, action } => Ok(handle_inspect(common, action)),
        Commands::Panes {
            mode,
            path,
            wave,
            interval,
        } => Ok(handle_panes(mode, path, wave, interval)),
    }
}

/// `bathos inspect <sub>` delegation — forwards to the single `bathos-inspect` (read-only crate).
/// A context-resolution failure (`--path` auto-discovery, E-PATH-NOT-FOUND) returns after having
/// already printed its exit-1 guidance, so here we simply propagate that code.
/// [Source: story-1-1-crate-scaffold-cli-kr.md AC, api-contracts-kr.md §C]
fn handle_inspect(
    common: bathos_inspect::CommonArgs,
    action: bathos_inspect::InspectCommand,
) -> i32 {
    match bathos_inspect::resolve_ctx(common) {
        Ok(ctx) => bathos_inspect::run(action, ctx),
        Err(exit_code) => exit_code,
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Panes handler (W2 panes/model design §B4.2) — `bathos panes` frontend selection/delegation
// ─────────────────────────────────────────────────────────────────────────────
//
// This handler picks and delegates to exactly one of the three frontends — it never builds a
// second state layer of its own. `--mode dump`/`tui` both go through `bathos-tui`'s public API
// (`render_dump`/`run_tui`), which itself only ever calls `bathos-inspect`'s `load_project` +
// `load_story_cards` + `build_vm` (ADR-D-0007) — the exact same pipeline `report`/`inspect vm`
// use. `--mode tmux` execs `scripts/bathos-panes.sh` (a separate process, ADR-D-0009).

fn handle_panes(
    mode: Option<PanesMode>,
    path: Option<PathBuf>,
    wave: Option<String>,
    interval: u64,
) -> i32 {
    let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    let agent_team_path = match bathos_inspect::context::resolve_agent_team_path(path, &cwd) {
        Ok(p) => p,
        Err(e) => {
            eprintln!("{e}");
            return 1;
        }
    };

    let resolved_mode = mode.unwrap_or_else(|| resolve_default_mode(&agent_team_path));

    match resolved_mode {
        PanesMode::Tui => {
            if !std::io::IsTerminal::is_terminal(&std::io::stdout()) {
                eprintln!(
                    "[E-PANES-NOTTY] 비대화형 환경(TTY 아님)에서는 대화식 TUI를 실행할 수 없습니다."
                );
                eprintln!("  안내: 파이프/CI에서는 `bathos panes --mode dump`를 사용하세요.");
                return 1;
            }
            bathos_tui::run_tui(
                &agent_team_path,
                bathos_tui::TuiOpts {
                    wave,
                    interval: std::time::Duration::from_secs(interval),
                },
            )
        }

        PanesMode::Dump => {
            let pv = match bathos_inspect::load_project(
                &agent_team_path,
                bathos_inspect::LoadOpts { verify_chain: true },
            ) {
                Ok(pv) => pv,
                Err(e) => {
                    eprintln!("[bathos panes] {e}");
                    return 1;
                }
            };
            let ctx = bathos_inspect::InspectCtx {
                agent_team_path: agent_team_path.clone(),
                json: false,
                verbose: false,
                strict: false,
            };
            let stories = bathos_inspect::dashboard::load_story_cards(&ctx, &pv);
            let vm = bathos_inspect::dashboard::viewmodel::build_vm(&pv, &stories);
            let (width, height) = crossterm::terminal::size().unwrap_or((100, 30));
            print!(
                "{}",
                bathos_tui::render_dump(&vm, wave.as_deref(), width, height)
            );
            0
        }

        PanesMode::Tmux => exec_tmux_panes(&agent_team_path, wave.as_deref(), interval),
    }
}

/// No `--mode` given: honors a previously-saved preference (`_state/panes/prefs`) if present;
/// otherwise, on a real TTY, asks once and saves the answer (§B4.2 "선택 결과를 기억"). On a
/// non-TTY with no saved preference, defaults to `dump` — the only mode that is always safe to
/// run unattended (matches `--mode tui`'s own E-PANES-NOTTY guard: a script/CI invocation with
/// no prior preference should get inert, pipeable text, never an interactive prompt it can't
/// answer).
fn resolve_default_mode(agent_team_path: &Path) -> PanesMode {
    let prefs_path = agent_team_path.join("_state/panes/prefs");
    if let Ok(saved) = std::fs::read_to_string(&prefs_path) {
        match saved.trim() {
            "tmux" => return PanesMode::Tmux,
            "tui" => return PanesMode::Tui,
            _ => {}
        }
    }

    if !std::io::IsTerminal::is_terminal(&std::io::stdout()) {
        return PanesMode::Dump;
    }

    let tmux_available = command_exists("tmux");
    eprintln!("패널 프론트엔드를 선택하세요:");
    eprintln!(
        "  [1] tmux 실시간 분할{}",
        if tmux_available {
            " (tmux 감지됨)"
        } else {
            " (미설치 — 선택 불가)"
        }
    );
    eprintln!("  [2] bathos TUI");
    eprint!("선택 [1/2]: ");
    use std::io::Write;
    let _ = std::io::stdout().flush();

    let mut line = String::new();
    let chosen = if std::io::stdin().read_line(&mut line).is_ok() {
        match line.trim() {
            "1" if tmux_available => PanesMode::Tmux,
            "1" => {
                eprintln!("tmux 미설치 — bathos TUI로 대체합니다.");
                PanesMode::Tui
            }
            _ => PanesMode::Tui,
        }
    } else {
        PanesMode::Tui
    };

    let pref_str = match chosen {
        PanesMode::Tmux => "tmux",
        PanesMode::Tui => "tui",
        PanesMode::Dump => "dump",
    };
    if let Some(dir) = prefs_path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let _ = std::fs::write(&prefs_path, pref_str);

    chosen
}

/// `--mode tmux`: execs `scripts/bathos-panes.sh up` (search order per §B4.2: `<project
/// root>/scripts/` then `$BATHOS_HOME/scripts/`). A project root here is the agent_team_path's
/// parent (`.agent-team`'s sibling), matching `bathos-panes.sh`'s own `--project` contract.
fn exec_tmux_panes(agent_team_path: &Path, wave: Option<&str>, interval: u64) -> i32 {
    let project_root = agent_team_path
        .parent()
        .map(Path::to_path_buf)
        .unwrap_or_else(|| agent_team_path.to_path_buf());

    let candidate = project_root.join("scripts/bathos-panes.sh");
    let script_path = if candidate.is_file() {
        Some(candidate)
    } else if let Ok(home) = std::env::var("BATHOS_HOME") {
        let p = PathBuf::from(home).join("scripts/bathos-panes.sh");
        if p.is_file() {
            Some(p)
        } else {
            None
        }
    } else {
        None
    };

    let Some(script_path) = script_path else {
        eprintln!(
            "[E-PANES-SCRIPT-ABSENT] scripts/bathos-panes.sh를 찾을 수 없습니다 \
             ({}/scripts/ 및 $BATHOS_HOME/scripts/ 모두 확인).",
            project_root.display()
        );
        eprintln!(
            "  수동 실행: bash <저장소>/scripts/bathos-panes.sh up --project '{}'{}",
            project_root.display(),
            wave.map(|w| format!(" --waves \"{w}\""))
                .unwrap_or_default()
        );
        return 4;
    };

    let mut cmd = std::process::Command::new("bash");
    cmd.arg(&script_path)
        .arg("up")
        .arg("--project")
        .arg(&project_root)
        .arg("--interval")
        .arg(interval.to_string());
    if let Some(w) = wave {
        cmd.arg("--waves").arg(w);
    }

    match cmd.status() {
        Ok(status) => status.code().unwrap_or(1),
        Err(e) => {
            eprintln!("[bathos panes] scripts/bathos-panes.sh 실행 실패: {e}");
            1
        }
    }
}

// (`command_exists` is defined once, further below, alongside the `doctor` handler — reused
// here rather than duplicated.)

// ─────────────────────────────────────────────────────────────────────────────
// State handler (B1 full implementation)
// ─────────────────────────────────────────────────────────────────────────────

fn handle_state(action: StateAction, state_dir: &Path) -> Result<i32> {
    match action {
        StateAction::Validate => {
            let manifest_path = state_dir.join("manifest.json");
            let content = std::fs::read_to_string(&manifest_path)
                .with_context(|| format!("manifest.json 읽기 실패: {}", manifest_path.display()))?;

            let value: serde_json::Value =
                serde_json::from_str(&content).with_context(|| "manifest.json JSON 파싱 실패")?;

            match validate_manifest(&value) {
                Ok(()) => {
                    println!("VALID — manifest.json 스키마 검증 통과");
                    Ok(0)
                }
                Err(e) => {
                    eprintln!("[E-STATE-CORRUPT] 스키마 검증 실패:\n{}", e);
                    Ok(1)
                }
            }
        }

        StateAction::Show => {
            let store = StateStore::open(state_dir)
                .with_context(|| format!("state_dir={} 열기 실패", state_dir.display()))?;

            let project = store.project();
            let json = serde_json::to_string_pretty(project).context("프로젝트 직렬화 실패")?;

            println!("{}", json);
            Ok(0)
        }

        StateAction::Init {
            codename,
            level,
            lang,
            project_id,
            force,
        } => {
            // Schema-valid manifest seed for kickoff bootstrap.
            // Rationale: the engine previously had no create/init command, so the very
            // first manifest.json was hand-authored by an LLM against a strict schema —
            // unreliable across runtimes (Codex-run kickoff produced an invalid
            // manifest). This stamps a guaranteed-valid seed.
            let manifest_path = state_dir.join("manifest.json");
            if manifest_path.exists() && !force {
                eprintln!(
                    "[E-STATE-EXISTS] manifest.json이 이미 존재합니다: {}",
                    manifest_path.display()
                );
                eprintln!("[bathos state init] 덮어쓰려면 --force 를 지정하세요.");
                return Ok(1);
            }
            if level > 4 {
                eprintln!("[E-ARG] --level 은 0~4 여야 합니다 (받음: {level}).");
                return Ok(1);
            }
            if codename.is_empty() {
                eprintln!("[E-ARG] --codename 은 비어 있을 수 없습니다.");
                return Ok(1);
            }
            if lang.chars().count() < 2 {
                eprintln!("[E-ARG] --lang 은 두 글자 이상이어야 합니다 (받음: {lang}).");
                return Ok(1);
            }
            // Project::new fills the schema-required defaults (project_id=bathos-<uuid>,
            // status=Active, created=now(RFC3339), empty relation vecs).
            let mut project = Project::new(codename, level);
            project.lang = lang;
            if let Some(pid) = project_id {
                if pid.strip_prefix("bathos-").is_none_or(str::is_empty) {
                    eprintln!(
                        "[E-ARG] --project-id 는 'bathos-' 뒤에 식별자가 있어야 합니다 (받음: {pid})."
                    );
                    return Ok(1);
                }
                project.project_id = pid;
            }
            let project_id = project.project_id.clone();
            // StateStore::create validates the manifest against the JSON Schema before
            // the atomic write, so a successful return guarantees a valid seed.
            StateStore::create(state_dir, project)
                .with_context(|| format!("state seed 생성 실패: {}", state_dir.display()))?;
            println!(
                "[bathos state init] ✓ manifest.json 생성: {} (project_id={project_id}, level={level})",
                manifest_path.display()
            );
            Ok(0)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Gate handler (B3 implementation)
// ─────────────────────────────────────────────────────────────────────────────

fn handle_gate(action: GateAction, state_dir: &Path) -> Result<i32> {
    match action {
        // ── bathos gate show ─────────────────────────────────────────────────
        // Core subcommand invoked by the gate-enforce.sh 4-a block.
        // Prints the latest Implementation gate as JSON.
        // No gate → empty stdout (exit 0, handled by the hook's [[ -n "$GATE_OUTPUT" ]])
        GateAction::Show => {
            let store = StateStore::open(state_dir)
                .with_context(|| format!("state 읽기 실패: {}", state_dir.display()))?;

            let project = store.project();

            match GateEngine::show_latest_implementation_gate(project) {
                None => {
                    // No gate → empty stdout (hook branches to its fail-safe path)
                    Ok(0)
                }
                Some(gate) => {
                    // gate-enforce.sh expected output:
                    // {"gate_type":"Implementation","verdict":"PASS|CONCERNS|FAIL",...}
                    let output = serde_json::json!({
                        "gate_type": format!("{:?}", gate.gate_type),
                        "verdict": VerdictAggregator::verdict_str(&gate.verdict),
                        "issues_total": gate.issues_total,
                        "issues_critical": gate.issues_critical,
                        "facilitator": gate.facilitator,
                        "wave_id": gate.wave_id,
                        "decided": gate.decided,
                    });
                    println!("{}", output);
                    Ok(0)
                }
            }
        }

        // ── bathos gate verdict ───────────────────────────────────────────────
        // Records the gate verdict in the StateStore.
        // Returns exit 2 on a FAIL verdict (for direct gate-enforce.sh invocation).
        //
        // H-4 fix: added --wave-id option. When unspecified, inferred from gate_type.
        GateAction::Verdict {
            gate_type,
            verdict,
            facilitator,
            report,
            story_key,
            issues_json,
            wave_id,
        } => {
            // Parse input
            let gate_type_parsed = GateEngine::parse_gate_type(&gate_type)
                .with_context(|| format!("gate_type 파싱 실패: {gate_type}"))?;
            let verdict_parsed = GateEngine::parse_verdict(&verdict)
                .with_context(|| format!("verdict 파싱 실패: {verdict}"))?;

            // Parse issue list (when --issues-json is provided)
            let issues: Vec<GateIssue> = if let Some(json_str) = issues_json {
                serde_json::from_str(&json_str).with_context(|| "issues_json 파싱 실패")?
            } else {
                vec![]
            };

            // H-4: determine wave_id — explicit value takes precedence, otherwise inferred from gate_type
            let actual_wave_id = wave_id
                .unwrap_or_else(|| infer_wave_id_from_gate_type(&gate_type_parsed).to_string());

            // Record verdict in the StateStore
            let mut store = StateStore::open(state_dir)
                .with_context(|| format!("state 열기 실패: {}", state_dir.display()))?;

            let recorded = GateEngine::record_verdict(
                &mut store,
                &actual_wave_id,
                gate_type_parsed,
                verdict_parsed.clone(),
                &issues,
                &facilitator,
                report,
                story_key,
            )
            .with_context(|| "게이트 판정 기록 실패")?;

            eprintln!(
                "[bathos gate verdict] {} — gate_id={} wave_id={} facilitator={}",
                VerdictAggregator::verdict_str(&recorded.verdict),
                recorded.gate_id,
                recorded.wave_id,
                recorded.facilitator
            );

            // Exit code: FAIL = 2 (blocks when gate-enforce.sh invokes directly)
            match verdict_parsed {
                Verdict::Fail => {
                    eprintln!("[bathos gate verdict] ⛔ FAIL — exit 2 (다음 웨이브 진입 차단)");
                    Ok(2)
                }
                _ => Ok(0),
            }
        }
    }
}

/// Infers the default wave_id from gate_type (H-4: removed W3 hardcoding).
///
/// - Brief → W0 (Analysis gate)
/// - Usp → W1 (Discovery gate)
/// - Plan → W2 (Design gate)
/// - Implementation → W3 (Story Eng & Readiness gate)
/// - Release → W6 (Verify·Doc·Report gate)
fn infer_wave_id_from_gate_type(gate_type: &GateType) -> &'static str {
    match gate_type {
        GateType::Brief => "W0",
        GateType::Usp => "W1",
        GateType::Plan => "W2",
        GateType::Implementation => "W3",
        GateType::Release => "W6",
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Wave handler (B2 complete, CLI wrapper)
// ─────────────────────────────────────────────────────────────────────────────

fn handle_wave(action: WaveAction, state_dir: &Path) -> Result<i32> {
    match action {
        // ── bathos wave init ──────────────────────────────────────────────────
        // D1 fix: exposes WaveEngine::initialize_waves() to the CLI.
        // Without this command `bathos wave activate` always returned E-WAVE-NOT-FOUND.
        WaveAction::Init { wave_set } => {
            use bathos_wave_engine::WaveEngine;
            let mut store = StateStore::open(state_dir)
                .with_context(|| format!("state 열기 실패: {}", state_dir.display()))?;

            // Parse comma-separated wave IDs (e.g. "W0,W1,W2,W3,W5,W6")
            let wave_ids: Vec<String> = wave_set
                .split(',')
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect();

            if wave_ids.is_empty() {
                anyhow::bail!("--wave-set이 비어있습니다. 예: --wave-set W0,W1,W2,W3,W5,W6");
            }

            WaveEngine
                .initialize_waves(&mut store, &wave_ids)
                .with_context(|| format!("웨이브 초기화 실패: {:?}", wave_ids))?;

            eprintln!(
                "[bathos wave init] ✅ 초기화 완료 — Pending: {:?} / 나머지: Skipped",
                wave_ids
            );
            Ok(0)
        }

        WaveAction::Activate { wave_id } => {
            use bathos_wave_engine::WaveEngine;
            let mut store = StateStore::open(state_dir)
                .with_context(|| format!("state 열기 실패: {}", state_dir.display()))?;

            WaveEngine
                .activate_wave(&mut store, &wave_id)
                .with_context(|| format!("웨이브 {wave_id} 활성화 실패"))?;

            eprintln!("[bathos wave activate] {wave_id} → Active");
            Ok(0)
        }
        WaveAction::Show => {
            let store = StateStore::open(state_dir)
                .with_context(|| format!("state 열기 실패: {}", state_dir.display()))?;

            let waves = &store.project().waves;
            let json = serde_json::to_string_pretty(waves).context("웨이브 직렬화 실패")?;
            println!("{}", json);
            Ok(0)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Route handler (B2 complete, CLI wrapper)
// ─────────────────────────────────────────────────────────────────────────────

fn handle_route(action: RouteAction, state_dir: &Path) -> Result<i32> {
    match action {
        RouteAction::Show => {
            let store = StateStore::open(state_dir)
                .with_context(|| format!("state 열기 실패: {}", state_dir.display()))?;

            let routing = &store.project().routing;
            let json = serde_json::to_string_pretty(routing).context("routing 직렬화 실패")?;
            println!("{}", json);
            Ok(0)
        }
        RouteAction::Decide {
            stakes_json,
            confirm,
        } => {
            use bathos_router::Router;
            use bathos_state::model::Stakes;

            // 1) Stakes input: --stakes-json or stdin
            let raw = if let Some(j) = stakes_json {
                j
            } else {
                use std::io::Read;
                let mut buf = String::new();
                std::io::stdin()
                    .read_to_string(&mut buf)
                    .context("stdin 읽기 실패")?;
                buf
            };
            let trimmed = raw.trim();
            if trimmed.is_empty() {
                anyhow::bail!(
                    "Stakes JSON이 비어있습니다. --stakes-json 또는 stdin으로 \
                     {{\"scope\":\"feature\",\"novelty\":true,\"regulation_ip\":false,\"team_size\":\"medium\"}} 형식을 제공하세요."
                );
            }
            let stakes: Stakes = serde_json::from_str(trimmed).context(
                "Stakes JSON 파싱 실패 (필드: scope, novelty, regulation_ip, team_size)",
            )?;

            // 2) Compute recommendation (no commit — User Sovereignty)
            let routing = Router.recommend(&stakes);
            let recommendation = serde_json::json!({
                "recommended_level": routing.recommended_level,
                "wave_set": routing.wave_set,
                "role_set": routing.role_set,
                "w4_mode": format!("{:?}", routing.w4_mode),
                "story_engineer": routing.story_engineer,
                "requires_confirmation": routing.requires_confirmation,
                "description": routing.description,
            });
            println!("{}", serde_json::to_string_pretty(&recommendation)?);

            // 3) Confirm and record only when --confirm is given (explicit user decision)
            match confirm {
                None => {
                    eprintln!(
                        "[bathos route decide] 추천 Lv{} — 확정하려면 `route decide --confirm <0-4>`를 다시 실행하세요(User Sovereignty).",
                        routing.recommended_level
                    );
                    Ok(0)
                }
                Some(level) => {
                    let mut store = StateStore::open(state_dir)
                        .with_context(|| format!("state 열기 실패: {}", state_dir.display()))?;
                    let project_id = store.project().project_id.clone();
                    let decision = Router
                        .confirm_level(&routing, level, &project_id)
                        .context("레벨 확정 실패 (유효 범위 0~4)")?;
                    let drift = decision.confirmed_level != decision.recommended_level;
                    Router::commit_decision(&mut store, decision).context("레벨 결정 기록 실패")?;
                    eprintln!(
                        "[bathos route decide] ✅ Lv{} 확정·기록{} (추천 Lv{})",
                        level,
                        if drift {
                            " [드리프트: 추천과 다름]"
                        } else {
                            ""
                        },
                        routing.recommended_level
                    );
                    Ok(0)
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Model handler (W2 panes/model design §A1.4) — `_state/model-plan.json` CLI
// ─────────────────────────────────────────────────────────────────────────────
//
// Every subcommand here is a thin wrapper over `bathos_state::model_plan`'s pure
// load/resolve/validate/save functions — this handler owns only I/O plumbing
// (finding `.claude/agents/_base`, printing, exit codes, audit logging).

fn handle_model(action: ModelAction, state_dir: &Path, root: &Path) -> Result<i32> {
    let agents_dir = root.join(".claude/agents/_base");

    match action {
        // ── bathos model show ────────────────────────────────────────────────
        ModelAction::Show { wave, json } => {
            let (plan, warnings) = model_plan::load(state_dir);
            for w in &warnings {
                eprintln!("[bathos model show] {} — {}", w.code, w.message);
            }

            let slugs = roles_to_display(&plan, wave.as_deref(), &agents_dir);

            let rows: Vec<serde_json::Value> = slugs
                .iter()
                .map(|slug| {
                    let fm = model_plan::find_frontmatter_model(&agents_dir, slug);
                    let eff = model_plan::resolve_effective(&plan, slug, fm.as_deref());
                    serde_json::json!({
                        "slug": slug,
                        "runtime": eff.runtime.as_str(),
                        "model": eff.model,
                        "reasoning_effort": eff.reasoning_effort,
                        "source": eff.source.as_str(),
                    })
                })
                .collect();

            if json {
                println!("{}", serde_json::to_string_pretty(&rows)?);
            } else {
                println!(
                    "역할별 모델 — session_backend={}{}",
                    plan.session_backend.as_str(),
                    wave.as_deref()
                        .map(|w| format!(" wave={w}"))
                        .unwrap_or_default()
                );
                println!("{:<32} {:<8} {:<20} source", "role", "runtime", "model");
                for row in &rows {
                    println!(
                        "{:<32} {:<8} {:<20} {}",
                        row["slug"].as_str().unwrap_or("?"),
                        row["runtime"].as_str().unwrap_or("?"),
                        row["model"].as_str().unwrap_or("(runtime default)"),
                        row["source"].as_str().unwrap_or("?"),
                    );
                }
            }
            Ok(0)
        }

        // ── bathos model set ─────────────────────────────────────────────────
        ModelAction::Set {
            slug,
            runtime,
            model,
            reasoning_effort,
        } => {
            let parsed_runtime = Runtime::parse(&runtime).map_err(|e| anyhow::anyhow!(e))?;

            // E1 second half: an existing-but-corrupt-JSON plan is backed up before we
            // overwrite it with a freshly reconstructed one (never silently discard bytes
            // the user might want to recover by hand).
            if model_plan::is_corrupt_json(state_dir) {
                model_plan::backup_corrupt(state_dir).context("model-plan.json.bak 백업 실패")?;
                eprintln!(
                    "[bathos model set] ⚠ 기존 model-plan.json이 손상되어 있어 .bak로 백업했습니다"
                );
            }

            let (mut plan, _warnings) = model_plan::load(state_dir);
            plan.roles.insert(
                slug.clone(),
                bathos_state::model_plan::RoleModelSpec {
                    runtime: parsed_runtime,
                    model: model.clone(),
                    reasoning_effort: reasoning_effort.clone(),
                },
            );
            plan.updated = chrono::Utc::now();
            plan.updated_by = "Paul".to_string();
            model_plan::save(state_dir, &plan).context("model-plan.json 저장 실패")?;

            // best-effort audit trail (never blocks — same fail-safe posture as `audit append`)
            let _ = bathos_state::audit::append_audit_entry(
                &state_dir.join("audit-log.jsonl"),
                &read_project_id_from_state(state_dir),
                "Paul",
                "model.set",
                &format!("{slug}→{runtime}"),
            );

            eprintln!(
                "[bathos model set] ✓ {slug} → runtime={runtime}{}{}",
                model.map(|m| format!(" model={m}")).unwrap_or_default(),
                reasoning_effort
                    .map(|r| format!(" reasoning_effort={r}"))
                    .unwrap_or_default()
            );
            Ok(0)
        }

        // ── bathos model unset ───────────────────────────────────────────────
        ModelAction::Unset { slug } => {
            let (mut plan, _warnings) = model_plan::load(state_dir);
            let existed = plan.roles.remove(&slug).is_some();
            model_plan::save(state_dir, &plan).context("model-plan.json 저장 실패")?;
            let _ = bathos_state::audit::append_audit_entry(
                &state_dir.join("audit-log.jsonl"),
                &read_project_id_from_state(state_dir),
                "Paul",
                "model.unset",
                &slug,
            );
            if existed {
                eprintln!("[bathos model unset] ✓ {slug} 제거 → frontmatter 폴백으로 복귀");
            } else {
                eprintln!("[bathos model unset] {slug}은 plan에 등재돼 있지 않았음(변화 없음)");
            }
            Ok(0)
        }

        // ── bathos model detect ──────────────────────────────────────────────
        ModelAction::Detect => {
            let backend = SessionBackend::detect_from_base_url(
                std::env::var("ANTHROPIC_BASE_URL").ok().as_deref(),
            );
            let (mut plan, _warnings) = model_plan::load(state_dir);
            plan.session_backend = backend;
            plan.updated = chrono::Utc::now();
            plan.updated_by = "Paul".to_string();
            model_plan::save(state_dir, &plan).context("model-plan.json 저장 실패")?;
            let _ = bathos_state::audit::append_audit_entry(
                &state_dir.join("audit-log.jsonl"),
                &read_project_id_from_state(state_dir),
                "Paul",
                "model.detect",
                backend.as_str(),
            );
            eprintln!("[bathos model detect] session_backend={}", backend.as_str());
            Ok(0)
        }

        // ── bathos model validate ────────────────────────────────────────────
        ModelAction::Validate { wave } => {
            let (plan, _warnings) = model_plan::load(state_dir);
            let roles: Vec<String> = match &wave {
                Some(w) => wave_role_slugs(w)
                    .map(|s| s.iter().map(|x| x.to_string()).collect())
                    .unwrap_or_else(|| plan.roles.keys().cloned().collect()),
                None => plan.roles.keys().cloned().collect(),
            };
            let wave_label = wave.as_deref().unwrap_or("(all)");

            match model_plan::validate_wave(&plan, wave_label, &roles) {
                Ok(()) => {
                    println!(
                        "PASS — {wave_label} 역할 배치 혼합 규칙 위반 없음 ({} roles)",
                        roles.len()
                    );
                    Ok(0)
                }
                Err(violation) => {
                    eprintln!("{}", violation.message);
                    eprintln!("해소 선택지:");
                    for r in &violation.resolutions {
                        eprintln!("  {r}");
                    }
                    let out = serde_json::json!({
                        "code": violation.code,
                        "message": violation.message,
                        "resolutions": violation.resolutions,
                    });
                    println!("{out}");
                    Ok(2)
                }
            }
        }

        // ── bathos model resolve ─────────────────────────────────────────────
        ModelAction::Resolve { slug, json } => {
            let (plan, _warnings) = model_plan::load(state_dir);
            let fm = model_plan::find_frontmatter_model(&agents_dir, &slug);
            let eff = model_plan::resolve_effective(&plan, &slug, fm.as_deref());
            if json {
                println!(
                    "{}",
                    serde_json::json!({
                        "slug": slug,
                        "runtime": eff.runtime.as_str(),
                        "model": eff.model,
                        "reasoning_effort": eff.reasoning_effort,
                        "source": eff.source.as_str(),
                    })
                );
            } else {
                println!(
                    "{}\t{}\t{}\t{}",
                    slug,
                    eff.runtime.as_str(),
                    eff.model.as_deref().unwrap_or("-"),
                    eff.source.as_str()
                );
            }
            Ok(0)
        }
    }
}

/// Resolves the role slugs `bathos model show` should display: the wave's registered roster
/// (`--wave`) if given, otherwise the union of every slug already in the plan and every slug
/// discoverable under `agents_dir` (so `show` is useful even before any `set` has ever run —
/// it should show the full "would-resolve-to-frontmatter" universe, not an empty table).
fn roles_to_display(plan: &ModelPlan, wave: Option<&str>, agents_dir: &Path) -> Vec<String> {
    if let Some(w) = wave {
        if let Some(slugs) = wave_role_slugs(w) {
            return slugs.iter().map(|s| s.to_string()).collect();
        }
    }

    let mut set: std::collections::BTreeSet<String> = plan.roles.keys().cloned().collect();
    if let Ok(entries) = std::fs::read_dir(agents_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().and_then(|e| e.to_str()) != Some("md") {
                continue;
            }
            if let Ok(content) = std::fs::read_to_string(&path) {
                if let Some(slug) = frontmatter_slug(&content) {
                    set.insert(slug);
                }
            }
        }
    }
    set.into_iter().collect()
}

/// Minimal `slug:` frontmatter extraction for `roles_to_display`'s directory scan. Intentionally
/// duplicated (not reused from `model_plan::find_frontmatter_model`, which is single-slug-keyed)
/// rather than widening that function's private helper's visibility — this one needs "give me
/// whatever slug this file declares", the other needs "does this file declare slug X".
fn frontmatter_slug(content: &str) -> Option<String> {
    let mut in_fm = false;
    for (i, line) in content.lines().enumerate() {
        let t = line.trim_end();
        if i == 0 && t == "---" {
            in_fm = true;
            continue;
        }
        if in_fm && t == "---" {
            break;
        }
        if in_fm {
            if let Some(rest) = t.trim_start().strip_prefix("slug:") {
                let v = rest.split('#').next().unwrap_or(rest).trim();
                if !v.is_empty() {
                    return Some(v.to_string());
                }
            }
        }
    }
    None
}

// ─────────────────────────────────────────────────────────────────────────────
// Story handler (B3 implementation)
// ─────────────────────────────────────────────────────────────────────────────

fn handle_story(action: StoryAction, _state_dir: &Path) -> Result<i32> {
    match action {
        // ── bathos story compile ─────────────────────────────────────────────
        // Validates storyfile D1 completeness and D2 source tracing.
        StoryAction::Compile { slug, file } => {
            // Load content: --file option or stdin
            let content = if let Some(path) = file {
                std::fs::read_to_string(&path)
                    .with_context(|| format!("스토리파일 읽기 실패: {}", path.display()))?
            } else {
                use std::io::Read;
                let mut buf = String::new();
                std::io::stdin().read_to_string(&mut buf)?;
                buf
            };

            match StoryEngine::validate_story_content(&slug, &content) {
                Ok(validation) => {
                    let output = serde_json::json!({
                        "story_key": slug,
                        "is_valid": validation.is_valid,
                        "missing_sections": validation.missing_sections,
                        "developer_context_empty": validation.developer_context_empty,
                        "sourceless_claim_count": validation.sourceless_claim_count,
                        "verdict": "OK"
                    });
                    println!("{}", output);
                    Ok(0)
                }
                Err(e) => {
                    // M-9 fix: emit the structured E-CTX-LOSS JSON output to stdout.
                    // Scripts and pipelines must be able to parse the `verdict: "E-CTX-LOSS"` JSON,
                    // so it is unified on the same channel as the OK case (println! above).
                    // exit code 1 is preserved (conveys the error state).
                    let output = serde_json::json!({
                        "story_key": slug,
                        "is_valid": false,
                        "error": e.to_string(),
                        "verdict": "E-CTX-LOSS"
                    });
                    println!("{}", output);
                    Ok(1)
                }
            }
        }

        // ── bathos story check-stale ──────────────────────────────────────────
        // D3 Freshness: compares the stored source_hash against current upstream file contents.
        StoryAction::CheckStale {
            slug,
            stored_hash,
            upstream_files,
        } => {
            // Load upstream file contents
            let mut contents: Vec<Vec<u8>> = Vec::new();
            for path in &upstream_files {
                let bytes = std::fs::read(path)
                    .with_context(|| format!("상류 파일 읽기 실패: {}", path.display()))?;
                contents.push(bytes);
            }

            let upstream_refs: Vec<&[u8]> = contents.iter().map(|v| v.as_slice()).collect();
            let current_hash = StoryEngine::compute_source_hash(&upstream_refs);

            let is_stale = stored_hash != current_hash;

            let output = serde_json::json!({
                "story_key": slug,
                "is_stale": is_stale,
                "stored_hash": &stored_hash[..stored_hash.len().min(12)],
                "current_hash": &current_hash[..current_hash.len().min(12)],
                "upstream_files": upstream_files.len()
            });

            if is_stale {
                eprintln!("[bathos story check-stale] ⚠️  E-STALE: {slug}");
                eprintln!("{}", output);
                Ok(1) // stale = exit 1
            } else {
                println!("FRESH");
                println!("{}", output);
                Ok(0)
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Plug handler (B4 implementation — M12 plug manager CLI wrapper)
// ─────────────────────────────────────────────────────────────────────────────

fn handle_plug(action: PlugAction, state_dir: &Path, modules_dir: &Path) -> Result<i32> {
    // Load the modules/ registry (empty registry if absent — not an error)
    let registry = ModuleRegistry::load(modules_dir)
        .with_context(|| format!("모듈 레지스트리 로드 실패: {}", modules_dir.display()))?;

    match action {
        // ── bathos plug list ─────────────────────────────────────────────────
        // Prints registry modules ⨉ manifest enabled state as a JSON array.
        PlugAction::List => {
            // Build the enabled map from manifest state (if present). Empty map if no state.
            let enabled_map: std::collections::HashMap<String, bool> =
                match StateStore::open(state_dir) {
                    Ok(store) => store
                        .project()
                        .modules
                        .iter()
                        .map(|m| (m.module_id.clone(), m.enabled))
                        .collect(),
                    Err(_) => std::collections::HashMap::new(),
                };

            let list: Vec<_> = registry
                .modules()
                .iter()
                .map(|m| {
                    serde_json::json!({
                        "module_id": m.module_id,
                        "name": m.name,
                        "wave": m.wave,
                        "trigger": m.trigger,
                        "enabled": enabled_map.get(&m.module_id).copied().unwrap_or(m.enabled_default),
                        "enabled_default": m.enabled_default,
                        "evidence_trace": m.evidence_trace,
                    })
                })
                .collect();

            println!(
                "{}",
                serde_json::to_string_pretty(&list).context("plug list 직렬화 실패")?
            );
            Ok(0)
        }

        // ── bathos plug enable / disable ──────────────────────────────────────
        PlugAction::Enable { module_id } => {
            let mut store = StateStore::open(state_dir)
                .with_context(|| format!("state 열기 실패: {}", state_dir.display()))?;
            PlugManager::set_enabled(&mut store, &registry, &module_id, true)
                .with_context(|| format!("모듈 활성화 실패: {module_id}"))?;
            eprintln!("[bathos plug enable] {module_id} → enabled");
            Ok(0)
        }
        PlugAction::Disable { module_id } => {
            let mut store = StateStore::open(state_dir)
                .with_context(|| format!("state 열기 실패: {}", state_dir.display()))?;
            PlugManager::set_enabled(&mut store, &registry, &module_id, false)
                .with_context(|| format!("모듈 비활성화 실패: {module_id}"))?;
            eprintln!("[bathos plug disable] {module_id} → disabled");
            Ok(0)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Audit handler (B-1 fix: single Rust writer)
// ─────────────────────────────────────────────────────────────────────────────

fn handle_audit(action: AuditAction, state_dir: &Path) -> Result<i32> {
    match action {
        AuditAction::Append {
            actor,
            audit_action,
            target,
        } => {
            // B-1 fail-safe: this function always returns exit 0 (avoids blocking hooks).
            // If state_dir is absent, quietly attempt to create it
            if !state_dir.exists() {
                let _ = std::fs::create_dir_all(state_dir);
            }

            let log_path = state_dir.join("audit-log.jsonl");

            // project_id: read from manifest.json. "unknown" on failure (hooks may run before init)
            let project_id = read_project_id_from_state(state_dir);

            // append_audit_entry: via the single Rust implementation → unified chain format
            let result = bathos_state::audit::append_audit_entry(
                &log_path,
                &project_id,
                &actor,
                &audit_action,
                &target,
            );

            match result {
                Ok(entry) => {
                    eprintln!(
                        "[bathos audit append] seq={} actor={} action={}",
                        entry.seq, entry.actor, entry.action
                    );
                }
                Err(e) => {
                    // On failure, only log and exit 0 (never block hooks)
                    eprintln!(
                        "[bathos audit append] 경고: audit 기록 실패 (fail-safe) — {}",
                        e
                    );
                }
            }

            // B-1 invariant: always exit 0
            Ok(0)
        }

        // ── bathos audit verify ──────────────────────────────────────────────
        // Verifies audit hash-chain integrity (exposes verify_chain).
        // Chain intact → exit 0, broken → exit 1 (unlike append, this is diagnostic so it reflects the result).
        AuditAction::Verify => {
            let log_path = state_dir.join("audit-log.jsonl");
            if !log_path.exists() {
                println!(
                    "OK — 감사 로그 없음(검증할 체인 없음): {}",
                    log_path.display()
                );
                return Ok(0);
            }

            // Entry count (for the message — irrelevant to the verification result even if it fails)
            let entry_count = std::fs::read_to_string(&log_path)
                .map(|c| c.lines().filter(|l| !l.trim().is_empty()).count())
                .unwrap_or(0);

            match bathos_state::audit::verify_chain(&log_path) {
                Ok(()) => {
                    println!(
                        "OK — 감사 해시체인 무결 ({} entries, genesis→tail linkage 정상): {}",
                        entry_count,
                        log_path.display()
                    );
                    Ok(0)
                }
                Err(e) => {
                    eprintln!(
                        "[E-AUDIT-TAMPER] 감사 체인 무결성 위반 — 변조 가능성:\n{}",
                        e
                    );
                    Ok(1)
                }
            }
        }

        // ── bathos audit reseal (SEC-02) ─────────────────────────────────────
        // One-time migration of a legacy unkeyed chain to keyed HMAC-SHA256.
        // Success → exit 0; a broken/tampered legacy chain → exit 1 (nothing rewritten).
        AuditAction::Reseal => {
            let log_path = state_dir.join("audit-log.jsonl");
            if !log_path.exists() {
                println!(
                    "OK — 감사 로그 없음(재봉인할 체인 없음): {}",
                    log_path.display()
                );
                return Ok(0);
            }

            match bathos_state::audit::reseal_chain(&log_path) {
                Ok(n) => {
                    let key_src = if std::env::var("BATHOS_AUDIT_KEY")
                        .map(|v| !v.is_empty())
                        .unwrap_or(false)
                    {
                        "BATHOS_AUDIT_KEY (env, out-of-band)".to_string()
                    } else {
                        format!("{}.audit-key (0600)", log_path.display())
                    };
                    println!(
                        "OK — SEC-02 재봉인 완료: {} entries → keyed HMAC-SHA256\n  키 소스: {}\n  백업: {}.presealbak",
                        n,
                        key_src,
                        log_path.display()
                    );
                    Ok(0)
                }
                Err(e) => {
                    eprintln!(
                        "[E-AUDIT-TAMPER] 재봉인 거부 — 기존(레거시) 체인이 무결하지 않음(변조 세탁 방지):\n{}",
                        e
                    );
                    Ok(1)
                }
            }
        }
    }
}

/// Reads project_id from manifest.json.
///
/// Returns "unknown" on failure (missing file, JSON parse error, etc.).
/// fail-safe: this function never panics.
fn read_project_id_from_state(state_dir: &Path) -> String {
    let manifest_path = state_dir.join("manifest.json");
    std::fs::read_to_string(&manifest_path)
        .ok()
        .and_then(|content| serde_json::from_str::<serde_json::Value>(&content).ok())
        .and_then(|v| v["project_id"].as_str().map(|s| s.to_string()))
        .unwrap_or_else(|| "unknown".to_string())
}

// ─────────────────────────────────────────────────────────────────────────────
// Fingerprint handler (Dynamis new, SS1 · CF-A1)
// ─────────────────────────────────────────────────────────────────────────────
//
// Per the A-3 (risk-log) restatement: this subcommand only handles the
// "cache preventing re-approval of risky-path Write/Edit/MultiEdit changes".
// Blocking bypass via Bash is handled separately by careful-guard.sh pattern
// extensions, and no complete blocking is claimed (inheriting the existing
// "known limitations" practice).
//
// fail-safe principle: if state_dir/manifest.json is absent, treat it as "new"
// (unapproved) so the hook leans to the safe side (requiring approval) —
// false-positive (over-blocking) > false-negative principle (careful/freeze style).

fn handle_fingerprint(action: FingerprintAction, state_dir: &Path) -> Result<i32> {
    match action {
        // ── bathos fingerprint check ─────────────────────────────────────────
        FingerprintAction::Check { diff_file } => {
            let diff_text = std::fs::read_to_string(&diff_file)
                .with_context(|| format!("diff 파일 읽기 실패: {}", diff_file.display()))?;
            let hash = bathos_state::fingerprint::compute_fingerprint(&diff_text);

            // No manifest / open failure → treat as "new" (fail-safe: lean to the safe side)
            let approved = StateStore::open(state_dir)
                .map(|store| {
                    bathos_state::fingerprint::is_approved(
                        &store.project().approved_fingerprints,
                        &hash,
                    )
                })
                .unwrap_or(false);

            let status = if approved { "approved" } else { "new" };
            println!("{}", serde_json::json!({ "status": status, "hash": hash }));
            Ok(0)
        }

        // ── bathos fingerprint approve ────────────────────────────────────────
        FingerprintAction::Approve { hash, actor, scope } => {
            // Hash format check (same as schema pattern: 64-char lowercase hex) — fail early to avoid contamination
            let is_valid_hash = hash.len() == 64
                && hash
                    .chars()
                    .all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase());
            if !is_valid_hash {
                anyhow::bail!("잘못된 hash 형식(64자 소문자 hex 필요): {hash}");
            }

            let mut store = StateStore::open(state_dir)
                .with_context(|| format!("state 열기 실패: {}", state_dir.display()))?;

            let mut updated = store.project().clone();
            // If already approved, pass through without a duplicate append (idempotency)
            if !bathos_state::fingerprint::is_approved(&updated.approved_fingerprints, &hash) {
                let entry = bathos_state::fingerprint::new_approval(&hash, &actor, &scope);
                updated.approved_fingerprints.push(entry);
                store
                    .commit(updated, &actor, "fingerprint.approved")
                    .with_context(|| "fingerprint 승인 기록 실패")?;
            }

            eprintln!("[bathos fingerprint approve] ✓ hash={hash} actor={actor} scope={scope}");
            Ok(0)
        }

        // ── bathos fingerprint list ───────────────────────────────────────────
        FingerprintAction::List => {
            let store = StateStore::open(state_dir)
                .with_context(|| format!("state 열기 실패: {}", state_dir.display()))?;
            let json = serde_json::to_string_pretty(&store.project().approved_fingerprints)
                .context("fingerprint 캐시 직렬화 실패")?;
            println!("{}", json);
            Ok(0)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Doctor handler — installation/wiring preflight diagnostics
// ─────────────────────────────────────────────────────────────────────────────

/// Known valid hook event names. Putting any other key (especially comment keys
/// starting with `_`) into the settings.json hooks block causes an infinite hang
/// when a subagent starts (a documented trap).
const KNOWN_HOOK_EVENTS: &[&str] = &[
    "PreToolUse",
    "PostToolUse",
    "TaskCompleted",
    "SubagentStop",
    "TeammateIdle",
    "Stop",
    "Notification",
    "UserPromptSubmit",
    "PreCompact",
    "SessionStart",
    "SessionEnd",
];

/// The 6 BATHOS safety hooks (M6).
const EXPECTED_HOOKS: &[&str] = &[
    "careful-guard.sh",
    "freeze-guard.sh",
    "audit-log.sh",
    "artifact-verify.sh",
    "gate-enforce.sh",
    "next-action.sh",
];

/// Installation/wiring diagnostics. Never panics (fail-safe); exit 0 if zero errors, otherwise exit 1.
fn handle_doctor(root: &Path, state_dir: &Path, modules_dir: &Path) -> Result<i32> {
    let mut errors = 0u32;
    let mut warns = 0u32;

    println!("BATHOS doctor — 설치·배선 진단");
    println!("  engine   : bathos v{}", env!("CARGO_PKG_VERSION"));
    println!(
        "  root={} · state_dir={} · modules_dir={}",
        root.display(),
        state_dir.display(),
        modules_dir.display()
    );
    println!("────────────────────────────────────────");

    // 1. BATHOS_BIN
    match std::env::var("BATHOS_BIN") {
        Ok(v) if !v.is_empty() => println!("✓ BATHOS_BIN 설정됨: {}", v),
        _ => {
            println!("⚠ BATHOS_BIN 미설정 — 훅이 엔진을 못 찾을 수 있음(fallback: core/target/debug/bathos)");
            warns += 1;
        }
    }

    // 2. Agent Teams flag
    match std::env::var("CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS")
        .ok()
        .as_deref()
    {
        Some("1") => println!("✓ CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"),
        _ => {
            println!("⚠ CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS≠1 — settings.json env로도 설정되나 셸 export 권장");
            warns += 1;
        }
    }

    // 3. jq (used by safety hooks for JSON parsing)
    if command_exists("jq") {
        println!("✓ jq 발견됨(안전 훅이 사용)");
    } else {
        println!(
            "✗ jq 없음 — 안전 훅(JSON 파싱) 동작 불가. 설치: brew install jq / apt-get install jq"
        );
        errors += 1;
    }

    // 4. settings.json hooks block — comment-key trap check
    let settings_path = root.join(".claude/settings.json");
    match std::fs::read_to_string(&settings_path) {
        Err(_) => {
            println!("✗ .claude/settings.json 없음: {}", settings_path.display());
            errors += 1;
        }
        Ok(content) => match serde_json::from_str::<serde_json::Value>(&content) {
            Err(e) => {
                println!("✗ settings.json JSON 파싱 실패: {}", e);
                errors += 1;
            }
            Ok(v) => match v.get("hooks").and_then(|h| h.as_object()) {
                None => {
                    println!("⚠ settings.json에 hooks 블록 없음");
                    warns += 1;
                }
                Some(hooks) => {
                    let (bad, unknown) = classify_hook_keys(hooks.keys());
                    if !bad.is_empty() {
                        println!("✗ settings.json hooks 블록에 주석/무효 키 {:?} — 서브에이전트 시작 무한 대기 유발! 제거 필요", bad);
                        errors += 1;
                    }
                    if !unknown.is_empty() {
                        println!("⚠ hooks 블록에 알 수 없는 이벤트 키: {:?}", unknown);
                        warns += 1;
                    }
                    if bad.is_empty() && unknown.is_empty() {
                        println!(
                            "✓ settings.json hooks 블록 유효(주석키 없음, {} 이벤트)",
                            hooks.len()
                        );
                    }
                }
            },
        },
    }

    // 5. Safety hook existence/executability
    let hooks_dir = root.join(".claude/hooks");
    let mut missing: Vec<&str> = vec![];
    let mut nonexec: Vec<&str> = vec![];
    for h in EXPECTED_HOOKS {
        let p = hooks_dir.join(h);
        if !p.exists() {
            missing.push(h);
        } else if !is_executable(&p) {
            nonexec.push(h);
        }
    }
    if !missing.is_empty() {
        println!("✗ 훅 누락: {:?}", missing);
        errors += 1;
    }
    if !nonexec.is_empty() {
        println!("⚠ 훅 실행권한 없음(chmod +x 필요): {:?}", nonexec);
        warns += 1;
    }
    if missing.is_empty() && nonexec.is_empty() {
        println!("✓ 안전 훅 6종 존재·실행가능");
    }

    // 6. assets/ · modules/
    if root.join("assets").is_dir() {
        println!("✓ assets/ 존재");
    } else {
        println!("⚠ assets/ 없음(W3 스토리엔진 템플릿 참조 불가)");
        warns += 1;
    }
    if modules_dir.is_dir() {
        println!("✓ modules/ 존재: {}", modules_dir.display());
    } else {
        println!("⚠ modules/ 없음(플러그 비활성): {}", modules_dir.display());
        warns += 1;
    }

    // 7. manifest schema (if present)
    let manifest_path = state_dir.join("manifest.json");
    if manifest_path.exists() {
        match std::fs::read_to_string(&manifest_path)
            .ok()
            .and_then(|c| serde_json::from_str::<serde_json::Value>(&c).ok())
        {
            Some(v) => match validate_manifest(&v) {
                Ok(()) => println!("✓ manifest.json 스키마 유효"),
                Err(e) => {
                    println!("✗ [E-STATE-CORRUPT] manifest.json 스키마 위반: {}", e);
                    errors += 1;
                }
            },
            None => {
                println!(
                    "✗ manifest.json 읽기/파싱 실패: {}",
                    manifest_path.display()
                );
                errors += 1;
            }
        }
    } else {
        println!("· manifest.json 없음(아직 /team-kickoff 전 — 정상)");
    }

    // 8. Audit chain integrity (if present)
    let log_path = state_dir.join("audit-log.jsonl");
    if log_path.exists() {
        match bathos_state::audit::verify_chain(&log_path) {
            Ok(()) => println!("✓ 감사 해시체인 무결"),
            Err(e) => {
                println!("✗ [E-AUDIT-TAMPER] 감사 체인 위반: {}", e);
                errors += 1;
            }
        }
    } else {
        println!("· 감사 로그 없음(아직 활동 전 — 정상)");
    }

    println!("────────────────────────────────────────");
    if errors == 0 {
        println!("결과: PASS (경고 {})", warns);
        Ok(0)
    } else {
        println!(
            "결과: FAIL — 오류 {}, 경고 {}. 위 ✗ 항목을 해결하세요.",
            errors, warns
        );
        Ok(1)
    }
}

/// Classifies hooks block keys into (comment/invalid keys, unknown event keys).
///
/// Keys starting with `_` are the documented infinite-hang trap (comment keys), so "bad".
/// Other keys not in `KNOWN_HOOK_EVENTS` are "unknown". Pure function (test target).
fn classify_hook_keys<'a>(keys: impl Iterator<Item = &'a String>) -> (Vec<String>, Vec<String>) {
    let mut bad = vec![];
    let mut unknown = vec![];
    for k in keys {
        if k.starts_with('_') {
            bad.push(k.clone());
        } else if !KNOWN_HOOK_EVENTS.contains(&k.as_str()) {
            unknown.push(k.clone());
        }
    }
    (bad, unknown)
}

/// Whether a command exists on PATH (fail-safe — false on failure).
fn command_exists(cmd: &str) -> bool {
    std::process::Command::new(cmd)
        .arg("--version")
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

/// Whether a file is executable. On unix checks the mode's execute bits; otherwise checks existence.
fn is_executable(p: &Path) -> bool {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::metadata(p)
            .map(|m| m.permissions().mode() & 0o111 != 0)
            .unwrap_or(false)
    }
    #[cfg(not(unix))]
    {
        p.exists()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn keys(v: &[&str]) -> Vec<String> {
        v.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn hook_keys_all_valid_no_flags() {
        let k = keys(&[
            "PreToolUse",
            "PostToolUse",
            "TaskCompleted",
            "SubagentStop",
            "TeammateIdle",
        ]);
        let (bad, unknown) = classify_hook_keys(k.iter());
        assert!(bad.is_empty());
        assert!(unknown.is_empty());
    }

    #[test]
    fn hook_keys_comment_key_flagged_as_bad() {
        // Documented trap: comment keys like `_note`/`_comment` → cause infinite hang
        let k = keys(&["PreToolUse", "_note", "_comment"]);
        let (bad, unknown) = classify_hook_keys(k.iter());
        assert_eq!(bad.len(), 2);
        assert!(unknown.is_empty());
    }

    #[test]
    fn hook_keys_unknown_event_flagged_as_unknown() {
        let k = keys(&["PreToolUse", "BogusEvent"]);
        let (bad, unknown) = classify_hook_keys(k.iter());
        assert!(bad.is_empty());
        assert_eq!(unknown, vec!["BogusEvent".to_string()]);
    }

    fn state_init_action(
        codename: &str,
        level: u8,
        project_id: Option<&str>,
        force: bool,
    ) -> StateAction {
        StateAction::Init {
            codename: codename.to_string(),
            level,
            lang: "en".to_string(),
            project_id: project_id.map(str::to_string),
            force,
        }
    }

    #[test]
    fn state_init_creates_schema_valid_manifest_for_all_levels() {
        for level in 0..=4 {
            let dir = TempDir::new().unwrap();
            let code = handle_state(
                state_init_action("BATHOS", level, Some("bathos-cli-test"), false),
                dir.path(),
            )
            .unwrap();
            assert_eq!(code, 0);

            let manifest = std::fs::read_to_string(dir.path().join("manifest.json")).unwrap();
            let value: serde_json::Value = serde_json::from_str(&manifest).unwrap();
            validate_manifest(&value).unwrap();
            assert_eq!(value["codename"], "BATHOS");
            assert_eq!(value["current_level"], level);
            assert_eq!(value["lang"], "en");
            assert_eq!(value["project_id"], "bathos-cli-test");
        }
    }

    #[test]
    fn state_init_preserves_existing_manifest_without_force_and_replaces_with_force() {
        let dir = TempDir::new().unwrap();
        assert_eq!(
            handle_state(
                state_init_action("ORIGINAL", 1, Some("bathos-original"), false),
                dir.path(),
            )
            .unwrap(),
            0
        );
        let manifest_path = dir.path().join("manifest.json");
        let original = std::fs::read_to_string(&manifest_path).unwrap();

        assert_eq!(
            handle_state(
                state_init_action("REPLACEMENT", 2, Some("bathos-replacement"), false),
                dir.path(),
            )
            .unwrap(),
            1
        );
        assert_eq!(std::fs::read_to_string(&manifest_path).unwrap(), original);

        assert_eq!(
            handle_state(
                state_init_action("REPLACEMENT", 2, Some("bathos-replacement"), true),
                dir.path(),
            )
            .unwrap(),
            0
        );
        let replaced: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(&manifest_path).unwrap()).unwrap();
        assert_eq!(replaced["codename"], "REPLACEMENT");
        assert_eq!(replaced["current_level"], 2);
        assert_eq!(replaced["project_id"], "bathos-replacement");
    }

    #[test]
    fn state_init_rejects_invalid_level_and_project_id_without_writing() {
        for action in [
            state_init_action("BATHOS", 5, Some("bathos-valid"), false),
            state_init_action("BATHOS", 0, Some("invalid"), false),
            state_init_action("BATHOS", 0, Some("bathos-"), false),
            state_init_action("", 0, Some("bathos-valid"), false),
        ] {
            let dir = TempDir::new().unwrap();
            assert_eq!(handle_state(action, dir.path()).unwrap(), 1);
            assert!(!dir.path().join("manifest.json").exists());
        }

        let dir = TempDir::new().unwrap();
        let mut invalid_lang = state_init_action("BATHOS", 0, Some("bathos-valid"), false);
        if let StateAction::Init { lang, .. } = &mut invalid_lang {
            *lang = "x".to_string();
        }
        assert_eq!(handle_state(invalid_lang, dir.path()).unwrap(), 1);
        assert!(!dir.path().join("manifest.json").exists());
    }
}
