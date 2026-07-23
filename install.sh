#!/usr/bin/env bash
# =============================================================================
# BATHOS bootstrap — build the engine and (optionally) install the method
# package into a target project.
#
#   ./install.sh                 build the `bathos` engine + print setup steps
#   ./install.sh --into <DIR>    also copy .claude/ assets/ modules/ into <DIR>
#   ./install.sh --help
#
# Safe by design: never deletes anything. Refuses to overwrite an existing
# .claude/ in the target unless you pass --force.
# =============================================================================
set -euo pipefail

PKG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTO=""
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --into) INTO="${2:-}"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

say()  { printf '\033[0;36m[bathos]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[bathos] ⚠ %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[0;31m[bathos] ✗ %s\033[0m\n' "$*" >&2; exit 1; }

# --- 1. prerequisites -------------------------------------------------------
say "Checking prerequisites…"
command -v cargo >/dev/null 2>&1 || die "Rust toolchain not found. Install from https://rustup.rs"
command -v jq    >/dev/null 2>&1 || warn "jq not found — the safety hooks need it (e.g. 'brew install jq' / 'apt-get install jq')."
command -v claude >/dev/null 2>&1 || warn "Claude Code CLI not found — BATHOS runs on Claude Code v2.1.32+ (https://claude.com/claude-code)."

# --- 2. build the engine ----------------------------------------------------
say "Building the bathos engine (release)…"
( cd "$PKG_ROOT/core" && cargo build --release )
BIN="$PKG_ROOT/core/target/release/bathos"
[[ -x "$BIN" ]] || die "build did not produce $BIN"
say "Engine built: $BIN ($("$BIN" --version))"

# --- 3. optional: install into a target project -----------------------------
if [[ -n "$INTO" ]]; then
  mkdir -p "$INTO"
  if [[ -e "$INTO/.claude" && "$FORCE" -ne 1 ]]; then
    die "$INTO/.claude already exists. Re-run with --force to overwrite, or merge manually."
  fi
  say "Installing method package into: $INTO"
  cp -R "$PKG_ROOT/.claude"  "$INTO/"
  cp -R "$PKG_ROOT/assets"   "$INTO/"
  cp -R "$PKG_ROOT/modules"  "$INTO/"
  say "Copied .claude/ assets/ modules/ → $INTO"
fi

# --- 4. next steps ----------------------------------------------------------
cat <<EOF

$(say "Done. Next steps:")

  1) Point hooks/commands at the engine:
       export BATHOS_BIN="$BIN"
     (or add "$PKG_ROOT/core/target/release" to your PATH)

  2) Enable Claude Code Agent Teams (the bundled settings.json already sets this):
       export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

  3) Open Claude Code in your project and drive the pipeline:
       /team-kickoff                     # seeds a schema-valid manifest via 'bathos state init'
       /route /abs/path/to/project
       /wave1-discovery /abs/path   …  /wave6-verify-report /abs/path
       /team-confirm

  Try the engine directly:
     # Seed a schema-valid manifest.json (kickoff does this for you):
     "$BIN" -s .agent-team/_state state init --codename MYPROJECT

     echo '{"scope":"feature","novelty":true,"regulation_ip":false,"team_size":"medium"}' \\
       | "$BIN" --state-dir .agent-team/_state route decide

  Full guide: docs/USAGE-kr.md   ·   Quickstart: examples/quickstart/README.md
EOF
