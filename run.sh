#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
swift build --disable-sandbox
bin="$(swift build --disable-sandbox --show-bin-path)/KeyboardColor"
exec "$bin"
