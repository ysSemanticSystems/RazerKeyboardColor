#!/bin/zsh

# run.sh
# KeyboardColor
#
# Builds the debug binary and replaces this process with the window.
# A release build is smaller; this script keeps the debug path so symbols remain available while developing.

set -euo pipefail
cd "$(dirname "$0")"
swift build --disable-sandbox
bin="$(swift build --disable-sandbox --show-bin-path)/KeyboardColor"
exec "$bin"
