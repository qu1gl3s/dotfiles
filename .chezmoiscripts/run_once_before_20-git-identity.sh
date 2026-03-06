#!/bin/bash
set -euo pipefail
#
# Script: run_once_before_20-git-identity.sh
# Purpose: Configure git user identity once when missing using ~/.gitconfig.local include file.
# Prerequisites: git available in PATH.
# Env flags: none.
# Failure behavior: exits non-zero only on git config write failures.

if ! command -v git >/dev/null 2>&1; then
  echo "git not found; skipping git identity setup."
  exit 0
fi

LOCAL_GITCONFIG="${HOME}/.gitconfig.local"

current_name="$(git config --file "${LOCAL_GITCONFIG}" --get user.name 2>/dev/null || true)"
current_email="$(git config --file "${LOCAL_GITCONFIG}" --get user.email 2>/dev/null || true)"

fallback_name="$(git config --global --get user.name || true)"
fallback_email="$(git config --global --get user.email || true)"

if [[ -z "${current_name}" && -n "${fallback_name}" ]]; then
  current_name="${fallback_name}"
fi

if [[ -z "${current_email}" && -n "${fallback_email}" ]]; then
  current_email="${fallback_email}"
fi

if [[ -n "${current_name}" && -n "${current_email}" ]]; then
  git config --file "${LOCAL_GITCONFIG}" user.name "${current_name}"
  git config --file "${LOCAL_GITCONFIG}" user.email "${current_email}"
  echo "Git identity already available; ensured in ${LOCAL_GITCONFIG}."
  exit 0
fi

if [[ ! -t 0 || ! -t 1 ]]; then
  echo "Git identity is incomplete and no interactive TTY is available. Configure manually in ${LOCAL_GITCONFIG}." >&2
  exit 0
fi

if [[ -z "${current_name}" ]]; then
  while [[ -z "${current_name}" ]]; do
    read -r -p "Enter git user.name: " current_name
  done
fi

if [[ -z "${current_email}" ]]; then
  while [[ -z "${current_email}" ]]; do
    read -r -p "Enter git user.email: " current_email
  done
fi

git config --file "${LOCAL_GITCONFIG}" user.name "${current_name}"
git config --file "${LOCAL_GITCONFIG}" user.email "${current_email}"
echo "Configured git identity in ${LOCAL_GITCONFIG}."
