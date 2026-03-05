#!/bin/bash
set -euo pipefail
#
# Script: run_onchange_after_41-screenshot-location.sh
# Purpose: Enforce screenshot save location under configured Synology Drive CloudStorage.
# Prerequisites: macOS with exactly one SynologyDrive-* root and an existing Screenshots folder.
# Env flags: CHEZMOI_SKIP_MACOS_DEFAULTS=1 skips this script.
# Failure behavior: exits non-zero when CloudStorage path is missing/ambiguous or Screenshots folder is absent.

if [[ "${CHEZMOI_SKIP_MACOS_DEFAULTS:-0}" == "1" ]]; then
  echo "Skipping screenshot location because CHEZMOI_SKIP_MACOS_DEFAULTS=1"
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  exit 0
fi

cloud_root_glob="${HOME}/Library/CloudStorage/SynologyDrive-*"

shopt -s nullglob
candidate_roots=( ${cloud_root_glob} )
shopt -u nullglob

if [[ "${#candidate_roots[@]}" -eq 0 ]]; then
  cat >&2 <<'EOF'
No Synology Drive CloudStorage root found.
Expected a path matching:
  ~/Library/CloudStorage/SynologyDrive-*
Configure Synology Drive first, then rerun:
  chezmoi apply
EOF
  exit 1
fi

if [[ "${#candidate_roots[@]}" -gt 1 ]]; then
  echo "Multiple Synology Drive CloudStorage roots found. Resolve ambiguity and rerun chezmoi apply." >&2
  for root in "${candidate_roots[@]}"; do
    echo "  - ${root}" >&2
  done
  exit 1
fi

synology_root="${candidate_roots[0]}"
desired_path="${synology_root}/Screenshots"

if [[ ! -d "${desired_path}" ]]; then
  cat >&2 <<EOF
Expected screenshot folder not found:
  ${desired_path}
Create/fix this folder in Synology Drive, then rerun:
  chezmoi apply
EOF
  exit 1
fi

desired_tilde_path="~${desired_path#${HOME}}"
current_path="$(defaults read com.apple.screencapture location 2>/dev/null || true)"

if [[ "${current_path}" == "${desired_path}" || "${current_path}" == "${desired_tilde_path}" ]]; then
  exit 0
fi

defaults write com.apple.screencapture location -string "${desired_path}"
killall SystemUIServer >/dev/null 2>&1 || true
echo "Applied screenshot location: ${desired_path}"
