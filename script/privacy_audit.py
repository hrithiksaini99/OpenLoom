#!/usr/bin/env python3
"""Check the signed app's entitlement boundary and obvious source-level network paths.

This is a regression guard, not a general-purpose security audit or packet capture.
"""
import pathlib
import plistlib
import re
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parents[1]
bundle = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else root / "dist/OpenLoom.app"
result = subprocess.run(
    ["/usr/bin/codesign", "-d", "--entitlements", ":-", str(bundle)],
    capture_output=True, check=True,
)
entitlements = plistlib.loads(result.stdout)
expected = {
    "com.apple.security.app-sandbox": True,
    "com.apple.security.device.audio-input": True,
    "com.apple.security.device.camera": True,
}
if entitlements != expected:
    raise SystemExit("FAIL: signed entitlements do not match the local-only allowlist")

blocked = re.compile(
    r"URLSession|URLRequest|import\s+(?:Network|WebKit)|WKWebView|NSAppleScript|"
    r"\bProcess\s*\(|\bsocket\s*\(|\bconnect\s*\(|https?://|"
    r"NSWorkspace\s*\.\s*shared\s*\.\s*open\s*\(|"
    r"\bSFSpeechRecognizer\b|\bassetInstallationRequest\s*\(|\bdownloadAndInstall\s*\("
)
for source in (root / "general/macos/Sources").rglob("*.swift"):
    if blocked.search(source.read_text()):
        raise SystemExit("FAIL: review a network/external-process path in " + str(source.relative_to(root)))

print("PASS: signed App Sandbox enabled; network client/server entitlements absent")
print("PASS: production sources have no listed network, webview, or process-launch APIs")
print("PASS: no server speech recognizer or speech asset download calls")
