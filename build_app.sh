#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$ROOT_DIR/AltTabWindowSwitcher.app"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
BUILD_UNIVERSAL="${BUILD_UNIVERSAL:-0}"

if [[ "$BUILD_UNIVERSAL" == "1" ]]; then
	ARM_TRIPLE="arm64-apple-macosx13.0"
	INTEL_TRIPLE="x86_64-apple-macosx13.0"
	ARM_BUILD_DIR="$ROOT_DIR/.build/arm64/arm64-apple-macosx/release"
	INTEL_BUILD_DIR="$ROOT_DIR/.build/x86_64/x86_64-apple-macosx/release"
	UNIVERSAL_BINARY="$ROOT_DIR/.build/AltTabWindowSwitcher-universal"

	swift build -c release --package-path "$ROOT_DIR" --triple "$ARM_TRIPLE" --scratch-path "$ROOT_DIR/.build/arm64"
	swift build -c release --package-path "$ROOT_DIR" --triple "$INTEL_TRIPLE" --scratch-path "$ROOT_DIR/.build/x86_64"
	lipo -create \
		"$ARM_BUILD_DIR/AltTabWindowSwitcher" \
		"$INTEL_BUILD_DIR/AltTabWindowSwitcher" \
		-output "$UNIVERSAL_BINARY"
	APP_BINARY="$UNIVERSAL_BINARY"
else
	swift build -c release --package-path "$ROOT_DIR"
	APP_BINARY="$ROOT_DIR/.build/release/AltTabWindowSwitcher"
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$APP_BINARY" "$APP_DIR/Contents/MacOS/AltTabWindowSwitcher"
cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

CODESIGN_ARGS=(--force --deep --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
	CODESIGN_ARGS+=(--timestamp=none)
else
	CODESIGN_ARGS+=(--options runtime --timestamp)
fi

codesign "${CODESIGN_ARGS[@]}" "$APP_DIR" >/dev/null
codesign --verify --deep --strict "$APP_DIR"

echo "Built $APP_DIR (identity: $SIGNING_IDENTITY)"
