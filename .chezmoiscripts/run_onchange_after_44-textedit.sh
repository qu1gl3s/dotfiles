#!/bin/bash
set -euo pipefail
#
# Script: run_onchange_after_44-textedit.sh
# Purpose: Enforce TextEdit plain text defaults and disable spell-related features.
# Prerequisites: macOS, TextEdit baseline file present in source dir.
# Env flags: CHEZMOI_SKIP_MACOS_DEFAULTS=1 skips this script.
# Failure behavior: exits non-zero on malformed settings entries or defaults write failures.

if [[ "${CHEZMOI_SKIP_MACOS_DEFAULTS:-0}" == "1" ]]; then
  echo "Skipping TextEdit defaults because CHEZMOI_SKIP_MACOS_DEFAULTS=1"
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  exit 0
fi

SOURCE_DIR="${CHEZMOI_SOURCE_DIR:-$HOME/.local/share/chezmoi}"
BASELINE_FILE="${SOURCE_DIR}/macos/textedit-baseline.sh"

if [[ ! -f "${BASELINE_FILE}" ]]; then
  echo "Missing TextEdit baseline file: ${BASELINE_FILE}" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "${BASELINE_FILE}"

if ! declare -F macos_textedit_settings_entries >/dev/null 2>&1; then
  echo "macos_textedit_settings_entries function not found in ${BASELINE_FILE}" >&2
  exit 1
fi

normalize_bool() {
  case "${1}" in
    1|true|TRUE|yes|YES|on|ON) echo 1 ;;
    0|false|FALSE|no|NO|off|OFF) echo 0 ;;
    *) echo "${1}" ;;
  esac
}

values_equal() {
  local type="$1"
  local current="$2"
  local desired="$3"

  case "${type}" in
    bool)
      [[ "$(normalize_bool "${current}")" == "$(normalize_bool "${desired}")" ]]
      ;;
    int)
      [[ "${current}" == "${desired}" ]]
      ;;
    string)
      [[ "${current}" == "${desired}" ]]
      ;;
    *)
      return 1
      ;;
  esac
}

write_setting() {
  local domain="$1"
  local key="$2"
  local type="$3"
  local value="$4"
  local normalized_bool=""

  case "${type}" in
    bool)
      normalized_bool="$(normalize_bool "${value}")"
      case "${normalized_bool}" in
        1) defaults write "${domain}" "${key}" -bool true ;;
        0) defaults write "${domain}" "${key}" -bool false ;;
        *)
          echo "Unsupported bool value '${value}' for ${domain} ${key}" >&2
          return 1
          ;;
      esac
      ;;
    int) defaults write "${domain}" "${key}" -int "${value}" ;;
    string) defaults write "${domain}" "${key}" -string "${value}" ;;
    *)
      echo "Unsupported type '${type}' for ${domain} ${key}" >&2
      return 1
      ;;
  esac
}

changes_applied=0

while IFS='|' read -r domain key type value; do
  [[ -z "${domain}" || "${domain:0:1}" == "#" ]] && continue

  current=""
  has_current=0
  if current="$(defaults read "${domain}" "${key}" 2>/dev/null)"; then
    has_current=1
  fi

  if [[ "${has_current}" -eq 1 ]] && values_equal "${type}" "${current}" "${value}"; then
    continue
  fi

  write_setting "${domain}" "${key}" "${type}" "${value}"
  echo "Applied ${domain} ${key}=${value}"
  changes_applied=1
done < <(macos_textedit_settings_entries)

if [[ "${changes_applied}" -eq 1 ]]; then
  echo "TextEdit preferences updated; reopen TextEdit to pick up default behavior changes."
fi
