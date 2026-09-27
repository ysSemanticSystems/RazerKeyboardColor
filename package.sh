#!/bin/zsh

# package.sh
# KeyboardColor
#
# Builds a release Razer Color Manager.app and a drag-to-Applications disk image.
# The image is written read-write first so Finder can store the background and icon layout, then compressed.

set -euo pipefail
cd "$(dirname "$0")"
source ./packaging/bundle-app.sh

name="Razer Color Manager"
dmg_name="RazerColorManager.dmg"
stage="dist/dmg-root"
scratch="dist/scratch"
final="dist/${dmg_name}"
# Finder paints the background at 1:1 pixels. A 2x canvas shows only a corner of the art.
window_width=660
window_height=400
icon_left=160
icon_right=500
icon_y=180
window_right=$((360 + window_width))
window_bottom=$((140 + window_height))

swift build -c release --disable-sandbox -Xswiftc -Osize -Xlinker -dead_strip
bin="$(swift build -c release --disable-sandbox --show-bin-path)/KeyboardColor"
"$bin" --check
strip -x "$bin"

rm -rf dist
mkdir -p "$stage/.background"
bundle_app "$bin" "$stage/${name}.app"
# Ad-hoc signing lets the copy in Applications launch on this Mac without a Developer ID.
codesign --force --sign - "$stage/${name}.app"
ln -s /Applications "$stage/Applications"
cp Assets/dmg-background.tiff "$stage/.background/background.tiff"
cp Sources/KeyboardColor/Resources/AppIcon.icns "$stage/.VolumeIcon.icns"

rm -f "${scratch}.dmg" "$final"
hdiutil create -ov -fs HFS+ -volname "$name" -srcfolder "$stage" -format UDRW -o "$scratch" >/dev/null
hdiutil attach -readwrite -noverify -noautoopen "${scratch}.dmg" >/dev/null
mount_dir="/Volumes/${name}"
if [[ ! -d "$mount_dir" ]]; then
    echo "package.sh: the disk image did not mount." >&2
    exit 1
fi

if command -v SetFile >/dev/null; then
    SetFile -a V "$mount_dir/.background"
    SetFile -c icnC "$mount_dir/.VolumeIcon.icns"
    SetFile -a C "$mount_dir"
fi

osascript <<EOF
tell application "Finder"
    tell disk "$name"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {360, 140, ${window_right}, ${window_bottom}}
        set theView to icon view options of container window
        set arrangement of theView to not arranged
        set icon size of theView to 128
        set background picture of theView to file ".background:background.tiff"
        set position of item "${name}.app" of container window to {${icon_left}, ${icon_y}}
        set position of item "Applications" of container window to {${icon_right}, ${icon_y}}
        update without registering applications
        delay 1
        close
        open
        delay 1
        close
    end tell
end tell
EOF

sync
hdiutil detach "$mount_dir" >/dev/null
hdiutil convert "${scratch}.dmg" -format UDZO -imagekey zlib-level=9 -o "$final" >/dev/null
rm -f "${scratch}.dmg"
rm -rf "$stage"

echo "$final"
