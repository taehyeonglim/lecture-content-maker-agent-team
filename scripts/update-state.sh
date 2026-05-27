#!/usr/bin/env bash
# scripts/update-state.sh — STATE.json atomic update 헬퍼
#
# 사용: bash scripts/update-state.sh <chapter> <role> <status> <error_message>

set -euo pipefail

CHAPTER="$1"
ROLE="$2"
STATUS="$3"
ERROR_MSG="${4:-}"

TASK_ID="task-${CHAPTER}-${ROLE}"

jq --arg cid "$CHAPTER" \
   --arg tid "$TASK_ID" \
   --arg role "$ROLE" \
   --arg status "$STATUS" \
   --arg err "$ERROR_MSG" \
   --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '.tasks |= (map(select(.id != $tid)) + [{
      id: $tid,
      chapter: $cid,
      role: $role,
      status: $status,
      error_message: $err,
      updated_at: $ts
    }])
    | .updated_at = $ts' \
   STATE.json > STATE.json.tmp

mv STATE.json.tmp STATE.json
echo "  📝 STATE.json: ${TASK_ID} → ${STATUS}" >&2
