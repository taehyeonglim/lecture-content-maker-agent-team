#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: bash scripts/export-pdf.sh <chapter_id> [<port>]" >&2
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command not found: $1" >&2
    exit 1
  fi
}

file_size_bytes() {
  wc -c < "$1" | tr -d '[:space:]'
}

estimate_slide_count() {
  python3 - "$1" <<'PY'
import re
import sys
from html.parser import HTMLParser

class SectionCounter(HTMLParser):
    def __init__(self):
        super().__init__()
        self.count = 0

    def handle_starttag(self, tag, attrs):
        if tag.lower() == "section":
            self.count += 1

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as f:
        parser = SectionCounter()
        parser.feed(f.read())
        print(parser.count)
except Exception:
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        print(len(re.findall(r"<section\b", f.read(), flags=re.IGNORECASE)))
PY
}

update_state() {
  local status="$1"
  local error_message="${2:-}"

  python3 - "$status" "$STATE_PATH" "$CHAPTER_ID" "$PDF_PATH" "$PDF_SIZE" "$SLIDE_COUNT" "$error_message" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

status, state_path, chapter_id, pdf_path, pdf_size, slide_count, error_message = sys.argv[1:8]
now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

if os.path.exists(state_path) and os.path.getsize(state_path) > 0:
    with open(state_path, "r", encoding="utf-8") as f:
        state = json.load(f)
else:
    state = {
        "course": "교육방법및교육공학 2026-2",
        "overall_progress": 0,
        "cumulative_cost_usd": 0,
        "chapters": [],
        "active_agents": [],
        "queue": [],
        "recent_events": [],
    }

if not isinstance(state, dict):
    state = {"chapters": [], "recent_events": []}

chapters = state.get("chapters")
if not isinstance(chapters, list):
    chapters = []
    state["chapters"] = chapters

chapter = next((item for item in chapters if isinstance(item, dict) and item.get("id") == chapter_id), None)
if chapter is None:
    chapter = {"id": chapter_id}
    if chapter_id.startswith("chapter-") and chapter_id[8:].isdigit():
        chapter["num"] = int(chapter_id[8:])
    chapters.append(chapter)

tasks = chapter.get("tasks")
if not isinstance(tasks, list):
    tasks = []
    chapter["tasks"] = tasks

developer_task = next((item for item in tasks if isinstance(item, dict) and item.get("role") == "developer"), None)
if developer_task is None:
    developer_task = {"role": "developer"}
    tasks.append(developer_task)

if status == "success":
    export = {
        "path": pdf_path,
        "size_bytes": int(pdf_size),
        "slide_count_estimate": int(slide_count),
        "exported_at": now,
    }
    chapter["status"] = "developed" if chapter.get("status") != "done" else "done"
    chapter["deck_pdf"] = export
    chapter["updated_at"] = now
    developer_task.update({
        "status": "done",
        "output_path": pdf_path,
        "finished_at": now,
        "error_message": None,
        "deck_pdf": export,
    })
    event = {
        "ts": now,
        "agent": "developer",
        "action": "pdf_exported",
        "chapter": chapter_id,
        "path": pdf_path,
        "size_bytes": int(pdf_size),
        "slide_count_estimate": int(slide_count),
    }
else:
    chapter["status"] = "manual_override"
    chapter["updated_at"] = now
    developer_task.update({
        "status": "failed",
        "error_message": error_message,
        "retry_count": 3,
    })
    event = {
        "ts": now,
        "agent": "developer",
        "action": "manual_override",
        "chapter": chapter_id,
        "error_message": error_message,
    }

recent_events = state.get("recent_events")
if not isinstance(recent_events, list):
    recent_events = []
state["recent_events"] = (recent_events + [event])[-50:]
state["updated_at"] = now

tmp_path = f"{state_path}.tmp"
with open(tmp_path, "w", encoding="utf-8") as f:
    json.dump(state, f, ensure_ascii=False, indent=2)
    f.write("\n")
os.replace(tmp_path, state_path)
PY
}

validate_pdf() {
  local file_output
  file_output=$(file "$PDF_PATH")
  if [[ "$file_output" != *"PDF document"* ]]; then
    echo "Error: output is not a PDF: $file_output" >&2
    return 1
  fi

  PDF_SIZE=$(file_size_bytes "$PDF_PATH")
  if (( PDF_SIZE <= 10240 )); then
    echo "Error: PDF is too small: ${PDF_SIZE} bytes" >&2
    return 1
  fi
}

run_decktape() {
  decktape reveal -s 1920x1080 --pause 1500 \
    --pdf-author "임태형" \
    --pdf-title "교육방법 및 교육공학 — ${CHAPTER_ID}" \
    "http://localhost:${PORT}/deck.html" \
    "$PDF_PATH"
}

if (( $# < 1 || $# > 2 )); then
  usage
  exit 1
fi

CHAPTER_ID="$1"
PORT="${2:-8765}"
STATE_PATH="STATE.json"
PDF_SIZE=0
SLIDE_COUNT=0

if [[ -z "$CHAPTER_ID" || "$CHAPTER_ID" == *"/"* || "$CHAPTER_ID" == *".."* ]]; then
  echo "Error: invalid chapter_id: $CHAPTER_ID" >&2
  exit 1
fi

if [[ ! "$PORT" =~ ^[0-9]+$ ]]; then
  echo "Error: port must be numeric: $PORT" >&2
  exit 1
fi

PORT=$((10#$PORT))
if (( PORT < 1 || PORT > 65535 )); then
  echo "Error: port out of range: $PORT" >&2
  exit 1
fi

SLIDES_DIR="content/chapters/${CHAPTER_ID}/slides"
DECK_HTML="${SLIDES_DIR}/deck.html"
PDF_PATH="${SLIDES_DIR}/deck.pdf"

if [[ ! -f "$DECK_HTML" ]]; then
  echo "Error: deck.html not found: $DECK_HTML" >&2
  exit 1
fi

require_command python3
require_command decktape
require_command file

SERVER_PID=""
SERVER_STARTED=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  python3 -m http.server "$PORT" -d "$SLIDES_DIR" >/dev/null 2>&1 &
  SERVER_PID=$!
  sleep 1
  if kill -0 "$SERVER_PID" 2>/dev/null; then
    SERVER_STARTED=1
    trap "kill $SERVER_PID 2>/dev/null || true" EXIT
    break
  fi
  wait "$SERVER_PID" 2>/dev/null || true
  if (( PORT >= 65535 )); then
    break
  fi
  PORT=$((PORT + 1))
done

if (( SERVER_STARTED == 0 )); then
  echo "Error: failed to start local static server after 10 port attempts" >&2
  exit 1
fi

BACKOFFS=(1 10 100)
ATTEMPT=1
MAX_ATTEMPTS=4
while (( ATTEMPT <= MAX_ATTEMPTS )); do
  if run_decktape && validate_pdf; then
    SLIDE_COUNT=$(estimate_slide_count "$DECK_HTML")
    update_state success
    echo "Exported ${PDF_PATH} (${PDF_SIZE} bytes, slide_count_estimate=${SLIDE_COUNT})"
    exit 0
  fi

  if (( ATTEMPT == MAX_ATTEMPTS )); then
    break
  fi

  sleep "${BACKOFFS[$((ATTEMPT - 1))]}"
  ATTEMPT=$((ATTEMPT + 1))
done

ERROR_MESSAGE="decktape failed after 3 retries; manual override required"
update_state failure "$ERROR_MESSAGE"
echo "Error: $ERROR_MESSAGE" >&2
exit 1
