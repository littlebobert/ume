#!/usr/bin/env bash
# Build the Debug macOS app (which bundles the Safari extension) and launch it.
#
# Usage: scripts/run-macos.sh [extra xcodebuild arguments]
#
# After it launches, enable Ume in Safari > Settings > Extensions. If Safari
# will not load a development build, use Develop > Allow Unsigned Extensions.
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="Safari/Ume/Ume.xcodeproj"
SCHEME="Ume (macOS)"
CONFIGURATION="Debug"

echo "Building $SCHEME ($CONFIGURATION)…"
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -quiet \
  -allowProvisioningUpdates \
  "$@"

settings=$(xcodebuild -showBuildSettings \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  "$@" 2>/dev/null)
products_dir=$(sed -n 's/^ *BUILT_PRODUCTS_DIR = //p' <<<"$settings" | head -n 1)
product_name=$(sed -n 's/^ *FULL_PRODUCT_NAME = //p' <<<"$settings" | head -n 1)
app="$products_dir/$product_name"

if [[ ! -d "$app" ]]; then
  echo "Built app not found at: $app" >&2
  exit 1
fi

bundle_id=$(defaults read "$app/Contents/Info" CFBundleIdentifier)
if pgrep -x "${product_name%.app}" >/dev/null 2>&1; then
  echo "Quitting the running copy of ${product_name%.app}…"
  osascript -e "quit app id \"$bundle_id\"" >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do
    pgrep -x "${product_name%.app}" >/dev/null 2>&1 || break
    sleep 0.25
  done
fi

echo "Launching $app"
open "$app"
echo "Done. Enable Ume in Safari > Settings > Extensions, then open http://localhost:8000 (npm run test-form)."
