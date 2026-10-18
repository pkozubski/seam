# Changelog

## Unreleased

### Updates

- macOS and Windows share the signed `dev-build` release and version number. Test builds
  check every two minutes and install during inactivity, deferring restarts while remote
  control or transferred windows are in use. macOS rechecks inactivity after downloading.
- Local builds read the shared `VERSION` file instead of silently identifying as 1.0.0.
- Older stable-channel Mac builds need one initial installation of the test build.

### Fixed

- Below 150% Windows scaling the virtual display uses a 2x HiDPI backing and capture downsamples
  to Windows monitor pixels, so Mac text is Retina-rendered and shown 1:1 instead of soft 1x output.
- Draw the Mac application menu in the Windows title bar next to the window title on a Mica
  backdrop instead of a separate light Win32 menu row; DWM keeps the caption buttons and Snap.
- Recognize Chrome's layer-zero `AXWindow/AXUnknown` omnibox and extension bubbles
  by their subrole and native window controls, instead of giving every AXWindow a
  separate application caption/menu. Do not make transient surfaces AXMain on click.
- Remove dismissed popup streams immediately, even when Chrome keeps their hidden
  CG windows alive. Fullscreen retention applies only to verified application owners
  with a fullscreen transient, never to arbitrary maximized sibling windows.
- Keep the native menu's Windows redirection surface so the row below a transferred
  window's caption renders normally instead of revealing the desktop through a gap.
- Mac window proxies use native Windows captions, resize borders, application menus and
  DWM corners. Maximize, Snap and DPI changes request a matching source window size.
- Preserve video aspect ratio and map input/popups to the actual displayed image. Keep
  captions accessible across disjoint monitor layouts and disconnected displays.
- Associate transient windows with their application, including layer-zero browser
  suggestions identified through Accessibility; capture child surfaces separately.
- Serialize ScreenCaptureKit size changes, discard stale encoder callbacks and cached
  buffers after resize, and reset H.264 decoding after queue overflow. Capture at the
  negotiated resolution during HiDPI/fullscreen transitions and improve encoding quality.

### Added

- **Mac virtual display on Windows** (experimental). macOS creates a driverless virtual display
  (`CGVirtualDisplay`) next to the edge facing Windows, captures it with ScreenCaptureKit,
  encodes it with hardware H.264 (VideoToolbox, low-latency rate control) and streams it over
  a separate, one-time TCP connection encrypted with a per-stream AES-256-GCM key. Windows
  decodes it with Media Foundation on the GPU (software fallback) and shows it full screen on
  the monitor next to the Mac while the pointer is on the virtual display.
- Protocol: `DISPLAY_START/STOP/READY/KEYFRAME/FOCUS` (0x80–0x84), new `STATUS` bits and an
  optional flags byte in `LEAVE`. Windows only uses them when the Mac advertises support, so
  mixed versions keep working.
- macOS: Screen Recording permission row, "Share a virtual display" toggle and stream status;
  `--display-selftest` diagnostic.
- Windows: "Mac display" card with a toggle, "show it whenever you control the Mac" option,
  status, throughput and restart.
- **Window mode** (default): every Mac window dragged onto the virtual display becomes a real
  Windows window styled like macOS — antialiased rounded corners (DirectComposition +
  Direct2D/DirectWrite), the macOS pointer shape mirrored with Windows system cursors, the Mac window's own title bar, and a dark
  macOS-style menu bar above it with the app's menu (read through Accessibility, with shortcuts
  and disabled/checked states) instead of the Mac menu bar; dragging and double-click maximize
  from that bar (the Mac window is resized to match), macOS-style close/minimize/maximize buttons
  on the bar, and dragging the bar to the Mac-side edge sends the window back to the MacBook; tiny helper windows are skipped; taskbar button with the Mac
  app icon, Alt+Tab, normal z-order, closing closes it on the Mac. Each window is captured independently (ScreenCaptureKit) and
  streamed separately, so moving it never reveals the wallpaper and corners are rounded like on
  macOS. The real Windows pointer drives it (absolute positions, clicks also activate the
  Windows window), the keyboard follows the active window with Windows shortcuts kept local,
  dropping a window hands the pointer to Windows, dragging it across the Mac-side edge returns
  it to the MacBook. Windows restored by macOS from a previous session are moved back to the
  MacBook. Nothing is captured until a window is moved (not even the whole virtual display).
  New messages `MOUSE_ABSOLUTE`, `WINDOW_ENTER/LEAVE/HANDOFF/RAISE/CLOSE`,
  `DISPLAY_MODE`, `DISPLAY_WINDOWS`, `WINDOW_ICON`, per-window video frames and STATUS bit 6.
- **Windows apps on the Mac** (experimental, reverse direction). A one-time, admin-approved
  install of the signed, MIT-licensed Virtual Display Driver (downloaded from GitHub with pinned
  SHA-256 checksums) gives Windows a virtual monitor. The app attaches it next to the Mac-side
  edge only during a session, sized like the Mac screen in points, and detaches it afterwards
  (also after a crash). Dragging a window across that edge moves it onto the monitor; the Mac
  shows each such window as a native macOS window in the same place (one DXGI Desktop
  Duplication capture, NV12 on the GPU with a CPU fallback, Media Foundation H.264, the same
  encrypted one-time video channel, VideoToolbox decoding into IOSurfaces cropped per window,
  rounded corners). The Windows pointer stays local over those windows (the Mac mirrors it and
  its shape), leaving them hands control to the Mac at that point, and moving the Mac pointer
  onto one hands it back to Windows. Protocol: `WINVIEW_*` (0x90–0x97) and STATUS bit 7.
- Windows: encrypted control frames are sealed and queued atomically, so frames sent from
  several threads can no longer reach the Mac out of order.
- Local macOS builds are signed with the Apple Development identity when available, so
  privacy permissions survive rebuilds.
- The virtual display is entered only while dragging (a mouse button is held); plain pointer
  movement across that edge still returns to Windows.
- Windows: `Ctrl + Alt + Shift + B` emergency shortcut for compact keyboards without
  Scroll Lock or Pause.
- Shared test vectors (CryptoKit ↔ .NET) and an H.264 fixture encoded on macOS that the Windows
  checks decrypt and, on Windows, decode.

## 2.0.2 — 2026-09-04

### Fixed

- Windows: audio never started since 2.0.0. The control socket is dual-stack, so an IPv4 Mac is
  reported as `::ffff:192.168.x.y`, and the source-address check added in 2.0.0 rejected it with
  "Cannot open UDP port: cannot determine the Mac IPv4 address". `AUDIO_START` was therefore never
  sent, which is also why macOS never asked for the audio permission. Mapped addresses are now
  normalized to IPv4, and a genuine IPv6 session says so instead of hiding behind a parameter name.

## 2.0.1 — 2026-09-04

### Fixed

- macOS: the Permissions page now really checks the system-audio-recording consent instead of
  mirroring the streaming state, so it no longer reports "missing" whenever no stream is running.
- macOS: added **Request** — the app can trigger the consent prompt itself, without waiting for a
  Windows peer to start a stream.
- macOS: added **Repair**, which clears a stale TCC entry
  (`tccutil reset AudioCapture com.borderlessmouse.mac`) and asks again. Needed when System
  Settings shows the permission as granted but macOS denies it, which happens after the app's
  code signature changes (ad-hoc local build ↔ signed release).

## 2.0.0 — 2026-09-03 — free beta

### Security

- Replaced unauthenticated protocol v1 with mutually authenticated protocol v2.
- Added a 128-bit Base32 pairing code stored in Keychain and DPAPI.
- Encrypted all control and clipboard frames with directional AES-256-GCM keys.
- Encrypted audio packets and added source, size, session and replay validation.
- Prevented unauthenticated connections from replacing an active session.
- Bounded the Windows send queue and fixed framed PONG responses.
- Made checksums and project-owned ECDSA signatures mandatory for all updates.

### Product

- Added guided first-run onboarding on macOS and Windows.
- Added pairing management and immediate access revocation.
- Added Polish/English system-language localization, including runtime diagnostics.
- Added a configurable emergency control shortcut: Scroll Lock, Pause/Break or F12.
- Simplified the macOS connection screen and moved ports to advanced details.
- Increased Windows control hit areas for accessibility.

### Distribution

- Enabled the macOS hardened runtime.
- Restricted certificate use to the release workflow.
- Added a zero-cost beta release path with explicit first-launch trust warnings.
- Reserved Apple notarization and trusted Windows Authenticode for the public commercial release.
- Added download size limits and rollback-safe updater replacement.
- Locked the Windows NuGet dependency graph for reproducible CI and release restores.
- Bundled complete third-party notices, including Inter OFL and ANGLE terms, with release artifacts.
