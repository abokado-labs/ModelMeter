#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_DIR="$ROOT_DIR/build/DerivedData"

xcodebuild \
  -project "$ROOT_DIR/ModelMeter.xcodeproj" \
  -scheme ModelMeter \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  build

echo "$DERIVED_DATA_DIR/Build/Products/Debug/Model Meter.app"
