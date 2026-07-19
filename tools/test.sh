#!/bin/sh
# Headless test run. The --import pass first refreshes Godot's global
# script-class cache so newly added class_name scripts resolve.
set -e
cd "$(dirname "$0")/.."
godot --headless --import >/dev/null 2>&1 || true
godot --headless -s res://addons/gut/gut_cmdln.gd
