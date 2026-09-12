#!/usr/bin/env bash
# =============================================================================
# BATHOS — wsl-setup.sh   (WSL preflight · repair)
# Run this once before using BATHOS on WSL (Windows Subsystem for Linux).
#
#   ./scripts/wsl-setup.sh            check + repair (normalize line endings to LF, exec bit)
#   ./scripts/wsl-setup.sh --check    check only (changes nothing)
#
# Background: WSL is a Linux environment, so it uses BATHOS's **bash edition (.sh hooks
# plus the Linux `bathos` binary)** as-is (the Windows PowerShell port .ps1 is not needed here).
# The one trap is a repo **cloned with CRLF on Windows** — the shebang of a `.sh` becomes
# `#!/usr/bin/env bash^M` and you get a `bad interpreter` error. `.gitattributes` prevents
# that from now on, but a tree that already arrived as CRLF is repaired to LF by this script.
#
# Safety: deletes nothing. It only strips CR from .sh files and grants the exec bit (idempotent).
# Portability: bash 3.2+ compatible (the macOS default) — no mapfile, no associative arrays.
# =============================================================================
set -uo pipefail

PKG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

say()  { printf '\033[0;36m[bathos-wsl]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[bathos-wsl] ⚠ %s\033[0m\n' "$*" >&2; }
ok()   { printf '\033[0;32m[bathos-wsl] ✓ %s\033[0m\n' "$*"; }

# List the .sh files in the product tree (excluding core/target, .git, node_modules).
list_sh() {
  find "$PKG_ROOT" -type f -name '*.sh' \
    -not -path '*/core/target/*' \
    -not -path '*/.git/*' \
    -not -path '*/node_modules/*' 2>/dev/null | sort
}

# --- 1. Report whether this is WSL (not enforced — harmless on Linux/macOS too) --
if grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; then
  say "WSL 환경 감지됨 — BATHOS는 여기서 bash(.sh) 버전으로 동작합니다."
else
  say "WSL이 아닌 것 같습니다(순수 Linux/macOS?). 이 스크립트는 그래도 안전하게 동작합니다."
fi

TOTAL_SH="$(list_sh | wc -l | tr -d ' ')"
say "검사 대상 .sh: ${TOTAL_SH}개"

# --- 2. Detect CRLF and, in repair mode, normalize to LF -------------------------
crlf_count=0
fixed_count=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if LC_ALL=C grep -lq $'\r' "$f" 2>/dev/null; then
    crlf_count=$((crlf_count + 1))
    rel="${f#$PKG_ROOT/}"
    if [ "$CHECK_ONLY" -eq 1 ]; then
      warn "CRLF: $rel"
    else
      tmp="$f.wsl-eol.$$"
      if tr -d '\r' < "$f" > "$tmp" 2>/dev/null && mv "$tmp" "$f"; then
        fixed_count=$((fixed_count + 1))
        ok "LF 정규화: $rel"
      else
        rm -f "$tmp" 2>/dev/null || true
        warn "정규화 실패(권한?): $rel"
      fi
    fi
  fi
done < <(list_sh)

if [ "$crlf_count" -eq 0 ]; then
  ok "모든 .sh가 이미 LF입니다(shebang 안전)."
elif [ "$CHECK_ONLY" -eq 1 ]; then
  warn "$crlf_count개 파일이 CRLF입니다 — './scripts/wsl-setup.sh'(--check 없이)로 복구하세요."
else
  say "$fixed_count개 파일을 LF로 정규화했습니다."
fi

# --- 3. Set the exec bit (repair mode) -------------------------------------------
if [ "$CHECK_ONLY" -eq 0 ]; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -x "$f" ] || chmod +x "$f" 2>/dev/null || true
  done < <(list_sh)
  ok ".sh 실행비트 확인/부여 완료."
fi

# --- 4. Dependency check (WSL is Linux -> apt hints) -----------------------------
say "의존성 점검:"
if command -v cargo >/dev/null 2>&1; then ok "cargo 있음 ($(cargo --version 2>/dev/null | awk '{print $2}'))"; else warn "Rust 미설치 — https://rustup.rs (WSL 안에서 설치). 엔진 빌드에 필요."; fi
if command -v jq >/dev/null 2>&1; then ok "jq 있음"; else warn "jq 미설치 — 'sudo apt-get update && sudo apt-get install -y jq' (bash 훅의 JSON 파싱에 필요)."; fi
if command -v claude >/dev/null 2>&1; then ok "claude CLI 있음"; else warn "Claude Code CLI 미발견 — WSL 안에 설치된 Claude Code로 실행하세요(v2.1.32+)."; fi

# --- 5. Engine binary status -----------------------------------------------------
# WSL is Linux, so the native binary is `bathos` (ELF). The classic mistake is carrying a
# `bathos.exe` (PE) built on Windows into WSL — we warn about exactly that case, on any OS.
LINUX_BIN="$PKG_ROOT/core/target/release/bathos"
if [ -x "$LINUX_BIN" ]; then
  btype="$(file "$LINUX_BIN" 2>/dev/null || true)"
  if printf '%s' "$btype" | grep -qiE 'PE32|MS Windows|MS-DOS'; then
    warn "core/target/release/bathos 가 Windows 실행파일(PE)로 보입니다 — WSL/리눅스에서는 'cd core && cargo build --release'로 네이티브(ELF) 바이너리를 다시 빌드하세요."
  else
    ok "엔진 빌드됨: core/target/release/bathos ($(printf '%s' "$btype" | sed 's/.*: //' | cut -c1-24))"
  fi
else
  say "엔진 미빌드 — WSL 안에서: cd core && cargo build --release  (→ core/target/release/bathos)"
fi

# --- 6. Next steps ---------------------------------------------------------------
printf '\n'
say "다음 단계(WSL):"
printf '  1) 엔진 빌드:   cd core && cargo build --release && cd ..\n'
printf '  2) 경로 지정:   export BATHOS_BIN="$PWD/core/target/release/bathos"\n'
printf '  3) 설치(선택):  ./install.sh --into /abs/path/to/project\n'
printf '  4) WSL 안에서 Claude Code를 열고 /team-kickoff 부터 진행\n'
printf '  가이드: docs/wsl-install-kr.md · docs/macos-linux-install-kr.md\n'

exit 0
