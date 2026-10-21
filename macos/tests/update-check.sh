#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library -swift-version 5 -framework AppKit -framework CryptoKit -framework Security \
  Seam/Sources/Localization/L10n.swift \
  Seam/Sources/Security/ArtifactSignature.swift \
  Seam/Sources/App/ReleaseSignature.swift \
  Seam/Sources/App/UpdatePolicy.swift \
  Seam/Sources/App/Updater.swift tests/UpdateChecks.swift -o "$TEST_DIR/update-checks"
"$TEST_DIR/update-checks"
