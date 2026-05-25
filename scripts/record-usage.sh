#!/usr/bin/env bash
#
# scripts/record-usage.sh — 에이전트 호출 사용량을 STATE.json에 누적 기록
#
# 사용: bash scripts/record-usage.sh <chapter_id> <role> <output_log_file> [<duration_sec>]
#
# 입력 로그에서 토큰 수("tokens used: N")를 파싱하고 호출수 + duration을 STATE.json의
# usage 객체(누적)와 chapter.tasks[].usage(개별)에 atomic write로 반영한다.
#
# STATE.json 스키마 확장 (추가만, 기존 cumulative_cost_usd 등은 보존):
#   top-level:
#     usage: {
#       total_tokens: int,
#       call_count: int,
#       session_started_at: ISO 8601 (최초 호출 시각),
#       last_call_at: ISO 8601
#     }
#   chapters[].tasks[]:
#     usage: {
#       tokens: int,
#       calls: int,
#       first_call_at: ISO 8601,
#       last_call_at: ISO 8601,
#       duration_sec: int (이번 호출 소요)
#     }

set -euo pipefail

STATE_FILE="${STATE_FILE:-STATE.json}"

usage() {
  cat <<EOF >&2
Usage: bash scripts/record-usage.sh <chapter_id> <role> <output_log_file> [<duration_sec>]

Examples:
  bash scripts/record-usage.sh chapter-01 decomposer /tmp/lecture-team-output-task-XXX.log
  bash scripts/record-usage.sh chapter-01 composer /tmp/log.txt 87
EOF
}

if [ "$#" -lt 3 ]; then
  usage
  exit 1
fi

CHAPTER_ID="$1"
ROLE="$2"
LOG_FILE="$3"
DURATION_SEC="${4:-0}"

if [ ! -f "$LOG_FILE" ]; then
  echo "WARN: log file not found: $LOG_FILE — recording 0 tokens" >&2
  TOKENS=0
else
  # codex exec 의 "tokens used: N" 패턴 파싱 (콤마 허용)
  TOKENS="$(grep -Eio 'tokens used[[:space:]]*[:=]?[[:space:]]*[0-9,]+' "$LOG_FILE" 2>/dev/null \
            | tail -n 1 | grep -Eo '[0-9,]+' | tail -n 1 | tr -d ',' || true)"
  TOKENS="${TOKENS:-0}"
fi

NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
TMP="$(mktemp "${STATE_FILE}.tmp.XXXXXX")"

# STATE.json 미존재 시 최소 스키마 생성
if [ ! -f "$STATE_FILE" ]; then
  jq -n --arg ts "$NOW" \
    '{course: "unknown", chapters: [], usage: {total_tokens: 0, call_count: 0, session_started_at: $ts, last_call_at: $ts}, updated_at: $ts}' \
    >"$STATE_FILE"
fi

jq \
  --arg chapter "$CHAPTER_ID" \
  --arg role "$ROLE" \
  --arg ts "$NOW" \
  --argjson tokens "$TOKENS" \
  --argjson duration "$DURATION_SEC" \
  '
  # top-level usage 보장
  .usage = (.usage // {total_tokens: 0, call_count: 0, session_started_at: $ts, last_call_at: $ts})
  | .usage.total_tokens = ((.usage.total_tokens // 0) + $tokens)
  | .usage.call_count = ((.usage.call_count // 0) + 1)
  | .usage.last_call_at = $ts
  | .usage.session_started_at = (.usage.session_started_at // $ts)
  # chapter 단위 task usage 누적 — chapter/role 매칭되는 task만 갱신
  | .chapters = (.chapters // [])
  | .chapters = (.chapters | map(
      if .id == $chapter then
        .tasks = (.tasks // [])
        | .tasks = (.tasks | map(
            if .role == $role then
              .usage = (.usage // {tokens: 0, calls: 0, first_call_at: $ts, last_call_at: $ts, duration_sec: 0})
              | .usage.tokens = ((.usage.tokens // 0) + $tokens)
              | .usage.calls = ((.usage.calls // 0) + 1)
              | .usage.first_call_at = (.usage.first_call_at // $ts)
              | .usage.last_call_at = $ts
              | .usage.duration_sec = $duration
            else . end
          ))
      else . end
    ))
  | .updated_at = $ts
  ' "$STATE_FILE" >"$TMP"

mv "$TMP" "$STATE_FILE"

echo "recorded: chapter=${CHAPTER_ID} role=${ROLE} tokens=${TOKENS} duration=${DURATION_SEC}s" >&2
