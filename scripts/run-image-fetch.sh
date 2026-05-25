#!/usr/bin/env bash
#
# scripts/run-image-fetch.sh
#
# DESIGN.md 의 "## Image Fetch Requests" 마크다운 표를 파싱하여
# 각 행을 scripts/fetch-image.sh 로 일괄 실행. designer 가 명세를 작성한
# 후 (또는 director 가 designer 완료 sentinel 을 감지한 후) 호출하면
# images/<request_id>.png 가 일괄 생성됨.
#
# 사용:
#   bash scripts/run-image-fetch.sh <chapter_id>           # 전체 실행
#   bash scripts/run-image-fetch.sh <chapter_id> --dry-run # 표만 출력
#   bash scripts/run-image-fetch.sh <chapter_id> --limit N # 처음 N 개만
#
# DESIGN.md 의 표 컬럼 순서 (필수):
#   request_id | slide_id | purpose | alt_text | requirements | preferred_source | fallback

set -euo pipefail

if [ "${1:-}" = "" ]; then
  cat >&2 <<EOF
Usage: bash scripts/run-image-fetch.sh <chapter_id> [--dry-run] [--limit N]

Examples:
  bash scripts/run-image-fetch.sh chapter-01
  bash scripts/run-image-fetch.sh chapter-01 --dry-run
  bash scripts/run-image-fetch.sh chapter-01 --limit 1
EOF
  exit 1
fi

CHAPTER_ID="$1"
shift || true
DRY_RUN=false
LIMIT=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --limit)   LIMIT="${2:-0}"; shift 2 ;;
    *)         echo "unknown option: $1" >&2; shift ;;
  esac
done

DESIGN="content/chapters/${CHAPTER_ID}/DESIGN.md"
OUT_DIR="content/chapters/${CHAPTER_ID}/images"

if [ ! -f "$DESIGN" ]; then
  echo "ERROR: $DESIGN not found" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

# python 으로 DESIGN.md 의 ## Image Fetch Requests 섹션 표 파싱 → JSON 배열
REQUESTS_JSON="$(python3 - "$DESIGN" <<'PY'
import re, pathlib, json, sys
content = pathlib.Path(sys.argv[1]).read_text()
m = re.search(r'## Image Fetch Requests\s*\n(.*?)(?=\n## |\n#### |\Z)', content, re.DOTALL)
if not m:
    print('[]'); raise SystemExit
section = m.group(1)
rows = []
for line in section.split('\n'):
    line = line.strip()
    if not line.startswith('|'): continue
    if line.startswith('|---') or line.startswith('| ---'): continue
    # 헤더 행 skip
    if 'request_id' in line.lower() and 'slide_id' in line.lower(): continue
    # | a | b | c | → 양 끝 | 제거 후 분리
    parts = [p.strip() for p in line.split('|')[1:-1]]
    if len(parts) < 7: continue
    if not parts[0]: continue
    rows.append({
        'request_id':       parts[0],
        'slide_id':         parts[1],
        'purpose':          parts[2],
        'alt_text':         parts[3],
        'requirements':     parts[4],
        'preferred_source': parts[5],
        'fallback':         parts[6],
    })
print(json.dumps(rows, ensure_ascii=False))
PY
)"

COUNT="$(echo "$REQUESTS_JSON" | jq 'length')"
echo "📋 ${COUNT} image requests parsed from ${DESIGN}" >&2

if [ "$COUNT" = "0" ]; then
  echo "⚠ no image requests found. check DESIGN.md '## Image Fetch Requests' table." >&2
  exit 0
fi

# dry-run: 표만 보여주고 종료
if [ "$DRY_RUN" = "true" ]; then
  echo "$REQUESTS_JSON" | jq -r '.[] | "  - \(.request_id) [\(.preferred_source) → \(.fallback)] \(.alt_text)"' >&2
  exit 0
fi

# limit 적용 (0 = 무제한)
if [ "$LIMIT" -gt 0 ]; then
  REQUESTS_JSON="$(echo "$REQUESTS_JSON" | jq --argjson n "$LIMIT" '.[0:$n]')"
  COUNT="$LIMIT"
  echo "  (limited to first ${LIMIT})" >&2
fi

# 각 요청을 fetch-image.sh 로 처리
# while-read 패턴은 codex exec 가 stdin 을 닫아 1회 후 종료되는 이슈가 있어
# 미리 배열로 읽은 후 for 루프 사용 (mapfile 은 bash 4+ 만 → IFS 트릭으로 호환).
REQ_LINES=()
_SAVE_IFS="$IFS"
IFS=$'\n'
for _line in $(echo "$REQUESTS_JSON" | jq -c '.[]'); do
  REQ_LINES+=("$_line")
done
IFS="$_SAVE_IFS"

SUCCESS=0
FAIL=0
INDEX=0
TOTAL="$COUNT"
for req in "${REQ_LINES[@]}"; do
  INDEX=$((INDEX + 1))
  ID="$(echo "$req" | jq -r .request_id)"
  ALT="$(echo "$req" | jq -r .alt_text)"
  REQ_TEXT="$(echo "$req" | jq -r .requirements)"
  PREF="$(echo "$req" | jq -r '.preferred_source // "gpt-image-gen"')"
  OUTFILE="${ID}.png"

  # preferred_source 정규화 (designer 가 "gpt-image-gen" 또는 "gpt_image_gen" 또는 "wiki" 표기)
  case "$(echo "$PREF" | tr '[:upper:]' '[:lower:]')" in
    wiki|wikimedia)        SRC_ARG="wiki" ; QUERY="$ALT"      ;;  # 인물 사진: alt_text 단답
    gpt-image-gen|gpt_image_gen|openai|"") SRC_ARG="gpt-image-gen" ; QUERY="$REQ_TEXT" ;;  # 다이어그램: requirements 자세히
    *) echo "   ? unknown preferred_source '$PREF' — gpt-image-gen 으로 강제" >&2
       SRC_ARG="gpt-image-gen" ; QUERY="$REQ_TEXT" ;;
  esac

  # 이미 존재 + 적절한 크기면 skip (재실행 시 시간 절약)
  if [ -f "$OUT_DIR/$OUTFILE" ] && [ "$(stat -f%z "$OUT_DIR/$OUTFILE" 2>/dev/null || echo 0)" -gt 1000 ]; then
    echo "⏭  [${INDEX}/${TOTAL}] ${ID} — 이미 존재 (skip)" >&2
    SUCCESS=$((SUCCESS + 1))
    continue
  fi
  echo "🔍 [${INDEX}/${TOTAL}] ${ID} (${SRC_ARG}) — ${QUERY:0:60}..." >&2
  # /dev/null < 로 stdin 차단 → codex exec 의 stdin 간섭 방지
  if bash scripts/fetch-image.sh "$QUERY" "$OUT_DIR/" "$OUTFILE" "$SRC_ARG" </dev/null 2>/dev/null; then
    SUCCESS=$((SUCCESS + 1))
    META="$OUT_DIR/${OUTFILE}.meta.json"
    if [ -f "$META" ]; then
      SRC="$(jq -r '.source // "unknown"' "$META")"
      LIC="$(jq -r '.license // "—"' "$META")"
      echo "   ✓ $SRC · $LIC" >&2
    fi
  else
    FAIL=$((FAIL + 1))
    echo "   ✗ 실패" >&2
  fi
done

echo "" >&2
echo "✅ ${SUCCESS} succeeded, ✗ ${FAIL} failed (of ${TOTAL}) — saved to ${OUT_DIR}/" >&2
