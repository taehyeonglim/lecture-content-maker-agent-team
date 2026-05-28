#!/usr/bin/env bash
# scripts/update-state.sh — STATE.json atomic update 헬퍼
#
# 사용: bash scripts/update-state.sh <chapter> <role> <round_or_status> <status_or_msg> [<msg>]
#
# 두 가지 호출 패턴:
#   (a) round 갱신: bash scripts/update-state.sh chapter-01 visual-reviewer 1 issues_count=2 auto_fixed=true
#   (b) status 갱신: bash scripts/update-state.sh chapter-01 visual-reviewer done|failed [error_message]
#
# round 갱신은 .chapters[].tasks[] 의 visual-reviewer task 의 rounds[] 배열에 append.
# status 갱신은 task 의 status 와 error_message 만 변경.

set -euo pipefail

CHAPTER="$1"
ROLE="$2"
MODE_OR_ROUND="$3"
TASK_ID="task-${CHAPTER}-${ROLE}"

if [[ "$MODE_OR_ROUND" == "done" || "$MODE_OR_ROUND" == "failed" || "$MODE_OR_ROUND" == "running" ]]; then
  # status 갱신 모드
  STATUS="$MODE_OR_ROUND"
  ERROR_MSG="${4:-}"
  TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  jq --arg cid "$CHAPTER" \
     --arg tid "$TASK_ID" \
     --arg role "$ROLE" \
     --arg status "$STATUS" \
     --arg err "$ERROR_MSG" \
     --arg ts "$TS" \
     '.chapters |= map(
       if .id == $cid then
         .tasks = (
           ((.tasks // []) | map(select(.id != $tid))) +
           [{
             id: $tid,
             chapter: $cid,
             role: $role,
             status: $status,
             error_message: $err,
             rounds: (((.tasks // []) | map(select(.id == $tid))[0].rounds) // []),
             updated_at: $ts
           }]
         )
       else . end
       )
       | .updated_at = $ts' \
     STATE.json > STATE.json.tmp
else
  # round 갱신 모드 — MODE_OR_ROUND は round number
  ROUND="$MODE_OR_ROUND"
  ISSUES_COUNT="${4:-0}"
  AUTO_FIXED="${5:-false}"
  TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  jq --arg cid "$CHAPTER" \
     --arg tid "$TASK_ID" \
     --arg role "$ROLE" \
     --argjson round "$ROUND" \
     --argjson issues "$ISSUES_COUNT" \
     --argjson auto "$AUTO_FIXED" \
     --arg ts "$TS" \
     '.chapters |= map(
       if .id == $cid then
         .tasks = (
           ((.tasks // []) | map(select(.id != $tid))) +
           [{
             id: $tid,
             chapter: $cid,
             role: $role,
             status: ((((.tasks // []) | map(select(.id == $tid))[0].status) // "running")),
             rounds: (
               # 같은 round 번호의 기존 entry 는 제거하고 새 entry 로 교체 (idempotent)
               (((.tasks // []) | map(select(.id == $tid))[0].rounds // [])
                | map(select(.round != $round)))
               + [{round: $round, issues_count: $issues, auto_fixed: $auto, ts: $ts}]
             ),
             updated_at: $ts
           }]
         )
       else . end
       )
       | .updated_at = $ts' \
     STATE.json > STATE.json.tmp
fi

mv STATE.json.tmp STATE.json
echo "  📝 STATE.json: ${TASK_ID} (mode=${MODE_OR_ROUND})" >&2
