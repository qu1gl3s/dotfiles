#!/bin/bash
set -euo pipefail

READINESS_STATE_DIR="${HOME}/.local/state/chezmoi/readiness"
WIREGUARD_APP_PATH="/Applications/WireGuard.app"
WIREGUARD_BUNDLE_ID="com.wireguard.macos"
WIREGUARD_MARKER_FILE="${HOME}/.local/state/chezmoi/wireguard-configured"
WIREGUARD_SCUTIL_SENTINEL="scutil-detected"
DEFENDER_BUNDLE_ID="com.microsoft.wdav"
DEFENDER_ACK_FILE="${READINESS_STATE_DIR}/defender-approvals-reboot.done"
ISTAT_ACK_FILE="${READINESS_STATE_DIR}/istat-profile-import.done"

PASS_COUNT=0
TODO_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

section() {
  echo
  echo "== $1 =="
}

pass() {
  echo "PASS: $1"
  ((PASS_COUNT += 1))
}

todo() {
  echo "TODO: $1"
  ((TODO_COUNT += 1))
}

warn() {
  echo "WARN: $1"
  ((WARN_COUNT += 1))
}

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

check_app_store_auth() {
  section "App Store auth"

  if ! command -v mas >/dev/null 2>&1; then
    warn "mas command not found; App Store auth readiness cannot be checked."
    return
  fi

  local mas_output=""
  local mas_status=0
  mas_output="$(run_with_timeout 20 env MAS_NO_AUTO_INDEX=1 mas list)" || mas_status=$?

  if [[ "${mas_status}" -eq 0 ]]; then
    pass "App Store authentication appears available for mas operations."
  elif [[ "${mas_status}" -eq 124 ]]; then
    todo "App Store authentication/session likely unavailable (mas list timed out). Sign in to App Store and rerun apply."
  elif grep -Eqi 'sign in|not signed|no account|account.*required' <<<"${mas_output}"; then
    todo "App Store authentication required. Sign in to App Store and rerun apply."
  else
    warn "Could not confirm App Store auth via mas: ${mas_output}"
  fi
}

check_wireguard() {
  section "WireGuard readiness"

  if ! is_wireguard_installed; then
    todo "WireGuard is not installed yet. Complete MAS install and rerun apply."
    return
  fi

  local tunnel_count=0
  tunnel_count="$(wireguard_tunnel_count_from_scutil)"
  if [[ "${tunnel_count}" -gt 0 ]]; then
    pass "WireGuard is installed and has ${tunnel_count} configured tunnel service(s)."
    return
  fi

  if is_wireguard_marker_valid; then
    pass "WireGuard is installed and has a valid local configuration marker."
  else
    todo "WireGuard is installed but not configured. Import/confirm tunnel setup and rerun apply."
  fi
}

check_synology_screenshot() {
  section "Synology screenshot target"

  local synology_roots=()
  shopt -s nullglob
  synology_roots=( "${HOME}"/Library/CloudStorage/SynologyDrive-* )
  shopt -u nullglob

  if [[ "${#synology_roots[@]}" -eq 0 ]]; then
    todo "SynologyDrive-* root not found under ~/Library/CloudStorage."
    return
  fi

  if [[ "${#synology_roots[@]}" -gt 1 ]]; then
    todo "Multiple SynologyDrive-* roots found under ~/Library/CloudStorage; cleanup/choose one."
    return
  fi

  local desired_path="${synology_roots[0]}/Screenshots"
  local desired_tilde_path="~${desired_path#"${HOME}"}"
  if [[ ! -d "${desired_path}" ]]; then
    todo "Synology screenshot folder missing: ${desired_path}"
    return
  fi

  local current_path=""
  current_path="$(defaults read com.apple.screencapture location 2>/dev/null || true)"
  if [[ "${current_path}" == "${desired_path}" || "${current_path}" == "${desired_tilde_path}" ]]; then
    pass "Screenshot location matches Synology target (${desired_path})."
  else
    todo "Screenshot location drift detected (current=${current_path:-<unset>}, expected=${desired_path})."
  fi
}

check_defender() {
  section "Microsoft Defender readiness"

  if ! is_defender_installed; then
    todo "Microsoft Defender for Consumers is not installed."
    return
  fi

  pass "Microsoft Defender for Consumers app is installed."

  if [[ -f "${DEFENDER_ACK_FILE}" ]]; then
    pass "Defender manual approval/reboot acknowledgement is present."
  else
    todo "Approve Defender system/network extensions, reboot, then mark done: readiness-ack.sh mark defender-approvals-reboot"
  fi
}

check_istat() {
  section "iStat Menus readiness"

  local istat_app_path="/Applications/iStat Menus.app"
  if [[ ! -d "${istat_app_path}" ]]; then
    warn "iStat Menus app not found; skipping profile import acknowledgement check."
    return
  fi

  if [[ -f "${ISTAT_ACK_FILE}" ]]; then
    pass "iStat Menus profile import acknowledgement is present."
  else
    todo "Import iStat Menus profile manually, then mark done: readiness-ack.sh mark istat-profile-import"
  fi
}

check_system_updates_security() {
  section "System updates + FileVault readiness"

  filevault_status="$(fdesetup status 2>/dev/null || true)"
  if grep -Eq '^FileVault is On\.' <<< "${filevault_status}"; then
    pass "FileVault is enabled."
  else
    todo "FileVault is off. Enable in System Settings with Apple Account escrow, then rerun apply."
  fi

  softwareupdate_schedule_output="$(softwareupdate --schedule 2>/dev/null || true)"
  if grep -Eqi 'turned on' <<< "${softwareupdate_schedule_output}"; then
    pass "Software Update schedule is enabled."
  else
    todo "Software Update schedule is off. Rerun apply (or enable automatic checking) to align."
  fi

  check_update_key() {
    local domain="$1"
    local key="$2"
    local label="$3"
    local current=""
    current="$(defaults read "${domain}" "${key}" 2>/dev/null || echo "<unset>")"

    if [[ "${current}" == "1" ]]; then
      pass "${label} is enabled."
    else
      todo "${label} is not enabled (current=${current}). Rerun apply to enforce."
    fi
  }

  check_update_key "/Library/Preferences/com.apple.SoftwareUpdate" "AutomaticDownload" "SoftwareUpdate AutomaticDownload"
  check_update_key "/Library/Preferences/com.apple.SoftwareUpdate" "ConfigDataInstall" "SoftwareUpdate ConfigDataInstall"
  check_update_key "/Library/Preferences/com.apple.SoftwareUpdate" "CriticalUpdateInstall" "SoftwareUpdate CriticalUpdateInstall"
  check_update_key "/Library/Preferences/com.apple.SoftwareUpdate" "AutomaticallyInstallMacOSUpdates" "SoftwareUpdate AutomaticallyInstallMacOSUpdates"
  check_update_key "/Library/Preferences/com.apple.commerce" "AutoUpdate" "Commerce AutoUpdate"
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  warn "Readiness checks are macOS-specific; skipping on non-macOS host."
  echo
  echo "SUMMARY: PASS=${PASS_COUNT} TODO=${TODO_COUNT} WARN=${WARN_COUNT} FAIL=${FAIL_COUNT}"
  exit 0
fi

check_app_store_auth
check_wireguard
check_synology_screenshot
check_defender
check_istat
check_system_updates_security

echo
echo "SUMMARY: PASS=${PASS_COUNT} TODO=${TODO_COUNT} WARN=${WARN_COUNT} FAIL=${FAIL_COUNT}"

if [[ "${CHEZMOI_READINESS_STRICT:-0}" == "1" && ( "${TODO_COUNT}" -gt 0 || "${FAIL_COUNT}" -gt 0 ) ]]; then
  echo "Readiness strict mode enabled; failing due to pending TODO/FAIL items." >&2
  exit 1
fi

exit 0
