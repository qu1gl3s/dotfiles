#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_SOURCE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_DIR="${CHEZMOI_SOURCE_DIR:-${REPO_SOURCE_DIR}}"
# shellcheck source=scripts/lib.sh
source "${SOURCE_DIR}/scripts/lib.sh"

BREWFILE="${SOURCE_DIR}/Brewfile"
MAS_REQUIRED_FILE="${SOURCE_DIR}/mas/apps.txt"
MAS_OPTIONAL_FILE="${SOURCE_DIR}/mas/optional-apps.txt"
DOCK_ORDER_FILE="${SOURCE_DIR}/macos/dock-app-order.txt"

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

check_currenthost_default_equals() {
  local domain="$1"
  local key="$2"
  local expected="$3"
  local current=""

  if ! current="$(defaults -currentHost read "${domain}" "${key}" 2>/dev/null)"; then
    fail "defaults -currentHost ${domain} ${key} missing (expected ${expected})"
    return
  fi

  if [[ "${current}" == "${expected}" ]]; then
    pass "defaults -currentHost ${domain} ${key}=${expected}"
  else
    fail "defaults -currentHost ${domain} ${key} expected ${expected}, found ${current}"
  fi
}

check_default_equals_if_present() {
  local domain="$1"
  local key="$2"
  local expected="$3"
  local current=""

  if ! current="$(defaults read "${domain}" "${key}" 2>/dev/null)"; then
    info "defaults ${domain} ${key} missing; skipping assertion"
    return
  fi

  if [[ "${current}" == "${expected}" ]]; then
    pass "defaults ${domain} ${key}=${expected}"
  else
    fail "defaults ${domain} ${key} expected ${expected}, found ${current}"
  fi
}

touchid_available() {
  ioreg -rd1 -c AppleBiometricServices >/dev/null 2>&1
}

sudo_local_contains_pam_tid() {
  grep -Eq '^[[:space:]]*auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so' /etc/pam.d/sudo_local 2>/dev/null
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
for cmd in brew chezmoi dockutil mas desktoppr displayplacer wg; do
  if command -v "${cmd}" >/dev/null 2>&1; then
    pass "command available: ${cmd}"
  else
    fail "command missing: ${cmd}"
  fi
done

section "1Password SSH agent"
if [[ "$(uname -s)" != "Darwin" ]]; then
  warn "Skipping 1Password SSH agent checks on non-macOS host"
else
  ssh_config_path="${HOME}/.ssh/config"
  modern_agent_sock="${HOME}/.1password/agent.sock"
  legacy_agent_sock="${HOME}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"

  if [[ -f "${ssh_config_path}" ]]; then
    if grep -Eq '^[[:space:]]*IdentityAgent[[:space:]]+~/.1password/agent\.sock([[:space:]]|$)' "${ssh_config_path}"; then
      pass "SSH config uses IdentityAgent ~/.1password/agent.sock"
    else
      fail "SSH config missing IdentityAgent ~/.1password/agent.sock in ${ssh_config_path}"
    fi
  else
    fail "SSH config not found: ${ssh_config_path}"
  fi

  if [[ -S "${modern_agent_sock}" ]]; then
    pass "1Password SSH agent socket present at ${modern_agent_sock}"
  elif [[ -S "${legacy_agent_sock}" ]]; then
    warn "Legacy 1Password socket exists but modern socket is missing; rerun chezmoi apply to link compatibility path."
  else
    warn "1Password SSH agent socket not detected; open 1Password, enable SSH agent, and rerun chezmoi apply."
  fi
fi

section "Homebrew convergence"
if [[ ! -f "${BREWFILE}" ]]; then
  fail "Brewfile not found: ${BREWFILE}"
elif ! command -v brew >/dev/null 2>&1; then
  warn "Skipping Brewfile install checks because brew is missing"
else
  echo "Checking installed formulas..."
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

  echo "Checking installed casks..."
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
  echo "Querying Mac App Store..."
  mas_list_output=""
  mas_list_ok=0
  mas_list_status=0
  if mas_list_output="$(run_with_timeout 20 env MAS_NO_AUTO_INDEX=1 mas list)"; then
    mas_list_ok=1
    pass "mas list query succeeded"
  else
    mas_list_status=$?
  fi

  mas_list_state="$(classify_mas_list_state "${mas_list_status}" "${mas_list_output}")"
  if [[ "${mas_list_state}" == "session-unavailable" ]]; then
    warn "mas list unavailable due to App Store auth/session issues; falling back to local app bundle checks"
    if [[ -n "${mas_list_output}" && "${mas_list_status}" -ne 124 ]]; then
      info "${mas_list_output}"
    fi
  elif [[ "${mas_list_state}" == "metadata-unavailable" ]]; then
    warn "mas list unavailable for a non-auth reason; Spotlight/App Store metadata may still be indexing"
    if [[ -n "${mas_list_output}" ]]; then
      info "${mas_list_output}"
    fi
  fi

  installed_mas_ids=""
  if [[ "${mas_list_ok}" -eq 1 ]]; then
    installed_mas_ids="$(awk '{print $1}' <<<"${mas_list_output}")"
  fi

  while IFS='|' read -r app_id app_name; do
    [[ -z "${app_id}" || "${app_id:0:1}" == "#" ]] && continue
    local_app_path=""
    local_app_found=0
    if local_app_path="$(guess_mas_app_path "${app_name}")"; then
      local_app_found=1
    fi

    if [[ "${mas_list_ok}" -eq 1 ]]; then
      if contains_line "${app_id}" "${installed_mas_ids}"; then
        pass "required MAS app installed: ${app_name} (${app_id})"
      elif [[ "${local_app_found}" -eq 1 ]]; then
        warn "required MAS app bundle present at ${local_app_path}, but mas did not report ${app_name} (${app_id}); Spotlight/App Store metadata may still be indexing"
      else
        fail "required MAS app missing: ${app_name} (${app_id})"
      fi
    elif [[ "${local_app_found}" -eq 1 ]]; then
      warn "required MAS app bundle present at ${local_app_path}, but App Store session/metadata is unavailable; could not verify ${app_name} (${app_id}) with mas"
    else
      warn "required MAS app not verified and bundle not found locally: ${app_name} (${app_id})"
    fi
  done < "${MAS_REQUIRED_FILE}"

  while IFS='|' read -r app_id app_name; do
    [[ -z "${app_id}" || "${app_id:0:1}" == "#" ]] && continue
    local_app_path=""
    local_app_found=0
    if local_app_path="$(guess_mas_app_path "${app_name}")"; then
      local_app_found=1
    fi

    if [[ "${mas_list_ok}" -eq 1 ]]; then
      if contains_line "${app_id}" "${installed_mas_ids}"; then
        info "optional MAS app installed: ${app_name} (${app_id})"
      elif [[ "${local_app_found}" -eq 1 ]]; then
        info "optional MAS app bundle present at ${local_app_path}, but mas did not report ${app_name} (${app_id})"
      else
        info "optional MAS app not installed: ${app_name} (${app_id})"
      fi
    elif [[ "${local_app_found}" -eq 1 ]]; then
      info "optional MAS app bundle present at ${local_app_path}, but App Store session/metadata is unavailable"
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
    if [[ "${DISPLAY_PARSE_ERROR}" == "built-in display not found" ]] && display_subsystem_reports_builtin_panel; then
      warn "display scaling check skipped: displayplacer did not enumerate the built-in panel, but lower-level display services did (likely MacBook Neo tooling gap)"
    else
      warn "display scaling check skipped: ${DISPLAY_PARSE_ERROR}"
    fi
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
  check_default_equals "com.apple.menuextra.clock" "ShowSeconds" "1"
  check_default_equals "com.apple.menuextra.clock" "ShowAMPM" "0"
  check_default_equals "com.apple.ControlCenter" "NSStatusItem VisibleCC Clock" "1"
  check_currenthost_default_equals "com.apple.controlcenter" "BatteryShowPercentage" "1"
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
  if is_macbook_neo; then
    pass "MacBook Neo preserves its model-matched accent color; skipping AppleAccentColor assertion"
    check_default_equals_if_present "NSGlobalDomain" "AppleHighlightColor" "0.752941 0.964706 0.678431 Green"
  else
    check_default_equals "NSGlobalDomain" "AppleAccentColor" "3"
    check_default_equals "NSGlobalDomain" "AppleHighlightColor" "0.752941 0.964706 0.678431 Green"
  fi
  check_default_equals "NSGlobalDomain" "com.apple.swipescrolldirection" "0"
  check_default_equals "NSGlobalDomain" "NavPanelFileListModeForOpenMode" "2"
  check_default_equals "NSGlobalDomain" "NSNavPanelFileListModeForOpenMode2" "2"
  check_default_equals "NSGlobalDomain" "NavPanelFileListModeForSaveMode" "2"
  check_default_equals "NSGlobalDomain" "NSNavPanelFileListModeForSaveMode2" "2"
  check_default_equals "com.apple.dock" "show-recents" "0"
  check_default_equals "com.apple.dock" "autohide" "0"
  check_default_equals "com.apple.dock" "magnification" "1"
  check_default_equals "com.apple.dock" "largesize" "93"
  check_default_equals "com.apple.dock" "minimize-to-application" "1"
  check_default_equals "com.apple.finder" "FXPreferredViewStyle" "Nlsv"
  check_default_equals "com.apple.finder" "FinderSpawnTab" "0"
  check_default_equals "com.apple.finder" "_FXSortFoldersFirst" "1"
  check_default_equals "com.apple.finder" "_FXSortFoldersFirstOnDesktop" "1"
  check_default_equals "com.apple.finder" "NewWindowTarget" "PfHm"
  check_default_equals "com.apple.finder" "ShowExternalHardDrivesOnDesktop" "1"
  check_default_equals "com.apple.finder" "ShowHardDrivesOnDesktop" "1"
  check_default_equals "com.apple.finder" "ShowMountedServersOnDesktop" "1"
  check_default_equals "com.apple.finder" "ShowPathbar" "1"
  check_default_equals "com.apple.finder" "ShowRecentTags" "0"
  check_default_equals "com.apple.finder" "ShowRemovableMediaOnDesktop" "1"
  check_default_equals "com.apple.finder" "ShowStatusBar" "1"
  check_default_equals "com.apple.WindowManager" "EnableStandardClickToShowDesktop" "0"
  check_default_equals "com.apple.WindowManager" "HideDesktop" "1"
  check_default_equals "com.apple.WindowManager" "StageManagerHideWidgets" "1"
  check_default_equals "com.apple.WindowManager" "StandardHideWidgets" "1"

  expected_home_uri="file://${HOME}/"
  current_new_window_target_path="$(defaults read com.apple.finder NewWindowTargetPath 2>/dev/null || true)"
  if [[ "${current_new_window_target_path}" == "${expected_home_uri}" ]]; then
    pass "defaults com.apple.finder NewWindowTargetPath=${expected_home_uri}"
  else
    fail "defaults com.apple.finder NewWindowTargetPath expected ${expected_home_uri}, found ${current_new_window_target_path:-<unset>}"
  fi
fi

section "Tips suppression"
if [[ "$(uname -s)" != "Darwin" ]]; then
  warn "Skipping Tips suppression checks on non-macOS host"
else
  check_default_equals "com.apple.tipsd" "TPSWaitingToShowWelcomeNotification" "0"
  check_default_equals "com.apple.tipsd" "TPSWelcomeNotificationReminderState" "1"

  ncprefs_path="${HOME}/Library/Preferences/com.apple.ncprefs.plist"
  if [[ ! -f "${ncprefs_path}" ]]; then
    info "com.apple.ncprefs not present; skipping optional Tips auth probe."
  else
    ncprefs_check_output=""
    ncprefs_check_status=0
    ncprefs_check_output="$(
      python3 - "${ncprefs_path}" <<'PY'
import plistlib
import sys
from pathlib import Path

ncprefs_path = Path(sys.argv[1])
if not ncprefs_path.exists():
    print("MISSING_FILE")
    sys.exit(20)

with ncprefs_path.open("rb") as fh:
    data = plistlib.load(fh)

apps = data.get("apps")
if not isinstance(apps, list):
    print("MISSING_ENTRY")
    sys.exit(21)

for entry in apps:
    if not isinstance(entry, dict):
        continue
    if entry.get("bundle-id") == "com.apple.tips":
        auth_value = entry.get("auth", "<unset>")
        print(f"FOUND_AUTH={auth_value}")
        sys.exit(0)

print("MISSING_ENTRY")
sys.exit(21)
PY
    )" || ncprefs_check_status=$?

    case "${ncprefs_check_status}" in
      0)
        tips_auth="${ncprefs_check_output#FOUND_AUTH=}"
        info "com.apple.ncprefs com.apple.tips auth=${tips_auth} (informational only)"
        ;;
      20)
        info "com.apple.ncprefs not found; skipping optional Tips auth probe."
        ;;
      21)
        info "com.apple.tips entry not present in com.apple.ncprefs (informational only)."
        ;;
      *)
        info "Unable to parse com.apple.ncprefs for Tips auth (informational only): ${ncprefs_check_output}"
        ;;
    esac
  fi
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

section "System updates + FileVault"
if [[ "$(uname -s)" != "Darwin" ]]; then
  warn "Skipping FileVault/software update checks on non-macOS host"
else
  echo "Checking FileVault status..."
  filevault_status="$(fdesetup status 2>/dev/null || true)"
  if grep -Eq '^FileVault is On\.' <<< "${filevault_status}"; then
    pass "FileVault is enabled"
  else
    fail "FileVault is not enabled"
  fi

  echo "Checking Software Update schedule..."
  softwareupdate_schedule_output="$(softwareupdate --schedule 2>/dev/null || true)"
  if grep -Eqi 'turned on' <<< "${softwareupdate_schedule_output}"; then
    pass "softwareupdate automatic schedule is on"
  else
    fail "softwareupdate automatic schedule is not on"
  fi

  check_default_equals "/Library/Preferences/com.apple.SoftwareUpdate" "AutomaticDownload" "1"
  check_default_equals "/Library/Preferences/com.apple.SoftwareUpdate" "ConfigDataInstall" "1"
  check_default_equals "/Library/Preferences/com.apple.SoftwareUpdate" "CriticalUpdateInstall" "1"
  check_default_equals "/Library/Preferences/com.apple.SoftwareUpdate" "AutomaticallyInstallMacOSUpdates" "1"
  check_default_equals "/Library/Preferences/com.apple.commerce" "AutoUpdate" "1"
fi

section "Privacy minimization"
if [[ "$(uname -s)" != "Darwin" ]]; then
  warn "Skipping privacy-minimization checks on non-macOS host"
else
  check_default_equals "com.apple.AdLib" "allowApplePersonalizedAdvertising" "0"
  check_default_equals "com.apple.assistant.support" "Assistant Enabled" "0"
  check_default_equals "com.apple.assistant.support" "Dictation Enabled" "0"
  check_default_equals "com.apple.Siri" "VoiceTriggerUserEnabled" "0"

  analytics_plist="/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist"
  if [[ ! -f "${analytics_plist}" ]]; then
    fail "CrashReporter analytics plist not found: ${analytics_plist}"
  else
    auto_submit_value="$(plutil -extract AutoSubmit raw -o - "${analytics_plist}" 2>/dev/null || true)"
    if [[ "${auto_submit_value}" == "false" ]]; then
      pass "CrashReporter AutoSubmit=false"
    else
      fail "CrashReporter AutoSubmit expected false, found ${auto_submit_value:-<unset>}"
    fi

    third_party_submit_value="$(plutil -extract ThirdPartyDataSubmit raw -o - "${analytics_plist}" 2>/dev/null || true)"
    if [[ "${third_party_submit_value}" == "false" ]]; then
      pass "CrashReporter ThirdPartyDataSubmit=false"
    else
      fail "CrashReporter ThirdPartyDataSubmit expected false, found ${third_party_submit_value:-<unset>}"
    fi
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
