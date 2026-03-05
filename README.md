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

By default, chezmoi applies only `Brewfile` (core formulas).

- Install optional formulas and VS Code extensions:

```sh
CHEZMOI_INSTALL_OPTIONAL=1 chezmoi apply
```

- Skip all Homebrew actions:

```sh
CHEZMOI_SKIP_BREW=1 chezmoi apply
```

Phase 1 intentionally excludes all casks from Homebrew manifests.

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
- `40`: post-bootstrap verification
- `90`: optional/local machine follow-ups

Naming examples:

- `run_once_before_10-macos-prereqs.sh`
- `run_once_before_20-bootstrap-toolchain.sh`
- `run_onchange_after_30-brew-bundle.sh`
- `run_onchange_after_40-verify-bootstrap.sh`
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
