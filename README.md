# Dotfiles managed with chezmoi

This repo bootstraps a macOS Apple Silicon machine with shell/git/ssh config, package installs, selected macOS settings, and post-apply checks.

## Bootstrap

```sh
sh -c "$(curl -fsLS get.chezmoi.io/lb)" -- init --apply <github-user>
```

Useful flags during bootstrap:

- `chezmoi apply -v` -- verbose output showing each action.
- `chezmoi apply -k` -- keep going after errors so remaining scripts still run.

## Configuration

`chezmoi init` generates `~/.config/chezmoi/chezmoi.toml` from `.chezmoi.toml.tmpl`. The default config enables progress output and sets all feature toggles to their safe defaults.

After init, customize toggles in `~/.config/chezmoi/chezmoi.toml`:

```toml
[data]
    skipBrew = false
    skipMas = false
    skipDefender = false
    skipWireguardSetup = false
    skipMacosDefaults = false
    skipDisplayScaling = false
    skipAppearance = false
    skipDockLayout = false
    skipPrivilegedSystem = false
    skipSystemUpdatesSecurity = false
    skipPrivacyMin = false
    skipVerify = false
    skipReadiness = false
    installOptional = false
    verifyStrict = false
    readinessStrict = false
```

| Toggle | Scripts affected | Description |
|---|---|---|
| `skipBrew` | 10, 30, 31, 32, 35, 42, 50 | Homebrew formulas, casks, and brew-dependent tools |
| `skipMas` | 34, 37 | Mac App Store installs via mas |
| `skipDefender` | 36 | Microsoft Defender for Consumers installer |
| `skipWireguardSetup` | 37 | WireGuard VPN interactive setup |
| `skipMacosDefaults` | 40, 41, 43, 44, 46, 47, 49 | macOS defaults and UX settings (Finder, Dock behavior, clock, TextEdit, Tips suppression, etc.) |
| `skipDisplayScaling` | 42 | Built-in display "More Space" scaling |
| `skipAppearance` | 45 | Appearance settings (dark mode, wallpaper) |
| `skipDockLayout` | 50 | Dock app layout management |
| `skipPrivilegedSystem` | 47, 48 | Firewall, stealth, pmset, Touch ID sudo |
| `skipSystemUpdatesSecurity` | 48 | FileVault + Software Update enforcement |
| `skipPrivacyMin` | 49 | Ads, analytics, Siri, Dictation |
| `skipVerify` | 60 | Post-apply bootstrap verification |
| `skipReadiness` | 61 | Post-apply readiness checklist |
| `installOptional` | 30 | Include Brewfile.optional in brew bundle |
| `verifyStrict` | 60 | Fail chezmoi apply on verification failures |
| `readinessStrict` | 61 | Fail chezmoi apply on readiness TODO/FAIL items |

Each toggle also has a one-off environment variable override for use in CI or single runs without editing the config file. See the "Common toggles" section below.

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
- `.chezmoiscripts/run_onchange_after_32-1password-ssh-agent-compat.sh.tmpl`
- `.chezmoiscripts/run_onchange_after_34-mas-apps.sh.tmpl`
- `.chezmoiscripts/run_once_after_35-optional-casks.sh.tmpl`
- `.chezmoiscripts/run_once_after_36-microsoft-defender-consumer.sh.tmpl`

Notes:

- HiddenBar is installed only on notch-capable MacBooks.
- Optional casks prompt once from `casks/optional-casks.txt`.
- `freac-continuous` installs from upstream DMG (not a Homebrew cask token).
- The Defender installer is PKG-only and validates package signature before install.
- SSH is configured to use `IdentityAgent ~/.1password/agent.sock`; slot `32` backfills a compatibility symlink from the legacy 1Password socket path when needed.
- WireGuard setup can generate a new client keypair and saves the client public key to `~/.local/state/chezmoi/wireguard-latest-public-key` for pfSense peer setup.

## macOS automation

- `.chezmoiscripts/run_onchange_after_40-macos-defaults.sh.tmpl`
- `.chezmoiscripts/run_onchange_after_41-screenshot-location.sh.tmpl`
- `.chezmoiscripts/run_onchange_after_42-display-more-space.sh.tmpl`
- `.chezmoiscripts/run_onchange_after_43-menu-bar-clock.sh.tmpl`
- `.chezmoiscripts/run_onchange_after_44-textedit.sh.tmpl`
- `.chezmoiscripts/run_onchange_after_45-appearance.sh.tmpl`
- `.chezmoiscripts/run_onchange_after_46-tips-notifications.sh.tmpl`
- `.chezmoiscripts/run_onchange_after_47-privileged-system.sh.tmpl`
- `.chezmoiscripts/run_onchange_after_48-system-updates-security.sh.tmpl`
- `.chezmoiscripts/run_onchange_after_49-privacy-minimization.sh.tmpl`
- `.chezmoiscripts/run_onchange_after_50-dock-layout.sh.tmpl`

Current defaults baseline (`40`) enforces:

- Theme + scrolling: accent/highlight colors and natural scrolling off.
- Finder defaults: list view, open folders in windows (not tabs), home target path, desktop item visibility, recent tags off.
- File dialogs: list-mode defaults for Open and Save panels.
- Dock behavior: recent apps section hidden.
- WindowManager behavior: desktop reveal-on-click disabled and desktop widgets hidden.

Menu bar (`43`) also enforces:

- Clock/date format baseline.
- Battery percentage visible in menu bar via `defaults -currentHost`.

Tips suppression (`46`):

- Suppresses Tips welcome/reminder prompts in `com.apple.tipsd`.
- Applies best-effort `com.apple.tips auth=0` in `com.apple.ncprefs`.
- If Tips is not yet present in `ncprefs`, it warns and retries on later `chezmoi apply`.

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

First-run UX deferrals:

- MAS auth/session unavailable warns and defers app installs (slot `34`), then retries on next `chezmoi apply`.
- Synology screenshot prerequisites missing warn and defer location enforcement (slot `41`), then retries on next `chezmoi apply`.
- Built-in display unavailable or display apply temporarily unavailable warns and defers More Space enforcement (slot `42`), then retries on next `chezmoi apply`.
- Slot `42` also re-runs when display state/topology changes (display fingerprint trigger), so reconnecting displays can re-enforce built-in More Space on the next `chezmoi apply`.

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

Persistent toggles live in `~/.config/chezmoi/chezmoi.toml` under `[data]` (see Configuration above). For one-off overrides, use environment variables:

```sh
CHEZMOI_SKIP_BREW=1 chezmoi apply
CHEZMOI_INSTALL_OPTIONAL=1 chezmoi apply
CHEZMOI_SKIP_MAS=1 chezmoi apply
CHEZMOI_SKIP_DEFENDER=1 chezmoi apply
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
- `32` 1Password SSH agent socket compatibility
- `34` MAS installs
- `35` optional cask prompt
- `36` Defender installer
- `37` WireGuard setup
- `40-50` macOS UX/system settings
- `46` Tips notification suppression
- `48` FileVault + Software Update enforcement
- `49` Privacy minimization (ads/analytics/Siri/Dictation)
- `60` verification
- `61` readiness checklist
