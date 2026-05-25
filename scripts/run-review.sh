#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: bash scripts/run-review.sh <chapter_id> <role> [target_file]" >&2
  echo "role: composer | designer | developer" >&2
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required dependency: $1" >&2
    exit 1
  fi
}

default_target_file() {
  case "$1" in
    composer) echo "content/chapters/${CHAPTER_ID}/composed.md" ;;
    designer) echo "content/chapters/${CHAPTER_ID}/DESIGN.md" ;;
    developer) echo "content/chapters/${CHAPTER_ID}/slides/deck.html" ;;
    *) return 1 ;;
  esac
}

round_criteria() {
  case "$1" in
    1) echo "오탈자, 문법, 한국어 자연스러움" ;;
    2) echo "내용 정확성, 인용 출처, 사실 오류" ;;
    3)
      if [[ "$ROLE" == "designer" ]]; then
        echo "일관성, 학습 흐름, Mayer 원리, 모든 Asset license 필드 batch 점검 및 PI 확인 트리거"
      else
        echo "일관성, 학습 흐름, Mayer 원리"
      fi
      ;;
    *) return 1 ;;
  esac
}

prompt_text_for_round() {
  local round="$1"
  local prompt_file="prompts/reviewer/round-${round}.md"

  if [[ -f "$prompt_file" ]]; then
    cat "$prompt_file"
    return
  fi

  echo "Reviewer prompt missing: ${prompt_file}. Using built-in placeholder." >&2
  cat <<EOF
당신은 lecture-content-maker-agent-team의 reviewer입니다.
모델/effort 규칙: gpt-5.5 xhigh 검수 전용.
검수 대상 role: ${ROLE}
검수 라운드: ${round}
검수 기준: $(round_criteria "$round")

대상 산출물을 검토하고, 필요한 경우 unified diff와 issues 목록을 작성하세요.
반드시 마지막에 아래 JSON 객체를 단독으로 출력하세요.
{"issues_count": 0, "issues": [], "summary": "통과 또는 주요 이슈 요약"}

issues_count는 issues 배열 길이와 일치해야 합니다.
EOF
}

parse_number() {
  tr -cd '0-9'
}

parse_issues_count() {
  local output_file="$1"
  local issues_count=""

  if issues_count="$(jq -er 'if type == "object" and has("issues_count") then .issues_count else empty end' "$output_file" 2>/dev/null)"; then
    echo "$issues_count"
    return
  fi

  issues_count="$(grep -Eo '"issues_count"[[:space:]]*:[[:space:]]*[0-9]+' "$output_file" 2>/dev/null | tail -n 1 | parse_number || true)"
  if [[ -n "$issues_count" ]]; then
    echo "$issues_count"
    return
  fi

  issues_count="$(grep -Eo 'issues_count[[:space:]]*[=:][[:space:]]*[0-9]+' "$output_file" 2>/dev/null | tail -n 1 | parse_number || true)"
  if [[ -n "$issues_count" ]]; then
    echo "$issues_count"
    return
  fi

  echo "Unable to parse issues_count from ${output_file}; treating as 1." >&2
  echo "1"
}

parse_token_value() {
  local label="$1"
  local output_file="$2"
  local value=""

  value="$(grep -Eio "${label}[[:space:]_-]*tokens?[[:space:]]*[:=][[:space:]]*[0-9,]+" "$output_file" 2>/dev/null | tail -n 1 | grep -Eo '[0-9,]+' | tail -n 1 | tr -d ',' || true)"
  if [[ -n "$value" ]]; then
    echo "$value"
    return
  fi

  value="$(grep -Eio "${label}[[:space:]]*[:=][[:space:]]*[0-9,]+" "$output_file" 2>/dev/null | tail -n 1 | grep -Eo '[0-9,]+' | tail -n 1 | tr -d ',' || true)"
  echo "${value:-0}"
}

parse_total_tokens() {
  local output_file="$1"
  local value=""

  value="$(grep -Eio 'tokens used[[:space:]]*[:=][[:space:]]*[0-9,]+' "$output_file" 2>/dev/null | tail -n 1 | grep -Eo '[0-9,]+' | tail -n 1 | tr -d ',' || true)"
  echo "${value:-0}"
}

calculate_cost_usd() {
  local input_tokens="$1"
  local output_tokens="$2"
  local input_rate="${GPT55_XHIGH_INPUT_USD_PER_1M:-0}"
  local output_rate="${GPT55_XHIGH_OUTPUT_USD_PER_1M:-0}"

  jq -nr \
    --argjson input_tokens "$input_tokens" \
    --argjson output_tokens "$output_tokens" \
    --argjson input_rate "$input_rate" \
    --argjson output_rate "$output_rate" \
    '((($input_tokens * $input_rate) + ($output_tokens * $output_rate)) / 1000000)'
}

ensure_state_json() {
  if [[ -f "$STATE_FILE" ]]; then
    return
  fi

  local tmp_file
  tmp_file="$(mktemp "${STATE_FILE}.tmp.XXXXXX")"
  jq -n \
    --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    '{cumulative_cost_usd: 0, chapters: [], updated_at: $ts}' >"$tmp_file"
  mv "$tmp_file" "$STATE_FILE"
}

update_state_cost() {
  local cost_usd="$1"
  local tmp_file
  tmp_file="$(mktemp "${STATE_FILE}.tmp.XXXXXX")"

  ensure_state_json
  jq \
    --arg chapter "$CHAPTER_ID" \
    --arg role "$ROLE" \
    --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --argjson cost "$cost_usd" \
    '
    .chapters = (.chapters // [])
    | if any(.chapters[]?; .id == $chapter) then . else .chapters += [{id: $chapter, tasks: []}] end
    | .chapters = (.chapters | map(
        if .id == $chapter then
          .tasks = (.tasks // [])
          | if any(.tasks[]?; .role == $role) then
              .tasks = (.tasks | map(if .role == $role then .cost_usd = ((.cost_usd // 0) + $cost) else . end))
            else
              .tasks += [{role: $role, cost_usd: $cost}]
            end
        else
          .
        end
      ))
    | .cumulative_cost_usd = ((.cumulative_cost_usd // 0) + $cost)
    | .updated_at = $ts
    ' "$STATE_FILE" >"$tmp_file"
  mv "$tmp_file" "$STATE_FILE"
}

update_state_manual_override() {
  local reason="$1"
  local tmp_file
  tmp_file="$(mktemp "${STATE_FILE}.tmp.XXXXXX")"

  ensure_state_json
  jq \
    --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg reason "$reason" \
    '.manual_override = true | .manual_override_reason = $reason | .updated_at = $ts' \
    "$STATE_FILE" >"$tmp_file"
  mv "$tmp_file" "$STATE_FILE"
}

record_usage_from_output() {
  # reviewer 호출의 토큰 + duration + USD를 record-usage.sh로 STATE.json에 누적.
  # reviewer 는 항상 codex gpt-5.5 xhigh effort 이므로 모델은 gpt-5.5 로 고정.
  local output_file="$1"
  local duration_sec="${2:-0}"
  bash scripts/record-usage.sh "$CHAPTER_ID" "reviewer" "$output_file" "$duration_sec" "gpt-5.5" || true
}

run_codex_with_retry() {
  local round="$1"
  local output_file="$2"
  local prompt_text target_text payload
  local delays=(1 10 100)
  local attempt

  prompt_text="$(prompt_text_for_round "$round")"
  target_text="$(cat "$TARGET_FILE")"
  payload="${prompt_text}"$'\n\n'"${target_text}"

  for attempt in 1 2 3; do
    if codex exec --model gpt-5.5 \
      -c model_reasoning_effort=xhigh \
      -c sandbox_mode="workspace-write" \
      "$payload" >"$output_file" 2>&1; then
      return 0
    fi

    echo "codex exec failed for round ${round}, attempt ${attempt}/3." >&2
    if [[ "$attempt" -lt 3 ]]; then
      sleep "${delays[$((attempt - 1))]}"
    fi
  done

  return 1
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
  usage
  exit 1
fi

require_command codex
require_command jq

CHAPTER_ID="$1"
ROLE="$2"
STATE_FILE="STATE.json"

case "$ROLE" in
  composer | designer | developer) ;;
  *)
    usage
    exit 1
    ;;
esac

TARGET_FILE="${3:-$(default_target_file "$ROLE")}"
if [[ ! -f "$TARGET_FILE" ]]; then
  echo "Target file not found: ${TARGET_FILE}" >&2
  exit 1
fi

REVIEW_DIR="content/chapters/${CHAPTER_ID}/reviews"
mkdir -p "$REVIEW_DIR"

for round in 1 2 3; do
  output_file="${REVIEW_DIR}/${ROLE}-round-${round}.md"

  T0_REVIEW=$(date +%s)
  if ! run_codex_with_retry "$round" "$output_file"; then
    update_state_manual_override "reviewer codex exec failed after 3 attempts: ${ROLE} round ${round}"
    exit 2
  fi
  T1_REVIEW=$(date +%s)

  record_usage_from_output "$output_file" "$((T1_REVIEW - T0_REVIEW))"

  issues_count="$(parse_issues_count "$output_file")"
  if [[ "$issues_count" == "0" ]]; then
    exit 0
  fi
done

update_state_manual_override "review did not pass after round 3: ${ROLE}"
exit 2
