#!/usr/bin/env bash
#
# devlog-cron.sh — Watch project timeline files; when significant new
# content has accumulated, invoke Claude to write a new dev-log blog
# post in the appropriate series of the configured blog repo. Designed
# to run from cron / launchd.
#
# Token-frugal by design: Claude is only invoked when the diff against
# the last snapshot exceeds a per-watch character threshold. Until then
# the script exits silently, having spent zero LLM tokens.
#
# State (snapshots, log) lives in $BLOGTRACK_ROOT/.devlog-state and is
# gitignored. See ../README.md and scripts/README.md for setup.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLOGTRACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="$SCRIPT_DIR/devlog-config.json"
PROMPT_TEMPLATE="$SCRIPT_DIR/devlog-prompt.txt"
STATE_DIR="$BLOGTRACK_ROOT/.devlog-state"
LOG_FILE="$STATE_DIR/cron.log"

mkdir -p "$STATE_DIR"
touch "$LOG_FILE"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"; }

# --- preflight ---------------------------------------------------------

if ! command -v jq >/dev/null 2>&1; then
  log "ERROR: jq not found on PATH; install with 'brew install jq'"
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  log "ERROR: claude CLI not on PATH; cron PATH may be too narrow."
  log "       set PATH=... at the top of your crontab to include the"
  log "       directory containing the claude binary"
  exit 1
fi

[[ -f "$CONFIG" ]]          || { log "ERROR: missing config $CONFIG"; exit 1; }
[[ -f "$PROMPT_TEMPLATE" ]] || { log "ERROR: missing prompt template $PROMPT_TEMPLATE"; exit 1; }

# Site repo is required at the top level of the config. Each watched
# file's generated post is written into this repo's blog source tree.
SITE_REPO=$(jq -r '.site_repo // ""' "$CONFIG")
if [[ -z "$SITE_REPO" || ! -d "$SITE_REPO" ]]; then
  log "ERROR: site_repo is missing or not a directory; set it in $CONFIG"
  exit 1
fi

WATCH_COUNT=$(jq '.watches | length' "$CONFIG")
if (( WATCH_COUNT == 0 )); then
  log "no watches configured; nothing to do"
  exit 0
fi

# --- iterate watches ---------------------------------------------------

jq -c '.watches[]' "$CONFIG" | while read -r entry; do
  WATCHED=$(echo "$entry"     | jq -r '.path')
  SERIES=$(echo "$entry"      | jq -r '.series')
  SLUG_PREFIX=$(echo "$entry" | jq -r '.slug_prefix')
  TITLE_PREFIX=$(echo "$entry"| jq -r '.title_prefix')
  THRESHOLD=$(echo "$entry"   | jq -r '.threshold_chars // 800')
  TAGS=$(echo "$entry"        | jq -r '.tags | join(", ")')
  STYLE_REF=$(echo "$entry"   | jq -r '.style_reference // ""')

  if [[ ! -f "$WATCHED" ]]; then
    log "skip: $WATCHED does not exist"
    continue
  fi

  KEY=$(printf '%s' "$WATCHED" | shasum | cut -c1-16)
  SNAPSHOT="$STATE_DIR/$KEY.last"

  # First run on this watch: snapshot only, no post.
  if [[ ! -f "$SNAPSHOT" ]]; then
    log "first-run snapshot for $WATCHED"
    cp "$WATCHED" "$SNAPSHOT"
    continue
  fi

  # Skip cheaply if file content hasn't changed at all.
  CUR_HASH=$(shasum -a 256 "$WATCHED" | cut -d' ' -f1)
  OLD_HASH=$(shasum -a 256 "$SNAPSHOT" | cut -d' ' -f1)
  if [[ "$CUR_HASH" == "$OLD_HASH" ]]; then
    continue
  fi

  # Compute the additions (lines new in current vs snapshot).
  ADDED=$(diff \
            --new-line-format='%L' \
            --old-line-format='' \
            --unchanged-line-format='' \
            "$SNAPSHOT" "$WATCHED" 2>/dev/null || true)
  ADDED_LEN=${#ADDED}

  log "$WATCHED: ${ADDED_LEN} new chars (threshold $THRESHOLD)"

  if (( ADDED_LEN < THRESHOLD )); then
    # Not enough yet; leave snapshot in place, accumulate.
    continue
  fi

  # --- threshold met → invoke Claude ---
  TODAY=$(date +%Y-%m-%d)
  SLUG="${SLUG_PREFIX}-${TODAY}"
  TITLE="${TITLE_PREFIX} · ${TODAY}"

  log "invoking claude · series=$SERIES slug=$SLUG added_chars=$ADDED_LEN site=$SITE_REPO"

  PROMPT=$(sed \
    -e "s|{{SERIES}}|$SERIES|g"             \
    -e "s|{{SLUG}}|$SLUG|g"                 \
    -e "s|{{TITLE}}|$TITLE|g"               \
    -e "s|{{TAGS}}|$TAGS|g"                 \
    -e "s|{{TODAY}}|$TODAY|g"               \
    -e "s|{{SITE_REPO}}|$SITE_REPO|g"       \
    -e "s|{{STYLE_REFERENCE}}|$STYLE_REF|g" \
    "$PROMPT_TEMPLATE")

  PROMPT="$PROMPT

---NEW TIMELINE CONTENT---
$ADDED
---END NEW TIMELINE CONTENT---"

  cd "$SITE_REPO"
  if claude --permission-mode acceptEdits -p "$PROMPT" >> "$LOG_FILE" 2>&1; then
    log "claude completed for $SLUG; advancing snapshot"
    cp "$WATCHED" "$SNAPSHOT"
  else
    log "claude FAILED for $SLUG; snapshot left in place to retry next run"
  fi
done
