# Dotfiles managed with chezmoi

This repository bootstraps a macOS Apple Silicon laptop with shell/git/ssh config, packages, selected system settings, appearance, and Dock layout.

## Bootstrap

Run one command on a new machine:

```sh
sh -c "$(curl -fsLS get.chezmoi.io/lb)" -- init --apply <github-user>
```

First run requires internet access and admin privileges.

License: MIT. See `LICENSE`.

## What this repo manages

- Shell: `~/.zshrc`, `~/.zprofile`, `~/.aliases`
- Git: `~/.gitconfig`
- SSH config: `~/.ssh/config` (config only, no keys)
- Homebrew formulas/casks
- Optional Homebrew selections
- Mac App Store apps via `mas`
- Allowlisted macOS defaults
- Built-in display "More Space" scaling automation
- Appearance baseline (dark mode + wallpaper)
- Deterministic Dock app order
- Post-apply verification report

## Homebrew and Mac App Store

Core package convergence is handled by:

- `.chezmoiscripts/run_onchange_after_30-brew-bundle.sh.tmpl`
- `.chezmoiscripts/run_after_31-hiddenbar-notch.sh`

This script template embeds `Brewfile`/`Brewfile.optional` hashes, so it re-runs automatically when those files change.

HiddenBar policy:

- Installed only on notch-capable MacBooks (detected from model/chip profile).
- Skipped on desktops and non-notch Apple Silicon laptop profiles.

Mac App Store apps are handled by:

- `.chezmoiscripts/run_onchange_after_34-mas-apps.sh.tmpl`

MAS app policy:

- Required: Magnet, WireGuard
- Optional (with optional toggle): Parcel

If App Store authentication is required, apply exits with instructions. Sign in to the App Store app, then rerun `chezmoi apply`.

WireGuard interactive setup is handled by:

- `.chezmoiscripts/run_onchange_after_37-wireguard-config.sh.tmpl`

Behavior:

- prompts only when WireGuard is installed and not yet marked configured
- if skipped, it prompts again on the next `chezmoi apply`
- if no TTY is available, it defers without failing
- writes tunnel config to `~/.config/wireguard/*.conf`
- opens the config file with WireGuard for import and asks for final confirmation

WireGuard setup is considered complete when:

- at least one WireGuard VPN service is detected via `scutil --nc list`, or
- marker file exists at `~/.local/state/chezmoi/wireguard-configured` and points to an existing `~/.config/wireguard/*.conf` file

Microsoft Defender for Consumers is installed from Microsoft directly (non-cask) via:

- `.chezmoiscripts/run_once_after_36-microsoft-defender-consumer.sh`

Installer source URL:

- `https://go.microsoft.com/fwlink/?linkid=2247001`

After install, approve required system/network extensions in System Settings, then reboot.

## Optional installs and skip toggles

```sh
# Install optional formulas, optional VS Code extensions, and optional MAS apps
CHEZMOI_INSTALL_OPTIONAL=1 chezmoi apply

# Skip all Homebrew work (including MAS and cask prompts)
CHEZMOI_SKIP_BREW=1 chezmoi apply

# Skip MAS app installs only
CHEZMOI_SKIP_MAS=1 chezmoi apply

# Skip interactive WireGuard setup prompt
CHEZMOI_SKIP_WIREGUARD_SETUP=1 chezmoi apply

# Skip built-in display scaling automation
CHEZMOI_SKIP_DISPLAY_SCALING=1 chezmoi apply

# Skip privileged security/power settings
CHEZMOI_SKIP_PRIVILEGED_SYSTEM=1 chezmoi apply

# Skip verification hook
CHEZMOI_SKIP_VERIFY=1 chezmoi apply

# Re-run optional cask prompts manually
bash "${HOME}/.local/share/chezmoi/.chezmoiscripts/run_once_after_35-optional-casks.sh"
```

Optional casks are prompted one time per machine from `casks/optional-casks.txt`.
In non-interactive sessions (no TTY), optional cask prompts are skipped.
`freac-continuous` is handled as a direct DMG install from the fre:ac continuous release channel (not a Homebrew cask token).

## macOS settings baseline

Allowlisted UI settings are applied by default via:

- `.chezmoiscripts/run_onchange_after_40-macos-defaults.sh`
- `.chezmoiscripts/run_onchange_after_41-screenshot-location.sh`
- `.chezmoiscripts/run_onchange_after_43-menu-bar-clock.sh`
- `.chezmoiscripts/run_onchange_after_44-textedit.sh`
- `.chezmoiscripts/run_onchange_after_47-privileged-system.sh.tmpl`
- `macos/settings-baseline.sh`

Skip:

```sh
CHEZMOI_SKIP_MACOS_DEFAULTS=1 chezmoi apply
```

Current tracked additions include:

- Accent color (`NSGlobalDomain AppleAccentColor=3`)
- Highlight color (`NSGlobalDomain AppleHighlightColor="0.752941 0.964706 0.678431 Green"`)

### Privileged security/power baseline

Applied by:

- `.chezmoiscripts/run_onchange_after_47-privileged-system.sh.tmpl`

Targets:

- Firewall global state enabled
- Firewall stealth mode on
- Screensaver lock prompt enabled (`askForPassword=1`)
- Screensaver lock delay immediate (`askForPasswordDelay=0`)
- `pmset` display sleep: battery `10`, AC `60`
- Touch ID for sudo via `/etc/pam.d/sudo_local` only when Touch ID hardware is detected

Behavior:

- Reads current state first
- Escalates with `sudo` only for drifted privileged changes
- Touch ID setup is skipped (non-fatal) when hardware support is unavailable

Not managed:

- Legacy macOS defaults previously managed in `40` (intentionally removed from baseline scope)
- Finder hidden-files visibility (`com.apple.finder AppleShowAllFiles`)
- Finder sidebar favorites
- `PowerButtonSleepsSystem` (unreliable/unsupported setter choice)
- VS Code settings/keybindings migration

### Screenshot location guard

Screenshot location is enforced separately from the collected allowlist:

- script: `.chezmoiscripts/run_onchange_after_41-screenshot-location.sh`
- source path rule: `~/Library/CloudStorage/SynologyDrive-*/Screenshots`

Behavior:

- requires exactly one `SynologyDrive-*` root under `~/Library/CloudStorage`
- fails fast if root is missing or ambiguous
- fails fast if `Screenshots` folder is missing
- writes `com.apple.screencapture location` only when drift is detected

If it fails, configure Synology Drive / folder structure and rerun `chezmoi apply`.

### Refreshing collected settings

```sh
# 1) Apply first so missing keys exist
chezmoi apply

# 2) Inspect collected values
./scripts/collect-macos-settings.sh

# 3) Regenerate baseline
./scripts/collect-macos-settings.sh --write-baseline ./macos/settings-baseline.sh
```

Source allowlist: `scripts/macos-settings-allowlist.txt`.

### Menu bar clock

Menu bar time/date preferences are enforced separately via:

- `macos/clock-baseline.sh`
- `.chezmoiscripts/run_onchange_after_43-menu-bar-clock.sh`

Enforced values:

- `NSGlobalDomain AppleICUForce24HourTime=1`
- `com.apple.menuextra.clock IsAnalog=0`
- `com.apple.menuextra.clock ShowDayOfWeek=1`
- `com.apple.menuextra.clock ShowDate=1` (always)
- `com.apple.menuextra.clock ShowAMPM=0`
- `com.apple.ControlCenter "NSStatusItem VisibleCC Clock"=1`

Notes:

- `ShowDate` is enum-based on modern macOS (`1` means always show date).
- With 24-hour mode enabled, AM/PM is suppressed visually.

### TextEdit defaults

TextEdit defaults are enforced separately via:

- `macos/textedit-baseline.sh`
- `.chezmoiscripts/run_onchange_after_44-textedit.sh`

Enforced values:

- `com.apple.TextEdit RichText=0` (plain text by default)
- `com.apple.TextEdit PlainTextEncoding=4` (UTF-8)
- `com.apple.TextEdit PlainTextEncodingForWrite=4` (UTF-8)
- `com.apple.TextEdit CheckSpellingWhileTyping=0`
- `com.apple.TextEdit CheckGrammarWithSpelling=0`
- `com.apple.TextEdit CorrectSpellingAutomatically=0`

Scope:

- TextEdit-only behavior; global typing/spelling defaults are intentionally not changed.

## Display scaling (More Space)

Built-in display scaling is enforced by:

- `.chezmoiscripts/run_onchange_after_42-display-more-space.sh`

Behavior:

- targets built-in display only
- uses `displayplacer list` to discover available built-in scaled modes
- picks the highest logical `scaling:on` mode as "More Space"
- applies only built-in display mode (`displayplacer "id:<id> res:<w>x<h> scaling:on"`)
- fails fast if built-in display is unavailable or no scaled modes are found

Skip:

```sh
CHEZMOI_SKIP_DISPLAY_SCALING=1 chezmoi apply
```

## Appearance baseline

Applied by `.chezmoiscripts/run_onchange_after_45-appearance.sh` using:

- `macos/appearance-baseline.sh`
- `desktoppr` (no AppleScript `System Events`)

Default baseline:

- `APPEARANCE_MODE="dark"`
- `APPEARANCE_AUTO_SWITCH=0`
- `WALLPAPER_PATH="/System/Library/Desktop Pictures/Solid Colors/Teal.png"`

Skips:

```sh
CHEZMOI_SKIP_APPEARANCE=1 chezmoi apply
CHEZMOI_SKIP_DARK_MODE=1 chezmoi apply
CHEZMOI_SKIP_WALLPAPER=1 chezmoi apply
```

## Dock layout baseline

Applied by `.chezmoiscripts/run_onchange_after_50-dock-layout.sh.tmpl` from `macos/dock-app-order.txt`.

Behavior:

- Resets Dock app section
- Re-adds apps in exact listed order
- Does not explicitly add Finder (prevents duplicate Finder Dock icons)
- Warns and skips missing app paths
- Restarts Dock once at end

Skip:

```sh
CHEZMOI_SKIP_DOCK_LAYOUT=1 chezmoi apply
```

## Verification

Post-apply verification is handled by:

- `.chezmoiscripts/run_onchange_after_60-verify-bootstrap.sh.tmpl`
- `scripts/verify-bootstrap.sh`

Verification checks:

- required core commands (`brew`, `chezmoi`, `dockutil`, `mas`, `desktoppr`, `displayplacer`)
- formulas/casks from `Brewfile` are installed
- required MAS apps from `mas/apps.txt` are installed
- optional MAS apps from `mas/optional-apps.txt` are reported as info
- WireGuard app presence and local setup marker state
- Microsoft Defender consumer app presence (`com.microsoft.wdav`)
- Synology screenshot guard conditions and current screenshot path
- built-in display scaling state (`scaling:on` + expected More Space target mode)
- menu bar clock/date settings
- TextEdit plain text/spell settings
- minimal macOS defaults spot-checks (accent/highlight)
- privileged security/power checks (firewall, screensaver lock settings, pmset, Touch ID sudo when available)
- Dock app presence checks from `macos/dock-app-order.txt` (excluding Finder)
- delegated privacy audit summary from `scripts/verify-privacy.sh`

Output format:

- sectioned report with `PASS`, `WARN`, and `FAIL` lines
- summary line: `PASS=<n> WARN=<n> FAIL=<n>`

Modes:

- default: report mode (always exits `0` so apply can continue)
- strict: `CHEZMOI_VERIFY_STRICT=1` exits non-zero when any `FAIL` exists

Manual run:

```sh
bash ~/.local/share/chezmoi/scripts/verify-bootstrap.sh
bash ~/.local/share/chezmoi/scripts/verify-privacy.sh --strict
```

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs on macOS and checks:

- bash syntax for scripts/hooks
- shellcheck for scripts/hooks
- `chezmoi apply --dry-run` against a temporary destination
- `scripts/verify-privacy.sh --history --strict`

Optional local pre-commit checks:

```sh
find .chezmoiscripts scripts -type f \( -name '*.sh' -o -name '*.sh.tmpl' \) -print0 | xargs -0 -n1 bash -n
shellcheck $(find .chezmoiscripts scripts -type f \( -name '*.sh' -o -name '*.sh.tmpl' \))
bash ./scripts/verify-privacy.sh --strict
```

## `.chezmoiscripts` naming and order

Filename format:

- `run_once_<phase>_<NN>-<purpose>.sh`
- `run_onchange_<phase>_<NN>-<purpose>.sh` (or `.sh.tmpl`)
- `run_after_<NN>-<purpose>.sh` (runs every apply)
- `<phase>`: `before` or `after`
- `<NN>`: two-digit slot number

Reserved slots:

- `10`: OS/system prerequisites
- `20`: toolchain/bootstrap prerequisites
- `30`: package manager actions (`brew bundle`)
- `31`: conditional package installs (for example notch-only HiddenBar)
- `34`: Mac App Store installs (`mas`)
- `36`: direct third-party installers (Microsoft Defender consumer)
- `37`: recurring interactive app configuration (WireGuard)
- `40`: macOS defaults baseline
- `41`: screenshot location guard
- `42`: built-in display scaling ("More Space")
- `43`: menu bar clock/date
- `44`: TextEdit plain text/spell defaults
- `45`: appearance baseline
- `47`: privileged security/power baseline
- `50`: Dock layout baseline
- `60`: post-apply verification/reporting
- `90`: optional/local follow-ups

## Secrets and SSH

- Secret material is intentionally not stored in this repo.
- SSH auth is expected via 1Password SSH agent configured in `~/.ssh/config`.
