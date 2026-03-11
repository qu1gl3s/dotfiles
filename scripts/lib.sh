#!/bin/bash
# Shared helper functions and constants for chezmoi scripts and verification.

# -- Constants -----------------------------------------------------------------

DEFENDER_BUNDLE_ID="com.microsoft.wdav"
# shellcheck disable=SC2034
DEFENDER_TEAM_ID="UBF8T346G9"

WIREGUARD_APP_PATH="/Applications/WireGuard.app"
WIREGUARD_BUNDLE_ID="com.wireguard.macos"
WIREGUARD_MARKER_FILE="${HOME}/.local/state/chezmoi/wireguard-configured"
WIREGUARD_SCUTIL_SENTINEL="scutil-detected"

# -- Utility -------------------------------------------------------------------

run_with_timeout() {
  local timeout_seconds="$1"
  shift
  local tmp_output=""
  local pid=""
  local elapsed=0
  local status=0

  tmp_output="$(mktemp)"
  "$@" >"${tmp_output}" 2>&1 &
  pid=$!

  while kill -0 "${pid}" 2>/dev/null; do
    if [[ "${elapsed}" -ge "${timeout_seconds}" ]]; then
      kill "${pid}" 2>/dev/null || true
      wait "${pid}" 2>/dev/null || true
      cat "${tmp_output}"
      rm -f "${tmp_output}"
      return 124
    fi
    sleep 1
    ((elapsed += 1))
  done

  wait "${pid}" || status=$?
  cat "${tmp_output}"
  rm -f "${tmp_output}"
  return "${status}"
}

normalize_bool() {
  case "${1}" in
    1|true|TRUE|yes|YES|on|ON) echo 1 ;;
    0|false|FALSE|no|NO|off|OFF) echo 0 ;;
    *) echo "${1}" ;;
  esac
}

# -- Defender ------------------------------------------------------------------

is_defender_installed() {
  local app_path=""
  local bundle_id=""

  for app_path in "/Applications/Microsoft Defender.app" "/Applications/Defender.app"; do
    if [[ -d "${app_path}" ]]; then
      bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${app_path}/Contents/Info.plist" 2>/dev/null || true)"
      if [[ "${bundle_id}" == "${DEFENDER_BUNDLE_ID}" ]]; then
        return 0
      fi
    fi
  done

  return 1
}

# -- WireGuard -----------------------------------------------------------------

is_wireguard_installed() {
  local bundle_id=""

  if [[ ! -d "${WIREGUARD_APP_PATH}" ]]; then
    return 1
  fi

  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${WIREGUARD_APP_PATH}/Contents/Info.plist" 2>/dev/null || true)"
  [[ "${bundle_id}" == "${WIREGUARD_BUNDLE_ID}" ]]
}

wireguard_tunnel_count_from_scutil() {
  local scutil_output=""
  scutil_output="$(scutil --nc list 2>/dev/null || true)"
  grep -cE '\(com\.wireguard\.macos\)|\[VPN:com\.wireguard\.macos\]' <<<"${scutil_output}" || true
}

is_wireguard_marker_valid() {
  if [[ ! -f "${WIREGUARD_MARKER_FILE}" ]]; then
    return 1
  fi

  local marker_path=""
  marker_path="$(head -n 1 "${WIREGUARD_MARKER_FILE}" 2>/dev/null || true)"
  if [[ -z "${marker_path}" || "${marker_path}" == "${WIREGUARD_SCUTIL_SENTINEL}" ]]; then
    return 0
  fi

  [[ -f "${marker_path}" ]]
}

# -- System --------------------------------------------------------------------

pmset_displaysleep_value() {
  local profile="$1"
  local pmset_output="$2"

  case "${profile}" in
    battery)
      awk '
        /^Battery Power:/ { section="battery"; next }
        /^AC Power:/ { section="" }
        section == "battery" && $1 == "displaysleep" { print $2; exit }
      ' <<< "${pmset_output}"
      ;;
    ac)
      awk '
        /^AC Power:/ { section="ac"; next }
        section == "ac" && $1 == "displaysleep" { print $2; exit }
      ' <<< "${pmset_output}"
      ;;
  esac
}
