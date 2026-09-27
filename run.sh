#!/bin/zsh

# run.sh
# KeyboardColor
#
# Builds the debug binary, wraps it in an app bundle, and replaces this process with the window.
# The bundle carries AppIcon.icns. A release disk image is package.sh; this script keeps the debug path so symbols remain available while developing.

set -euo pipefail
cd "$(dirname "$0")"
source ./packaging/bundle-app.sh
swift build --disable-sandbox
bin="$(swift build --disable-sandbox --show-bin-path)/KeyboardColor"
app="$(swift build --disable-sandbox --show-bin-path)/Razer Color Manager.app"
bundle_app "$bin" "$app"
exec "$app/Contents/MacOS/KeyboardColor"
