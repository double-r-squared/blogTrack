#!/usr/bin/env bash
#
# track4blog.sh — manage the watch list in devlog-config.json.
#
# Two modes:
#
#   track4blog.sh <file> [<file>...]
#       Toggle each given file in the watches[] array. If a file is
#       already tracked it's removed; otherwise it's added with sensible
#       defaults derived from the parent directory name.
#
#   track4blog.sh --set-destination <abs-path-to-blog-repo>
#       Update the config's site_repo (the destination blog repo where
#       the cron will write generated posts). One destination per
#       blogTrack install; many sources publish into it.
#
# macOS notification confirms what happened in either mode.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/devlog-config.json"

notify() {
  /usr/bin/osascript -e "display notification \"$1\" with title \"track4blog\"" >/dev/null 2>&1 || true
}

fail() { notify "$1"; echo "$1" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || fail "jq not installed (brew install jq)"

(( $# >= 1 )) || fail "usage: track4blog.sh <file>... | --set-destination <path>"

# Initialize empty config on first use
if [[ ! -f "$CONFIG" ]]; then
  echo '{"site_repo":"","watches":[]}' > "$CONFIG"
fi

# --- mode: set destination -------------------------------------------

if [[ "$1" == "--set-destination" ]]; then
  DEST="${2:-}"
  [[ -n "$DEST" ]] || fail "set-destination: path required"
  [[ -d "$DEST" ]] || fail "set-destination: $DEST is not a directory"

  # Resolve to absolute, then write
  ABS=$(cd "$DEST" && pwd)
  TMP=$(mktemp)
  jq --arg p "$ABS" '.site_repo = $p' "$CONFIG" > "$TMP"
  mv "$TMP" "$CONFIG"
  notify "Destination: $ABS"
  exit 0
fi

# --- mode: toggle watches --------------------------------------------

ADDED_COUNT=0
REMOVED_COUNT=0
LAST_NAME=""
LAST_PROJ=""

for ARG in "$@"; do
  if [[ ! -e "$ARG" ]]; then
    notify "skip: $ARG not found"
    continue
  fi
  FILE=$(cd "$(dirname "$ARG")" && pwd)/$(basename "$ARG")

  ALREADY=$(jq --arg p "$FILE" '.watches | map(select(.path == $p)) | length' "$CONFIG")

  TMP=$(mktemp)
  if (( ALREADY > 0 )); then
    jq --arg p "$FILE" '.watches |= map(select(.path != $p))' "$CONFIG" > "$TMP"
    mv "$TMP" "$CONFIG"
    REMOVED_COUNT=$((REMOVED_COUNT + 1))
    LAST_NAME=$(basename "$FILE")
  else
    # Defaults: derive series + slug from the parent directory name. User
    # can edit the entry afterward if the auto-naming is off.
    PARENT=$(basename "$(dirname "$FILE")")
    PROJ_LOWER=$(printf '%s' "$PARENT" | tr '[:upper:]' '[:lower:]' | tr ' _' '--')
    PROJ_TITLE=$(printf '%s' "$PARENT" | sed 's/[-_]/ /g')
    TAGS_JSON=$(jq -nc --arg p "$PROJ_LOWER" '["devlog", $p]')

    jq --arg path        "$FILE"                              \
       --arg series      "$PROJ_TITLE development log"        \
       --arg slug_prefix "$PROJ_LOWER-devlog"                 \
       --arg title_prefix "$PROJ_TITLE development log"       \
       --argjson tags    "$TAGS_JSON"                         \
       '.watches += [{
          "path": $path,
          "series": $series,
          "slug_prefix": $slug_prefix,
          "title_prefix": $title_prefix,
          "threshold_chars": 800,
          "tags": $tags
        }]' "$CONFIG" > "$TMP"
    mv "$TMP" "$CONFIG"
    ADDED_COUNT=$((ADDED_COUNT + 1))
    LAST_NAME=$(basename "$FILE")
    LAST_PROJ="$PROJ_TITLE"
  fi
done

# Single tidy notification summarizing the batch
if (( ADDED_COUNT == 1 && REMOVED_COUNT == 0 )); then
  notify "Tracking: $LAST_NAME (as $LAST_PROJ)"
elif (( ADDED_COUNT == 0 && REMOVED_COUNT == 1 )); then
  notify "Untracked: $LAST_NAME"
elif (( ADDED_COUNT > 0 && REMOVED_COUNT == 0 )); then
  notify "Tracking $ADDED_COUNT files"
elif (( ADDED_COUNT == 0 && REMOVED_COUNT > 0 )); then
  notify "Untracked $REMOVED_COUNT files"
else
  notify "+$ADDED_COUNT, -$REMOVED_COUNT"
fi
