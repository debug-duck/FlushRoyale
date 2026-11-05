#!/usr/bin/env bash
# Build the Android DEBUG apk:  tools/ci/setup_godot.sh --templates && tools/ci/android_setup.sh && tools/ci/build_apk.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="${GODOT_ANDROID_KEYSTORE_DEBUG_PATH:-$HOME/.android/debug.keystore}"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER="androiddebugkey"
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="android"
# first import occasionally exits non-zero on a cold checkout; a second pass is clean
godot --headless --path . --import || true
godot --headless --path . --import
godot --headless --path . --export-debug "Android" build/flush-royale-debug.apk
ls -la build/
unzip -l build/flush-royale-debug.apk | tail -3
