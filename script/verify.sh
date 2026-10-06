#!/usr/bin/env bash
set -euo pipefail
OPENLOOM_VERIFY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$OPENLOOM_VERIFY_ROOT"

# Local verification only. Does not launch the recorder or open capture devices.
./script/test.sh
./script/build_and_run.sh --release-stage-only
/usr/bin/codesign --verify --strict dist/OpenLoom-next.app
python3 script/privacy_audit.py dist/OpenLoom-next.app
./dist/OpenLoomPrivacyProbe.app/Contents/MacOS/OpenLoomPrivacyProbe
echo "Local verification passed. The staged bundle is dist/OpenLoom-next.app; device acceptance is separate."
