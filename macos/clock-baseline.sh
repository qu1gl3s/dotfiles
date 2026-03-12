#!/bin/bash
# Source of truth for menu bar clock settings.

macos_clock_settings_entries() {
  cat <<'SETTINGS'
NSGlobalDomain|AppleICUForce24HourTime|bool|1
com.apple.menuextra.clock|IsAnalog|bool|0
com.apple.menuextra.clock|ShowDayOfWeek|bool|1
com.apple.menuextra.clock|ShowDate|int|1
com.apple.menuextra.clock|ShowSeconds|bool|1
com.apple.menuextra.clock|ShowAMPM|bool|0
com.apple.ControlCenter|NSStatusItem VisibleCC Clock|int|1
SETTINGS
}
