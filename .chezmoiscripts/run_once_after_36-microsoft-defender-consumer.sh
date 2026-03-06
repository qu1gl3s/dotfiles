#!/bin/bash
set -euo pipefail
#
# Script: run_once_after_36-microsoft-defender-consumer.sh
# Purpose: Install Microsoft Defender for Consumers from Microsoft's fwlink.
# Prerequisites: macOS, internet access, admin privileges.
# Env flags: CHEZMOI_SKIP_BREW=1 skips this script.
# Failure behavior: exits non-zero on download/mount/install failures.

if [[ "${CHEZMOI_SKIP_BREW:-0}" == "1" ]]; then
  echo "Skipping Microsoft Defender install because CHEZMOI_SKIP_BREW=1"
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  exit 0
fi

DEFENDER_BUNDLE_ID="com.microsoft.wdav"
DEFENDER_URL="https://go.microsoft.com/fwlink/?linkid=2247001"

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

if is_defender_installed; then
  echo "Microsoft Defender already installed; skipping installer."
  exit 0
fi

tmp_dir="$(mktemp -d)"
download_path="${tmp_dir}/defender-installer.dmg"
mount_point=""

cleanup() {
  if [[ -n "${mount_point}" && -d "${mount_point}" ]]; then
    hdiutil detach "${mount_point}" >/dev/null 2>&1 || true
  fi
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

echo "Downloading Microsoft Defender installer..."
curl -fL --retry 3 --retry-delay 2 -o "${download_path}" "${DEFENDER_URL}"

if [[ ! -s "${download_path}" ]]; then
  echo "Downloaded installer is empty: ${download_path}" >&2
  exit 1
fi

attach_output="$(hdiutil attach -nobrowse "${download_path}")"
mount_point="$(awk '/\/Volumes\// {for(i=1;i<=NF;i++) if ($i ~ /^\/Volumes\//) {print $i; exit}}' <<< "${attach_output}")"

if [[ -z "${mount_point}" || ! -d "${mount_point}" ]]; then
  echo "Unable to resolve mounted installer volume." >&2
  exit 1
fi

pkg_path="$(find "${mount_point}" -maxdepth 3 -type f -name '*.pkg' | head -n1 || true)"
app_path="$(find "${mount_point}" -maxdepth 3 -type d -name '*.app' | head -n1 || true)"

if [[ -n "${pkg_path}" ]]; then
  echo "Installing package: ${pkg_path}"
  sudo /usr/sbin/installer -pkg "${pkg_path}" -target /
elif [[ -n "${app_path}" ]]; then
  echo "Installing app bundle: ${app_path}"
  sudo /usr/bin/ditto "${app_path}" "/Applications/$(basename "${app_path}")"
else
  echo "No installable pkg/app found in mounted installer volume: ${mount_point}" >&2
  exit 1
fi

if ! is_defender_installed; then
  echo "Microsoft Defender app was not detected after installer run." >&2
  exit 1
fi

cat <<'EOF'
Microsoft Defender app installation completed.

Manual post-install steps required by macOS:
1) Approve Microsoft system extensions and network extensions in System Settings.
2) Reboot after approvals.
EOF
