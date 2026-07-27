#!/bin/bash

set -euo pipefail

if [[ $# -ne 4 ]]; then
    echo "Usage: $0 <source.ipa> <output.ipa> <icon.png> <work-directory>" >&2
    exit 2
fi

SOURCE_IPA="$1"
OUTPUT_IPA="$2"
SOURCE_ICON="$3"
WORK_DIR="$4"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
unzip -q "$SOURCE_IPA" -d "$WORK_DIR"

APP_PATH="$(find "$WORK_DIR/Payload" -maxdepth 1 -type d -name '*.app' -print -quit)"
if [[ -z "$APP_PATH" ]]; then
    echo "No .app bundle was found in $SOURCE_IPA" >&2
    exit 1
fi

INFO_PLIST="$APP_PATH/Info.plist"

# A free Apple ID can sign the main application, but not Telegram's App Group,
# push, Siri, widget, watch, or notification extension capabilities.
rm -rf \
    "$APP_PATH/PlugIns" \
    "$APP_PATH/Watch" \
    "$APP_PATH/_CodeSignature"
rm -f "$APP_PATH/embedded.mobileprovision"

while IFS= read -r -d '' signed_item; do
    /usr/bin/codesign --remove-signature "$signed_item" >/dev/null 2>&1 || true
done < <(find "$APP_PATH" \( -type d -name '*.framework' -o -type f -name '*.dylib' \) -print0)
/usr/bin/codesign --remove-signature "$APP_PATH" >/dev/null 2>&1 || true

"$PLIST_BUDDY" -c "Set :CFBundleDisplayName Congyugram" "$INFO_PLIST"
"$PLIST_BUDDY" -c "Set :CFBundleName Congyugram" "$INFO_PLIST"

make_icon() {
    local size="$1"
    local destination="$2"
    /usr/bin/sips -s format png -z "$size" "$size" "$SOURCE_ICON" --out "$destination" >/dev/null
}

make_icon 60 "$APP_PATH/CongyugramIcon60.png"
make_icon 120 "$APP_PATH/CongyugramIcon60@2x.png"
make_icon 180 "$APP_PATH/CongyugramIcon60@3x.png"
make_icon 76 "$APP_PATH/CongyugramIcon76.png"
make_icon 152 "$APP_PATH/CongyugramIcon76@2x.png"
make_icon 167 "$APP_PATH/CongyugramIcon83.5@2x.png"

# Keep Telegram's optional icon choices, but replace the primary icon with the
# Congyugram icon. Omitting CFBundleIconName makes iOS use these PNG files
# instead of the original icon embedded in Assets.car.
"$PLIST_BUDDY" -c "Delete :CFBundleIcons:CFBundlePrimaryIcon" "$INFO_PLIST" 2>/dev/null || true
"$PLIST_BUDDY" -c "Add :CFBundleIcons:CFBundlePrimaryIcon dict" "$INFO_PLIST"
"$PLIST_BUDDY" -c "Add :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconFiles array" "$INFO_PLIST"
"$PLIST_BUDDY" -c "Add :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconFiles:0 string CongyugramIcon60" "$INFO_PLIST"

"$PLIST_BUDDY" -c "Delete :CFBundleIcons~ipad:CFBundlePrimaryIcon" "$INFO_PLIST" 2>/dev/null || true
"$PLIST_BUDDY" -c "Add :CFBundleIcons~ipad:CFBundlePrimaryIcon dict" "$INFO_PLIST"
"$PLIST_BUDDY" -c "Add :CFBundleIcons~ipad:CFBundlePrimaryIcon:CFBundleIconFiles array" "$INFO_PLIST"
"$PLIST_BUDDY" -c "Add :CFBundleIcons~ipad:CFBundlePrimaryIcon:CFBundleIconFiles:0 string CongyugramIcon60" "$INFO_PLIST"
"$PLIST_BUDDY" -c "Add :CFBundleIcons~ipad:CFBundlePrimaryIcon:CFBundleIconFiles:1 string CongyugramIcon76" "$INFO_PLIST"
"$PLIST_BUDDY" -c "Add :CFBundleIcons~ipad:CFBundlePrimaryIcon:CFBundleIconFiles:2 string CongyugramIcon83.5" "$INFO_PLIST"

# Push and VoIP are intentionally unavailable in this free-signed build.
"$PLIST_BUDDY" -c "Delete :UIBackgroundModes" "$INFO_PLIST" 2>/dev/null || true
"$PLIST_BUDDY" -c "Add :UIBackgroundModes array" "$INFO_PLIST"
"$PLIST_BUDDY" -c "Add :UIBackgroundModes:0 string audio" "$INFO_PLIST"
"$PLIST_BUDDY" -c "Add :UIBackgroundModes:1 string fetch" "$INFO_PLIST"
"$PLIST_BUDDY" -c "Add :UIBackgroundModes:2 string location" "$INFO_PLIST"

if find "$APP_PATH" -maxdepth 2 -type d \( -name '*.appex' -o -name '*.app' \) ! -path "$APP_PATH" | grep -q .; then
    echo "Unexpected embedded application or extension remains in the IPA." >&2
    exit 1
fi
if [[ -e "$APP_PATH/embedded.mobileprovision" || -d "$APP_PATH/_CodeSignature" ]]; then
    echo "The IPA still contains a provisioning profile or main signature." >&2
    exit 1
fi
if [[ "$("$PLIST_BUDDY" -c "Print :CFBundleDisplayName" "$INFO_PLIST")" != "Congyugram" ]]; then
    echo "CFBundleDisplayName validation failed." >&2
    exit 1
fi

mkdir -p "$(dirname "$OUTPUT_IPA")"
OUTPUT_IPA="$(cd "$(dirname "$OUTPUT_IPA")" && pwd)/$(basename "$OUTPUT_IPA")"
rm -f "$OUTPUT_IPA"
(
    cd "$WORK_DIR"
    zip -qry "$OUTPUT_IPA" Payload
)

echo "Prepared sideload IPA: $OUTPUT_IPA"
