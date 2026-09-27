#!/bin/zsh

# bundle-app.sh
# KeyboardColor
#
# Assembles Razer Color Manager.app around a built KeyboardColor binary.
# The icns is stored in Contents/Resources so a copy in Applications still has a Dock mark.

set -euo pipefail

bundle_app() {
    local bin="$1"
    local app="$2"
    local root="$PWD"
    if [[ ! -f "$root/packaging/Info.plist" ]]; then
        echo "bundle_app: run from the repository root." >&2
        return 1
    fi

    rm -rf "$app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    cp "$bin" "$app/Contents/MacOS/KeyboardColor"
    chmod +x "$app/Contents/MacOS/KeyboardColor"
    cp "$root/Sources/KeyboardColor/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
    cp "$root/packaging/Info.plist" "$app/Contents/Info.plist"
    # The icns lives in Contents/Resources. A SwiftPM .bundle next to the executable is not a signed nested bundle.
}
