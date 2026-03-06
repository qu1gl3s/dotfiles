#!/bin/bash
set -euo pipefail

SOURCE_DIR="${CHEZMOI_SOURCE_DIR:-$HOME/.local/share/chezmoi}"
STRICT=0
CHECK_HISTORY=0

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

section() {
  echo
  echo "== $1 =="
}

pass() {
  echo "PASS: $1"
  ((PASS_COUNT += 1))
}

warn() {
  echo "WARN: $1"
  ((WARN_COUNT += 1))
}

fail() {
  echo "FAIL: $1"
  ((FAIL_COUNT += 1))
}

info() {
  echo "INFO: $1"
}

usage() {
  cat <<'EOF'
Usage: scripts/verify-privacy.sh [--history] [--strict] [--source-dir <path>]

Options:
  --history            Scan all commits in git history.
  --strict             Exit non-zero when any FAIL is found.
  --source-dir <path>  Override source directory (default: CHEZMOI_SOURCE_DIR or ~/.local/share/chezmoi).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --history)
      CHECK_HISTORY=1
      shift
      ;;
    --strict)
      STRICT=1
      shift
      ;;
    --source-dir)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --source-dir" >&2
        usage
        exit 2
      fi
      SOURCE_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if ! command -v git >/dev/null 2>&1; then
  fail "git is required for privacy verification"
  echo
  echo "SUMMARY: PASS=${PASS_COUNT} WARN=${WARN_COUNT} FAIL=${FAIL_COUNT}"
  exit 1
fi

if ! git -C "${SOURCE_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  fail "Source dir is not a git worktree: ${SOURCE_DIR}"
  echo
  echo "SUMMARY: PASS=${PASS_COUNT} WARN=${WARN_COUNT} FAIL=${FAIL_COUNT}"
  exit 1
fi

check_working_tree() {
  section "Working tree checks"

  if [[ -f "${SOURCE_DIR}/dot_gitconfig" ]] && grep -Eq '^\[user\]' "${SOURCE_DIR}/dot_gitconfig"; then
    fail "dot_gitconfig contains a committed [user] identity block"
  else
    pass "dot_gitconfig has no committed [user] identity block"
  fi

  if [[ -f "${SOURCE_DIR}/private_dot_ssh/private_config" ]]; then
    ssh_host_matches="$(grep -En '^[[:space:]]*Host[[:space:]]+[^*[:space:]]' "${SOURCE_DIR}/private_dot_ssh/private_config" || true)"
    if [[ -n "${ssh_host_matches}" ]]; then
      fail "private_dot_ssh/private_config contains specific Host entries"
      while IFS= read -r match_line; do
        info "  ${match_line}"
      done <<< "${ssh_host_matches}"
    else
      pass "private_dot_ssh/private_config contains only Host * entries"
    fi
  else
    warn "private_dot_ssh/private_config not found"
  fi

  hardcoded_home_matches="$(git -C "${SOURCE_DIR}" grep -n -I -E -- 'file:///Users/[A-Za-z0-9._-]+/?|/Users/[A-Za-z0-9._-]+' -- . ':(exclude)scripts/verify-privacy.sh' ':(exclude)scripts/verify-bootstrap.sh' ':(exclude)scripts/collect-macos-settings.sh' 2>/dev/null || true)"
  if [[ -n "${hardcoded_home_matches}" ]]; then
    fail "hardcoded /Users paths found in tracked files"
    while IFS= read -r match_line; do
      info "  ${match_line}"
    done <<< "${hardcoded_home_matches}"
  else
    pass "no hardcoded /Users paths found in tracked files"
  fi

  bootstrap_user_matches="$(git -C "${SOURCE_DIR}" grep -n -I -E -- 'get\\.chezmoi\\.io/lb\\)" -- init --apply [^<[:space:]]+' -- README.md .chezmoiscripts 2>/dev/null || true)"
  if [[ -n "${bootstrap_user_matches}" ]]; then
    fail "hardcoded bootstrap username found (expected <github-user> placeholder)"
    while IFS= read -r match_line; do
      info "  ${match_line}"
    done <<< "${bootstrap_user_matches}"
  else
    pass "bootstrap examples use <github-user> placeholder"
  fi
}

check_history() {
  section "History checks"
  commit_count="$(git -C "${SOURCE_DIR}" rev-list --all | wc -l | tr -d ' ')"
  info "Scanning ${commit_count} commits"

  offending_home_commit=""
  offending_home_match=""
  offending_bootstrap_commit=""
  offending_bootstrap_match=""
  offending_dotfiles_commit=""
  offending_dotfiles_reason=""

  while IFS= read -r commit; do
    if [[ -z "${offending_home_commit}" ]]; then
      home_matches="$(git -C "${SOURCE_DIR}" grep -n -I -E -- 'file:///Users/[A-Za-z0-9._-]+/?|/Users/[A-Za-z0-9._-]+' "${commit}" -- . ':(exclude)scripts/verify-privacy.sh' ':(exclude)scripts/verify-bootstrap.sh' ':(exclude)scripts/collect-macos-settings.sh' 2>/dev/null | head -n 1 || true)"
      if [[ -n "${home_matches}" ]]; then
        offending_home_commit="${commit}"
        offending_home_match="${home_matches}"
      fi
    fi

    if [[ -z "${offending_bootstrap_commit}" ]]; then
      bootstrap_matches="$(git -C "${SOURCE_DIR}" grep -n -I -E -- 'get\\.chezmoi\\.io/lb\\)" -- init --apply [^<[:space:]]+' "${commit}" -- README.md .chezmoiscripts 2>/dev/null | head -n 1 || true)"
      if [[ -n "${bootstrap_matches}" ]]; then
        offending_bootstrap_commit="${commit}"
        offending_bootstrap_match="${bootstrap_matches}"
      fi
    fi

    if [[ -z "${offending_dotfiles_commit}" ]]; then
      if git -C "${SOURCE_DIR}" show "${commit}:dot_gitconfig" 2>/dev/null | grep -Eq '^\[user\]'; then
        offending_dotfiles_commit="${commit}"
        offending_dotfiles_reason="dot_gitconfig contains [user] identity block"
      elif git -C "${SOURCE_DIR}" show "${commit}:private_dot_ssh/private_config" 2>/dev/null | grep -Eq '^[[:space:]]*Host[[:space:]]+[^*[:space:]]'; then
        offending_dotfiles_commit="${commit}"
        offending_dotfiles_reason="private_dot_ssh/private_config contains specific Host entries"
      fi
    fi
  done < <(git -C "${SOURCE_DIR}" rev-list --all)

  if [[ -n "${offending_home_commit}" ]]; then
    fail "hardcoded /Users paths found in commit history (commit ${offending_home_commit})"
    info "  ${offending_home_match}"
  else
    pass "no hardcoded /Users paths found in commit history"
  fi

  if [[ -n "${offending_bootstrap_commit}" ]]; then
    fail "hardcoded bootstrap username found in commit history (commit ${offending_bootstrap_commit})"
    info "  ${offending_bootstrap_match}"
  else
    pass "no hardcoded bootstrap username found in commit history"
  fi

  if [[ -n "${offending_dotfiles_commit}" ]]; then
    fail "privacy-sensitive dotfiles content found in history commit ${offending_dotfiles_commit}: ${offending_dotfiles_reason}"
  else
    pass "no committed git [user] block or specific SSH Host entries in history"
  fi
}

check_working_tree

if [[ "${CHECK_HISTORY}" -eq 1 ]]; then
  check_history
fi

echo
echo "SUMMARY: PASS=${PASS_COUNT} WARN=${WARN_COUNT} FAIL=${FAIL_COUNT}"

if [[ "${STRICT}" -eq 1 && "${FAIL_COUNT}" -gt 0 ]]; then
  exit 1
fi

exit 0
