#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
DEST="${1:-platform=iOS Simulator,name=iPhone 17}"
xcodebuild -scheme Loggy -destination "$DEST" build test
