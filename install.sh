#!/usr/bin/env bash
# Nyxory CLI installer.
#
# This script is the canonical curl-pipe installer. It is meant to be
# served from the public release repo (`nyxory/homebrew-tap`):
#
#   curl -fsSL https://raw.githubusercontent.com/nyxory/homebrew-tap/main/install.sh | bash
#
# It auto-detects the platform, fetches the latest release tarball
# from `nyxory/homebrew-tap`, verifies the SHA-256 checksum against
# the goreleaser-published `checksums.txt`, and drops the binary on
# the user's $PATH.
#
# The source of truth lives in `nyxory/cli` under `release/install.sh`
# and is mirrored to `nyxory/homebrew-tap` whenever it changes.

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
  --dir <path>      Install to this directory. Default: /usr/local/bin
                    if writable, else \$HOME/.local/bin (created if needed).
  --version <tag>   Install a specific tag (e.g. v0.5.0). Default: latest.
  -h, --help        Show this message.
USAGE
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# --- platform detection ------------------------------------------------------

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$OS" in
  darwin|linux) ;;
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

ASSET="nyx-${VERSION}-${OS}-${ARCH}.tar.gz"
ASSET_URL="https://github.com/${REPO}/releases/download/${VERSION}/${ASSET}"
CHECKSUMS_URL="https://github.com/${REPO}/releases/download/${VERSION}/checksums.txt"

# --- resolve install dir -----------------------------------------------------

if [[ -z "$INSTALL_DIR" ]]; then
  if [[ -w /usr/local/bin ]]; then
    INSTALL_DIR=/usr/local/bin
  else
    INSTALL_DIR="${HOME}/.local/bin"
    mkdir -p "$INSTALL_DIR"
  fi
fi

# --- download + verify + install --------------------------------------------

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Downloading ${ASSET}"
curl -fsSL -o "$TMP/${ASSET}" "$ASSET_URL"

echo "==> Verifying checksum"
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

echo "==> Extracting"
tar -xzf "$TMP/${ASSET}" -C "$TMP"
EXTRACT_DIR="$TMP/nyx-${VERSION}-${OS}-${ARCH}"
if [[ ! -x "$EXTRACT_DIR/nyx" ]]; then
  echo "extracted archive does not contain nyx at ${EXTRACT_DIR}/nyx" >&2
  exit 1
fi

echo "==> Installing to ${INSTALL_DIR}/nyx"
install -m 0755 "$EXTRACT_DIR/nyx" "$INSTALL_DIR/nyx"

echo
echo "✓ nyx ${VERSION} installed to ${INSTALL_DIR}/nyx"
case ":$PATH:" in
  *":${INSTALL_DIR}:"*) ;;
  *)
    echo
    echo "  ⚠ ${INSTALL_DIR} is not on your \$PATH. Add this to your shell rc:"
    echo "      export PATH=\"${INSTALL_DIR}:\$PATH\""
    ;;
esac
echo "  Run \`nyx --help\` to get started."
