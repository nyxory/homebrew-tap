#!/usr/bin/env bash
# Nyxory CLI installer.
#
# This script is the canonical curl-pipe installer. It is meant to be
# served from the public release repo (`nyxory/homebrew-tap`):
#
#   curl -fsSL https://nyxory.com/install.sh | bash
#
# It auto-detects the platform, fetches the latest release tarball
# from `nyxory/homebrew-tap`, verifies the SHA-256 checksum against
# the goreleaser-published `checksums.txt`, and drops the binary on
# the user's $PATH.
#
# The source of truth lives in `nyxory/cli` under `release/install.sh`.
# A push to main that touches this file triggers
# `.github/workflows/mirror-install.yml`, which mirrors it to the root
# of `nyxory/homebrew-tap` (where the curl-pipe URL above serves from).
#
# Cosmetics: the installer prints a terminal-adaptive brand banner. It
# degrades cleanly — no TTY (curl | bash into a pipe), NO_COLOR, or
# NYX_NO_ANIM all dial it back automatically; the install logic is
# unaffected.

set -euo pipefail

REPO="nyxory/homebrew-tap"
INSTALL_DIR=""
VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)     INSTALL_DIR="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    -h|--help)
      cat <<USAGE
nyx installer

Usage:
  install.sh [--dir <path>] [--version <tag>]

Options:
  --dir <path>      Install to this directory (created if needed). Default:
                    /usr/local/bin if writable without sudo, else
                    \$HOME/.local/bin.
  --version <tag>   Install a specific tag (e.g. v0.5.0). Default: latest.
  -h, --help        Show this message.

Environment:
  NYX_INSTALL_DIR   Default install dir when --dir is omitted (handy for
                    the curl|bash form: ... | NYX_INSTALL_DIR=~/bin bash).
  NYX_INSTALL_ONLY  Set (any non-empty value) to skip the login/setup chain.
  NO_COLOR          Disable all color.
  NYX_NO_ANIM       Skip the reveal animation (banner still prints).
USAGE
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# --- presentation ------------------------------------------------------------
# Color is emitted with raw ANSI only when stdout is a TTY and NO_COLOR
# is unset. Truecolor is used when COLORTERM advertises it, otherwise we
# fall back to the xterm-256 cube. The accent palette flips for light
# backgrounds (detected via COLORFGBG) so the lime wordmark stays legible.

USE_COLOR=0
TRUECOLOR=0
LIGHT_BG=0
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  USE_COLOR=1
  case "${COLORTERM:-}" in
    *truecolor*|*24bit*) TRUECOLOR=1 ;;
  esac
  if [[ -n "${COLORFGBG:-}" ]]; then
    bg="${COLORFGBG##*;}"
    case "$bg" in
      0|1|2|3|4|5|6|8) LIGHT_BG=0 ;;          # dark ANSI slots
      ''|*[!0-9]*)     LIGHT_BG=0 ;;          # unparseable → assume dark
      *)               LIGHT_BG=1 ;;          # 7, 15, … → light
    esac
  fi
fi

RESET=""; DIM=""
[[ $USE_COLOR -eq 1 ]] && { RESET=$'\033[0m'; DIM=$'\033[2m'; }

# Gradient stops (r g b), bright→deep. Two palettes: dark- and light-bg.
GRAD_DARK=( "204 255 0" "180 230 0" "150 205 0" "120 180 10" "90 150 20" "70 120 25" )
GRAD_LIGHT=( "92 122 0" "80 108 0" "68 94 0" "56 80 0" "46 66 0" "36 52 0" )

# fg <r> <g> <b> → emits the SGR foreground escape for the active mode.
fg() {
  [[ $USE_COLOR -eq 1 ]] || return 0
  local r=$1 g=$2 b=$3
  if [[ $TRUECOLOR -eq 1 ]]; then
    printf '\033[38;2;%d;%d;%dm' "$r" "$g" "$b"
  else
    # nearest xterm-256 color-cube index
    local qr=$(( r * 5 / 255 )) qg=$(( g * 5 / 255 )) qb=$(( b * 5 / 255 ))
    printf '\033[38;5;%dm' $(( 16 + 36*qr + 6*qg + qb ))
  fi
}

ACCENT_RGB() { if [[ $LIGHT_BG -eq 1 ]]; then echo "${GRAD_LIGHT[0]}"; else echo "${GRAD_DARK[0]}"; fi; }

# The NYXORY wordmark (ANSI Shadow). Kept in lockstep with internal/ui.
LOGO=(
' ███╗   ██╗██╗   ██╗██╗  ██╗ ██████╗ ██████╗ ██╗   ██╗'
' ████╗  ██║╚██╗ ██╔╝╚██╗██╔╝██╔═══██╗██╔══██╗╚██╗ ██╔╝'
' ██╔██╗ ██║ ╚████╔╝  ╚███╔╝ ██║   ██║██████╔╝ ╚████╔╝ '
' ██║╚██╗██║  ╚██╔╝   ██╔██╗ ██║   ██║██╔══██╗  ╚██╔╝  '
' ██║ ╚████║   ██║   ██╔╝ ██╗╚██████╔╝██║  ██║   ██║   '
' ╚═╝  ╚═══╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   '
)

banner() {
  # No bash-4 namerefs here — macOS ships bash 3.2 and `curl | bash`
  # runs whatever `bash` resolves to. Pick the palette by index instead.
  local animate=0
  [[ $USE_COLOR -eq 1 && -z "${NYX_NO_ANIM:-}" ]] && animate=1

  echo
  local i rgb
  for i in "${!LOGO[@]}"; do
    if [[ $LIGHT_BG -eq 1 ]]; then rgb="${GRAD_LIGHT[$i]}"; else rgb="${GRAD_DARK[$i]}"; fi
    # shellcheck disable=SC2086
    printf '%s%s%s\n' "$(fg $rgb)" "${LOGO[$i]}" "$RESET"
    [[ $animate -eq 1 ]] && sleep 0.045
  done
  printf '%sthe nyxory deployment platform%s\n\n' "$DIM" "$RESET"
}

# step <msg> — accent-colored progress line.
step() {
  # shellcheck disable=SC2046
  printf '%s==>%s %s\n' "$(fg $(ACCENT_RGB))" "$RESET" "$1"
}

# spin <pid> <msg> — animate a braille spinner next to <msg> until the
# background <pid> exits. No-op (just prints the line) without a TTY.
spin() {
  local pid=$1 msg=$2
  if [[ $USE_COLOR -ne 1 || -n "${NYX_NO_ANIM:-}" ]]; then
    wait "$pid"; return $?
  fi
  local frames=( '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' ) k=0 n
  n=${#frames[@]}
  # shellcheck disable=SC2046
  local a; a="$(fg $(ACCENT_RGB))"
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r%s%s%s %s' "$a" "${frames[k++%n]}" "$RESET" "$msg"
    sleep 0.08
  done
  local rc=0; wait "$pid" || rc=$?
  printf '\r\033[K'   # clear the spinner line
  return $rc
}

banner

# --- platform detection ------------------------------------------------------

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$OS" in
  darwin|linux) ;;
  mingw*|msys*|cygwin*)
    # Git-Bash / MSYS / Cygwin on Windows — point at the native installer.
    echo "this is the mac/linux installer; on Windows use PowerShell instead:" >&2
    echo '  powershell -ExecutionPolicy Bypass -c "irm https://nyxory.com/install.ps1 | iex"' >&2
    exit 1
    ;;
  *)
    echo "unsupported OS: $OS" >&2
    echo "  → try the Homebrew tap (mac/linux): brew install nyxory/tap/nyx" >&2
    echo "  → or download manually: https://github.com/${REPO}/releases" >&2
    exit 1
    ;;
esac

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ARCH=amd64 ;;
  arm64|aarch64) ARCH=arm64 ;;
  *)
    echo "unsupported arch: $ARCH (need amd64 or arm64)" >&2
    exit 1
    ;;
esac

# --- resolve version ---------------------------------------------------------

if [[ -z "$VERSION" ]]; then
  # Anonymous GitHub API call — public repo, 60 req/h per IP, plenty for installs.
  VERSION="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -n1)"
  if [[ -z "$VERSION" ]]; then
    echo "could not resolve latest release from github.com/${REPO}" >&2
    echo "  → check that the repo exists and has at least one release published" >&2
    exit 1
  fi
fi

# Tags are always v-prefixed; tolerate --version 0.6.0 / NYX_VERSION=0.6.0.
[[ "$VERSION" == v* ]] || VERSION="v${VERSION}"

ASSET="nyx-${VERSION}-${OS}-${ARCH}.tar.gz"
ASSET_URL="https://github.com/${REPO}/releases/download/${VERSION}/${ASSET}"
CHECKSUMS_URL="https://github.com/${REPO}/releases/download/${VERSION}/checksums.txt"

# --- resolve install dir -----------------------------------------------------
#
# Precedence: --dir flag > NYX_INSTALL_DIR env > /usr/local/bin (only when
# writable WITHOUT sudo — we never prompt for a password inside a pipe) >
# ~/.local/bin. The chosen directory is always created (one code path), so
# a custom --dir / NYX_INSTALL_DIR that doesn't exist yet just works.

if [[ -z "$INSTALL_DIR" ]]; then
  INSTALL_DIR="${NYX_INSTALL_DIR:-}"
fi
if [[ -z "$INSTALL_DIR" ]]; then
  if [[ -w /usr/local/bin ]]; then
    INSTALL_DIR=/usr/local/bin
  else
    if [[ -z "${HOME:-}" ]]; then
      echo "cannot determine install dir: \$HOME is unset and /usr/local/bin isn't writable" >&2
      echo "  → pass one explicitly: install.sh --dir /path/to/bin (or set NYX_INSTALL_DIR)" >&2
      exit 1
    fi
    INSTALL_DIR="${HOME}/.local/bin"
  fi
fi

if ! mkdir -p "$INSTALL_DIR" 2>/dev/null; then
  echo "could not create install dir: ${INSTALL_DIR}" >&2
  echo "  → it may need elevated permissions; pick a writable path with --dir or NYX_INSTALL_DIR" >&2
  exit 1
fi

# --- download + verify + install --------------------------------------------

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

step "Downloading ${ASSET} (${VERSION})"
( curl -fsSL -o "$TMP/${ASSET}" "$ASSET_URL" ) &
spin $! "fetching ${OS}/${ARCH} binary…"

step "Verifying checksum"
if curl -fsSL -o "$TMP/checksums.txt" "$CHECKSUMS_URL"; then
  cd "$TMP"
  if command -v sha256sum >/dev/null 2>&1; then
    grep " ${ASSET}\$" checksums.txt | sha256sum -c -
  elif command -v shasum >/dev/null 2>&1; then
    expected="$(grep " ${ASSET}\$" checksums.txt | awk '{print $1}')"
    actual="$(shasum -a 256 "$ASSET" | awk '{print $1}')"
    if [[ "$expected" != "$actual" ]]; then
      echo "checksum mismatch: expected $expected, got $actual" >&2
      exit 1
    fi
  else
    echo "warning: no sha256sum/shasum available — skipping checksum verification" >&2
  fi
  cd - >/dev/null
else
  echo "warning: checksums.txt not available for ${VERSION}; skipping verification" >&2
fi

step "Extracting"
tar -xzf "$TMP/${ASSET}" -C "$TMP"
# goreleaser tar.gz archives don't wrap their contents in a directory by
# default, so `nyx` lands at the archive root — but some configs (and a
# future wrap_in_directory: true) nest it one level down. Locate the
# binary either way instead of assuming a fixed path.
NYX_BIN="$(find "$TMP" -type f -name nyx -not -name '*.tar.gz' 2>/dev/null | head -n1)"
if [[ -z "$NYX_BIN" || ! -f "$NYX_BIN" ]]; then
  echo "extracted archive does not contain a nyx binary (looked under ${TMP})" >&2
  echo "  → archive contents:" >&2
  tar -tzf "$TMP/${ASSET}" >&2 || true
  exit 1
fi
chmod +x "$NYX_BIN"

step "Installing to ${INSTALL_DIR}/nyx"
install -m 0755 "$NYX_BIN" "$INSTALL_DIR/nyx"

echo
# shellcheck disable=SC2046
printf '%s✓%s nyx %s installed to %s%s%s\n' \
  "$(fg $(ACCENT_RGB))" "$RESET" "$VERSION" "$(fg $(ACCENT_RGB))" "${INSTALL_DIR}/nyx" "$RESET"
case ":$PATH:" in
  *":${INSTALL_DIR}:"*) ;;
  *)
    # Point the user at the right rc file + syntax for their shell. The
    # PATH we test is this (non-interactive) shell's, so the hint can
    # fire even when the dir is on the user's interactive PATH — a
    # harmless, conservative nudge.
    shell_name="$(basename "${SHELL:-sh}")"
    echo
    echo "  ⚠ ${INSTALL_DIR} is not on your \$PATH yet."
    case "$shell_name" in
      fish)
        echo "    Add it with:"
        echo "      fish_add_path \"${INSTALL_DIR}\""
        ;;
      zsh)
        rc="${ZDOTDIR:-$HOME}/.zshrc"
        echo "    Add it to ${rc}:"
        echo "      echo 'export PATH=\"${INSTALL_DIR}:\$PATH\"' >> \"${rc}\""
        echo "    then restart your shell (or: source \"${rc}\")."
        ;;
      bash)
        # macOS login shells read .bash_profile; Linux interactive shells .bashrc.
        if [[ "$OS" == darwin ]]; then rc="$HOME/.bash_profile"; else rc="$HOME/.bashrc"; fi
        echo "    Add it to ${rc}:"
        echo "      echo 'export PATH=\"${INSTALL_DIR}:\$PATH\"' >> \"${rc}\""
        echo "    then restart your shell (or: source \"${rc}\")."
        ;;
      *)
        echo "    Add this to your shell's startup file:"
        echo "      export PATH=\"${INSTALL_DIR}:\$PATH\""
        ;;
    esac
    ;;
esac
echo

# --- first-run chain ----------------------------------------------------------
# One pasted command end-to-end: sign in (browser OAuth) and wire every
# detected AI client via `nyx setup`. Interactivity comes from /dev/tty —
# stdin is the curl pipe. Skipped when NYX_INSTALL_ONLY is set or without
# a controlling terminal (CI). Older pinned versions without `nyx setup`
# fall back to printed next steps. Probe is `setup --help`, NOT `help
# setup` — cobra exits 0 ("Unknown help topic" on stderr) for the latter,
# so it can't detect a missing command.

NYX="${INSTALL_DIR}/nyx"
HAVE_TTY=0
if { : </dev/tty; } 2>/dev/null; then HAVE_TTY=1; fi
HAS_SETUP=0
if "$NYX" setup --help >/dev/null 2>&1; then HAS_SETUP=1; fi

if [[ $HAS_SETUP -eq 1 && $HAVE_TTY -eq 1 && -z "${NYX_INSTALL_ONLY:-}" ]]; then
  step "Signing in"
  if ! "$NYX" login </dev/tty; then
    echo "  ⚠ login didn't complete — finish later with: nyx login && nyx setup" >&2
    exit 0
  fi
  step "Wiring your AI clients"
  # NYX_SETUP_SOURCE marks this run as the chained installer path in
  # the install funnel (vs a hand-typed `nyx setup`). No --all: setup
  # shows its pre-selected checklist so nothing gets wired unseen —
  # stdin is /dev/tty, so the prompt works inside the curl pipe.
  NYX_SETUP_SOURCE=installer "$NYX" setup </dev/tty \
    || echo "  ⚠ setup didn't complete — re-run anytime with: nyx setup" >&2
else
  echo "  Next:"
  echo "    nyx login          # sign in (defaults to the prod endpoint)"
  if [[ $HAS_SETUP -eq 1 ]]; then
    echo "    nyx setup          # wire your AI clients (Claude Code, Codex, Cursor, VS Code)"
  else
    echo "    nyx claude install # wire your agent (also: nyx cursor / codex install)"
  fi
  echo "    nyx --help         # everything else"
fi
