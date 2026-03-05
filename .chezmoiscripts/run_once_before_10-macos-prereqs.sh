#!/bin/bash
set -euo pipefail
#
# Script: run_once_before_10-macos-prereqs.sh
# Purpose: Ensure macOS bootstrap prerequisites are available once per machine.
# Prerequisites: macOS (Apple Silicon), internet access, admin privileges.
# Env flags: CHEZMOI_SKIP_BREW=1 skips this script.
# Failure behavior: exits non-zero with actionable errors when Homebrew/CLT checks fail.

if [[ "${CHEZMOI_SKIP_BREW:-0}" == "1" ]]; then
  echo "Skipping macOS prerequisites because CHEZMOI_SKIP_BREW=1"
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  exit 0
fi

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "This bootstrap supports Apple Silicon only (arm64)." >&2
  exit 1
fi

if [[ ! -x /opt/homebrew/bin/brew ]]; then
  if ! command -v curl >/dev/null 2>&1; then
    echo "curl is required to install Homebrew." >&2
    exit 1
  fi

  echo "Installing Homebrew (non-interactive)..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew installation failed. Re-run bootstrap after fixing Homebrew." >&2
  exit 1
fi

if ! xcode-select -p >/dev/null 2>&1; then
  cat >&2 <<'EOF'
Xcode Command Line Tools are not available after Homebrew install.
Re-run bootstrap after confirming CLT installation is complete.
EOF
  exit 1
fi
