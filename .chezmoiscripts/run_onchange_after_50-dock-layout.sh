#!/bin/bash
set -euo pipefail
#
# Script: run_onchange_after_50-dock-layout.sh
# Purpose: Rebuild Dock app layout to the baseline order using dockutil.
# Prerequisites: macOS, Homebrew Bash, dockutil, and macos/dock-app-order.txt present.
# Env flags:
#   CHEZMOI_SKIP_DOCK_LAYOUT=1 skips this script
#   CHEZMOI_SKIP_BREW=1 skips this script because dockutil is Homebrew-managed
# Failure behavior: exits non-zero if Homebrew Bash/dockutil/order file is missing or Dock reset fails.

if [[ "${CHEZMOI_SKIP_DOCK_LAYOUT:-0}" == "1" ]]; then
  echo "Skipping Dock layout because CHEZMOI_SKIP_DOCK_LAYOUT=1"
  exit 0
fi

if [[ "${CHEZMOI_SKIP_BREW:-0}" == "1" ]]; then
  echo "Skipping Dock layout because CHEZMOI_SKIP_BREW=1"
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  exit 0
fi

# Use Homebrew Bash for modern features (e.g., mapfile).
if [[ "${BASH_VERSINFO[0]:-0}" -lt 4 ]]; then
  if [[ -x /opt/homebrew/bin/bash ]]; then
    exec /opt/homebrew/bin/bash "$0" "$@"
  fi
  cat >&2 <<'EOF'
Homebrew Bash is required for Dock layout management but was not found.
Install prerequisites with:
  brew install bash
EOF
  exit 1
fi

if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

if ! command -v dockutil >/dev/null 2>&1; then
  cat >&2 <<'EOF'
dockutil is required for Dock layout management but is not installed.
Re-run bootstrap/apply without CHEZMOI_SKIP_BREW, or install it manually:
  brew install dockutil
EOF
  exit 1
fi

SOURCE_DIR="${CHEZMOI_SOURCE_DIR:-$HOME/.local/share/chezmoi}"
ORDER_FILE="${SOURCE_DIR}/macos/dock-app-order.txt"
FINDER_APP="/System/Library/CoreServices/Finder.app"

if [[ ! -f "${ORDER_FILE}" ]]; then
  echo "Dock order file not found: ${ORDER_FILE}" >&2
  exit 1
fi

mapfile -t apps < <(awk 'NF > 0 && $1 !~ /^#/ { print }' "${ORDER_FILE}")

if [[ "${#apps[@]}" -eq 0 ]]; then
  echo "Dock order file is empty after filtering comments: ${ORDER_FILE}" >&2
  exit 1
fi

dockutil --remove all --no-restart

added_count=0
missing_count=0
for app_path in "${apps[@]}"; do
  if [[ "${app_path}" == "${FINDER_APP}" ]]; then
    echo "Skipping Finder; it is managed by macOS to avoid duplicate Dock icons."
    continue
  fi

  if [[ -d "${app_path}" ]]; then
    dockutil --add "${app_path}" --no-restart
    echo "Added to Dock: ${app_path}"
    ((added_count += 1))
  else
    echo "Warning: app not found, skipping Dock item: ${app_path}" >&2
    ((missing_count += 1))
  fi
done

killall Dock >/dev/null 2>&1 || true
echo "Dock layout applied (${added_count} added, ${missing_count} missing)."
