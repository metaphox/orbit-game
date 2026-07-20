#!/bin/sh
# Export release builds for all three desktop platforms into build/.
# Requires Godot 4.7's export templates installed (Editor > Manage Export
# Templates, or download Godot_v4.7.1-stable_export_templates.tpz into
# ~/Library/Application Support/Godot/export_templates/4.7.1.stable/).
set -e
cd "$(dirname "$0")/.."
mkdir -p build/macos build/windows build/linux
godot --headless --export-release "macOS" "$(pwd)/build/macos/OrbitGame.app"
godot --headless --export-release "Windows Desktop" "$(pwd)/build/windows/OrbitGame.exe"
godot --headless --export-release "Linux" "$(pwd)/build/linux/OrbitGame.x86_64"
echo "Builds in build/macos, build/windows, build/linux"
