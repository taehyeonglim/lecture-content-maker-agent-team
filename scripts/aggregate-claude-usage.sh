#!/usr/bin/env bash
#
# scripts/aggregate-claude-usage.sh
#
# ~/.claude/projects/<encoded-cwd>/*.jsonl 의 assistant 메시지에서 모델별
# input/cache_creation/cache_read/output 토큰을 집계해 STATE.json 의
# usage.by_model[claude-*] 와 cumulative_cost_usd 에 반영.
#
# - SESSION_START (= STATE.json.usage.session_started_at) 이후의 메시지만 카운트
# - by_model 의 claude-* 키만 replace (codex/gpt-* 키는 보존)
# - idempotent (매 호출이 절대값으로 set 하므로 중복 호출 OK)
# - monitor pane 의 watch loop 에서 5초마다 호출 권장

set -euo pipefail

STATE_FILE="${STATE_FILE:-STATE.json}"
PRICING_FILE="${PRICING_FILE:-config/pricing.json}"

# 프로젝트 경로 인코딩 — 절대 경로의 / 를 - 로 치환 (맨 앞 / 도 자동 변환)
PROJECT_PATH="$(pwd)"
PROJECT_ENC="${PROJECT_PATH//\//-}"
CLAUDE_DIR="$HOME/.claude/projects/$PROJECT_ENC"

if [ ! -d "$CLAUDE_DIR" ]; then
  echo "no claude project dir: $CLAUDE_DIR" >&2
  exit 0
fi

if [ ! -f "$STATE_FILE" ]; then
  echo "STATE.json not found in $(pwd)" >&2
  exit 0
fi

if [ ! -f "$PRICING_FILE" ]; then
  echo "pricing.json not found: $PRICING_FILE" >&2
  exit 0
fi

SESSION_START="$(jq -r '.usage.session_started_at // "1970-01-01T00:00:00Z"' "$STATE_FILE")"

# Step 1: 모든 .jsonl 에서 assistant 메시지의 model + usage 추출, 모델별 집계
# (jq -s 로 모든 input 을 한 array 로)
CLAUDE_AGG="$(
  cat "$CLAUDE_DIR"/*.jsonl 2>/dev/null \
  | jq -c -s --arg start "$SESSION_START" '
      [.[]
        | select(.type == "assistant"
                 and .message.usage
                 and (.timestamp // "") >= $start)]
      | group_by(.message.model)
      | map({
          model: .[0].message.model,
          input:   (map(.message.usage.input_tokens // 0)               | add),
          cache_c: (map(.message.usage.cache_creation_input_tokens // 0)| add),
          cache_r: (map(.message.usage.cache_read_input_tokens // 0)    | add),
          output:  (map(.message.usage.output_tokens // 0)              | add),
          calls:   length,
          last_call_at: (map(.timestamp) | max)
        })
    '
)"

if [ -z "$CLAUDE_AGG" ] || [ "$CLAUDE_AGG" = "null" ] || [ "$CLAUDE_AGG" = "[]" ]; then
  echo "no claude assistant messages since $SESSION_START" >&2
  exit 0
fi

# Step 2: pricing 로딩 + 모델별 cost 계산 + STATE.json 머지 (atomic)
TMP="$(mktemp "${STATE_FILE}.tmp.XXXXXX")"
NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

jq --argjson agg "$CLAUDE_AGG" \
   --slurpfile pricing "$PRICING_FILE" \
   --arg ts "$NOW" '
   ($pricing[0]) as $p
   # 모델별 객체 {model: {tokens, calls, cost_usd, last_call_at, breakdown}}
   | ($agg | map({
       key: .model,
       value: (
         # alias 해석
         (($p.aliases[.model] // .model)) as $resolved
         | (($p.models[$resolved] // {})) as $rates
         | (($rates.input_per_1m // 0) * .input          / 1000000) as $c_in
         | (($rates.cache_creation_per_1m
             // (($rates.input_per_1m // 0) * 1.25))    * .cache_c / 1000000) as $c_cc
         | (($rates.cached_input_per_1m
             // (($rates.input_per_1m // 0) * 0.1))     * .cache_r / 1000000) as $c_cr
         | (($rates.output_per_1m // 0) * .output       / 1000000) as $c_out
         | {
             tokens:  (.input + .cache_c + .cache_r + .output),
             calls:   .calls,
             cost_usd: ($c_in + $c_cc + $c_cr + $c_out),
             last_call_at: .last_call_at,
             breakdown: {
               input: .input,
               cache_creation: .cache_c,
               cache_read: .cache_r,
               output: .output
             }
           }
       )
     }) | from_entries) as $claude_models
   # 기존 by_model 에서 claude-* 외 키만 유지
   | (.usage.by_model // {}) as $cur
   | ($cur | with_entries(select(.key | startswith("claude-") | not))) as $non_claude
   | ($non_claude + $claude_models) as $merged
   | .usage.by_model = $merged
   | .usage.total_tokens = ($merged | to_entries | map(.value.tokens // 0) | add // 0)
   | .usage.call_count   = ($merged | to_entries | map(.value.calls // 0) | add // 0)
   | .cumulative_cost_usd = ($merged | to_entries | map(.value.cost_usd // 0) | add // 0)
   | .usage.last_call_at = $ts
   | .updated_at = $ts
' "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"

# 요약 출력
echo "$CLAUDE_AGG" | jq -r 'map("\(.model): \(.calls)c \(.input + .cache_c + .cache_r + .output)t") | join(", ") | "claude-aggregate: \(.)"' >&2
