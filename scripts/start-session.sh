#!/usr/bin/env bash
set -euo pipefail

SESSION_NAME="lecture-team"
DASHBOARD_PORT="${DASHBOARD_PORT:-8080}"

if [[ -f .env ]]; then
  set -a; source .env; set +a
fi

usage() {
  echo "Usage: bash scripts/start-session.sh <chapter_id>" >&2
  echo "Example: bash scripts/start-session.sh chapter-01" >&2
}

die() {
  echo "Error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed. Please install $1 and retry."
}

shell_quote() {
  printf "'%s'" "$(printf "%s" "$1" | sed "s/'/'\\\\''/g")"
}

utc_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

chapter_num() {
  if [[ "$1" =~ ^chapter-[0-9]+$ ]]; then
    printf "%d" "$((10#${1#chapter-}))"
    return 0
  fi

  printf "0"
}

init_state() {
  local chapter_id="$1"
  local now="$2"
  local tmp_path="STATE.json.tmp"

  jq -n \
    --arg course "교육방법및교육공학 2026-2" \
    --arg chapter_id "$chapter_id" \
    --arg title "교육방법 및 교육공학 도입/개관" \
    --arg source_path "Previous_lecture_content/2026-1 교육방법및교육공학/[2026-1]교육방법및교육공학_1주차.gslides" \
    --arg now "$now" \
    --argjson chapter_num "$(chapter_num "$chapter_id")" \
    '{
      course: $course,
      overall_progress: 0,
      cumulative_cost_usd: 0,
      usage: {
        total_tokens: 0,
        call_count: 0,
        session_started_at: $now,
        last_call_at: $now
      },
      chapters: [
        {
          id: $chapter_id,
          num: $chapter_num,
          title: $title,
          status: "planned",
          source_paths: [$source_path],
          target_audience: "교직과목 수강 학부생",
          learning_objectives: [],
          created_at: $now,
          updated_at: $now,
          tasks: [
            {
              id: ("task-" + $chapter_id + "-decomposer"),
              chapter_id: $chapter_id,
              role: "decomposer",
              model: "gpt-5.5-medium",
              status: "queued",
              input_paths: [$source_path],
              output_path: ("content/chapters/" + $chapter_id + "/decomposed.md"),
              started_at: null,
              finished_at: null,
              retry_count: 0,
              reviews_passed: 0,
              cost_usd: 0,
              error_message: null
            },
            {
              id: ("task-" + $chapter_id + "-composer"),
              chapter_id: $chapter_id,
              role: "composer",
              model: "gpt-5.5-high",
              status: "queued",
              input_paths: [
                ("content/chapters/" + $chapter_id + "/decomposed.md"),
                "Previous_lecture_content/목차_학지사_교육방법및교육공학.hwp"
              ],
              output_path: ("content/chapters/" + $chapter_id + "/composed.md"),
              started_at: null,
              finished_at: null,
              retry_count: 0,
              reviews_passed: 0,
              cost_usd: 0,
              error_message: null
            },
            {
              id: ("task-" + $chapter_id + "-designer"),
              chapter_id: $chapter_id,
              role: "designer",
              model: "sonnet-latest",
              status: "queued",
              input_paths: [("content/chapters/" + $chapter_id + "/composed.md")],
              output_path: ("content/chapters/" + $chapter_id + "/DESIGN.md"),
              started_at: null,
              finished_at: null,
              retry_count: 0,
              reviews_passed: 0,
              cost_usd: 0,
              error_message: null
            },
            {
              id: ("task-" + $chapter_id + "-developer"),
              chapter_id: $chapter_id,
              role: "developer",
              model: "sonnet-latest",
              status: "queued",
              input_paths: [
                ("content/chapters/" + $chapter_id + "/DESIGN.md"),
                ("content/chapters/" + $chapter_id + "/composed.md"),
                ("content/chapters/" + $chapter_id + "/images/")
              ],
              output_path: ("content/chapters/" + $chapter_id + "/slides/deck.html"),
              started_at: null,
              finished_at: null,
              retry_count: 0,
              reviews_passed: 0,
              cost_usd: 0,
              error_message: null
            }
          ]
        }
      ],
      active_agents: [],
      queue: [
        ("task-" + $chapter_id + "-decomposer"),
        ("task-" + $chapter_id + "-composer"),
        ("task-" + $chapter_id + "-designer"),
        ("task-" + $chapter_id + "-developer")
      ],
      recent_events: [
        {
          ts: $now,
          agent: "system",
          action: "initialized",
          chapter: $chapter_id
        }
      ],
      updated_at: $now
    }' > "$tmp_path"
  mv "$tmp_path" STATE.json
}

resume_message() {
  local chapter_id="$1"

  jq -r --arg chapter_id "$chapter_id" '
    [.chapters[]? | select(.id == $chapter_id) | .tasks[]? |
      select(.status == "in_progress" or .status == "running")] |
    last |
    if . == null then
      "STATE.json exists. No in_progress task found; director should inspect queue and task statuses."
    else
      "STATE.json exists. Resume from " + (.role // "unknown") + " (" + (.id // "unknown-task") + ")."
    end
  ' STATE.json
}

port_is_free() {
  python3 - "$1" <<'PY'
import socket
import sys

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
try:
    sock.bind(("127.0.0.1", int(sys.argv[1])))
except OSError:
    sys.exit(1)
finally:
    sock.close()
PY
}

start_dashboard() {
  if [[ ! -d dashboard ]]; then
    echo "Dashboard directory not found; server was not started."
    return 0
  fi

  # 실제 응답 가능한지 검증(TIME_WAIT 상태의 socket이 port_is_free에서 잘못 감지될 수 있음)
  local existing_status
  existing_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 1 "http://127.0.0.1:${DASHBOARD_PORT}/dashboard/" 2>/dev/null || echo "000")
  if [ "$existing_status" = "200" ]; then
    echo "Dashboard server already running on http://127.0.0.1:${DASHBOARD_PORT}/dashboard/"
    return 0
  fi
  # 안 떠 있으면 (port_is_free 판단과 무관하게) 시작
  if ! port_is_free "$DASHBOARD_PORT"; then
    # socket이 점유 상태로 보이지만 응답 없음 → 잔여 프로세스 정리 시도
    pkill -f "http.server.*${DASHBOARD_PORT}" 2>/dev/null || true
    sleep 1
  fi
  nohup python3 -m http.server -d . "$DASHBOARD_PORT" >/dev/null 2>&1 &
  echo "Dashboard server started on http://127.0.0.1:${DASHBOARD_PORT}/dashboard/"
}

send_bootstrap() {
  # 워커 pane은 interactive Claude Code (sonnet) 세션을 부팅한다.
  # director가 send-keys로 자연어 prompt를 주입하면 그 Claude Code가 작업을 수행한다.
  # bare shell 아님 — 모든 워커는 Claude Code interactive UI 상태로 대기.
  local pane_id="$1"
  local role="$2"
  local root_quoted="$3"

  # 셸 셋업 후 claude 부팅. claude 가 interactive UI를 띄우고 prompt 입력 대기 상태가 된다.
  tmux send-keys -t "$pane_id" "cd ${root_quoted}; if [ -f .env ]; then set -a; source .env; set +a; fi; clear; printf '%s\n' '[${role}] booting Claude Code (sonnet)...'; claude" C-m
}

create_session() {
  local chapter_id="$1"
  local root_dir="$2"
  local root_quoted="$3"
  local resume_note="$4"
  local window_id
  local director_pane
  local decomposer_pane
  local composer_pane
  local designer_pane
  local developer_pane
  local monitor_pane
  local director_message_quoted
  local resume_note_quoted

  tmux new-session -d -x 180 -y 48 -s "$SESSION_NAME" -n "$chapter_id" -c "$root_dir"
  window_id="$(tmux display-message -p -t "$SESSION_NAME" '#{window_id}')"
  director_pane="$(tmux display-message -p -t "$window_id" '#{pane_id}')"
  tmux set-option -t "$SESSION_NAME" pane-border-status top >/dev/null

  decomposer_pane="$(tmux split-window -h -p 38 -t "$director_pane" -P -F '#{pane_id}' -c "$root_dir")"
  composer_pane="$(tmux split-window -v -p 80 -t "$decomposer_pane" -P -F '#{pane_id}' -c "$root_dir")"
  designer_pane="$(tmux split-window -v -p 75 -t "$composer_pane" -P -F '#{pane_id}' -c "$root_dir")"
  developer_pane="$(tmux split-window -v -p 67 -t "$designer_pane" -P -F '#{pane_id}' -c "$root_dir")"
  monitor_pane="$(tmux split-window -v -p 50 -t "$developer_pane" -P -F '#{pane_id}' -c "$root_dir")"

  # 시각용 title (Claude Code 부팅 시 "✳ Claude Code"로 덮어써질 수 있음)
  tmux select-pane -t "$director_pane" -T "director"
  tmux select-pane -t "$decomposer_pane" -T "decomposer"
  tmux select-pane -t "$composer_pane" -T "composer"
  tmux select-pane -t "$designer_pane" -T "designer"
  tmux select-pane -t "$developer_pane" -T "developer"
  tmux select-pane -t "$monitor_pane" -T "STATE.json watch"

  # 안정적 lookup용 pane-specific 사용자 옵션 (@role) — Claude Code 의 title 변경에 영향받지 않음
  tmux set-option -p -t "$director_pane" '@role' 'director'
  tmux set-option -p -t "$decomposer_pane" '@role' 'decomposer'
  tmux set-option -p -t "$composer_pane" '@role' 'composer'
  tmux set-option -p -t "$designer_pane" '@role' 'designer'
  tmux set-option -p -t "$developer_pane" '@role' 'developer'
  tmux set-option -p -t "$monitor_pane" '@role' 'monitor'

  director_message_quoted="$(shell_quote "${chapter_id} 처리 시작 — STATE.json 확인 후 다음 작업을 진행하세요.")"
  resume_note_quoted="$(shell_quote "$resume_note")"
  tmux send-keys -t "$director_pane" "cd ${root_quoted}; if [ -f .env ]; then set -a; source .env; set +a; fi; clear; printf '%s\n' ${director_message_quoted}; printf '%s\n' ${resume_note_quoted}" C-m
  send_bootstrap "$decomposer_pane" "decomposer" "$root_quoted"
  send_bootstrap "$composer_pane" "composer" "$root_quoted"
  send_bootstrap "$designer_pane" "designer" "$root_quoted"
  send_bootstrap "$developer_pane" "developer" "$root_quoted"
  tmux send-keys -t "$monitor_pane" "cd ${root_quoted}; while true; do clear; date; if [ -f STATE.json ]; then jq . STATE.json; else echo 'STATE.json not found'; fi; sleep 5; done" C-m
  tmux select-pane -t "$director_pane"
}

if [[ "$#" -lt 1 || -z "${1:-}" ]]; then
  usage
  exit 1
fi

CHAPTER_ID="$1"
PROJECT_ROOT="$(pwd)"

[[ -f PRD/01_PRD.md && -f PRD/03_PHASES.md && -f PRD/04_PROJECT_SPEC.md && -f spike/RESULTS.md ]] || \
  die "current directory must be the lecture-content-maker-agent-team project root"

require_command tmux
require_command jq
require_command python3

if [[ ! -f STATE.json ]]; then
  init_state "$CHAPTER_ID" "$(utc_now)"
  RESUME_NOTE="STATE.json initialized with queued decomposer, composer, designer, and developer tasks."
else
  RESUME_NOTE="$(resume_message "$CHAPTER_ID")"
fi

DASHBOARD_STATUS="$(start_dashboard)"
ROOT_QUOTED="$(shell_quote "$PROJECT_ROOT")"

if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  echo "$DASHBOARD_STATUS"
  echo "Dashboard URL: http://127.0.0.1:${DASHBOARD_PORT}/dashboard/"
  echo "Existing tmux session found. Attaching: tmux attach -t ${SESSION_NAME}"
  if [[ -t 1 ]]; then
    exec tmux attach-session -t "$SESSION_NAME"
  fi
  exit 0
fi

create_session "$CHAPTER_ID" "$PROJECT_ROOT" "$ROOT_QUOTED" "$RESUME_NOTE"

echo "$DASHBOARD_STATUS"
echo "$RESUME_NOTE"
echo "Dashboard URL: http://127.0.0.1:${DASHBOARD_PORT}/dashboard/"
echo "Tmux attach: tmux attach -t ${SESSION_NAME}"
