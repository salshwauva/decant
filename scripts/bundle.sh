#!/bin/sh
# build hearth and assemble a launchable .app bundle. no xcode project, just
# swiftpm plus a hand-written Info.plist, so it builds against the command
# line tools sdk.
set -e
cd "$(dirname "$0")/.."

CONF=${1:-release}
swift build -c "$CONF"
BIN="$(swift build -c "$CONF" --show-bin-path)/hearth"

APP="build/hearth.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/hearth"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>hearth</string>
  <key>CFBundleDisplayName</key><string>hearth</string>
  <key>CFBundleIdentifier</key><string>com.sophia.hearth</string>
  <key>CFBundleExecutable</key><string>hearth</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>0.0.0</string>
  <key>CFBundleShortVersionString</key><string>0.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "built $APP"
