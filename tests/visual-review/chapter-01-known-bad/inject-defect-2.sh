#!/usr/bin/env bash
set -euo pipefail
DECK="content/chapters/chapter-01/slides/deck.html"
# cover-content 의 transform: translate 라인 삭제
sed -i.bak '/section.layout-cover .cover-content/,/^}$/ { /transform: translate/d; }' "$DECK"
rm -f "${DECK}.bak"
echo "✓ defect-2 injected (canvas-center-alignment)" >&2
