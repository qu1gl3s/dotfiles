#!/bin/bash
set -euo pipefail

READINESS_STATE_DIR="${HOME}/.local/state/chezmoi/readiness"
DEFENDER_ACK_FILE="${READINESS_STATE_DIR}/defender-approvals-reboot.done"
ISTAT_ACK_FILE="${READINESS_STATE_DIR}/istat-profile-import.done"

usage() {
  cat <<'EOF'
Usage:
  readiness-ack.sh list
  readiness-ack.sh mark <task>
  readiness-ack.sh clear <task|all>

Tasks:
  defender-approvals-reboot
  istat-profile-import
EOF
}

ack_file_for_task() {
  local task="$1"
  case "${task}" in
    defender-approvals-reboot) echo "${DEFENDER_ACK_FILE}" ;;
    istat-profile-import) echo "${ISTAT_ACK_FILE}" ;;
    *)
      echo "Unknown readiness task: ${task}" >&2
      return 1
      ;;
  esac
}

print_task_status() {
  local task="$1"
  local ack_file=""
  ack_file="$(ack_file_for_task "${task}")"
  if [[ -f "${ack_file}" ]]; then
    echo "DONE    ${task}"
  else
    echo "PENDING ${task}"
  fi
}

command_name="${1:-list}"

case "${command_name}" in
  list|status)
    print_task_status "defender-approvals-reboot"
    print_task_status "istat-profile-import"
    ;;
  mark)
    task="${2:-}"
    if [[ -z "${task}" ]]; then
      usage
      exit 1
    fi
    ack_file="$(ack_file_for_task "${task}")"
    mkdir -p "${READINESS_STATE_DIR}"
    date -u +"%Y-%m-%dT%H:%M:%SZ" > "${ack_file}"
    echo "Marked readiness task done: ${task}"
    ;;
  clear)
    task="${2:-}"
    if [[ -z "${task}" ]]; then
      usage
      exit 1
    fi

    if [[ "${task}" == "all" ]]; then
      rm -f "${DEFENDER_ACK_FILE}" "${ISTAT_ACK_FILE}"
      echo "Cleared all readiness task acknowledgements."
    else
      ack_file="$(ack_file_for_task "${task}")"
      rm -f "${ack_file}"
      echo "Cleared readiness task acknowledgement: ${task}"
    fi
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac
