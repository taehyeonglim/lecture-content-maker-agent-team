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
  output_log="/tmp/lecture-team-output-${task_id}.log"
  rm -f "$sentinel_file" "$output_log" || true

  # task_id 패턴(task-<chapter>-<role>)에서 chapter_id 추출 — director 외 워커는 task-chapter-NN-role 형식
  local chapter_id=""
  if [[ "$task_id" =~ ^task-(chapter-[0-9]+)-(decomposer|composer|designer|developer)$ ]]; then
    chapter_id="${BASH_REMATCH[1]}"
  fi

  # director 호출은 usage 추적 제외(자기 자신은 외부 codex 호출 없음). 워커만 wrap.
  local wrapped_command
  if [ -n "$chapter_id" ] && [ "$pane_name" != "director" ]; then
    # bash 안에서 단일 따옴표는 esc 까다로움 → printf %q 로 안전하게 인자 quote
    local proj_root_q chapter_q role_q log_q sentinel_q
    proj_root_q="$(printf %q "$PWD")"
    chapter_q="$(printf %q "$chapter_id")"
    role_q="$(printf %q "$pane_name")"
    log_q="$(printf %q "$output_log")"
    sentinel_q="$(printf %q "$sentinel_file")"
    # T0/T1: 호출 duration 측정
    # 2>&1 | tee: stdout+stderr 모두 capture 하면서 화면에도 표시
    # record-usage 실패해도 sentinel 은 계속 진행 (|| true)
    wrapped_command="cd ${proj_root_q}; T0=\$(date +%s); { ${command}; } 2>&1 | tee ${log_q}; T1=\$(date +%s); bash scripts/record-usage.sh ${chapter_q} ${role_q} ${log_q} \$((T1-T0)) || true; touch ${sentinel_q}; echo '${sentinel}'"
  else
    wrapped_command="${command}; touch '${sentinel_file}'; echo '${sentinel}'"
  fi

  tmux send-keys -t "$target" "$wrapped_command" Enter

  if [ "$wait_mode" = "true" ]; then
    wait_for_sentinel_file "$sentinel_file" "$timeout_seconds"
  fi
}

main "$@"
