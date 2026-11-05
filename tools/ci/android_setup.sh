#!/usr/bin/env bash
# Prepare Android SDK components, a throw-away DEBUG keystore and Godot editor settings for a non-gradle export.
# No secrets are involved: the debug keystore is generated fresh each run and never committed.
set -euo pipefail
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/usr/local/lib/android/sdk}}"
JAVA="${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(which java)")")")}"
SDKMANAGER="$SDK/cmdline-tools/latest/bin/sdkmanager"
yes | "$SDKMANAGER" --licenses >/dev/null 2>&1 || true
"$SDKMANAGER" --install "platform-tools" "build-tools;35.0.1" "build-tools;34.0.0" "platforms;android-35" "platforms;android-34" "cmdline-tools;latest" >/dev/null
mkdir -p "$HOME/.android" "$HOME/.config/godot"
KS="$HOME/.android/debug.keystore"
if [ ! -f "$KS" ]; then
  keytool -keyalg RSA -genkeypair -alias androiddebugkey -keypass android -keystore "$KS" -storepass android \
    -dname "CN=Android Debug,O=Android,C=US" -validity 9999 -deststoretype pkcs12
fi
cat > "$HOME/.config/godot/editor_settings-4.4.tres" <<TRES
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$SDK"
export/android/java_sdk_path = "$JAVA"
export/android/debug_keystore = "$KS"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
export/android/force_system_user = false
TRES
echo "ANDROID_SDK=$SDK JAVA=$JAVA KEYSTORE=$KS"
