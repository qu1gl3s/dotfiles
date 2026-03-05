# Dotfiles managed with chezmoi

This repository manages shell, git, SSH config, and Homebrew formulas for new machine bootstrap.

## Bootstrap a new laptop

Run this one command:

```sh
sh -c "$(curl -fsLS get.chezmoi.io/lb)" -- init --apply <github-user>
```

On first run, this bootstrap handles prerequisites (Xcode Command Line Tools via Homebrew install path + Homebrew) before running `brew bundle`.
It requires internet access and admin privileges.

## Homebrew behavior

By default, chezmoi applies `Brewfile` (core formulas + compulsory casks).
Core formulas include `dockutil`, used to enforce Dock icon order.
Homebrew bundle runs via `run_onchange_after_30-brew-bundle.sh.tmpl`.
The script template embeds `Brewfile` hashes so it re-runs automatically when `Brewfile` or `Brewfile.optional` changes.

- Install optional formulas and VS Code extensions:

```sh
CHEZMOI_INSTALL_OPTIONAL=1 chezmoi apply
```

- Skip all Homebrew actions:

```sh
CHEZMOI_SKIP_BREW=1 chezmoi apply
```

Mac App Store apps are managed with `mas` via `run_onchange_after_34-mas-apps.sh.tmpl`.

- Required MAS apps (always installed): Magnet
- Optional MAS apps (installed only with optional toggle): Parcel

If App Store authentication is required, `chezmoi apply` will stop with an actionable message.
After signing in, rerun `chezmoi apply`.
To bypass MAS app installs temporarily:

```sh
CHEZMOI_SKIP_MAS=1 chezmoi apply
```

Optional casks are not installed by default.
On first run per machine, chezmoi prompts for each optional cask in `casks/optional-casks.txt`.
Default answer is No for every optional cask.
If no TTY is available (for example CI/non-interactive runs), optional cask prompts are skipped safely.

To re-run optional cask selection manually:

```sh
bash "${HOME}/.local/share/chezmoi/.chezmoiscripts/run_once_after_35-optional-casks.sh"
```

## macOS system settings baseline

This repo can apply an allowlisted set of macOS UI settings after package install.

- Apply is enabled by default during `chezmoi apply`.
- Skip with:

```sh
CHEZMOI_SKIP_MACOS_DEFAULTS=1 chezmoi apply
```

### Collection workflow

1. Apply current baseline first (ensures missing keys exist before collection):

```sh
chezmoi apply
```

2. Review/edit allowlist entries:
   - `scripts/macos-settings-allowlist.txt`
3. Collect current values from this machine:

```sh
./scripts/collect-macos-settings.sh
```

4. Regenerate the baseline from current machine values:

```sh
./scripts/collect-macos-settings.sh --write-baseline ./macos/settings-baseline.sh
```

5. Review `macos/settings-baseline.sh` before commit.

Scope guardrails:

- includes: safe UI baseline keys for `NSGlobalDomain`, `com.apple.AppleMultitouchTrackpad`, `com.apple.finder`, `com.apple.desktopservices`, `com.apple.dock`, `com.apple.screencapture`, `com.apple.WindowManager`
- excludes: `com.apple.finder AppleShowAllFiles`, Dock app layout (`persistent-apps`), screenshot path/location, network/privacy/account/iCloud keys

Current additions in this phase:

- trackpad scroll direction: `NSGlobalDomain com.apple.swipescrolldirection=0` (natural scroll off)
- built-in tap-to-click only: `com.apple.AppleMultitouchTrackpad Clicking=1`
- disable network `.DS_Store` writes: `com.apple.desktopservices DSDontWriteNetworkStores=1`
- desktop click behavior: `com.apple.WindowManager EnableStandardClickToShowDesktop=0` ("Only in Stage Manager")
- Finder hidden-files visibility remains unmanaged by this repo

## Appearance baseline

This repo applies appearance settings without AppleScript `System Events`.

- dark mode is enforced with `defaults` keys in `NSGlobalDomain`
- wallpaper is enforced with `desktoppr`
- changes are applied only when current state differs from baseline

Appearance source file:

- `macos/appearance-baseline.sh`

Default baseline:

- `APPEARANCE_MODE="dark"`
- `APPEARANCE_AUTO_SWITCH=0`
- `WALLPAPER_PATH="/System/Library/Desktop Pictures/Solid Colors/Teal.png"`

Skip controls:

```sh
CHEZMOI_SKIP_APPEARANCE=1 chezmoi apply
CHEZMOI_SKIP_DARK_MODE=1 chezmoi apply
CHEZMOI_SKIP_WALLPAPER=1 chezmoi apply
```

## Dock layout baseline

This repo enforces an exact Dock app order with `dockutil`.
Dock app paths are sourced from:

- `macos/dock-app-order.txt`

Behavior:

- Dock app section is reset on apply (`dockutil --remove all --no-restart`).
- Apps are re-added in exact listed order (Finder is validated as position 1).
- Missing app paths are warned and skipped; remaining apps continue.
- Dock is restarted once at the end.
- Script uses Homebrew Bash (formula `bash`) for modern Bash features.

Skip control:

```sh
CHEZMOI_SKIP_DOCK_LAYOUT=1 chezmoi apply
```

## `.chezmoiscripts` convention

Script filenames follow a strict deterministic pattern:

- `run_<frequency>_<phase>_<NN>-<purpose>.sh`
- `<frequency>` is `once` or `onchange`
- `<phase>` is `before` or `after`
- `<NN>` is a two-digit order slot (`10`, `20`, `30`, ...)
- `<purpose>` is short kebab-case

Lifecycle meanings:

- `run_once_before`: run once before apply actions
- `run_once_after`: run once after apply actions
- `run_onchange_before`: run before apply when source state changes
- `run_onchange_after`: run after apply when source state changes

Reserved slots:

- `10`: OS/system prerequisites (CLT, Homebrew env checks)
- `20`: toolchain/bootstrap prerequisites
- `30`: package manager actions (`brew bundle`)
- `34`: Mac App Store installs (`mas`)
- `40`: macOS defaults/settings baseline
- `45`: appearance baseline
- `50`: Dock layout baseline
- `90`: optional/local machine follow-ups

Naming examples:

- `run_once_before_10-macos-prereqs.sh`
- `run_once_before_20-bootstrap-toolchain.sh`
- `run_onchange_after_30-brew-bundle.sh.tmpl`
- `run_onchange_after_34-mas-apps.sh.tmpl`
- `run_onchange_after_40-macos-defaults.sh`
- `run_onchange_after_45-appearance.sh`
- `run_onchange_after_50-dock-layout.sh`
- `run_once_after_90-local-followups.sh`

New script checklist:

- choose lifecycle (`once`/`onchange`, `before`/`after`)
- choose the correct slot number
- define skip behavior (for example `CHEZMOI_SKIP_BREW`)
- define fail-fast or warn-and-continue behavior
- add a test command (at minimum `bash -n <script>`)

## Managed files in phase 1

- `~/.zshrc`
- `~/.zprofile`
- `~/.aliases`
- `~/.gitconfig`
- `~/.ssh/config` (config only, no keys or known_hosts)

## Secrets and SSH

- Secret material is intentionally not stored in this repo.
- SSH authentication is expected to use the 1Password SSH agent socket configured in `~/.ssh/config`.
