#!/bin/sh
# pro-preflight.sh — ensure the Proteos `pro` CLI is installed, pointed at
# production, and signed in. Idempotent: a re-run detects an installed binary,
# an existing `prod` profile, and a valid session, and passes straight through.
#
# Usage:
#   sh pro-preflight.sh                    # install/verify the latest release
#   sh pro-preflight.sh --version 0.18.1   # pin a specific release
#   PRO_VERSION=0.18.1 sh pro-preflight.sh # same, via env
#   PRO_INSTALL_DIR=/usr/local/bin sh pro-preflight.sh
#   sh pro-preflight.sh --skip-login       # binary + profile only
#
# Exit codes:
#   0 — ready (signed in, or --skip-login)
#   4 — binary + profile ready but sign-in needs the user (soft; relay the
#       printed message, don't treat as failure)
#   anything else — hard error
#
# Windows note: this script is POSIX sh (macOS/Linux only). On Windows,
# download pro_<version>_windows_<arch>.zip from
# https://github.com/proteos-ai/cli/releases, verify its sha256 against
# checksums.txt from the same release (`Get-FileHash -Algorithm SHA256`),
# put the extracted pro.exe on PATH, then run the same
# `pro profiles add prod --api-url https://api.proteos.ai`,
# `pro profiles use prod`, and `pro login` steps in PowerShell.

set -eu

REPO="proteos-ai/cli"
API_URL="https://api.proteos.ai"
PROFILE="prod"
INSTALL_DIR="${PRO_INSTALL_DIR:-$HOME/.local/bin}"
WANT_VERSION="${PRO_VERSION:-}"
SKIP_LOGIN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --version)    WANT_VERSION="$2"; shift 2 ;;
    --version=*)  WANT_VERSION="${1#--version=}"; shift ;;
    --skip-login) SKIP_LOGIN=1; shift ;;
    -h|--help)    sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "pro-preflight: unknown flag $1 (see --help)" >&2; exit 2 ;;
  esac
done

log()  { printf '>> %s\n' "$*"; }
fail() { printf 'pro-preflight ERROR: %s\n' "$*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || fail "curl is required"

# ---------- desired version --------------------------------------------------
# The repo is public — no token needed for the API or the downloads.
resolve_latest() {
  api_json=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest") ||
    return 1
  if command -v jq >/dev/null 2>&1; then
    printf '%s\n' "$api_json" | jq -r '.tag_name // empty'
  else
    printf '%s\n' "$api_json" |
      grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1 |
      sed -e 's/.*:[[:space:]]*"//' -e 's/"$//'
  fi
}

if [ -z "$WANT_VERSION" ]; then
  WANT_VERSION=$(resolve_latest) ||
    fail "cannot reach the GitHub releases API for $REPO"
  WANT_VERSION=${WANT_VERSION#v}
  [ -n "$WANT_VERSION" ] || fail "could not parse .tag_name from the releases API response"
else
  WANT_VERSION=${WANT_VERSION#v}
fi

# ---------- binary -----------------------------------------------------------
installed_version() {
  pro version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+[0-9A-Za-z.+-]*' | head -n 1
}

CURRENT=""
if command -v pro >/dev/null 2>&1; then
  CURRENT=$(installed_version || true)
fi

if [ "$CURRENT" = "$WANT_VERSION" ]; then
  log "pro $CURRENT already installed ($(command -v pro)) — skipping download"
else
  [ -n "$CURRENT" ] && log "pro $CURRENT installed, want $WANT_VERSION — replacing"

  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  case "$os" in
    darwin|linux) ;;
    mingw*|msys*|cygwin*) fail "Windows shell detected — follow the Windows note in this script's header" ;;
    *) fail "unsupported OS '$os' (release assets cover darwin/linux/windows)" ;;
  esac
  arch=$(uname -m)
  case "$arch" in
    x86_64|amd64)  arch=amd64 ;;
    arm64|aarch64) arch=arm64 ;;
    *) fail "unsupported architecture '$arch' (release assets cover amd64/arm64)" ;;
  esac

  asset="pro_${WANT_VERSION}_${os}_${arch}.tar.gz"
  base="https://github.com/$REPO/releases/download/v$WANT_VERSION"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT

  log "downloading $asset"
  curl -fsSL -o "$tmp/$asset" "$base/$asset" ||
    fail "download failed for $base/$asset — no asset for ${os}/${arch} in v$WANT_VERSION, or that version doesn't exist"
  curl -fsSL -o "$tmp/checksums.txt" "$base/checksums.txt" ||
    fail "checksums.txt missing from release v$WANT_VERSION"

  # goreleaser checksums.txt: "<sha256>  <filename>" per line.
  want_sha=$(grep " ${asset}\$" "$tmp/checksums.txt" | awk '{print $1}' | head -n 1)
  [ -n "$want_sha" ] || fail "no entry for $asset in checksums.txt"
  if command -v sha256sum >/dev/null 2>&1; then
    got_sha=$(sha256sum "$tmp/$asset" | awk '{print $1}')
  elif command -v shasum >/dev/null 2>&1; then
    got_sha=$(shasum -a 256 "$tmp/$asset" | awk '{print $1}')
  else
    fail "need sha256sum or shasum to verify the download"
  fi
  [ "$got_sha" = "$want_sha" ] ||
    fail "sha256 MISMATCH for $asset — expected $want_sha, got $got_sha. Aborting; nothing was installed."

  tar -xzf "$tmp/$asset" -C "$tmp" || fail "could not extract $asset"
  [ -f "$tmp/pro" ] || fail "archive $asset did not contain a 'pro' binary"

  mkdir -p "$INSTALL_DIR" 2>/dev/null || true
  { [ -d "$INSTALL_DIR" ] && [ -w "$INSTALL_DIR" ]; } ||
    fail "$INSTALL_DIR is not writable — re-run with PRO_INSTALL_DIR=<writable PATH dir>"
  chmod +x "$tmp/pro"
  mv -f "$tmp/pro" "$INSTALL_DIR/pro"
  log "installed pro $WANT_VERSION to $INSTALL_DIR/pro"

  case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *) log "WARNING: $INSTALL_DIR is not on PATH — add:  export PATH=\"$INSTALL_DIR:\$PATH\"" ;;
  esac
fi

# The rest of this run must use the verified binary even if PATH lacks it.
PATH="$INSTALL_DIR:$PATH"; export PATH

resolved=$(command -v pro) || fail "pro not found on PATH after install"
ver=$(installed_version || true)
[ -n "$ver" ] || fail "'pro version' failed or unparseable — $resolved is not runnable"
if [ "$ver" != "$WANT_VERSION" ]; then
  log "WARNING: PATH resolves pro $ver at $resolved (wanted $WANT_VERSION) — an older copy shadows $INSTALL_DIR/pro; fix PATH order or remove it"
fi
log "pro $ver at $resolved"

# ---------- prod profile -----------------------------------------------------
if pro profiles list 2>/dev/null | grep -qw "$PROFILE"; then
  log "profile '$PROFILE' already exists"
else
  pro profiles add "$PROFILE" --api-url "$API_URL" ||
    fail "pro profiles add $PROFILE --api-url $API_URL failed"
  log "created profile '$PROFILE' -> $API_URL"
fi
pro profiles use "$PROFILE" || fail "pro profiles use $PROFILE failed"

# ---------- auth -------------------------------------------------------------
whoami_line() { pro whoami 2>/dev/null | head -n 3 | tr '\n' ' '; }

if [ "$SKIP_LOGIN" = 1 ]; then
  printf 'preflight ok (login skipped) — pro %s, profile %s @ %s\n' "$ver" "$PROFILE" "$API_URL"
  exit 0
fi

if pro whoami >/dev/null 2>&1; then
  printf 'preflight ok — signed in as %s(pro %s, profile %s @ %s)\n' "$(whoami_line)" "$ver" "$PROFILE" "$API_URL"
  exit 0
fi

log "no valid session — starting 'pro login' (Auth0 authorization-code + PKCE; a browser should open)"
if pro login && pro whoami >/dev/null 2>&1; then
  printf 'preflight ok — signed in as %s(pro %s, profile %s @ %s)\n' "$(whoami_line)" "$ver" "$PROFILE" "$API_URL"
  exit 0
fi

cat <<EOF
pro-preflight: couldn't complete sign-in automatically (headless / no browser?).
Finish it yourself — either:
  pro login              # in your own terminal, with the '$PROFILE' profile active
  pro login --no-browser # prints the sign-in URL to open manually
then re-run this script (idempotent), or just continue — everything else is done.
preflight incomplete — pro $ver installed, profile '$PROFILE' active, sign-in pending: run 'pro login'
EOF
exit 4
