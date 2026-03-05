#!/bin/bash
set -euo pipefail
#
# Script: run_onchange_after_42-display-more-space.sh
# Purpose: Enforce built-in display to "More Space" by selecting the highest scaled mode.
# Prerequisites: macOS with displayplacer available.
# Env flags:
#   CHEZMOI_SKIP_BREW=1 skips this script
#   CHEZMOI_SKIP_DISPLAY_SCALING=1 skips this script
# Failure behavior: exits non-zero if built-in display or scaled modes cannot be resolved/applied.

if [[ "${CHEZMOI_SKIP_BREW:-0}" == "1" ]]; then
  echo "Skipping display scaling because CHEZMOI_SKIP_BREW=1"
  exit 0
fi

if [[ "${CHEZMOI_SKIP_DISPLAY_SCALING:-0}" == "1" ]]; then
  echo "Skipping display scaling because CHEZMOI_SKIP_DISPLAY_SCALING=1"
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  exit 0
fi

if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

if ! command -v displayplacer >/dev/null 2>&1; then
  cat >&2 <<'EOF'
displayplacer is required for display scaling automation but was not found.
Install prerequisites with:
  brew install displayplacer
EOF
  exit 1
fi

display_list_output="$(displayplacer list 2>/dev/null || true)"
if [[ -z "${display_list_output}" ]]; then
  echo "displayplacer list returned no output; cannot determine display modes." >&2
  exit 1
fi

builtin_count=0
current_id=""
current_builtin=0
current_best_area=-1
current_best_res=""
current_resolution=""
current_scaling=""

builtin_id=""
builtin_target_res=""
builtin_current_res=""
builtin_current_scaling=""

finalize_display() {
  if [[ "${current_builtin}" -eq 1 ]]; then
    ((builtin_count += 1))
    builtin_id="${current_id}"
    builtin_target_res="${current_best_res}"
    builtin_current_res="${current_resolution}"
    builtin_current_scaling="${current_scaling}"
  fi
}

while IFS= read -r line; do
  if [[ "${line}" =~ ^[[:space:]]*Persistent[[:space:]]screen[[:space:]]id:[[:space:]]*(.+)$ ]]; then
    if [[ -n "${current_id}" ]]; then
      finalize_display
    fi
    current_id="${BASH_REMATCH[1]}"
    current_builtin=0
    current_best_area=-1
    current_best_res=""
    current_resolution=""
    current_scaling=""
    continue
  fi

  [[ -z "${current_id}" ]] && continue

  if [[ "${line}" =~ ^[[:space:]]*Type:[[:space:]]*(.+)$ ]]; then
    display_type="${BASH_REMATCH[1]}"
    if [[ "${display_type}" =~ [Bb]uilt-?[Ii]n|[Ii]nternal|[Mm]ac[Bb]ook ]]; then
      current_builtin=1
    fi
    continue
  fi

  if [[ "${line}" =~ ^[[:space:]]*Resolution:[[:space:]]*([0-9]+x[0-9]+) ]]; then
    current_resolution="${BASH_REMATCH[1]}"
    continue
  fi

  if [[ "${line}" =~ ^[[:space:]]*Scaling:[[:space:]]*(on|off) ]]; then
    current_scaling="${BASH_REMATCH[1]}"
    continue
  fi

  if [[ "${current_builtin}" -eq 1 && "${line}" =~ res:([0-9]+)x([0-9]+).*scaling:on ]]; then
    mode_w="${BASH_REMATCH[1]}"
    mode_h="${BASH_REMATCH[2]}"
    mode_area=$((mode_w * mode_h))
    if [[ "${mode_area}" -gt "${current_best_area}" ]]; then
      current_best_area="${mode_area}"
      current_best_res="${mode_w}x${mode_h}"
    fi
  fi
done <<< "${display_list_output}"

if [[ -n "${current_id}" ]]; then
  finalize_display
fi

if [[ "${builtin_count}" -eq 0 ]]; then
  cat >&2 <<'EOF'
Built-in display not detected in displayplacer output.
This can happen in clamshell mode or when no internal panel is active.
Connect/open your built-in display, then rerun:
  chezmoi apply
EOF
  exit 1
fi

if [[ "${builtin_count}" -gt 1 ]]; then
  echo "Multiple built-in displays detected; cannot choose a single target mode safely." >&2
  exit 1
fi

if [[ -z "${builtin_target_res}" ]]; then
  echo "No scaling:on modes found for built-in display; cannot enforce More Space." >&2
  exit 1
fi

if [[ "${builtin_current_scaling}" == "on" && "${builtin_current_res}" == "${builtin_target_res}" ]]; then
  echo "Built-in display already set to More Space (${builtin_target_res})."
  exit 0
fi

if ! displayplacer "id:${builtin_id} res:${builtin_target_res} scaling:on" >/dev/null 2>&1; then
  cat >&2 <<EOF
Failed to apply More Space mode with displayplacer.
Attempted:
  displayplacer "id:${builtin_id} res:${builtin_target_res} scaling:on"
You may need to unlock Displays settings or reconnect displays, then rerun chezmoi apply.
EOF
  exit 1
fi

echo "Applied built-in display More Space mode: ${builtin_target_res}"
