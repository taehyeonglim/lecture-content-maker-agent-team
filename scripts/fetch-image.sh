#!/usr/bin/env bash
# PI 정책 2026-05-26: 모든 이미지 자료는 gpt-image-gen, 인물 사진만 Wikimedia.
# preferred_source 기본값은 gpt-image-gen. 인물 사진 fetch 시에만 'wiki' 전달.

set -euo pipefail

if [[ $# -lt 2 || $# -gt 4 ]]; then
  cat >&2 <<USAGE
Usage: bash scripts/fetch-image.sh <query> <out_dir> [<filename>] [<preferred_source>]
  preferred_source = gpt-image-gen (default) | wiki

  gpt-image-gen : OpenAI Images API 로 생성. 다이어그램·차트·일러스트·분위기 사진용.
  wiki          : Wikimedia Commons 검색 우선, 실패 시 gpt-image-gen 폴백. 인물 사진 전용.
USAGE
  exit 2
fi

QUERY="$1"
OUT_DIR="$2"
REQUESTED_FILENAME="${3:-}"
PREFERRED_SOURCE="${4:-gpt-image-gen}"

if [[ "$PREFERRED_SOURCE" != "gpt-image-gen" && "$PREFERRED_SOURCE" != "wiki" ]]; then
  echo "Invalid preferred_source: $PREFERRED_SOURCE (must be gpt-image-gen or wiki)" >&2
  exit 2
fi

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
  # PI 정책 (2026-05-26 갱신): codex CLI 의 내장 image_gen.imagegen tool 사용.
  # OPENAI_API_KEY 별도 발급/결제 불필요 — ChatGPT subscription auth 로 호출됨.
  # 비용은 PI 의 ChatGPT Pro/Plus plan 에 흡수.
  local filename output_path meta_path abs_output codex_prompt

  filename="$REQUESTED_FILENAME"
  if [[ -z "$filename" ]]; then
    filename="$(slugify "$QUERY").png"
  fi

  output_path="${OUT_DIR%/}/$filename"
  meta_path="${output_path}.meta.json"

  # codex sandbox 에서 작성 가능한 절대 경로로 변환
  mkdir -p "$OUT_DIR"
  abs_output="$(cd "$(dirname "$output_path")" && pwd)/$(basename "$output_path")"

  codex_prompt="Use the image_gen.imagegen tool (not Python/PIL/matplotlib — only the actual image generation tool) to create the following image, then save the generated PNG to the exact path ${abs_output} (overwrite if exists).

Image prompt:
${QUERY}

Output requirements:
- Single PNG file at ${abs_output}
- After saving, output the file path on a single line and exit. No other commentary."

  if codex exec --model gpt-5.5 \
        -c model_reasoning_effort=low \
        -c sandbox_mode=workspace-write \
        --skip-git-repo-check \
        "$codex_prompt" >/dev/null 2>&1; then
    if [[ -f "$output_path" ]] && [[ "$(stat -f%z "$output_path" 2>/dev/null || echo 0)" -gt 5000 ]]; then
      jq -n \
        --arg source "gpt-image-gen (codex image_gen.imagegen)" \
        --arg license "AI-generated" \
        --arg model "gpt-5.5 + image_gen.imagegen" \
        --arg prompt "$QUERY" \
        '{source: $source, license: $license, model: $model, prompt: $prompt}' \
        > "$meta_path"
      return 0
    fi
    echo "codex 호출은 성공했으나 출력 파일(${abs_output})이 비어있음/없음." >&2
    return 1
  else
    echo "codex exec image_gen 호출 실패 (codex auth 또는 quota 확인 필요)." >&2
    return 1
  fi
}

require_command curl
require_command jq
require_command base64

mkdir -p "$OUT_DIR"

# preferred_source=gpt-image-gen (기본): Wikimedia 건너뛰고 바로 OpenAI 호출.
# preferred_source=wiki (인물 사진): Wikimedia 우선, 실패 시 OpenAI 폴백.
if [[ "$PREFERRED_SOURCE" == "wiki" ]]; then
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
  echo "Wikimedia 검색·다운로드 실패 — codex image_gen 폴백 시도." >&2
fi

generate_with_codex
