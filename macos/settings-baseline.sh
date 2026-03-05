#!/bin/bash
# Source of truth for allowlisted macOS settings.

macos_settings_entries() {
  cat <<'SETTINGS'
NSGlobalDomain AppleShowAllExtensions bool 1
NSGlobalDomain ApplePressAndHoldEnabled bool 0
NSGlobalDomain com.apple.swipescrolldirection bool 0
NSGlobalDomain InitialKeyRepeat int 15
NSGlobalDomain KeyRepeat int 2
NSGlobalDomain NSAutomaticCapitalizationEnabled bool 0
NSGlobalDomain NSAutomaticDashSubstitutionEnabled bool 0
NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled bool 0
NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled bool 0
NSGlobalDomain NSAutomaticSpellingCorrectionEnabled bool 0
com.apple.AppleMultitouchTrackpad Clicking bool 1
com.apple.finder ShowPathbar bool 1
com.apple.finder ShowStatusBar bool 1
com.apple.finder FXPreferredViewStyle string Nlsv
com.apple.finder _FXSortFoldersFirst bool 1
com.apple.finder FXEnableExtensionChangeWarning bool 0
com.apple.finder NewWindowTarget string PfHm
com.apple.finder NewWindowTargetPath string __HOME_URI__
com.apple.finder ShowExternalHardDrivesOnDesktop bool 1
com.apple.finder ShowHardDrivesOnDesktop bool 1
com.apple.finder ShowMountedServersOnDesktop bool 1
com.apple.finder ShowRemovableMediaOnDesktop bool 1
com.apple.desktopservices DSDontWriteNetworkStores bool 1
com.apple.dock autohide bool 0
com.apple.dock autohide-delay float 0
com.apple.dock autohide-time-modifier float 0.4
com.apple.dock magnification bool 1
com.apple.dock largesize int 94
com.apple.dock mineffect string genie
com.apple.dock minimize-to-application bool 1
com.apple.dock orientation string bottom
com.apple.dock show-recents bool 0
com.apple.dock launchanim bool 1
com.apple.screencapture type string png
com.apple.screencapture disable-shadow bool 1
com.apple.screencapture show-thumbnail bool 1
com.apple.WindowManager EnableStandardClickToShowDesktop bool 0
SETTINGS
}
