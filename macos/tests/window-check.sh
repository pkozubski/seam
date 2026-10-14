#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library -swift-version 5 -framework AppKit -framework CryptoKit -framework Security \
  -framework VideoToolbox -framework CoreMedia -framework CoreVideo \
  -import-objc-header macos/BorderlessMouse/Sources/Display/CGVirtualDisplay.h \
  macos/BorderlessMouse/Sources/Security/PairingSecurity.swift \
  macos/BorderlessMouse/Sources/Localization/L10n.swift \
  macos/BorderlessMouse/Sources/Protocol/Protocol.swift \
  macos/BorderlessMouse/Sources/Protocol/ClipboardContent.swift \
  macos/BorderlessMouse/Sources/Protocol/VideoStream.swift \
  macos/BorderlessMouse/Sources/Display/VirtualDisplay.swift \
  macos/BorderlessMouse/Sources/Display/WindowControl.swift \
  macos/BorderlessMouse/Sources/Display/WindowTracker.swift \
  macos/BorderlessMouse/Sources/Display/VideoEncoder.swift \
  macos/tests/WindowChecks.swift -o "$TEST_DIR/window-checks"
"$TEST_DIR/window-checks"
