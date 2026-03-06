#!/bin/bash
# Source of truth for allowlisted macOS settings.

macos_settings_entries() {
  cat <<'SETTINGS'
NSGlobalDomain AppleAccentColor int 3
NSGlobalDomain AppleHighlightColor string 0.752941 0.964706 0.678431 Green
SETTINGS
}
