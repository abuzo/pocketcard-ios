#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/generate_xcode_project.py --check
python3 -m unittest discover -s scripts/tests -v
swift test
(cd signer && python3 -m pytest -q)
python3 scripts/check_wire_contract.py
if command -v xcodebuild >/dev/null 2>&1; then
  bash scripts/test-ios.sh
else
  echo "SKIPPED: native iOS build and XCTest (Xcode is unavailable). Portable checks passed; native verification is still required."
fi
