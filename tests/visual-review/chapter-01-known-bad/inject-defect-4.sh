#!/usr/bin/env bash
set -euo pipefail
DECK="content/chapters/chapter-01/slides/deck.html"
# section.layout-image .body-area { ... } 안 align-items: center 라인 삭제
sed -i.bak '/section.layout-image .body-area {/,/^}$/ { /align-items: center/d; }' "$DECK"
rm -f "${DECK}.bak"
echo "✓ defect-4 injected (figure-vertical-alignment)" >&2
