#!/bin/bash
# Builds PPTX Link Editor as a double-clickable macOS .app and packages it into a
# .zip ready to copy to other machines (universal binary arm64 + x86_64).
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="PPTX Link Editor"
BUNDLE_ID="com.angelbadillo.pptxlinkeditor"
VERSION="1.0"

# Try a universal binary; if the SDK lacks x86_64, fall back to the native arch.
ARCH_FLAGS="--arch arm64 --arch x86_64"
echo "▶︎ Building release (universal arm64 + x86_64)…"
if ! swift build -c release --product PPTXLinkEditor $ARCH_FLAGS 2>/dev/null; then
    echo "  (x86_64 unavailable; building for this architecture only)"
    ARCH_FLAGS=""
    swift build -c release --product PPTXLinkEditor
fi

BIN_PATH="$(swift build -c release --product PPTXLinkEditor $ARCH_FLAGS --show-bin-path)/PPTXLinkEditor"
APP="$APP_NAME.app"

echo "▶︎ Building bundle $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/PPTXLinkEditor"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>     <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>         <string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleExecutable</key>      <string>PPTXLinkEditor</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>PowerPoint Presentation</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSItemContentTypes</key>
            <array><string>org.openxmlformats.presentationml.presentation</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Ad-hoc signature: required so the binary (especially on Apple Silicon) can run.
# It's not an Apple certificate, so on other machines it must be authorized the first
# time (see instructions at the end).
echo "▶︎ Signing (ad-hoc)…"
codesign --force --deep --sign - "$APP"

echo "▶︎ Preparing distribution folder…"
DIST="$APP_NAME (distribution)"
rm -rf "$DIST"
mkdir -p "$DIST"
cp -R "$APP" "$DIST/"

# Double-clickable unlock script. Runs ON THE TARGET MACHINE: removes the quarantine
# flag from the app next to it and opens it. Also clears its own quarantine.
OPENER="$DIST/▶︎ Open the app (first time).command"
cat > "$OPENER" <<OPEN
#!/bin/bash
# Unlocks the app (removes macOS quarantine flag) and opens it.
DIR="\$(cd "\$(dirname "\$0")" && pwd)"
APP="\$DIR/$APP_NAME.app"
echo "Unlocking \$APP …"
xattr -dr com.apple.quarantine "\$APP" 2>/dev/null
xattr -dr com.apple.quarantine "\$0"  2>/dev/null
open "\$APP" && echo "Done. The app should be opening." || echo "Couldn't find the app next to this script."
OPEN
chmod +x "$OPENER"

cat > "$DIST/READ ME — how to open.txt" <<TXT
PPTX Link Editor
================

This app is NOT signed with a paid Apple certificate, so macOS blocks it the first
time. You have two ways to open it:

OPTION 1 (easiest) — the unlock script
  1. RIGHT-CLICK "▶︎ Open the app (first time).command" → "Open".
  2. In the dialog, click "Open". The block is removed and the app launches.
  (Only needed the first time. Afterwards you can open the app with a double-click.)

OPTION 2 — manual
  1. Right-click "$APP_NAME.app" → "Open" → "Open".

If you prefer, move "$APP_NAME.app" to /Applications.
Requires macOS 13 or later. Works on Intel and Apple Silicon Macs.
TXT

echo "▶︎ Packaging for distribution…"
ZIP="$APP_NAME.zip"
rm -f "$ZIP"
find "$DIST" -name '.DS_Store' -delete 2>/dev/null || true
# ditto preserves permissions, links and the bundle signature (better than plain zip).
ditto -c -k --keepParent "$DIST" "$ZIP"

echo ""
echo "✓ App:        $APP"
echo "✓ Folder:     $DIST/  (app + unlock script + READ ME)"
echo "✓ DISTRIBUTE: copy this file to other machines →  $ZIP"
echo "   Architectures: $(lipo -archs "$APP/Contents/MacOS/PPTXLinkEditor" 2>/dev/null || echo 'native')"
echo ""
echo "── On the target machine ───────────────────────────────────────────────"
echo "Unzip and RIGHT-CLICK → \"Open\" on"
echo "\"▶︎ Open the app (first time).command\". It removes the block and opens the app."
echo "────────────────────────────────────────────────────────────────────────"
