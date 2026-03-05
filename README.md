# Dotfiles managed with chezmoi

This repository bootstraps a macOS Apple Silicon laptop with shell/git/ssh config, packages, selected system settings, appearance, and Dock layout.

## Bootstrap

Run one command on a new machine:

```sh
sh -c "$(curl -fsLS get.chezmoi.io/lb)" -- init --apply <github-user>
```

First run requires internet access and admin privileges.

## What this repo manages

- Shell: `~/.zshrc`, `~/.zprofile`, `~/.aliases`
- Git: `~/.gitconfig`
- SSH config: `~/.ssh/config` (config only, no keys)
- Homebrew formulas/casks
- Optional Homebrew selections
- Mac App Store apps via `mas`
- Allowlisted macOS defaults
- Appearance baseline (dark mode + wallpaper)
- Deterministic Dock app order

## Homebrew and Mac App Store

Core package convergence is handled by:

- `.chezmoiscripts/run_onchange_after_30-brew-bundle.sh.tmpl`

This script template embeds `Brewfile`/`Brewfile.optional` hashes, so it re-runs automatically when those files change.

Mac App Store apps are handled by:

- `.chezmoiscripts/run_onchange_after_34-mas-apps.sh.tmpl`

MAS app policy:

- Required: Magnet
- Optional (with optional toggle): Parcel

If App Store authentication is required, apply exits with instructions. Sign in to the App Store app, then rerun `chezmoi apply`.

## Optional installs and skip toggles

```sh
# Install optional formulas, optional VS Code extensions, and optional MAS apps
CHEZMOI_INSTALL_OPTIONAL=1 chezmoi apply

# Skip all Homebrew work (including MAS and cask prompts)
CHEZMOI_SKIP_BREW=1 chezmoi apply

# Skip MAS app installs only
CHEZMOI_SKIP_MAS=1 chezmoi apply

# Re-run optional cask prompts manually
bash "${HOME}/.local/share/chezmoi/.chezmoiscripts/run_once_after_35-optional-casks.sh"
```

Optional casks are prompted one time per machine from `casks/optional-casks.txt`.
In non-interactive sessions (no TTY), optional cask prompts are skipped.

## macOS settings baseline

Allowlisted UI settings are applied by default via:

- `.chezmoiscripts/run_onchange_after_40-macos-defaults.sh`
- `macos/settings-baseline.sh`

Skip:

```sh
CHEZMOI_SKIP_MACOS_DEFAULTS=1 chezmoi apply
```

Current tracked additions include:

- Trackpad scroll direction off (`NSGlobalDomain com.apple.swipescrolldirection=0`)
- Built-in tap-to-click on (`com.apple.AppleMultitouchTrackpad Clicking=1`)
- Disable network `.DS_Store` files (`com.apple.desktopservices DSDontWriteNetworkStores=1`)
- Click wallpaper behavior set to "Only in Stage Manager" (`com.apple.WindowManager EnableStandardClickToShowDesktop=0`)

Not managed:

- Finder hidden-files visibility (`com.apple.finder AppleShowAllFiles`)
- Dock `persistent-apps` layout in defaults (Dock layout is managed separately with `dockutil`)
- Screenshot location/path
- Network/privacy/account/iCloud identity settings

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

Applied by `.chezmoiscripts/run_onchange_after_50-dock-layout.sh` from `macos/dock-app-order.txt`.

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

## `.chezmoiscripts` naming and order

Filename format:

- `run_<frequency>_<phase>_<NN>-<purpose>.sh`
- `<frequency>`: `once` or `onchange`
- `<phase>`: `before` or `after`
- `<NN>`: two-digit slot number

Reserved slots:

- `10`: OS/system prerequisites
- `20`: toolchain/bootstrap prerequisites
- `30`: package manager actions (`brew bundle`)
- `34`: Mac App Store installs (`mas`)
- `40`: macOS defaults baseline
- `45`: appearance baseline
- `50`: Dock layout baseline
- `90`: optional/local follow-ups

## Secrets and SSH

- Secret material is intentionally not stored in this repo.
- SSH auth is expected via 1Password SSH agent configured in `~/.ssh/config`.
