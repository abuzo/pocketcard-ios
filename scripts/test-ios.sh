#!/bin/bash
# Builds and runs the native XCTest target. Requires a Mac, Xcode 16+ and an iOS Simulator.
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "ERROR: iOS tests require Xcode on macOS. They have NOT run." >&2
  exit 2
fi
xcodebuild -version
python3 scripts/generate_xcode_project.py --check
if [ -n "${SIMULATOR_UDID:-}" ]; then
  device="$SIMULATOR_UDID"
else
  device="$(xcrun simctl list devices available --json | python3 -c '
import json,sys
items=[]
for runtime,devices in json.load(sys.stdin)["devices"].items():
    if "iOS" not in runtime: continue
    for d in devices:
        if d.get("isAvailable") and "iPhone" in d["name"]:
            version=tuple(int(n) for n in runtime.split("iOS-")[-1].split("-") if n.isdigit())
            if version and version[0]>=17: items.append((d.get("state")=="Booted",version,d["udid"]))
if not items: sys.exit("Install an iOS 17+ iPhone Simulator runtime in Xcode Settings > Components.")
print(sorted(items,reverse=True)[0][2])
')"
fi
# A generic simulator build destination cannot execute XCTest; a concrete UDID is required.
xcodebuild -project ios/PocketCard.xcodeproj -scheme PocketCard -configuration Debug \
  -destination "platform=iOS Simulator,id=$device" \
  -derivedDataPath .build/DerivedData -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO test
