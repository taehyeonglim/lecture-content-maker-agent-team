#!/usr/bin/env bash
# scripts/run-visual-review.sh — visual-reviewer loop (max 3 round + rollback)
#
# 사용: bash scripts/run-visual-review.sh <chapter_id>
#
# director 가 developer sentinel 감지 후 호출.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: bash scripts/run-visual-review.sh <chapter_id>" >&2
  exit 2
fi

CHAPTER="$1"
DECK="content/chapters/${CHAPTER}/slides/deck.html"
MAX_ROUND=3
PREV_ISSUES=99   # 초기값 (큰 수)

if [[ ! -f "$DECK" ]]; then
  echo "deck.html not found: $DECK" >&2
  exit 1
fi

echo "🔍 visual-review: ${CHAPTER} (max ${MAX_ROUND} round)" >&2

for ROUND in $(seq 1 $MAX_ROUND); do
  echo "" >&2
  echo "━━━ Round ${ROUND} ━━━" >&2

  # rollback snapshot
  cp "$DECK" "${DECK}.before-round-${ROUND}"

  # 1. PNG 캡처
  if ! bash scripts/capture-deck.sh "$CHAPTER" "$ROUND" >&2; then
    echo "  ✗ capture failed" >&2
    bash scripts/update-state.sh "$CHAPTER" visual-reviewer failed "capture-deck.sh failed"
    exit 1
  fi

  # 2. visual-reviewer 호출 (sentinel 폴링은 send-to-pane.sh 가 처리)
  TASK_ID="task-${CHAPTER}-visual-reviewer-round-${ROUND}"
  PROMPT="@.claude/agents/visual-reviewer.md

Task: ${CHAPTER} round ${ROUND} 시각 검수.

PNG 경로: $PWD/content/chapters/${CHAPTER}/visual-review/round-${ROUND}/slide-{00..18}.png
DESIGN.md: $PWD/content/chapters/${CHAPTER}/DESIGN.md
출력: 같은 round 폴더에 eval.json + fix.patch (auto_apply 가능한 issue 만)

종료 시: touch /tmp/lecture-team-sentinel-${TASK_ID}.done"

  if ! bash scripts/send-to-pane.sh --wait visual-reviewer "$TASK_ID" "$PROMPT"; then
    echo "  ✗ visual-reviewer 호출 실패" >&2
    bash scripts/update-state.sh "$CHAPTER" visual-reviewer failed "send-to-pane.sh failed"
    exit 1
  fi

  EVAL="content/chapters/${CHAPTER}/visual-review/round-${ROUND}/eval.json"
  if [[ ! -f "$EVAL" ]]; then
    echo "  ✗ eval.json 없음 (visual-reviewer 출력 실패)" >&2
    bash scripts/update-state.sh "$CHAPTER" visual-reviewer failed "eval.json missing"
    exit 1
  fi

  ISSUES=$(jq -r '.issues_count' "$EVAL")
  echo "  📋 issues_count: ${ISSUES}" >&2

  # Round 통계를 STATE.json 의 rounds[] 에 append
  AUTO_FIXED_FLAG="false"
  bash scripts/update-state.sh "$CHAPTER" visual-reviewer "$ROUND" "$ISSUES" "$AUTO_FIXED_FLAG"

  # 3-a. 통과
  if [[ "$ISSUES" -eq 0 ]]; then
    echo "✅ visual-review 통과 (round ${ROUND})" >&2
    bash scripts/update-state.sh "$CHAPTER" visual-reviewer done ""
    # snapshot cleanup
    rm -f "${DECK}.before-round-"*
    exit 0
  fi

  # 3-b. 회귀 감지 (issues 가 늘어남)
  if [[ "$ISSUES" -gt "$PREV_ISSUES" ]]; then
    echo "⚠ 회귀 감지 (${PREV_ISSUES} → ${ISSUES}). rollback." >&2
    # 가장 issues 적은 round 의 backup 복구
    cp "${DECK}.before-round-1" "$DECK"
    bash scripts/update-state.sh "$CHAPTER" visual-reviewer failed "회귀 감지 — manual_override"
    exit 1
  fi
  PREV_ISSUES="$ISSUES"

  # 4. fix.patch 자동 적용 (auto_apply_allowed 만)
  PATCH="content/chapters/${CHAPTER}/visual-review/round-${ROUND}/fix.patch"

  AUTO_COUNT=$(jq -r '[.issues[] | select(.auto_apply_allowed == true)] | length' "$EVAL")
  MANUAL_COUNT=$(jq -r '[.issues[] | select(.auto_apply_allowed == false)] | length' "$EVAL")

  echo "  🔧 auto-fix: ${AUTO_COUNT} / manual: ${MANUAL_COUNT}" >&2

  if [[ "$MANUAL_COUNT" -gt 0 ]]; then
    echo "⚠ manual review required (${MANUAL_COUNT} issues)" >&2
    bash scripts/update-state.sh "$CHAPTER" visual-reviewer failed "manual_override: ${MANUAL_COUNT} non-auto-fixable issues"
    exit 1
  fi

  if [[ ! -f "$PATCH" ]]; then
    echo "  ✗ fix.patch 없음 (auto-fix 가능한 issue 인데 patch 누락)" >&2
    bash scripts/update-state.sh "$CHAPTER" visual-reviewer failed "patch missing"
    exit 1
  fi

  if ! git apply --check "$PATCH" 2>/dev/null; then
    echo "  ✗ git apply --check 실패 — patch 형식 오류" >&2
    bash scripts/update-state.sh "$CHAPTER" visual-reviewer failed "patch invalid"
    exit 1
  fi

  git apply "$PATCH"
  echo "  ✓ patch 적용 완료" >&2

done   # end round loop

# round 3 까지 갔는데 통과 못 함
echo "✗ visual-review max round (${MAX_ROUND}) 통과 실패 — manual_override" >&2
bash scripts/update-state.sh "$CHAPTER" visual-reviewer failed "max round 미통과"
exit 1
