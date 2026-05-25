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
Usage: bash scripts/record-usage.sh <chapter_id> <role> <output_log_file> [<duration_sec>] [<model>]

Examples:
  bash scripts/record-usage.sh chapter-01 decomposer /tmp/codex-XXX.log 87 gpt-5.5
  bash scripts/record-usage.sh chapter-01 reviewer /tmp/log.txt 42 gpt-5.5
  bash scripts/record-usage.sh chapter-01 composer /tmp/log.txt   # 모델 미지정 시 USD 0

<model> 가 주어지면 config/pricing.json 으로 USD 환산을 계산해 STATE.json 의
task.cost_usd 와 top-level cumulative_cost_usd 에 누적합니다.
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
MODEL="${5:-}"
PRICING_FILE="${PRICING_FILE:-config/pricing.json}"

if [ ! -f "$LOG_FILE" ]; then
  echo "WARN: log file not found: $LOG_FILE — recording 0 tokens" >&2
  TOKENS=0
else
  # codex exec 의 "tokens used: N" 패턴 파싱 (콤마 허용)
  TOKENS="$(grep -Eio 'tokens used[[:space:]]*[:=]?[[:space:]]*[0-9,]+' "$LOG_FILE" 2>/dev/null \
            | tail -n 1 | grep -Eo '[0-9,]+' | tail -n 1 | tr -d ',' || true)"
  TOKENS="${TOKENS:-0}"
fi

# USD 환산 (model 지정 + pricing.json 존재 시)
COST_USD=0
if [ -n "$MODEL" ] && [ -f "$PRICING_FILE" ] && [ "$TOKENS" != "0" ]; then
  RESOLVED_MODEL="$(jq -r --arg m "$MODEL" '.aliases[$m] // $m' "$PRICING_FILE" 2>/dev/null || echo "$MODEL")"
  IN_RATE="$(jq -r --arg m "$RESOLVED_MODEL" '.models[$m].input_per_1m // 0' "$PRICING_FILE" 2>/dev/null || echo 0)"
  OUT_RATE="$(jq -r --arg m "$RESOLVED_MODEL" '.models[$m].output_per_1m // 0' "$PRICING_FILE" 2>/dev/null || echo 0)"
  RATIO="$(jq -r '.fallback_input_ratio // 0.7' "$PRICING_FILE" 2>/dev/null || echo 0.7)"
  # codex 출력에는 input/output 분리 없음 → blended rate 사용:
  #   blended_per_1m = IN_RATE × ratio + OUT_RATE × (1-ratio)
  #   cost_usd = TOKENS × blended_per_1m / 1_000_000
  COST_USD="$(awk -v t="$TOKENS" -v ir="$IN_RATE" -v or="$OUT_RATE" -v r="$RATIO" \
    'BEGIN { printf "%.6f", t * (ir * r + or * (1 - r)) / 1000000 }')"
fi

NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
TMP="$(mktemp "${STATE_FILE}.tmp.XXXXXX")"

# STATE.json 미존재 시 최소 스키마 생성 (대시보드가 기대하는 모든 키 포함)
if [ ! -f "$STATE_FILE" ]; then
  jq -n --arg ts "$NOW" \
    '{course: "unknown", overall_progress: 0, cumulative_cost_usd: 0,
      usage: {total_tokens: 0, call_count: 0, session_started_at: $ts, last_call_at: $ts},
      chapters: [], active_agents: [], queue: [], recent_events: [], updated_at: $ts}' \
    >"$STATE_FILE"
fi

jq \
  --arg chapter "$CHAPTER_ID" \
  --arg role "$ROLE" \
  --arg ts "$NOW" \
  --argjson tokens "$TOKENS" \
  --argjson duration "$DURATION_SEC" \
  --argjson cost_usd "$COST_USD" \
  --arg model "$MODEL" \
  '
  # top-level usage 보장
  .usage = (.usage // {total_tokens: 0, call_count: 0, session_started_at: $ts, last_call_at: $ts})
  | .usage.total_tokens = ((.usage.total_tokens // 0) + $tokens)
  | .usage.call_count = ((.usage.call_count // 0) + 1)
  | .usage.last_call_at = $ts
  | .usage.session_started_at = (.usage.session_started_at // $ts)
  # 누적 USD (backwards compat 으로 cumulative_cost_usd 필드 재활성화)
  | .cumulative_cost_usd = ((.cumulative_cost_usd // 0) + $cost_usd)
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
              | .cost_usd = ((.cost_usd // 0) + $cost_usd)
              | .last_model = (if $model != "" then $model else .last_model end)
            else . end
          ))
      else . end
    ))
  | .updated_at = $ts
  ' "$STATE_FILE" >"$TMP"

mv "$TMP" "$STATE_FILE"

printf "recorded: chapter=%s role=%s tokens=%s duration=%ss model=%s cost=$%s\n" \
  "$CHAPTER_ID" "$ROLE" "$TOKENS" "$DURATION_SEC" "${MODEL:-—}" "$COST_USD" >&2
