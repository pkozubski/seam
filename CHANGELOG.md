# Changelog

## Unreleased — test channel

- macOS: each Windows app shown on the Mac is now its own Mac app, as Mac apps already are on the Windows taskbar. It has its own Dock icon with the app's Windows icon, its own entry in Cmd+Tab and its name in the menu bar, instead of every Windows window sitting under the Seam icon. Choosing it in the Dock or Cmd+Tab brings its window forward on Windows and sends the keyboard there; the Dock menu lists its windows; Quit closes its windows on Windows the way the × button does (the app can still ask to save). Requires the matching Windows version; with an older one, windows stay under Seam as before.
- Windows apps on the Mac: windows stay on whichever Mac desktop (Space) is open. Bringing a Windows window forward or moving the pointer onto one no longer switches to the desktop where it first appeared or where the Seam window is.
- Windows apps on the Mac: dragging a Windows window is smoother. Position, picture and cursor reach the Mac's main thread together and only in their newest state, and the main thread is no longer busy redrawing the interface (see below).
- Windows apps on the Mac: no more brief zoom while a window moves onto the virtual monitor. When its DPI changes, a frame captured mid-resize used to be cropped to the window's new bounds, which showed a magnified corner of the window; such frames are now sent whole.

- macOS: much lower energy use. The interface only redraws what actually changed: before, the audio level (about 23 times a second), packet counters and video statistics redrew the whole window and the menu bar icon, which kept the main thread busy and loaded WindowServer. The level meter now reads the level itself, 20 times a second and only while it is on screen.
- macOS: the update progress bar stops animating once it is full (its sparks used to redraw at 60 fps for as long as the Updates page was open after an update).
- macOS: in window mode the list of Mac windows is read 30 times a second only while something is happening (windows changing or input from Windows), then 10 and 4 times a second; any click, key or movement from Windows restores the full rate at once. The Mac cursor shape is read only while the Windows pointer is over a Mac window.
- macOS: after about a second of digital silence the Mac stops sending audio packets and resumes on the first sound (sequence numbers stay contiguous, so Windows just refills its buffer). The clipboard is polled only while Windows is connected; permissions are checked every 2 s only while Seam is the active app (otherwise every 30 s); timers allow the system to coalesce wakeups.
- macOS: the encoder stops refining a still image as soon as a refinement frame is nearly empty (typing usually needs one or two passes instead of eight); fewer copies per frame in the H.264 encoder output and in the decoder for Windows windows; control messages from one TCP read reach the engine in one batch; the scroll direction setting is no longer read from global preferences on every wheel event.
- Windows: the Windows-windows-on-the-Mac loops no longer raise the system timer resolution (`timeBeginPeriod`) for the whole session and sleep when there is nothing on the virtual monitor; capture polling slows down when windows are still; the window tracker ignores events from windows elsewhere and reads the cursor quickly only near the virtual monitor. Short waits use a high-resolution waitable timer instead.
- Windows: the hardware H.264 encoder no longer throws and catches an exception on every empty event poll (dozens per frame) and waits with a precise timer instead of spinning.
- Windows: WASAPI playback stops after 3 s without sound (no audio stream holding the device and blocking sleep) and starts again on the first sound; the audio receiver reuses its buffers and AES-GCM instance; Raw Input is registered only while the pointer controls the Mac, so local mouse movement no longer wakes the UI thread.
- Windows: discovery stops broadcasting while connected and backs off while the Mac is away; reconnect attempts back off from 3 to 30 s and retry at once when the Mac reappears or the network changes (a Mac that did not answer within 4 s no longer ends the reconnect loop for good); the 4 Hz statistics timer runs only while the window is visible on a page with live values; the clipboard is polled only while connected; settings are saved once after a burst of changes; the viewer thread no longer wakes 10 times a second; large illustrations are decoded at display size.

- Windows: one graphite backdrop runs under the title bar, sidebar and content with no separate bands and no grain; cards are translucent glass, switches are green with a white knob, and primary buttons are light. Only the Windows tab turns the whole window green, using the design tokens (tokens.css).
- Windows: the sidebar blends into the backdrop with icons and names; the selected section sits in a rounded glass pill (no side bar), and a thin separator fades out towards the top and bottom. The title bar shows the current page name. The floating connection orb is gone; connection status is a coloured dot on the Connection icon, with the full status in its tooltip.
- macOS and Windows: new smaller plateless sidebar icons for every section: Connection, Displays, Keyboard & mouse, Audio, Clipboard, Windows, Permissions (macOS), Settings and Log (`assets/seam/nav-*.png`); icons are balanced by visual weight rather than longest side and dimmed on Windows so they blend into the backdrop (the selected one stays brighter), and the selected section gets a green tile.
- Windows: the sidebar now matches macOS. The app icon and name sit at the top, sections are grouped under Features and System (Log moves to System), and below Settings a footer shows this PC's name, "Local network only" and the version. Sidebar icons are no longer dimmed and are decoded once, at high quality, straight to the screen's pixel size, so they stay as sharp as on the Mac at any display scaling.
- Windows: redesigned Windows tab. A main switch for both directions under the headline, a card with the window-moving illustration and a See how button, a live connection card (MacBook ● — PC, Connection settings) and the screen arrangement with Mac/PC tiles. Per-direction switches, the driver and display options sit below the how-it-works steps.
- macOS: the sidebar matches Windows. The selected section sits in a glass pill (lighter top edge, soft shadow) that slides between rows, without the green icon tile; the sidebar shares one backdrop with the content and is separated only by a thin line fading towards the top and bottom. The system split view (whose macOS 26 glass lightened the sidebar and drew a hard divider with a shadow) is replaced by a custom two-column layout; ↑/↓ still move between sections. The Windows tab turns the whole window green, including its icon rail. The page name no longer repeats in the title bar, since every page has its own heading.
- macOS: the Windows tab now uses the Windows design: a centred headline with the main switch in a pill, a Move any window card with See how, a live connection card and the screen arrangement (read-only on the Mac, with a pointer to Seam on Windows → Displays), then How it works and Display options. The whole window turns green with the same tokens as Windows, and the full sidebar stays instead of the icon rail.
- Windows: Mac windows no longer appear as extra thumbnails under the Seam taskbar button. Each Mac app gets its own taskbar button with its icon, its windows are grouped there like those of a Windows app, and Alt+Tab lists them separately. The buttons cannot be pinned, since a pin would start Seam rather than the Mac app.
- Windows previews (`--screenshot`) no longer save their demo data to `settings.json`; before, a preview could replace the Mac address and turn off automatic connection.

## 2.1.23 — test channel (2026-10-19)

- BorderlessMouse is now **Seam**: app name, Windows executable (`Seam.exe`), macOS bundle (`Seam.app`), release files and the repository (github.com/pkozubski/seam).
- Updates, settings, pairing and macOS permissions carry over: the bundle ID, Keychain entry, settings folders and pairing cryptography keep their previous identifiers. Releases also include the files under their old names so existing installs can update.
- macOS: the updater renames an install still called `BorderlessMouse.app` to `Seam.app` and re-registers the login item.
- Repository: `CLAUDE.md` working rules for both platforms, Windows preview scripts (`windows/scripts/preview.ps1`, `capture-window.ps1`), protocol docs moved to `docs/`.

## 2.1.22 — test channel (2026-10-18)

- macOS and Windows: a new scrollable Windows tab explains the second-monitor model with a large window-crossing illustration, three visual steps, display arrangement and return direction.
- Add two original bundled desktop wallpapers; the windows, arrows and localized labels remain native and sharp at every size.
- Diagrams follow all four screen positions. macOS reads the negotiated edge and labels disconnected or inactive arrangements as examples.
- Keep live feature switches, permission and connection feedback; Windows retains both transfer directions, driver installation, restart and display options.
- The Windows tab uses a compact navigation rail and hides the home-screen connection orb. Other pages retain their existing layout.
- Add full-page UI previews for visual checks; allow a separate local macOS build output so previews do not replace a running app.

## 2.1.20 — test channel (2026-10-18)

- macOS: settings take over the main window. The sidebar becomes the General, Updates and Advanced pages with search and a Back row; ⌘, toggles settings and Esc closes them.
- macOS: Updates page with a version pill in the header that turns into "Update & restart" and then into the progress bar.
- macOS: one forward-only progress bar across download (with sizes), signature checks and install; steps without byte counts ease forward so the bar never stalls.
- macOS: after an update the user started, the relaunched app opens Updates, finishes the bar and shows the release notes. An accent dot on Settings marks a waiting update.
- Windows: unchanged apart from the version number.

## 2.1.19 — test channel (2026-10-18)

- Every sidebar section is its own page. macOS drops the Keyboard / Audio / Display / Clipboard segments that duplicated the sidebar; "Sterowanie" is now "Klawiatura i mysz" (Keyboard & mouse) on both platforms.
- Feature pages open with a card holding the main switch and live status (Audio adds the level meter); options below are grouped (Keyboard, Scrolling, Playback, Latency, …).
- macOS: sidebar grouped into Features and System. A missing permission shows a banner with a Grant button on the feature page that needs it, plus a dot next to Permissions.
- macOS: scroll direction and the capture buffer (Fastest / Balanced / Stable) are segmented controls; TCP port and custom signing certificate move to a collapsed Advanced section; the log gets a Copy button.
- Windows: new Displays page. Place the Mac by clicking one of four spots around this monitor; it replaces the "Mac stoi względem tego ekranu" list.
- New Displays icon in the silver icon family.

## 2.1.18 — test channel (2026-10-18)

- Windows: match the macOS look. The same graphite backdrop runs under the title bar, a darker sidebar pane and the content.
- Windows: sidebar and quick-toggle icons sit on graphite gradient plates; the selected section takes the accent color.
- Windows: use the sage accent from macOS instead of the system accent color.
- Windows: use the graphite two-window app icon for the executable, title bar, tray and sidebar logo.
- macOS: unchanged since 2.1.17 apart from the version number.

## 2.1.17 — test channel (2026-10-18)

- macOS: replace the flat canvas with one continuous graphite backdrop (cool studio light, a faint accent glow under the status orb, grain against banding). The sidebar continues it under a darker veil and the title bar is transparent.
- macOS: set sidebar and quick-toggle icons on graphite gradient plates; the selected section takes the accent color.
- macOS: restore the graphite two-window app icon from 2.1.15 and show the app icon as the sidebar logo.
- Windows: unchanged apart from the version number.

## 2.1.16 — test channel (2026-10-18)

- Introduce the shared dark seam home screen with bundled glass artwork and eight silver 3D icons.
- Keep platform controls: SwiftUI on macOS and FluentAvalonia on Windows.
- Display connection status in an attached circular panel extending beyond the bottom window edge. Open connection details on click and clamp the panel to the screen's working area.
- Add direct audio, clipboard and window navigation alongside quick sharing toggles.
- Retain the 2.1.15 transport fixes, pairing protocol, bundle identity and signed dev updater.

## Unreleased

### Updates

- macOS and Windows share the signed `dev-build` release and version number. Test builds
  check every two minutes and install during inactivity, deferring restarts while remote
  control or transferred windows are in use. macOS rechecks inactivity after downloading.
- Local builds read the shared `VERSION` file instead of silently identifying as 1.0.0.
- Older stable-channel Mac builds need one initial installation of the test build.

### Changed

- New app icon on macOS and Windows (two windows on a dark tile), exported from
  `assets/logo/app-icon.png`; the macOS icon follows the Dock grid with a soft shadow.

### Fixed

- Mac windows on Windows: setting up the Mica caption no longer sends the Mac a resize request
  with the pre-frame client size, which shrank the source window and stretched its picture with
  bands above and below. The proxy also adopts the Mac window's final size after a local resize,
  and window pictures are never upscaled (1:1 at the top left while the source catches up).
- Static Mac content is re-encoded a few times after it settles, so text sharpens instead of
  keeping the heavily quantized first frame after every change.
- Size the Windows virtual monitor to the Mac screen's visible area (without menu bar and Dock)
  so maximized Windows windows are not covered and the pointer stays on Windows.
- Do not dispose the device's cached D3D11 immediate context in per-window capture and the
  hardware encoder; a failure in one window no longer stops the whole window stream.
- Windows apps on the Mac stream each window separately via Windows.Graphics.Capture and a
  hardware H.264 encoder (software fallback). Geometry is sent event-driven on the control
  channel, the virtual monitor uses Mac pixels at matching DPI, and Snap overlays are ignored.
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
