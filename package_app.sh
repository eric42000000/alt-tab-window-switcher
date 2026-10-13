#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="${1:-$ROOT_DIR/AltTabWindowSwitcher.app}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
DMG_PATH="$DIST_DIR/AltTabWindowSwitcher.dmg"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/alt-tab-window-switcher.XXXXXX")"

if [[ ! -d "$APP_PATH" ]]; then
	echo "App bundle not found: $APP_PATH" >&2
	exit 1
fi

mkdir -p "$DIST_DIR"
trap 'rm -rf "$STAGING_DIR"' EXIT

ditto "$APP_PATH" "$STAGING_DIR/AltTabWindowSwitcher.app"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create \
	-volname "AltTab Window Switcher" \
	-srcfolder "$STAGING_DIR" \
	-ov \
	-format UDZO \
	"$DMG_PATH"

echo "Created $DMG_PATH"
