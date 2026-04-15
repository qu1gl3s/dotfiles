#!/bin/bash
# Source of truth for allowlisted macOS settings.

macos_settings_entries() {
  cat <<'SETTINGS'
NSGlobalDomain AppleAccentColor int 3
NSGlobalDomain AppleHighlightColor string 0.752941 0.964706 0.678431 Green
NSGlobalDomain com.apple.swipescrolldirection bool 0
NSGlobalDomain NavPanelFileListModeForOpenMode int 2
NSGlobalDomain NSNavPanelFileListModeForOpenMode2 int 2
NSGlobalDomain NavPanelFileListModeForSaveMode int 2
NSGlobalDomain NSNavPanelFileListModeForSaveMode2 int 2
com.apple.dock show-recents bool 0
com.apple.dock autohide bool 0
com.apple.dock magnification bool 1
com.apple.dock largesize int 93
com.apple.dock minimize-to-application bool 1
com.apple.finder FXPreferredViewStyle string Nlsv
com.apple.finder FinderSpawnTab bool 0
com.apple.finder _FXSortFoldersFirst bool 1
com.apple.finder _FXSortFoldersFirstOnDesktop bool 1
com.apple.finder NewWindowTarget string PfHm
com.apple.finder NewWindowTargetPath string __HOME_URI__
com.apple.finder ShowExternalHardDrivesOnDesktop bool 1
com.apple.finder ShowHardDrivesOnDesktop bool 1
com.apple.finder ShowMountedServersOnDesktop bool 1
com.apple.finder ShowPathbar bool 1
com.apple.finder ShowRecentTags bool 0
com.apple.finder ShowRemovableMediaOnDesktop bool 1
com.apple.finder ShowStatusBar bool 1
com.apple.WindowManager EnableStandardClickToShowDesktop bool 0
com.apple.WindowManager HideDesktop bool 1
com.apple.WindowManager StageManagerHideWidgets bool 1
com.apple.WindowManager StandardHideWidgets bool 1
SETTINGS
}

finder_toolbar_item_identifiers() {
  cat <<'ITEMS'
com.apple.finder.BACK
com.apple.finder.SWCH
NSToolbarSpaceItem
com.apple.finder.ARNG
NSToolbarSpaceItem
com.apple.finder.SHAR
com.apple.finder.LABL
com.apple.finder.ACTN
NSToolbarSpaceItem
com.apple.finder.TRSH
com.apple.finder.SRCH
ITEMS
}

finder_toolbar_default_item_identifiers() {
  cat <<'ITEMS'
com.apple.finder.BACK
com.apple.finder.SWCH
NSToolbarSpaceItem
com.apple.finder.ARNG
NSToolbarSpaceItem
com.apple.finder.SHAR
com.apple.finder.LABL
com.apple.finder.ACTN
NSToolbarSpaceItem
com.apple.finder.SRCH
ITEMS
}
