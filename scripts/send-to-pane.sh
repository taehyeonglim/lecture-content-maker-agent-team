#!/usr/bin/env bash
set -euo pipefail

SESSION_NAME="lecture-team"
POLL_INTERVAL_SECONDS=3

usage() {
  cat >&2 <<'USAGE'
Usage: bash scripts/send-to-pane.sh [--wait] [--timeout seconds] <pane_name> <task_id> <command_or_prompt>

Pane names: director, decomposer, composer, designer, developer
USAGE
}

pane_index() {
  case "$1" in
    director) echo "0" ;;
    decomposer) echo "1" ;;
    composer) echo "2" ;;
    designer) echo "3" ;;
    developer) echo "4" ;;
    *) return 1 ;;
  esac
}

validate_safe_command() {
  if printf '%s\n' "$1" | grep -qiE 'password|secret|token=|api[_-]?key=|refresh[_-]?token='; then
    echo "ERROR: command appears to contain a plaintext password, secret, or token. Refusing to send it through tmux." >&2
    return 1
  fi
}

wait_for_sentinel() {
  local target="$1"
  local sentinel="$2"
  local timeout_seconds="$3"
  local start_ts
  local now_ts

  start_ts="$(date +%s)"

  while true; do
    if tmux capture-pane -t "$target" -p | grep -Fq "$sentinel"; then
      return 0
    fi

    now_ts="$(date +%s)"
    if [ "$((now_ts - start_ts))" -ge "$timeout_seconds" ]; then
      echo "ERROR: timed out after ${timeout_seconds}s waiting for sentinel: ${sentinel}" >&2
      echo "Hint: record this timeout in STATE.json using the atomic write pattern (STATE.json.tmp -> STATE.json)." >&2
      return 1
    fi

    sleep "$POLL_INTERVAL_SECONDS"
  done
}

main() {
  local wait_mode="false"
  local timeout_seconds="${SEND_TO_PANE_TIMEOUT_SECONDS:-3600}"

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --wait)
        wait_mode="true"
        shift
        ;;
      --timeout)
        if [ "$#" -lt 2 ]; then
          usage
          exit 1
        fi
        timeout_seconds="$2"
        shift 2
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      --)
        shift
        break
        ;;
      --*)
        echo "ERROR: unknown option: $1" >&2
        usage
        exit 1
        ;;
      *)
        break
        ;;
    esac
  done

  if [ "$#" -ne 3 ]; then
    usage
    exit 1
  fi

  local pane_name="$1"
  local task_id="$2"
  local command="$3"
  local pane_idx
  local target
  local sentinel

  if ! [[ "$timeout_seconds" =~ ^[0-9]+$ ]] || [ "$timeout_seconds" -le 0 ]; then
    echo "ERROR: --timeout must be a positive integer number of seconds." >&2
    exit 1
  fi

  if ! [[ "$task_id" =~ ^[A-Za-z0-9._:-]+$ ]]; then
    echo "ERROR: task_id may contain only letters, numbers, dot, underscore, colon, and hyphen." >&2
    exit 1
  fi

  if ! pane_idx="$(pane_index "$pane_name")"; then
    echo "ERROR: unknown pane_name: ${pane_name}" >&2
    usage
    exit 1
  fi

  validate_safe_command "$command"

  if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "ERROR: tmux session '${SESSION_NAME}' does not exist. Start it with scripts/start-session.sh first." >&2
    exit 1
  fi

  target="${SESSION_NAME}:0.${pane_idx}"
  if ! tmux display-message -p -t "$target" '#{pane_id}' >/dev/null 2>&1; then
    echo "ERROR: tmux pane target does not exist: ${target}" >&2
    exit 1
  fi

  sentinel="# AGENT_DONE_SIGNAL: ${task_id}"
  tmux send-keys -t "$target" "${command}; echo '${sentinel}'" Enter

  if [ "$wait_mode" = "true" ]; then
    wait_for_sentinel "$target" "$sentinel" "$timeout_seconds"
  fi
}

main "$@"
