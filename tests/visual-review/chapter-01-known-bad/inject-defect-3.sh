#!/usr/bin/env bash
set -euo pipefail
DECK="content/chapters/chapter-01/slides/deck.html"
# .body-text { ... } 블록 안 font-size: 44px → 24px
sed -i.bak '/^\.body-text {/,/^}$/ { s/font-size: 44px/font-size: 24px/; }' "$DECK"
rm -f "${DECK}.bak"
echo "✓ defect-3 injected (content-overflow / font-too-small)" >&2
