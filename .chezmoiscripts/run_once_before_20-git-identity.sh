#!/bin/bash
set -euo pipefail
#
# Script: run_once_before_20-git-identity.sh
# Purpose: Configure git user identity once when missing.
# Prerequisites: git available in PATH.
# Env flags: none.
# Failure behavior: exits non-zero only on git config write failures.

if ! command -v git >/dev/null 2>&1; then
  echo "git not found; skipping git identity setup."
  exit 0
fi

current_name="$(git config --global --get user.name || true)"
current_email="$(git config --global --get user.email || true)"

if [[ -n "${current_name}" && -n "${current_email}" ]]; then
  echo "Git identity already configured; skipping."
  exit 0
fi

if [[ ! -t 0 || ! -t 1 ]]; then
  echo "Git identity is incomplete and no interactive TTY is available. Configure manually with git config --global." >&2
  exit 0
fi

if [[ -z "${current_name}" ]]; then
  while [[ -z "${current_name}" ]]; do
    read -r -p "Enter git user.name: " current_name
  done
  git config --global user.name "${current_name}"
  echo "Configured git user.name."
fi

if [[ -z "${current_email}" ]]; then
  while [[ -z "${current_email}" ]]; do
    read -r -p "Enter git user.email: " current_email
  done
  git config --global user.email "${current_email}"
  echo "Configured git user.email."
fi
