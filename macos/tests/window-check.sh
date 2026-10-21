#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library -swift-version 5 -framework AppKit -framework CryptoKit -framework Security \
  -framework VideoToolbox -framework CoreMedia -framework CoreVideo \
  -import-objc-header macos/Seam/Sources/Display/CGVirtualDisplay.h \
  macos/Seam/Sources/Security/PairingSecurity.swift \
  macos/Seam/Sources/Localization/L10n.swift \
  macos/Seam/Sources/Protocol/Protocol.swift \
  macos/Seam/Sources/Protocol/ClipboardContent.swift \
  macos/Seam/Sources/Protocol/VideoStream.swift \
  macos/Seam/Sources/Display/VirtualDisplay.swift \
  macos/Seam/Sources/Display/WindowControl.swift \
  macos/Seam/Sources/Display/WindowTracker.swift \
  macos/Seam/Sources/Display/VideoEncoder.swift \
  macos/tests/WindowChecks.swift -o "$TEST_DIR/window-checks"
"$TEST_DIR/window-checks"
