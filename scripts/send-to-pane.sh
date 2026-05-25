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

pane_id_for() {
  local title="$1"
  case "$title" in
    director|decomposer|composer|designer|developer) ;;
    *) return 1 ;;
  esac
  tmux list-panes -t "$SESSION_NAME" -a -F '#{pane_id}' \
    -f "#{==:#{pane_title},${title}}" | head -n1
}

validate_safe_command() {
  if printf '%s\n' "$1" | grep -qiE 'password|secret|token=|api[_-]?key=|refresh[_-]?token='; then
    echo "ERROR: command appears to contain a plaintext password, secret, or token. Refusing to send it through tmux." >&2
    return 1
  fi
}

wait_for_sentinel_file() {
  local sentinel_file="$1"
  local timeout_seconds="$2"
  local start_ts
  local now_ts

  start_ts="$(date +%s)"

  while true; do
    if [ -f "$sentinel_file" ]; then
      return 0
    fi

    now_ts="$(date +%s)"
    if [ "$((now_ts - start_ts))" -ge "$timeout_seconds" ]; then
      echo "ERROR: timed out after ${timeout_seconds}s waiting for sentinel file: ${sentinel_file}" >&2
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

  validate_safe_command "$command"

  if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "ERROR: tmux session '${SESSION_NAME}' does not exist. Start it with scripts/start-session.sh first." >&2
    exit 1
  fi

  if ! target="$(pane_id_for "$pane_name")" || [ -z "$target" ]; then
    echo "ERROR: tmux pane with title '${pane_name}' not found in session '${SESSION_NAME}'." >&2
    echo "Hint: start-session.sh sets pane titles via 'tmux select-pane -T'. Verify titles with: tmux list-panes -t ${SESSION_NAME} -a -F '#{pane_title}'" >&2
    exit 1
  fi

  sentinel="# AGENT_DONE_SIGNAL: ${task_id}"
  sentinel_file="/tmp/lecture-team-sentinel-${task_id}.done"
  rm -f "$sentinel_file" || true

  # 모든 워커 pane은 interactive `claude` (Claude Code Sonnet) 세션이다.
  # send-keys 로 prompt 텍스트를 Claude UI에 paste 한다 (shell 명령 실행 아님).
  # multi-line prompt 안정 전달을 위해 tmux paste-buffer 사용.
  #
  # Claude Code 워커가 작업 끝에 `touch <sentinel_file>` 을 실행해야 sentinel 감지가 작동한다.
  # director의 prompt 작성 시 이를 명시해야 하지만, 누락 방지를 위해 안전망으로 prompt 끝에
  # sentinel touch 지시를 자동 append 한다.
  local prompt_with_sentinel
  prompt_with_sentinel="${command}

작업 완료 시 마지막 단계로 다음 Bash 명령을 반드시 실행:
  touch ${sentinel_file}
(이 sentinel 파일 생성이 director의 완료 감지 신호다.)"

  local buffer_name="lcm-${task_id}"
  tmux set-buffer -b "$buffer_name" -- "$prompt_with_sentinel"
  tmux paste-buffer -t "$target" -b "$buffer_name"
  tmux send-keys -t "$target" Enter
  tmux delete-buffer -b "$buffer_name" 2>/dev/null || true

  if [ "$wait_mode" = "true" ]; then
    wait_for_sentinel_file "$sentinel_file" "$timeout_seconds"
  fi
}

main "$@"
