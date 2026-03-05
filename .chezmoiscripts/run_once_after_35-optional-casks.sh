#!/bin/bash
set -euo pipefail
#
# Script: run_once_after_35-optional-casks.sh
# Purpose: Prompt once for optional Homebrew cask installs.
# Prerequisites: macOS with Homebrew available in /opt/homebrew.
# Env flags: CHEZMOI_SKIP_BREW=1 skips this script.
# Failure behavior: exits non-zero if Homebrew is unavailable or chosen cask install fails.

if [[ "${CHEZMOI_SKIP_BREW:-0}" == "1" ]]; then
  echo "Skipping optional cask prompt because CHEZMOI_SKIP_BREW=1"
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  exit 0
fi

if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found; cannot prompt for optional casks." >&2
  exit 1
fi

SOURCE_DIR="${CHEZMOI_SOURCE_DIR:-$HOME/.local/share/chezmoi}"
OPTIONAL_CASKS_FILE="${SOURCE_DIR}/casks/optional-casks.txt"

if [[ ! -f "${OPTIONAL_CASKS_FILE}" ]]; then
  echo "Optional cask file not found: ${OPTIONAL_CASKS_FILE}" >&2
  exit 1
fi

if [[ ! -t 0 || ! -t 1 ]]; then
  echo "No TTY detected; skipping optional cask prompts."
  exit 0
fi

while read -r cask_token; do
  [[ -z "${cask_token}" || "${cask_token:0:1}" == "#" ]] && continue

  read -r -p "Install optional cask '${cask_token}'? [y/N] " reply
  case "${reply}" in
    y|Y|yes|YES)
      brew install --cask "${cask_token}"
      ;;
    *)
      ;;
  esac
done < "${OPTIONAL_CASKS_FILE}"
