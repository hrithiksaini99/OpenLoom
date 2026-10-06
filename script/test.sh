#!/usr/bin/env bash
set -euo pipefail
OPENLOOM_TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$OPENLOOM_TEST_ROOT"
mkdir -p .build/module-cache .build/cache .build/config .build/security
export CLANG_MODULE_CACHE_PATH="$OPENLOOM_TEST_ROOT/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$OPENLOOM_TEST_ROOT/.build/module-cache"
# Some Swift Build versions omit the bundled Testing macro search path incrementally.
OPENLOOM_SWIFTC="$(xcrun --find swiftc)"
OPENLOOM_TEST_PLUGINS="$(dirname "$OPENLOOM_SWIFTC")/../lib/swift/host/plugins/testing"
OPENLOOM_TEST_FLAGS=()
if [ -d "$OPENLOOM_TEST_PLUGINS" ]; then
  OPENLOOM_TEST_FLAGS=(-Xswiftc -plugin-path -Xswiftc "$OPENLOOM_TEST_PLUGINS")
fi
swift test --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security "${OPENLOOM_TEST_FLAGS[@]}" "$@"
