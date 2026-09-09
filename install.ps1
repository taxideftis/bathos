<#
=============================================================================
BATHOS bootstrap (Windows PowerShell 포트) — 엔진 빌드 + (선택) 메서드 패키지 설치
원본: install.sh (repo root, Bash)

  .\install.ps1                    엔진(bathos.exe) 빌드 + 설정 안내 출력
  .\install.ps1 -Into <DIR>        위에 더해 .claude/ assets/ modules/ 를 <DIR>에 복사
  .\install.ps1 -Help

안전 설계: 아무것도 삭제하지 않는다. 대상에 이미 .claude/ 가 있으면
-Force 없이는 덮어쓰지 않는다.

타깃: Windows PowerShell 5.1 하한(추가 설치 0) + PowerShell 7+ 호환.
  - 삼항 연산자·널병합(`??`) 미사용, `$IsWindows` 대신 `$env:OS` 검사.
  - Windows 엔진 바이너리는 `bathos.exe`(core/target/release/bathos.exe).

★ 설치 시점 OS 디스패치(핵심 기능) — Install-BathosHooksForWindows 함수:
  -Into 로 대상 프로젝트에 자산을 복사한 뒤, 이 스크립트를 Windows에서
  실행 중이면(OS 판별: `$env:OS -eq 'Windows_NT'`) 리포지토리 루트의
  `.claude/settings.windows.json`(모든 훅 command가 .ps1을 가리키고
  각 훅 항목에 "shell":"powershell" 이 설정된 참조본)을 대상의
  `.claude\settings.json` 으로 복사해, 대상 프로젝트가 PowerShell로
  배선된 훅을 갖도록 만든다. 커밋된 리포지토리 자체의
  `.claude/settings.json`(macOS/Linux용 bash 배선)은 건드리지 않는다.
  `-NoWindowsHooks` 플래그로 이 자동 배선을 끌 수 있다(예: 대상에서
  Git Bash 등으로 bash 훅을 그대로 쓰고 싶은 경우).
=============================================================================
#>

param(
    [Alias('into')]
    [string] $Into = '',

    [Alias('force')]
    [switch] $Force,

    [Alias('help', 'h')]
    [switch] $Help,

    # Windows에서 -Into 사용 시 settings.json을 PowerShell 배선본으로 교체할지.
    # 기본 동작(스위치 없음): Windows면 자동으로 교체한다.
    [switch] $NoWindowsHooks
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$PkgRoot = $PSScriptRoot

function Say {
    param([string] $Message)
    Write-Host "[bathos] $Message" -ForegroundColor Cyan
}

function Warn {
    param([string] $Message)
    Write-Host "[bathos] ⚠ $Message" -ForegroundColor Yellow
}

function Die {
    param([string] $Message)
    Write-Host "[bathos] ✗ $Message" -ForegroundColor Red
    exit 1
}

if ($Help) {
    Write-Host @'
BATHOS bootstrap — build the engine and (optionally) install the method
package into a target project.

  .\install.ps1                 build the `bathos` engine + print setup steps
  .\install.ps1 -Into <DIR>     also copy .claude/ assets/ modules/ into <DIR>
  .\install.ps1 -Help

Safe by design: never deletes anything. Refuses to overwrite an existing
.claude/ in the target unless you pass -Force.
'@
    exit 0
}

# -----------------------------------------------------------------------------
# Windows 여부 판별 — $IsWindows 는 PS 5.1에 없으므로 $env:OS 로 판별한다.
# PS7+에서도 $env:OS 는 Windows에서 'Windows_NT' 로 동일하게 설정된다.
# -----------------------------------------------------------------------------
function Test-IsWindowsHost {
    if ($env:OS -eq 'Windows_NT') { return $true }
    return $false
}

# --- 1. prerequisites -------------------------------------------------------
Say 'Checking prerequisites...'

if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    Die 'Rust toolchain not found. Install from https://rustup.rs'
}
if (-not (Get-Command jq -ErrorAction SilentlyContinue)) {
    Warn "jq not found - the safety hooks need it (e.g. 'winget install jqlang.jq' / 'choco install jq')."
}
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Warn 'Claude Code CLI not found - BATHOS runs on Claude Code v2.1.32+ (https://claude.com/claude-code).'
}

# --- 2. build the engine ----------------------------------------------------
Say 'Building the bathos engine (release)...'

Push-Location (Join-Path $PkgRoot 'core')
try {
    & cargo build --release
    if ($LASTEXITCODE -ne 0) { Die 'cargo build --release failed' }
} finally {
    Pop-Location
}

$ExeName = 'bathos'
if (Test-IsWindowsHost) { $ExeName = 'bathos.exe' }
$Bin = Join-Path $PkgRoot ('core\target\release\' + $ExeName)

if (-not (Test-Path -LiteralPath $Bin -PathType Leaf)) {
    Die "build did not produce $Bin"
}

$BinVersion = & $Bin --version
Say "Engine built: $Bin ($BinVersion)"

# -----------------------------------------------------------------------------
# ★ 설치 시점 OS 디스패치 — Windows 타깃에 PowerShell 배선 settings.json 심기.
# -----------------------------------------------------------------------------
function Install-BathosHooksForWindows {
    param(
        [Parameter(Mandatory = $true)] [string] $TargetDir,
        [Parameter(Mandatory = $true)] [string] $SourceRoot
    )

    $winSettings = Join-Path $SourceRoot '.claude\settings.windows.json'
    if (-not (Test-Path -LiteralPath $winSettings -PathType Leaf)) {
        Warn ".claude/settings.windows.json not found in package root - skipping Windows hook wiring. Target keeps the copied (bash-wired) settings.json."
        return
    }

    $targetSettings = Join-Path $TargetDir '.claude\settings.json'
    Copy-Item -LiteralPath $winSettings -Destination $targetSettings -Force
    Say "Windows detected: wired PowerShell hooks into $targetSettings (source: .claude/settings.windows.json, each hook command -> *.ps1 with \"shell\": \"powershell\")."
}

# --- 3. optional: install into a target project -----------------------------
if ($Into -ne '') {
    New-Item -ItemType Directory -Force -Path $Into | Out-Null

    $targetClaude = Join-Path $Into '.claude'
    if ((Test-Path -LiteralPath $targetClaude) -and (-not $Force)) {
        Die "$targetClaude already exists. Re-run with -Force to overwrite, or merge manually."
    }

    Say "Installing method package into: $Into"
    Copy-Item -Path (Join-Path $PkgRoot '.claude') -Destination $Into -Recurse -Force
    Copy-Item -Path (Join-Path $PkgRoot 'assets')  -Destination $Into -Recurse -Force
    Copy-Item -Path (Join-Path $PkgRoot 'modules') -Destination $Into -Recurse -Force
    Say "Copied .claude/ assets/ modules/ -> $Into"

    # ★ OS 디스패치: Windows 호스트면 자동으로 PowerShell 배선 settings.json으로 교체.
    # 코미티드 리포지토리 자체의 .claude/settings.json(bash 배선, macOS/Linux)은
    # 원본 그대로 두고, "복사본"(대상 프로젝트 쪽)만 교체한다.
    if ((Test-IsWindowsHost) -and (-not $NoWindowsHooks)) {
        Install-BathosHooksForWindows -TargetDir $Into -SourceRoot $PkgRoot
    } elseif ($NoWindowsHooks) {
        Say '-NoWindowsHooks specified: keeping bash-wired settings.json in target (use Git Bash or WSL to run hooks).'
    } else {
        Say 'Non-Windows host detected: keeping bash-wired settings.json in target.'
    }
}

# --- 4. next steps ----------------------------------------------------------
Write-Host ''
Say 'Done. Next steps:'
Write-Host ''
Write-Host '  1) Point hooks/commands at the engine:'
Write-Host "       `$env:BATHOS_BIN = `"$Bin`""
Write-Host '     (or add "' -NoNewline
Write-Host (Join-Path $PkgRoot 'core\target\release') -NoNewline
Write-Host '" to your PATH)'
Write-Host ''
Write-Host '  2) Enable Claude Code Agent Teams (the bundled settings.json already sets this):'
Write-Host '       $env:CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1"'
Write-Host ''
Write-Host '  3) Open Claude Code in your project and drive the pipeline:'
Write-Host '       /team-kickoff                     # seeds a schema-valid manifest via bathos state init'
Write-Host '       /route /abs/path/to/project'
Write-Host '       /wave1-discovery /abs/path   ...  /wave6-verify-report /abs/path'
Write-Host '       /team-confirm'
Write-Host ''
Write-Host '  Try the engine directly:'
Write-Host "       & `"$Bin`" -s .agent-team\_state state init --codename MYPROJECT"
Write-Host ''
Write-Host "     '{`"scope`":`"feature`",`"novelty`":true,`"regulation_ip`":false,`"team_size`":`"medium`"}' |"
Write-Host "       & `"$Bin`" --state-dir .agent-team\_state route decide"
Write-Host ''
Write-Host '  Full guide: docs/USAGE-kr.md   ·   Quickstart: examples/quickstart/README.md'
