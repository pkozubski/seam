#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library -swift-version 5 -framework AppKit -framework CryptoKit -framework Security \
  BorderlessMouse/Sources/Localization/L10n.swift \
  BorderlessMouse/Sources/Security/ArtifactSignature.swift \
  BorderlessMouse/Sources/App/ReleaseSignature.swift \
  BorderlessMouse/Sources/App/UpdatePolicy.swift \
  BorderlessMouse/Sources/App/Updater.swift tests/UpdateChecks.swift -o "$TEST_DIR/update-checks"
"$TEST_DIR/update-checks"
