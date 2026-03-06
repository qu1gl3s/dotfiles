#!/bin/bash
set -euo pipefail

SOURCE_DIR="${CHEZMOI_SOURCE_DIR:-$HOME/.local/share/chezmoi}"
BREWFILE="${SOURCE_DIR}/Brewfile"
MAS_REQUIRED_FILE="${SOURCE_DIR}/mas/apps.txt"
MAS_OPTIONAL_FILE="${SOURCE_DIR}/mas/optional-apps.txt"
DOCK_ORDER_FILE="${SOURCE_DIR}/macos/dock-app-order.txt"
DEFENDER_BUNDLE_ID="com.microsoft.wdav"
WIREGUARD_APP_PATH="/Applications/WireGuard.app"
WIREGUARD_BUNDLE_ID="com.wireguard.macos"
WIREGUARD_MARKER_FILE="${HOME}/.local/state/chezmoi/wireguard-configured"
WIREGUARD_SCUTIL_SENTINEL="scutil-detected"

PASS_COUNT=0
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

warn() {
  echo "WARN: $1"
  ((WARN_COUNT += 1))
}

fail() {
  echo "FAIL: $1"
  ((FAIL_COUNT += 1))
}

info() {
  echo "INFO: $1"
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

contains_line() {
  local needle="$1"
  local haystack="$2"
  grep -Fxq "${needle}" <<<"${haystack}"
}

check_default_equals() {
  local domain="$1"
  local key="$2"
  local expected="$3"
  local current=""

  if ! current="$(defaults read "${domain}" "${key}" 2>/dev/null)"; then
    fail "defaults ${domain} ${key} missing (expected ${expected})"
    return
  fi

  if [[ "${current}" == "${expected}" ]]; then
    pass "defaults ${domain} ${key}=${expected}"
  else
    fail "defaults ${domain} ${key} expected ${expected}, found ${current}"
  fi
}

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

touchid_available() {
  ioreg -rd1 -c AppleBiometricServices >/dev/null 2>&1
}

sudo_local_contains_pam_tid() {
  grep -Eq '^[[:space:]]*auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so' /etc/pam.d/sudo_local 2>/dev/null
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
  if [[ -z "${marker_path}" ]]; then
    return 0
  fi

  if [[ "${marker_path}" == "${WIREGUARD_SCUTIL_SENTINEL}" ]]; then
    return 0
  fi

  [[ -f "${marker_path}" ]]
}

parse_displayplacer_builtin() {
  local display_output="$1"

  DISPLAY_PARSE_ERROR=""
  DISPLAY_BUILTIN_COUNT=0
  DISPLAY_BUILTIN_ID=""
  DISPLAY_TARGET_RES=""
  DISPLAY_CURRENT_RES=""
  DISPLAY_CURRENT_SCALING=""

  local current_id=""
  local current_builtin=0
  local current_best_area=-1
  local current_best_res=""
  local current_resolution=""
  local current_scaling=""
  local line=""
  local display_type=""
  local mode_w=""
  local mode_h=""
  local mode_area=0

  finalize_verify_display() {
    if [[ "${current_builtin}" -eq 1 ]]; then
      ((DISPLAY_BUILTIN_COUNT += 1))
      DISPLAY_BUILTIN_ID="${current_id}"
      DISPLAY_TARGET_RES="${current_best_res}"
      DISPLAY_CURRENT_RES="${current_resolution}"
      DISPLAY_CURRENT_SCALING="${current_scaling}"
    fi
  }

  while IFS= read -r line; do
    if [[ "${line}" =~ ^[[:space:]]*Persistent[[:space:]]screen[[:space:]]id:[[:space:]]*(.+)$ ]]; then
      if [[ -n "${current_id}" ]]; then
        finalize_verify_display
      fi
      current_id="${BASH_REMATCH[1]}"
      current_builtin=0
      current_best_area=-1
      current_best_res=""
      current_resolution=""
      current_scaling=""
      continue
    fi

    [[ -z "${current_id}" ]] && continue

    if [[ "${line}" =~ ^[[:space:]]*Type:[[:space:]]*(.+)$ ]]; then
      display_type="${BASH_REMATCH[1]}"
      if [[ "${display_type}" =~ [Bb]uilt-?[Ii]n|[Ii]nternal|[Mm]ac[Bb]ook ]]; then
        current_builtin=1
      fi
      continue
    fi

    if [[ "${line}" =~ ^[[:space:]]*Resolution:[[:space:]]*([0-9]+x[0-9]+) ]]; then
      current_resolution="${BASH_REMATCH[1]}"
      continue
    fi

    if [[ "${line}" =~ ^[[:space:]]*Scaling:[[:space:]]*(on|off) ]]; then
      current_scaling="${BASH_REMATCH[1]}"
      continue
    fi

    if [[ "${current_builtin}" -eq 1 && "${line}" =~ res:([0-9]+)x([0-9]+).*scaling:on ]]; then
      mode_w="${BASH_REMATCH[1]}"
      mode_h="${BASH_REMATCH[2]}"
      mode_area=$((mode_w * mode_h))
      if [[ "${mode_area}" -gt "${current_best_area}" ]]; then
        current_best_area="${mode_area}"
        current_best_res="${mode_w}x${mode_h}"
      fi
    fi
  done <<< "${display_output}"

  if [[ -n "${current_id}" ]]; then
    finalize_verify_display
  fi

  if [[ "${DISPLAY_BUILTIN_COUNT}" -eq 0 ]]; then
    DISPLAY_PARSE_ERROR="built-in display not found"
    return 1
  fi

  if [[ "${DISPLAY_BUILTIN_COUNT}" -gt 1 ]]; then
    DISPLAY_PARSE_ERROR="multiple built-in displays found"
    return 1
  fi

  if [[ -z "${DISPLAY_TARGET_RES}" ]]; then
    DISPLAY_PARSE_ERROR="no scaling:on modes found for built-in display"
    return 1
  fi

  return 0
}

section "Core toolchain"
for cmd in brew chezmoi dockutil mas desktoppr displayplacer; do
  if command -v "${cmd}" >/dev/null 2>&1; then
    pass "command available: ${cmd}"
  else
    fail "command missing: ${cmd}"
  fi
done

section "Homebrew convergence"
if [[ ! -f "${BREWFILE}" ]]; then
  fail "Brewfile not found: ${BREWFILE}"
elif ! command -v brew >/dev/null 2>&1; then
  warn "Skipping Brewfile install checks because brew is missing"
else
  installed_formulas="$(brew list --formula 2>/dev/null || true)"
  while read -r formula; do
    [[ -z "${formula}" ]] && continue
    formula_short="${formula##*/}"
    if contains_line "${formula}" "${installed_formulas}" || contains_line "${formula_short}" "${installed_formulas}"; then
      pass "formula installed: ${formula}"
    else
      fail "formula missing: ${formula}"
    fi
  done < <(awk -F'"' '/^brew / { print $2 }' "${BREWFILE}")

  installed_casks="$(brew list --cask 2>/dev/null || true)"
  while read -r cask; do
    [[ -z "${cask}" ]] && continue
    if contains_line "${cask}" "${installed_casks}"; then
      pass "cask installed: ${cask}"
    else
      fail "cask missing: ${cask}"
    fi
  done < <(awk -F'"' '/^cask / { print $2 }' "${BREWFILE}")
fi

section "MAS apps"
if [[ ! -f "${MAS_REQUIRED_FILE}" ]]; then
  fail "MAS required list not found: ${MAS_REQUIRED_FILE}"
elif [[ ! -f "${MAS_OPTIONAL_FILE}" ]]; then
  fail "MAS optional list not found: ${MAS_OPTIONAL_FILE}"
elif ! command -v mas >/dev/null 2>&1; then
  warn "Skipping MAS app checks because mas is missing"
else
  mas_list_output=""
  mas_list_ok=0
  if mas_list_output="$(run_with_timeout 20 env MAS_NO_AUTO_INDEX=1 mas list)"; then
    mas_list_ok=1
    pass "mas list query succeeded"
  elif [[ "$?" -eq 124 ]]; then
    warn "mas list timed out after 20s (likely App Store auth/session issue)"
  else
    warn "mas list unavailable (likely App Store auth/session issue): ${mas_list_output}"
  fi

  installed_mas_ids=""
  if [[ "${mas_list_ok}" -eq 1 ]]; then
    installed_mas_ids="$(awk '{print $1}' <<<"${mas_list_output}")"
  fi

  while IFS='|' read -r app_id app_name; do
    [[ -z "${app_id}" || "${app_id:0:1}" == "#" ]] && continue
    if [[ "${mas_list_ok}" -eq 1 ]]; then
      if contains_line "${app_id}" "${installed_mas_ids}"; then
        pass "required MAS app installed: ${app_name} (${app_id})"
      else
        fail "required MAS app missing: ${app_name} (${app_id})"
      fi
    else
      warn "required MAS app not verified: ${app_name} (${app_id})"
    fi
  done < "${MAS_REQUIRED_FILE}"

  while IFS='|' read -r app_id app_name; do
    [[ -z "${app_id}" || "${app_id:0:1}" == "#" ]] && continue
    if [[ "${mas_list_ok}" -eq 1 ]]; then
      if contains_line "${app_id}" "${installed_mas_ids}"; then
        info "optional MAS app installed: ${app_name} (${app_id})"
      else
        info "optional MAS app not installed: ${app_name} (${app_id})"
      fi
    else
      info "optional MAS app not verified: ${app_name} (${app_id})"
    fi
  done < "${MAS_OPTIONAL_FILE}"
fi

section "WireGuard setup"
if [[ "$(uname -s)" != "Darwin" ]]; then
  warn "Skipping WireGuard setup checks on non-macOS host"
elif is_wireguard_installed; then
  pass "WireGuard app detected"
  wireguard_tunnel_count="$(wireguard_tunnel_count_from_scutil)"
  if [[ "${wireguard_tunnel_count}" -gt 0 ]]; then
    pass "WireGuard tunnel services detected in macOS VPN services (${wireguard_tunnel_count})"
  elif is_wireguard_marker_valid; then
    marker_path="$(head -n 1 "${WIREGUARD_MARKER_FILE}" 2>/dev/null || true)"
    if [[ "${marker_path}" == "${WIREGUARD_SCUTIL_SENTINEL}" || -z "${marker_path}" ]]; then
      pass "WireGuard setup marker present"
    else
      pass "WireGuard configured marker points to ${marker_path}"
    fi
  else
    warn "WireGuard is installed but no tunnel configuration was detected yet."
  fi
else
  fail "WireGuard app not detected at ${WIREGUARD_APP_PATH}"
fi

section "Microsoft Defender"
if [[ "$(uname -s)" != "Darwin" ]]; then
  warn "Skipping Microsoft Defender checks on non-macOS host"
elif is_defender_installed; then
  pass "Microsoft Defender for Consumers app detected"
else
  fail "Microsoft Defender for Consumers app not detected (bundle id ${DEFENDER_BUNDLE_ID})"
fi

section "Screenshot guard"
if [[ "$(uname -s)" != "Darwin" ]]; then
  warn "Skipping screenshot checks on non-macOS host"
else
  shopt -s nullglob
  synology_roots=( "${HOME}"/Library/CloudStorage/SynologyDrive-* )
  shopt -u nullglob

  if [[ "${#synology_roots[@]}" -eq 0 ]]; then
    fail "No SynologyDrive-* root found under ~/Library/CloudStorage"
  elif [[ "${#synology_roots[@]}" -gt 1 ]]; then
    fail "Multiple SynologyDrive-* roots found under ~/Library/CloudStorage"
    for root in "${synology_roots[@]}"; do
      info "Synology root candidate: ${root}"
    done
  else
    desired_screenshot_path="${synology_roots[0]}/Screenshots"
    desired_screenshot_tilde="~${desired_screenshot_path#"${HOME}"}"

    if [[ -d "${desired_screenshot_path}" ]]; then
      pass "Screenshot folder exists: ${desired_screenshot_path}"
    else
      fail "Screenshot folder missing: ${desired_screenshot_path}"
    fi

    current_screenshot_path="$(defaults read com.apple.screencapture location 2>/dev/null || true)"
    if [[ "${current_screenshot_path}" == "${desired_screenshot_path}" || "${current_screenshot_path}" == "${desired_screenshot_tilde}" ]]; then
      pass "Screenshot location matches Synology target"
    else
      fail "Screenshot location mismatch (current=${current_screenshot_path:-<unset>}, expected=${desired_screenshot_path})"
    fi
  fi
fi

section "Display scaling"
if [[ "$(uname -s)" != "Darwin" ]]; then
  warn "Skipping display scaling checks on non-macOS host"
elif ! command -v displayplacer >/dev/null 2>&1; then
  fail "displayplacer is missing (required for built-in More Space automation)"
else
  display_list_output=""
  display_list_status=0
  display_list_output="$(run_with_timeout 20 displayplacer list)" || display_list_status=$?

  if [[ "${display_list_status}" -eq 124 ]]; then
    fail "displayplacer list timed out after 20s"
  elif [[ "${display_list_status}" -ne 0 ]]; then
    fail "displayplacer list failed: ${display_list_output}"
  elif ! parse_displayplacer_builtin "${display_list_output}"; then
    warn "display scaling check skipped: ${DISPLAY_PARSE_ERROR}"
  else
    pass "Built-in display target resolved: ${DISPLAY_TARGET_RES} (id ${DISPLAY_BUILTIN_ID})"

    if [[ "${DISPLAY_CURRENT_SCALING}" == "on" ]]; then
      pass "Built-in display scaling is on"
    else
      fail "Built-in display scaling is not on (current=${DISPLAY_CURRENT_SCALING:-<unset>})"
    fi

    if [[ "${DISPLAY_CURRENT_RES}" == "${DISPLAY_TARGET_RES}" && "${DISPLAY_CURRENT_SCALING}" == "on" ]]; then
      pass "Built-in display is set to More Space target (${DISPLAY_TARGET_RES})"
    else
      fail "Built-in display drift (current=${DISPLAY_CURRENT_RES:-<unset>} scaling=${DISPLAY_CURRENT_SCALING:-<unset>}, target=${DISPLAY_TARGET_RES} scaling=on)"
    fi
  fi
fi

section "Menu bar clock"
if [[ "$(uname -s)" != "Darwin" ]]; then
  warn "Skipping menu bar clock checks on non-macOS host"
else
  check_default_equals "NSGlobalDomain" "AppleICUForce24HourTime" "1"
  check_default_equals "com.apple.menuextra.clock" "IsAnalog" "0"
  check_default_equals "com.apple.menuextra.clock" "ShowDayOfWeek" "1"
  check_default_equals "com.apple.menuextra.clock" "ShowDate" "1"
  check_default_equals "com.apple.menuextra.clock" "ShowAMPM" "0"
  check_default_equals "com.apple.ControlCenter" "NSStatusItem VisibleCC Clock" "1"
fi

section "TextEdit preferences"
if [[ "$(uname -s)" != "Darwin" ]]; then
  warn "Skipping TextEdit preference checks on non-macOS host"
else
  check_default_equals "com.apple.TextEdit" "RichText" "0"
  check_default_equals "com.apple.TextEdit" "PlainTextEncoding" "4"
  check_default_equals "com.apple.TextEdit" "PlainTextEncodingForWrite" "4"
  check_default_equals "com.apple.TextEdit" "CheckSpellingWhileTyping" "0"
  check_default_equals "com.apple.TextEdit" "CheckGrammarWithSpelling" "0"
  check_default_equals "com.apple.TextEdit" "CorrectSpellingAutomatically" "0"
fi

section "Privacy audit"
PRIVACY_SCRIPT="${SOURCE_DIR}/scripts/verify-privacy.sh"
if [[ ! -f "${PRIVACY_SCRIPT}" ]]; then
  warn "Privacy audit script not found: ${PRIVACY_SCRIPT}"
else
  privacy_output=""
  if privacy_output="$(bash "${PRIVACY_SCRIPT}" --source-dir "${SOURCE_DIR}" 2>&1)"; then
    fail_count_from_summary="$(awk -F'FAIL=' '/^SUMMARY:/ {print $2}' <<<"${privacy_output}" | awk '{print $1}' | tail -n1)"
    if [[ "${fail_count_from_summary:-0}" =~ ^[0-9]+$ && "${fail_count_from_summary}" -gt 0 ]]; then
      warn "privacy audit reported ${fail_count_from_summary} fail findings; run scripts/verify-privacy.sh --strict"
    else
      pass "privacy audit completed with zero fail findings"
    fi
  else
    warn "privacy audit script execution failed; run manually: bash ${PRIVACY_SCRIPT} --strict"
    info "${privacy_output}"
  fi
fi

section "macOS settings spot-check"
if [[ "$(uname -s)" != "Darwin" ]]; then
  warn "Skipping macOS defaults checks on non-macOS host"
else
  check_default_equals "NSGlobalDomain" "AppleAccentColor" "3"
  check_default_equals "NSGlobalDomain" "AppleHighlightColor" "0.752941 0.964706 0.678431 Green"
fi

section "Privileged security/power"
if [[ "$(uname -s)" != "Darwin" ]]; then
  warn "Skipping privileged security/power checks on non-macOS host"
else
  firewall_state="$("/usr/libexec/ApplicationFirewall/socketfilterfw" --getglobalstate 2>/dev/null || true)"
  if grep -qi "enabled" <<< "${firewall_state}"; then
    pass "Firewall global state is enabled"
  else
    fail "Firewall global state is not enabled"
  fi

  stealth_state="$("/usr/libexec/ApplicationFirewall/socketfilterfw" --getstealthmode 2>/dev/null || true)"
  if grep -qi "on" <<< "${stealth_state}"; then
    pass "Firewall stealth mode is on"
  else
    fail "Firewall stealth mode is not on"
  fi

  check_default_equals "com.apple.screensaver" "askForPassword" "1"

  ask_for_password_delay="$(defaults read com.apple.screensaver askForPasswordDelay 2>/dev/null || true)"
  if [[ "${ask_for_password_delay}" == "0" || "${ask_for_password_delay}" == "0.0" ]]; then
    pass "defaults com.apple.screensaver askForPasswordDelay=0"
  else
    fail "defaults com.apple.screensaver askForPasswordDelay expected 0, found ${ask_for_password_delay:-<unset>}"
  fi

  pmset_output="$(pmset -g custom 2>/dev/null || true)"
  pmset_battery="$(pmset_displaysleep_value battery "${pmset_output}")"
  pmset_ac="$(pmset_displaysleep_value ac "${pmset_output}")"

  if [[ -z "${pmset_battery:-}" ]]; then
    warn "pmset battery displaysleep could not be read without sudo"
  elif [[ "${pmset_battery}" == "10" ]]; then
    pass "pmset battery displaysleep=10"
  else
    fail "pmset battery displaysleep expected 10, found ${pmset_battery}"
  fi

  if [[ -z "${pmset_ac:-}" ]]; then
    warn "pmset AC displaysleep could not be read without sudo"
  elif [[ "${pmset_ac}" == "60" ]]; then
    pass "pmset AC displaysleep=60"
  else
    fail "pmset AC displaysleep expected 60, found ${pmset_ac}"
  fi

  if touchid_available; then
    if sudo_local_contains_pam_tid; then
      pass "Touch ID sudo config present in /etc/pam.d/sudo_local"
    else
      fail "Touch ID hardware detected but pam_tid.so is missing in /etc/pam.d/sudo_local"
    fi
  else
    warn "Touch ID hardware not detected; skipping sudo Touch ID check"
  fi
fi

section "Dock baseline"
if [[ ! -f "${DOCK_ORDER_FILE}" ]]; then
  fail "Dock order file not found: ${DOCK_ORDER_FILE}"
elif ! command -v dockutil >/dev/null 2>&1; then
  warn "Skipping Dock baseline check because dockutil is missing"
elif [[ "$(uname -s)" != "Darwin" ]]; then
  warn "Skipping Dock baseline check on non-macOS host"
else
  dock_list_output="$(dockutil --list 2>/dev/null || true)"
  if [[ -z "${dock_list_output}" ]]; then
    fail "dockutil --list returned empty output"
  else
    while IFS= read -r app_path; do
      [[ -z "${app_path}" || "${app_path:0:1}" == "#" ]] && continue
      if [[ "${app_path}" == "/System/Library/CoreServices/Finder.app" ]]; then
        continue
      fi
      encoded_app_path="${app_path// /%20}"
      expected_uri="file://${encoded_app_path}/"
      if grep -Fq "${expected_uri}" <<<"${dock_list_output}"; then
        pass "Dock contains app: ${app_path}"
      else
        fail "Dock missing app: ${app_path}"
      fi
    done < "${DOCK_ORDER_FILE}"
  fi
fi

echo
echo "SUMMARY: PASS=${PASS_COUNT} WARN=${WARN_COUNT} FAIL=${FAIL_COUNT}"

if [[ "${CHEZMOI_VERIFY_STRICT:-0}" == "1" && "${FAIL_COUNT}" -gt 0 ]]; then
  echo "Strict verification mode enabled; failing due to verification errors." >&2
  exit 1
fi

exit 0
