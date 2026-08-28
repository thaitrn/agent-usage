#!/bin/zsh
# Builds dist/Agent Usage.app from the SwiftPM executable.
#   ./scripts/build-app.sh            build only
#   ./scripts/build-app.sh --install  build, copy to /Applications, launch it
set -eu

cd "${0:a:h}/.."

app_name="Agent Usage"
bundle_id="com.thaitrn.agentusage"
version="1.0.0"
executable="AIProviderMenuBar"
app="dist/${app_name}.app"

swift build -c release
binary="$(swift build -c release --show-bin-path)/${executable}"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/${executable}"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>${app_name}</string>
	<key>CFBundleDisplayName</key><string>${app_name}</string>
	<key>CFBundleIdentifier</key><string>${bundle_id}</string>
	<key>CFBundleExecutable</key><string>${executable}</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>${version}</string>
	<key>CFBundleVersion</key><string>${version}</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<!-- Menu bar only: no Dock icon, no app switcher entry. -->
	<key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature. It changes on every build, so macOS re-asks for Keychain
# access to the Claude Code credentials after each rebuild — answer Always Allow.
codesign --force --sign - "$app" >/dev/null 2>&1

echo "Built $app"

if [[ "${1:-}" == "--install" ]]; then
    installed="/Applications/${app_name}.app"
    osascript -e "quit app \"${app_name}\"" >/dev/null 2>&1 || true
    pkill -f "${executable}" >/dev/null 2>&1 || true
    rm -rf "$installed"
    cp -R "$app" "$installed"
    open "$installed"
    echo "Installed and launched $installed"
fi
