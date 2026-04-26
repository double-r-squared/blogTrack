#!/usr/bin/env bash
#
# bump.sh — bump the patch version in package.json, rename the symlink
# in ~/.vscode/extensions/ to match (so VS Code re-loads the extension
# as a new version on next window reload), and print the reload step.
#
# Why the symlink rename matters: VS Code parses the install folder
# name as <publisher>.<name>-<version> and treats a renamed folder as a
# new install. Without the rename, code changes are picked up on
# reload but the version VS Code reports stays stuck at the old number.
#
# Usage:  ./bump.sh [major|minor|patch]   (default: patch)

set -euo pipefail

EXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$EXT_DIR/package.json"
LEVEL="${1:-patch}"

command -v jq >/dev/null 2>&1 || {
  echo "ERROR: jq not installed (brew install jq)" >&2
  exit 1
}

PUBLISHER=$(jq -r '.publisher' "$PKG")
NAME=$(jq -r '.name' "$PKG")
OLD_VERSION=$(jq -r '.version' "$PKG")

IFS='.' read -r MAJOR MINOR PATCH <<< "$OLD_VERSION"
case "$LEVEL" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
  *)
    echo "ERROR: unknown bump level '$LEVEL' (expected major|minor|patch)" >&2
    exit 1
    ;;
esac
NEW_VERSION="$MAJOR.$MINOR.$PATCH"

# Write new version to package.json
TMP=$(mktemp)
jq --arg v "$NEW_VERSION" '.version = $v' "$PKG" > "$TMP"
mv "$TMP" "$PKG"

# Update the symlink in ~/.vscode/extensions/. VS Code reads the
# version from the folder name, so we have to rename the link itself
# (not just the package.json field) for the new version to register.
EXT_INSTALL_BASE="$HOME/.vscode/extensions"
OLD_LINK="$EXT_INSTALL_BASE/${PUBLISHER}.${NAME}-${OLD_VERSION}"
NEW_LINK="$EXT_INSTALL_BASE/${PUBLISHER}.${NAME}-${NEW_VERSION}"

if [[ -L "$OLD_LINK" ]]; then
  TARGET=$(readlink "$OLD_LINK")
  rm "$OLD_LINK"
  ln -s "$TARGET" "$NEW_LINK"
  echo "renamed install: ${PUBLISHER}.${NAME}-${OLD_VERSION} → ${PUBLISHER}.${NAME}-${NEW_VERSION}"
elif [[ ! -e "$NEW_LINK" ]]; then
  ln -s "$EXT_DIR" "$NEW_LINK"
  echo "created install: $NEW_LINK → $EXT_DIR"
else
  echo "warning: $NEW_LINK already exists and isn't a symlink — review manually" >&2
fi

cat <<MSG

version: $OLD_VERSION → $NEW_VERSION

reload VS Code so the change takes effect:
  Cmd+Shift+P → Developer: Reload Window

(or quit and reopen VS Code; either works.)
MSG
