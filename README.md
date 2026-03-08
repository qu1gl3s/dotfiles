# Dotfiles managed with chezmoi

This repo bootstraps a macOS Apple Silicon machine with shell/git/ssh config, package installs, selected macOS settings, and post-apply checks.

## Bootstrap

```sh
sh -c "$(curl -fsLS get.chezmoi.io/lb)" -- init --apply <github-user>
```

## Managed areas

- Shell: `~/.zshrc`, `~/.zprofile`, `~/.aliases`
- Git: `~/.gitconfig` (+ local identity in `~/.gitconfig.local`)
- SSH config: `~/.ssh/config` (no private keys)
- Homebrew formulas/casks
- Mac App Store apps via `mas`
- macOS settings/scripts (display, clock, TextEdit, appearance, screenshot path, Dock)
- Verification and readiness reporting

## Homebrew + MAS

Core automation:

- `.chezmoiscripts/run_onchange_after_30-brew-bundle.sh.tmpl`
- `.chezmoiscripts/run_onchange_after_31-hiddenbar-notch.sh.tmpl`
- `.chezmoiscripts/run_onchange_after_34-mas-apps.sh.tmpl`
- `.chezmoiscripts/run_once_after_35-optional-casks.sh`
- `.chezmoiscripts/run_once_after_36-microsoft-defender-consumer.sh`

Notes:

- HiddenBar is installed only on notch-capable MacBooks.
- Optional casks prompt once from `casks/optional-casks.txt`.
- `freac-continuous` installs from upstream DMG (not a Homebrew cask token).

## macOS automation

- `.chezmoiscripts/run_onchange_after_40-macos-defaults.sh`
- `.chezmoiscripts/run_onchange_after_41-screenshot-location.sh`
- `.chezmoiscripts/run_onchange_after_42-display-more-space.sh`
- `.chezmoiscripts/run_onchange_after_43-menu-bar-clock.sh`
- `.chezmoiscripts/run_onchange_after_44-textedit.sh`
- `.chezmoiscripts/run_onchange_after_45-appearance.sh`
- `.chezmoiscripts/run_onchange_after_47-privileged-system.sh.tmpl`
- `.chezmoiscripts/run_onchange_after_48-system-updates-security.sh.tmpl`
- `.chezmoiscripts/run_onchange_after_49-privacy-minimization.sh.tmpl`
- `.chezmoiscripts/run_onchange_after_50-dock-layout.sh.tmpl`

Current defaults baseline (`40`) is intentionally minimal:

- `NSGlobalDomain AppleAccentColor=3`
- `NSGlobalDomain AppleHighlightColor="0.752941 0.964706 0.678431 Green"`

System updates + FileVault enforcement (`48`):

- Hard-fails apply when FileVault is off.
- Enforces automatic Software Update posture (schedule on, download/install/security keys enabled).
- FileVault enablement is manual in System Settings to preserve Apple Account escrow flow.
- Emergency bypass: `CHEZMOI_SKIP_SYSTEM_UPDATES_SECURITY=1`.

Privacy minimization (`49`):

- Enforces personalized ads off.
- Enforces analytics sharing off (`AutoSubmit=false`, `ThirdPartyDataSubmit=false`).
- Disables Siri and Dictation.
- Siri Suggestions remain intentionally unmanaged.
- Emergency bypass: `CHEZMOI_SKIP_PRIVACY_MIN=1`.

## Verification

- `.chezmoiscripts/run_onchange_after_60-verify-bootstrap.sh.tmpl`
- `scripts/verify-bootstrap.sh`
- `scripts/verify-privacy.sh`

Manual:

```sh
bash ~/.local/share/chezmoi/scripts/verify-bootstrap.sh
bash ~/.local/share/chezmoi/scripts/verify-privacy.sh --strict
```

## Readiness checklist

- `.chezmoiscripts/run_onchange_after_61-readiness.sh.tmpl`
- `scripts/verify-readiness.sh`
- `scripts/readiness-ack.sh`

Manual:

```sh
bash ~/.local/share/chezmoi/scripts/verify-readiness.sh
bash ~/.local/share/chezmoi/scripts/readiness-ack.sh list
bash ~/.local/share/chezmoi/scripts/readiness-ack.sh mark defender-approvals-reboot
bash ~/.local/share/chezmoi/scripts/readiness-ack.sh mark istat-profile-import
bash ~/.local/share/chezmoi/scripts/readiness-ack.sh clear all
```

Local ack state is stored under `~/.local/state/chezmoi/readiness/` and is not tracked.

## Common toggles

```sh
CHEZMOI_SKIP_BREW=1 chezmoi apply
CHEZMOI_INSTALL_OPTIONAL=1 chezmoi apply
CHEZMOI_SKIP_MAS=1 chezmoi apply
CHEZMOI_SKIP_WIREGUARD_SETUP=1 chezmoi apply
CHEZMOI_SKIP_MACOS_DEFAULTS=1 chezmoi apply
CHEZMOI_SKIP_DISPLAY_SCALING=1 chezmoi apply
CHEZMOI_SKIP_APPEARANCE=1 chezmoi apply
CHEZMOI_SKIP_DOCK_LAYOUT=1 chezmoi apply
CHEZMOI_SKIP_PRIVILEGED_SYSTEM=1 chezmoi apply
CHEZMOI_SKIP_SYSTEM_UPDATES_SECURITY=1 chezmoi apply
CHEZMOI_SKIP_PRIVACY_MIN=1 chezmoi apply
CHEZMOI_SKIP_VERIFY=1 chezmoi apply
CHEZMOI_SKIP_READINESS=1 chezmoi apply
CHEZMOI_VERIFY_STRICT=1 chezmoi apply
CHEZMOI_READINESS_STRICT=1 chezmoi apply
```

## Script slots

- `10` prereqs
- `20` git identity bootstrap
- `30` brew bundle
- `31` conditional cask installs
- `34` MAS installs
- `35` optional cask prompt
- `36` Defender installer
- `37` WireGuard setup
- `40-50` macOS UX/system settings
- `48` FileVault + Software Update enforcement
- `49` Privacy minimization (ads/analytics/Siri/Dictation)
- `60` verification
- `61` readiness checklist
