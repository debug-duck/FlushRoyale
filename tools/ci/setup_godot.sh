#!/usr/bin/env bash
# Install the pinned Godot editor (and optionally export templates) into $GODOT_HOME (default /opt/godot).
# Usage: tools/ci/setup_godot.sh [--templates]
set -euo pipefail
cd "$(dirname "$0")/../.."
source tools/ci/godot_version.env
GODOT_HOME="${GODOT_HOME:-/opt/godot}"
SUDO=""; [ "$(id -u)" != "0" ] && SUDO="sudo"
$SUDO mkdir -p "$GODOT_HOME"; $SUDO chown "$(id -u)" "$GODOT_HOME"
if [ ! -x "$GODOT_HOME/godot" ]; then
  curl -fsSL -o /tmp/godot.zip "$GODOT_BASE_URL/$GODOT_LINUX_ZIP"
  echo "$GODOT_LINUX_SHA512  /tmp/godot.zip" | sha512sum -c -
  unzip -qo /tmp/godot.zip -d "$GODOT_HOME"
  mv "$GODOT_HOME/Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_linux.x86_64" "$GODOT_HOME/godot"
  rm -f /tmp/godot.zip
fi
$SUDO ln -sf "$GODOT_HOME/godot" /usr/local/bin/godot
if [ "${1:-}" = "--templates" ]; then
  TDIR="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.${GODOT_RELEASE}"
  if [ ! -f "$TDIR/android_debug.apk" ]; then
    curl -fsSL -o /tmp/templates.tpz "$GODOT_BASE_URL/$GODOT_TEMPLATES_TPZ"
    echo "$GODOT_TEMPLATES_SHA512  /tmp/templates.tpz" | sha512sum -c -
    mkdir -p "$TDIR" /tmp/tpl && unzip -qo /tmp/templates.tpz -d /tmp/tpl
    mv /tmp/tpl/templates/* "$TDIR/" && rm -rf /tmp/tpl /tmp/templates.tpz
  fi
fi
godot --version
