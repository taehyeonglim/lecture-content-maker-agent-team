#!/usr/bin/env bash
set -euo pipefail
DECK="content/chapters/chapter-01/slides/deck.html"
# section.layout-image { ... } 블록 안 height: 100% 라인 삭제
sed -i.bak '/^section.layout-image {/,/^}$/ { /height: 100%/d; }' "$DECK"
rm -f "${DECK}.bak"
echo "✓ defect-1 injected (figure-vertical-alignment)" >&2
