#!/bin/sh
# build decant and assemble a launchable .app bundle. no xcode project, just
# swiftpm plus a hand-written Info.plist, so it builds against the command
# line tools sdk.
set -e
cd "$(dirname "$0")/.."

CONF=${1:-release}
swift build -c "$CONF"
BIN="$(swift build -c "$CONF" --show-bin-path)/decant"

APP="build/decant.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/decant"
cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
mkdir -p "$APP/Contents/Resources/Fonts"
cp Resources/Fonts/*.ttf "$APP/Contents/Resources/Fonts/"
cp Resources/logo-d.png "$APP/Contents/Resources/logo-d.png"
cp Resources/cellar-bg.jpg "$APP/Contents/Resources/cellar-bg.jpg"
mkdir -p "$APP/Contents/Resources/pour"
cp Resources/pour/*.png "$APP/Contents/Resources/pour/"

# deploy launch wrapper + engine recipe so the .app works without the git tree
ENGINE_DIR="$HOME/Library/Application Support/decant/engine"
mkdir -p "$ENGINE_DIR"
cp scripts/decant-launch.sh "$ENGINE_DIR/decant-launch.sh"
chmod +x "$ENGINE_DIR/decant-launch.sh"
if [ -d engine/scripts ]; then
  rsync -a \
    --exclude 'vendor' \
    --exclude '.git' \
    --exclude '.DS_Store' \
    engine/ "$ENGINE_DIR/"
  # launch script stays the UI entrypoint at engine/decant-launch.sh
  cp scripts/decant-launch.sh "$ENGINE_DIR/decant-launch.sh"
  chmod +x "$ENGINE_DIR/decant-launch.sh"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>decant</string>
  <key>CFBundleDisplayName</key><string>decant</string>
  <key>CFBundleIdentifier</key><string>com.sophia.decant</string>
  <key>CFBundleExecutable</key><string>decant</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
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
