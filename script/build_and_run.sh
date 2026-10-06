#!/usr/bin/env bash
set -euo pipefail

OPENLOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$OPENLOOM_ROOT"
OPENLOOM_MODE="${1:-run}"
OPENLOOM_CONFIGURATION="debug"
OPENLOOM_STAGE_ONLY=false
case "$OPENLOOM_MODE" in
  run|--build-only|--verify|--debug|--logs|--telemetry) ;;
  --release-build-only) OPENLOOM_CONFIGURATION="release" ;;
  --release-stage-only) OPENLOOM_CONFIGURATION="release"; OPENLOOM_STAGE_ONLY=true ;;
  *) echo "Usage: $0 [--build-only|--release-build-only|--release-stage-only|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac

# Never replace a live recorder, even when its UI appears idle. Stage a separate
# bundle while it is running; installation waits for an explicit normal quit.
openloom_require_idle_install() {
  local openloom_process_status
  if pgrep -x OpenLoom >/dev/null 2>&1; then
    echo "OpenLoom is running. Use --release-stage-only to build alongside it, or quit normally before replacing its bundle." >&2
    exit 1
  else
    openloom_process_status=$?
    if [ "$openloom_process_status" -ne 1 ]; then
      echo "Cannot verify whether OpenLoom is running. Use --release-stage-only; do not replace a potentially active recorder." >&2
      exit 1
    fi
  fi
}
if [ "$OPENLOOM_STAGE_ONLY" = false ]; then openloom_require_idle_install; fi

mkdir -p .build/module-cache .build/cache .build/config .build/security
export CLANG_MODULE_CACHE_PATH="$OPENLOOM_ROOT/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$OPENLOOM_ROOT/.build/module-cache"
OPENLOOM_SWIFT_FLAGS=(--disable-sandbox --cache-path "$OPENLOOM_ROOT/.build/cache" --config-path "$OPENLOOM_ROOT/.build/config" --security-path "$OPENLOOM_ROOT/.build/security")
swift build "${OPENLOOM_SWIFT_FLAGS[@]}" -c "$OPENLOOM_CONFIGURATION"
OPENLOOM_BIN="$(swift build "${OPENLOOM_SWIFT_FLAGS[@]}" -c "$OPENLOOM_CONFIGURATION" --show-bin-path)"
OPENLOOM_BUNDLE="$OPENLOOM_ROOT/dist/OpenLoom.app"
if [ "$OPENLOOM_STAGE_ONLY" = true ]; then OPENLOOM_BUNDLE="$OPENLOOM_ROOT/dist/OpenLoom-next.app"; fi
if [ "$OPENLOOM_STAGE_ONLY" = false ]; then openloom_require_idle_install; fi
mkdir -p "$OPENLOOM_BUNDLE/Contents/MacOS" "$OPENLOOM_BUNDLE/Contents/Resources"
cp "$OPENLOOM_BIN/OpenLoom" "$OPENLOOM_BUNDLE/Contents/MacOS/OpenLoom"
cp general/macos/Config/Info.plist "$OPENLOOM_BUNDLE/Contents/Info.plist"
if [ ! -x .build/make_app_icon ] || [ script/make_app_icon.swift -nt .build/make_app_icon ]; then
  swiftc script/make_app_icon.swift -o .build/make_app_icon
fi
./.build/make_app_icon .build/OpenLoom.iconset
/usr/bin/iconutil -c icns .build/OpenLoom.iconset -o "$OPENLOOM_BUNDLE/Contents/Resources/OpenLoom.icns"
chmod +x "$OPENLOOM_BUNDLE/Contents/MacOS/OpenLoom"
/usr/bin/codesign --force --sign - --entitlements general/macos/Config/OpenLoom.entitlements "$OPENLOOM_BUNDLE"
/usr/bin/codesign --verify --strict "$OPENLOOM_BUNDLE"
python3 script/privacy_audit.py "$OPENLOOM_BUNDLE"
OPENLOOM_PROBE_BUNDLE="$OPENLOOM_ROOT/dist/OpenLoomPrivacyProbe.app"
mkdir -p "$OPENLOOM_PROBE_BUNDLE/Contents/MacOS"
cp "$OPENLOOM_BIN/OpenLoomPrivacyProbe" "$OPENLOOM_PROBE_BUNDLE/Contents/MacOS/OpenLoomPrivacyProbe"
cp general/macos/Config/PrivacyProbe-Info.plist "$OPENLOOM_PROBE_BUNDLE/Contents/Info.plist"
/usr/bin/codesign --force --sign - --entitlements general/macos/Config/OpenLoom.entitlements "$OPENLOOM_PROBE_BUNDLE"

case "$OPENLOOM_MODE" in
  --build-only|--release-build-only|--release-stage-only) echo "Built: $OPENLOOM_BUNDLE" ;;
  --debug) lldb -- "$OPENLOOM_BUNDLE/Contents/MacOS/OpenLoom" ;;
  --logs)
    /usr/bin/open -n "$OPENLOOM_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'process == "OpenLoom"'
    ;;
  --telemetry)
    /usr/bin/open -n "$OPENLOOM_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "org.openloom.local"'
    ;;
  --verify)
    /usr/bin/open -n "$OPENLOOM_BUNDLE"
    sleep 2
    pgrep -x OpenLoom >/dev/null
    echo "Launch verified: OpenLoom process is running."
    ;;
  run) /usr/bin/open -n "$OPENLOOM_BUNDLE" ;;
esac
