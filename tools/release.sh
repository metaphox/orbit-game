#!/bin/sh
# Release pipeline: export packaged builds for Windows, macOS, and Linux.
#
# Portable POSIX sh — runs on macOS and Linux (and Linux CI). Godot can
# cross-export to every desktop target from any host, so one machine (or one
# CI runner) produces all three artifacts.
#
#   tools/release.sh              # build + package all three
#   tools/release.sh windows      # just one (windows | macos | linux)
#   tools/release.sh windows linux
#
# Output: dist/OrbitGame-<version>-<platform>.(zip|tar.gz) + a checksums file.
# <version> comes from `git describe` (a tag like v0.3.0, else a short SHA).
#
# Requires Godot 4.7's export templates. Install them from the editor
# (Editor > Manage Export Templates) or drop the .tpz for your Godot version
# into the templates dir printed below if they are missing.
set -eu

cd "$(dirname "$0")/.."
ROOT=$(pwd)

# --- locate Godot -----------------------------------------------------------
GODOT_BIN=${GODOT:-}
if [ -z "$GODOT_BIN" ]; then
	for c in godot godot4 Godot; do
		if command -v "$c" >/dev/null 2>&1; then GODOT_BIN=$c; break; fi
	done
fi
[ -n "$GODOT_BIN" ] || { echo "error: Godot not found. Set \$GODOT or put 'godot' on PATH." >&2; exit 1; }

GODOT_VER=$("$GODOT_BIN" --version 2>/dev/null | head -n1)
# "4.7.1.stable.official.a13da4feb" -> "4.7.1.stable" (the templates dir name)
TEMPLATE_ID=$(printf '%s' "$GODOT_VER" | cut -d. -f1-4)

# --- verify export templates are installed ----------------------------------
case "$(uname)" in
	Darwin) TPL_DIR="$HOME/Library/Application Support/Godot/export_templates/$TEMPLATE_ID" ;;
	*)      TPL_DIR="$HOME/.local/share/godot/export_templates/$TEMPLATE_ID" ;;
esac
if [ ! -d "$TPL_DIR" ]; then
	echo "error: export templates for $TEMPLATE_ID not found at:" >&2
	echo "       $TPL_DIR" >&2
	echo "       Install via Editor > Manage Export Templates, or drop the matching .tpz there." >&2
	exit 1
fi

# --- version + sha256 helpers -----------------------------------------------
VERSION=$(git describe --tags --always --dirty 2>/dev/null || echo dev)
if command -v sha256sum >/dev/null 2>&1; then SHA="sha256sum"; else SHA="shasum -a 256"; fi

DIST="$ROOT/dist"
rm -rf "$DIST"
mkdir -p "$DIST" build/macos build/windows build/linux

# export <preset> <raw-output-path>
export_one() {
	echo "==> exporting: $1"
	"$GODOT_BIN" --headless --export-release "$1" "$2" 2>&1 | sed 's/^/    /'
	[ -e "$2" ] || { echo "error: export produced nothing at $2" >&2; exit 1; }
}

# zip_dir <parent-dir> <entry-name> <out.zip>  — bundle-safe archiving
zip_dir() {
	if [ "$(uname)" = "Darwin" ]; then
		( cd "$1" && ditto -c -k --keepParent "$2" "$3" )
	else
		( cd "$1" && zip -q -r -y "$3" "$2" )
	fi
}

want() { # is platform $1 requested?
	[ "$BUILD_ALL" = 1 ] && return 0
	for p in $REQUESTED; do [ "$p" = "$1" ] && return 0; done
	return 1
}

# --- parse args -------------------------------------------------------------
REQUESTED="$*"
BUILD_ALL=0
[ -z "$REQUESTED" ] && BUILD_ALL=1

echo "Limited Propellant — release $VERSION  (Godot $GODOT_VER)"

if want windows; then
	export_one "Windows Desktop" "$ROOT/build/windows/OrbitGame.exe"
	zip_dir "$ROOT/build/windows" "OrbitGame.exe" "$DIST/OrbitGame-$VERSION-windows.zip"
fi

if want linux; then
	export_one "Linux" "$ROOT/build/linux/OrbitGame.x86_64"
	chmod +x "$ROOT/build/linux/OrbitGame.x86_64"
	tar -C "$ROOT/build/linux" -czf "$DIST/OrbitGame-$VERSION-linux.tar.gz" OrbitGame.x86_64
fi

if want macos; then
	export_one "macOS" "$ROOT/build/macos/OrbitGame.app"
	zip_dir "$ROOT/build/macos" "OrbitGame.app" "$DIST/OrbitGame-$VERSION-macos.zip"
fi

# --- manifest ---------------------------------------------------------------
echo
echo "Packaged into dist/:"
( cd "$DIST" && ls -1 && echo && $SHA ./* > CHECKSUMS.txt && cat CHECKSUMS.txt )
