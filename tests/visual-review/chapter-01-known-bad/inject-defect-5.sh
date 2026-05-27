#!/usr/bin/env bash
set -euo pipefail
DECK="content/chapters/chapter-01/slides/deck.html"
# .header-bar 의 background line 다음에 box-shadow 추가 (KRDS flat 위반)
sed -i.bak 's|background: var(--navy);|background: var(--navy);\n  box-shadow: 0 4px 8px rgba(0,0,0,0.2);|' "$DECK"
rm -f "${DECK}.bak"
echo "✓ defect-5 injected (flat-design-violation)" >&2
