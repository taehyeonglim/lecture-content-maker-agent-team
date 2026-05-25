#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: bash scripts/fetch-image.sh <query> <out_dir> [<filename>]" >&2
  exit 2
fi

QUERY="$1"
OUT_DIR="$2"
REQUESTED_FILENAME="${3:-}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

if [[ -z "${WIKIMEDIA_USER_AGENT:-}" ]]; then
  echo "WIKIMEDIA_USER_AGENT is not set in .env; using default User-Agent." >&2
  WIKIMEDIA_USER_AGENT="lecture-content-maker-agent-team/0.1 (local script; set WIKIMEDIA_USER_AGENT in .env)"
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 127
  fi
}

slugify() {
  local slug
  slug="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | sed 's/^-//; s/-$//')"
  if [[ -z "$slug" ]]; then
    slug="image"
  fi
  printf '%s' "$slug"
}

retry_curl() {
  local attempt delay output
  local delays=(1 10 100)

  for attempt in 0 1 2; do
    if output="$(curl --fail --silent --show-error --location --max-time 60 --connect-timeout 15 "$@" 2>/dev/null)"; then
      printf '%s' "$output"
      return 0
    fi

    delay="${delays[$attempt]}"
    if [[ "$attempt" -lt 2 ]]; then
      echo "HTTP/API request failed. Retrying in ${delay}s..." >&2
      sleep "$delay"
    fi
  done

  return 1
}

retry_download() {
  local output_path="$1"
  shift

  local attempt delay
  local delays=(1 10 100)

  for attempt in 0 1 2; do
    if curl --fail --silent --show-error --location --max-time 60 --connect-timeout 15 "$@" --output "$output_path" 2>/dev/null; then
      return 0
    fi

    rm -f "$output_path"
    delay="${delays[$attempt]}"
    if [[ "$attempt" -lt 2 ]]; then
      echo "HTTP/API download failed. Retrying in ${delay}s..." >&2
      sleep "$delay"
    fi
  done

  return 1
}

extension_from_url() {
  local url_path ext
  url_path="${1%%\?*}"
  ext="${url_path##*.}"
  ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"

  case "$ext" in
    jpg|jpeg|png|webp|gif)
      printf '.%s' "$ext"
      ;;
    *)
      printf '.png'
      ;;
  esac
}

resolve_filename() {
  local url="$1"

  if [[ -n "$REQUESTED_FILENAME" ]]; then
    printf '%s' "$REQUESTED_FILENAME"
    return 0
  fi

  printf '%s%s' "$(slugify "$QUERY")" "$(extension_from_url "$url")"
}

search_wikimedia() {
  retry_curl \
    --get "https://commons.wikimedia.org/w/api.php" \
    --user-agent "$WIKIMEDIA_USER_AGENT" \
    --data-urlencode "action=query" \
    --data-urlencode "format=json" \
    --data-urlencode "formatversion=2" \
    --data-urlencode "generator=search" \
    --data-urlencode "gsrnamespace=6" \
    --data-urlencode "gsrlimit=10" \
    --data-urlencode "gsrsearch=$QUERY" \
    --data-urlencode "prop=imageinfo" \
    --data-urlencode "iiprop=url|mime|extmetadata"
}

extract_candidates() {
  jq -c '
    def text($v): (($v.value? // $v // "") | tostring | gsub("<[^>]+>"; "") | gsub("&quot;"; "\"") | gsub("&amp;"; "&") | gsub("\\s+"; " ") | gsub("^\\s+|\\s+$"; ""));
    def allowed_license($license):
      ($license | ascii_upcase) as $u
      | ($u == "PUBLIC DOMAIN"
         or $u == "CC BY"
         or $u == "CC BY-SA"
         or $u == "CC-BY"
         or $u == "CC-BY-SA"
         or ($u | startswith("CC BY "))
         or ($u | startswith("CC BY-SA "))
         or ($u | startswith("CC-BY "))
         or ($u | startswith("CC-BY-SA "))
         or ($u | startswith("CC-BY-"))
         or ($u | startswith("CC-BY-SA-")));
    (.query.pages // [])
    | map(. as $page
      | ($page.imageinfo[0] // {}) as $info
      | ($info.extmetadata // {}) as $meta
      | {
          title: ($page.title // ""),
          url: ($info.url // ""),
          mime: ($info.mime // ""),
          license: text($meta.LicenseShortName),
          attribution: (
            text($meta.Attribution)
            | if . == "" then text($meta.Artist) else . end
            | if . == "" then text($meta.Credit) else . end
          )
        })
    | map(select(
        (.url != "")
        and (.mime | startswith("image/"))
        and (.license != "")
        and (.attribution != "")
        and allowed_license(.license)
      ))
    | .[:3]
    | .[]
  '
}

write_wiki_meta() {
  local meta_path="$1"
  local candidate="$2"

  jq -n \
    --arg source "wiki" \
    --arg url "$(jq -r '.url' <<<"$candidate")" \
    --arg license "$(jq -r '.license' <<<"$candidate")" \
    --arg attribution "$(jq -r '.attribution' <<<"$candidate")" \
    --arg alt_text "$QUERY" \
    --arg query "$QUERY" \
    '{source: $source, url: $url, license: $license, attribution: $attribution, alt_text: $alt_text, query: $query}' \
    > "$meta_path"
}

generate_with_codex() {
  # codex exec 에게 이미지 생성을 위임. codex 는 적절한 도구
  # (matplotlib/graphviz/PIL/SVG)를 선택해 코드 작성 후 실행, PNG 저장.
  # OPENAI_API_KEY 불필요 — codex CLI OAuth 만으로 동작. 다이어그램/표/차트류에 적합.
  local filename output_path meta_path codex_output
  filename="$REQUESTED_FILENAME"
  if [[ -z "$filename" ]]; then
    filename="$(slugify "$QUERY").png"
  fi
  output_path="${OUT_DIR%/}/$filename"
  meta_path="${output_path}.meta.json"

  # codex 가 일관된 결과 위치에 저장하도록 절대 경로 지정
  local abs_output
  abs_output="$(cd "$(dirname "$output_path")" && pwd)/$(basename "$output_path")"

  local codex_prompt
  codex_prompt="다음 시각자료를 PNG 파일로 만들어 ${abs_output} 에 저장하라.

설명: ${QUERY}

요구사항:
- 1024×768 또는 1280×720 권장 (16:9 슬라이드 배경에 들어갈 수 있는 크기)
- 흰 배경, 한국어 텍스트는 시스템 한글 폰트 활용 (matplotlib rcParams 또는 PIL ImageFont)
- 가능한 도구 우선순위:
  1) 단순 다이어그램/벤다이어그램/원형/타임라인/매트릭스/표 → matplotlib + 한글 폰트 ('AppleGothic' on macOS)
  2) 노드-엣지 다이어그램 → graphviz (dot)
  3) 흐름도/방사형 → matplotlib patches 또는 plantuml/mermaid
  4) 이미 라이브러리가 부족하면 PIL/Pillow 로 직접 도형 + 텍스트 그림
- 사실적 사진(예: 교실 장면)은 제외 — 추상 도형/도식만. 사진 요구사항이면 placeholder 박스 + 라벨로 대체.
- 종속성 미설치 시 pip install (PIL/Pillow, matplotlib, graphviz 정도는 환경에 있을 것)
- 완료 후 ${abs_output} 파일이 존재하고 크기 > 0 이어야 함

마지막에 단 한 줄 'OK ${abs_output}' 만 출력하라 (다른 메시지 없이)."

  if codex_output="$(codex exec --model gpt-5.5 \
                      -c model_reasoning_effort=medium \
                      -c sandbox_mode="workspace-write" \
                      "$codex_prompt" 2>&1)"; then
    if [[ -f "$output_path" && -s "$output_path" ]]; then
      jq -n \
        --arg source "codex-generated" \
        --arg license "AI-generated (codex matplotlib/graphviz/PIL)" \
        --arg prompt "$QUERY" \
        '{source: $source, license: $license, prompt: $prompt}' \
        > "$meta_path"
      return 0
    fi
  fi
  echo "codex generation failed for query: ${QUERY:0:50}..." >&2
  return 1
}

generate_with_openai() {
  local filename output_path meta_path api_key response image_b64
  api_key="${GPT_IMAGE_GEN_KEY:-${OPENAI_API_KEY:-}}"

  if [[ -z "$api_key" ]]; then
    # OpenAI key 없으면 codex 로 위임
    generate_with_codex
    return $?
  fi

  filename="$REQUESTED_FILENAME"
  if [[ -z "$filename" ]]; then
    filename="$(slugify "$QUERY").png"
  fi

  output_path="${OUT_DIR%/}/$filename"
  meta_path="${output_path}.meta.json"

  response="$(retry_curl \
    --request POST "https://api.openai.com/v1/images/generations" \
    --header "Authorization: Bearer ${api_key}" \
    --header "Content-Type: application/json" \
    --data "$(jq -n --arg prompt "$QUERY" '{model: "gpt-image-1", prompt: $prompt, size: "1024x1024"}')")"

  image_b64="$(jq -r '.data[0].b64_json // empty' <<<"$response")"
  if [[ -z "$image_b64" ]]; then
    echo "OpenAI Images API response did not include image data." >&2
    return 1
  fi

  printf '%s' "$image_b64" | base64 --decode > "$output_path"
  jq -n \
    --arg source "gpt-image-gen" \
    --arg license "AI-generated" \
    --arg prompt "$QUERY" \
    '{source: $source, license: $license, prompt: $prompt}' \
    > "$meta_path"
}

require_command curl
require_command jq
require_command base64

mkdir -p "$OUT_DIR"

wiki_response=""
if wiki_response="$(search_wikimedia)"; then
  while IFS= read -r candidate; do
    [[ -z "$candidate" ]] && continue

    image_url="$(jq -r '.url' <<<"$candidate")"
    filename="$(resolve_filename "$image_url")"
    output_path="${OUT_DIR%/}/$filename"
    meta_path="${output_path}.meta.json"

    if retry_download "$output_path" --user-agent "$WIKIMEDIA_USER_AGENT" "$image_url"; then
      write_wiki_meta "$meta_path" "$candidate"
      exit 0
    fi
  done < <(extract_candidates <<<"$wiki_response")
fi

generate_with_openai
