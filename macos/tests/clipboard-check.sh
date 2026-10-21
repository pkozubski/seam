#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library -swift-version 5 -framework AppKit -framework ImageIO -framework CryptoKit -framework Security \
  macos/Seam/Sources/Security/PairingSecurity.swift \
  macos/Seam/Sources/Localization/L10n.swift \
  macos/Seam/Sources/Protocol/Protocol.swift \
  macos/Seam/Sources/Protocol/ClipboardContent.swift \
  macos/Seam/Sources/Protocol/VideoStream.swift \
  macos/Seam/Sources/App/ClipboardSync.swift \
  macos/tests/ClipboardChecks.swift -o "$TEST_DIR/clipboard-checks"
"$TEST_DIR/clipboard-checks" "$PWD/tests/fixtures/clipboard.json"
