#!/usr/bin/env bash
# tests/visual-review/chapter-01-known-bad/run-validation.sh
#
# 5 결함 inject → visual-reviewer 호출 → recall 측정.
# 통과 기준: 5/5 결함 발견, false positive 0.

set -euo pipefail

DECK="content/chapters/chapter-01/slides/deck.html"
DECK_BAK="${DECK}.before-validation"

cp "$DECK" "$DECK_BAK"

# bash 3.2 호환 (macOS 기본) — associative array 대신 case 함수
expected_category() {
  case "$1" in
    1) echo "figure-vertical-alignment" ;;
    2) echo "canvas-center-alignment" ;;
    3) echo "content-overflow" ;;
    4) echo "figure-vertical-alignment" ;;
    5) echo "flat-design-violation" ;;
  esac
}

PASS=0
FAIL=0

# false positive 검사 (정상 deck 먼저)
echo "━━━ False positive 검사 (정상 deck) ━━━"
rm -rf content/chapters/chapter-01/visual-review/
bash scripts/run-visual-review.sh chapter-01
FP_EVAL="content/chapters/chapter-01/visual-review/round-1/eval.json"
FP_ISSUES=$(jq -r '.issues_count' "$FP_EVAL")
if [[ "$FP_ISSUES" -eq 0 ]]; then
  echo "  ✓ false positive 0"
else
  echo "  ✗ 정상 deck 에 ${FP_ISSUES} 개 issue 발견 (false positive)" >&2
  FAIL=$((FAIL + 1))
fi

# 5 결함 각각 검사
for N in 1 2 3 4 5; do
  echo ""
  echo "━━━ Defect ${N}: $(expected_category $N) ━━━"
  rm -rf content/chapters/chapter-01/visual-review/
  cp "$DECK_BAK" "$DECK"   # 원본 복구
  bash "tests/visual-review/chapter-01-known-bad/inject-defect-${N}.sh"
  bash scripts/run-visual-review.sh chapter-01 || true   # 실패해도 eval.json 만들어짐
  EVAL="content/chapters/chapter-01/visual-review/round-1/eval.json"
  FOUND=$(jq -r --arg cat "$(expected_category $N)" \
    '[.issues[] | select(.category == $cat)] | length' "$EVAL")
  if [[ "$FOUND" -ge 1 ]]; then
    echo "  ✓ defect-${N} 발견 ($(expected_category $N))"
    PASS=$((PASS + 1))
  else
    echo "  ✗ defect-${N} 못 찾음" >&2
    FAIL=$((FAIL + 1))
  fi
done

# 원본 복구
cp "$DECK_BAK" "$DECK"
rm "$DECK_BAK"

echo ""
echo "━━━ 결과 ━━━"
echo "PASS: ${PASS}/5  FAIL: ${FAIL}"
if [[ "$PASS" -eq 5 && "$FAIL" -eq 0 ]]; then
  echo "✅ visual-reviewer 통과 — Stage 2 (단일 챕터) 진입 OK"
  exit 0
else
  echo "❌ visual-reviewer 미통과 — system prompt 수정 필요"
  exit 1
fi
