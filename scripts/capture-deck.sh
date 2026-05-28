#!/usr/bin/env bash
# scripts/capture-deck.sh — Chrome/Chromium headless 로 deck.html 의 모든 슬라이드를 PNG 캡처.
#
# 사용: bash scripts/capture-deck.sh <chapter_id> <round_num>
# 예:   bash scripts/capture-deck.sh chapter-01 1
#
# 출력: content/chapters/<chapter_id>/visual-review/round-<N>/slide-<idx>.png (19장)

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: bash scripts/capture-deck.sh <chapter_id> <round_num>" >&2
  exit 2
fi

CHAPTER="$1"
ROUND="$2"

DECK="$PWD/content/chapters/${CHAPTER}/slides/deck.html"
OUT_DIR="$PWD/content/chapters/${CHAPTER}/visual-review/round-${ROUND}"

if [[ ! -f "$DECK" ]]; then
  echo "deck.html not found: $DECK" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

# Chrome 우선 (PI 환경에서 brew chromium 이 Trash 처리되는 케이스 — T1 검증 결과)
if [[ -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]]; then
  CHROME_BIN="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
elif command -v chromium >/dev/null 2>&1; then
  CHROME_BIN="chromium"
elif command -v chromium-browser >/dev/null 2>&1; then
  CHROME_BIN="chromium-browser"
else
  echo "Chrome / Chromium not found. Install: brew install --cask chromium" >&2
  echo "또는 Google Chrome 을 /Applications/ 에 설치." >&2
  exit 127
fi

echo "🎬 Capturing ${CHAPTER} round ${ROUND} (binary: ${CHROME_BIN})..." >&2

# Reveal.js 슬라이드 hash 0-base (#/0 ~ #/18). 19 슬라이드.
# --virtual-time-budget=5000 으로 transition fade 안정화.
# --disable-dev-shm-usage: /dev/shm 대신 /tmp 사용 (메모리 압박 시 chrome SIGKILL 회피).
# slide-N 캡처 실패 시 최대 3회 retry (lecture-team session 의 6 claude processes 와 메모리 경합).
for IDX in $(seq 0 18); do
  OUT="${OUT_DIR}/slide-$(printf '%02d' $IDX).png"
  for ATTEMPT in 1 2 3; do
    "$CHROME_BIN" \
      --headless=new \
      --no-sandbox \
      --disable-gpu \
      --disable-dev-shm-usage \
      --window-size=1920,1080 \
      --virtual-time-budget=5000 \
      --screenshot="$OUT" \
      "file://${DECK}#/${IDX}" 2>/dev/null || true

    if [[ -s "$OUT" ]]; then
      break
    fi

    if [[ "$ATTEMPT" -lt 3 ]]; then
      echo "  ⟳ slide-${IDX} attempt ${ATTEMPT} failed, retrying after 2s..." >&2
      sleep 2
    fi
  done

  if [[ ! -s "$OUT" ]]; then
    echo "  ✗ slide-${IDX} failed after 3 attempts" >&2
    continue
  fi
  SIZE=$(stat -f%z "$OUT" 2>/dev/null || stat -c%s "$OUT")
  echo "  ✓ slide-$(printf '%02d' $IDX).png (${SIZE} bytes)" >&2

  sleep 0.3
done

# 출력 PNG 개수 검증
COUNT=$(ls -1 "$OUT_DIR"/slide-*.png 2>/dev/null | wc -l | tr -d ' ')
echo "📸 Captured ${COUNT}/19 slides to ${OUT_DIR}" >&2

if [[ "$COUNT" -lt 19 ]]; then
  echo "⚠ ${COUNT}/19 — 일부 슬라이드 캡처 실패" >&2
  exit 1
fi
