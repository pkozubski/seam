import AppKit
import CoreMedia
import CoreVideo
import Foundation

@main
struct WindowChecks {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    static func buffer(width: Int, height: Int) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        expect(CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                  [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer) == kCVReturnSuccess,
               "create pixel buffer")
        let result = buffer!
        CVPixelBufferLockBaseAddress(result, [])
        memset(CVPixelBufferGetBaseAddress(result), 128, CVPixelBufferGetBytesPerRow(result) * height)
        CVPixelBufferUnlockBaseAddress(result, [])
        return result
    }

    static func main() throws {
        checkPopupLifecycle()
        let display = CGRect(x: -1920, y: 200, width: 1920, height: 1080)
        let initial = CGRect(x: -400, y: 900, width: 320, height: 240)
        let maximized = WindowControl.resizedFrame(initial, to: CGSize(width: 1920, height: 1080), within: display)
        expect(maximized == display, "maximizing near a virtual-display edge must not move its centre onto a different screen")
        let larger = WindowControl.resizedFrame(initial, to: CGSize(width: 800, height: 600), within: display)
        expect(display.contains(larger) && larger.size == CGSize(width: 800, height: 600), "resize stays on the virtual display")
        let oversized = WindowControl.resizedFrame(initial, to: CGSize(width: 3840, height: 2160), within: display)
        expect(oversized == display, "larger Windows monitor is bounded by the source display")

        let encoder = try VideoEncoder(width: 160, height: 96)
        let lock = NSLock()
        var errors = 0
        var frames: [VideoEncoder.EncodedFrame] = []
        let received = DispatchSemaphore(value: 0)
        encoder.onError = { _ in lock.withLock { errors += 1 } }
        encoder.onFrame = { frame in
            lock.withLock { frames.append(frame) }
            received.signal()
        }
        // Simulate a keyframe request racing with a resize: cached pixels still have the old size.
        encoder.encode(buffer(width: 320, height: 192), presentationTime: CMTime(value: 1, timescale: 60))
        expect(lock.withLock { errors == 1 && frames.isEmpty }, "a stale-size buffer must not be scaled into the new stream")
        encoder.encode(buffer(width: 160, height: 96), presentationTime: CMTime(value: 2, timescale: 60))
        expect(received.wait(timeout: .now() + 5) == .success, "encoder recovers after stale buffer rejection")
        expect(lock.withLock { frames.count == 1 && frames[0].isKeyframe && frames[0].width == 160 && frames[0].height == 96 },
               "recovery starts with a keyframe at the negotiated size")
        encoder.invalidate()
        print("✓ Window resize bounds and H.264 recovery after a stale-size keyframe request")
    }

    static func checkPopupLifecycle() {
        // Observed on real Chrome: both omnibox suggestions and extension bubbles are
        // AXWindow/AXUnknown at CG layer zero, without native window controls.
        expect(!WindowControl.isApplicationWindow(role: "AXWindow", subrole: "AXUnknown", hasWindowControls: false),
               "Chrome bubbles must not receive application captions or taskbar entries")
        expect(!WindowControl.isApplicationWindow(role: "AXWindow", subrole: "AXDialog", hasWindowControls: false),
               "borderless dialogs are transient too")
        expect(WindowControl.isApplicationWindow(role: "AXWindow", subrole: "AXStandardWindow", hasWindowControls: false),
               "standard windows remain independent even while their titlebar controls are hidden")
        expect(WindowControl.isApplicationWindow(role: "AXWindow", subrole: "AXDialog", hasWindowControls: true),
               "a real dialog with native window controls retains its frame")

        let display = CGRect(x: 1710, y: 0, width: 1920, height: 1080)
        func window(_ id: UInt32, _ frame: CGRect, popup: Bool = false, pid: Int32 = 100) -> TrackedWindow {
            TrackedWindow(id: id, pid: pid, frame: frame, isMenuBar: false, isPopup: popup, title: "")
        }
        let browser = window(1, display)
        let otherBrowser = window(2, display)
        let suggestions = window(3, CGRect(x: 1845, y: 56, width: 1542, height: 138))
        let extensions = window(4, CGRect(x: 3160, y: 111, width: 320, height: 537))
        let appWindows: [Int32: Set<UInt32>] = [100: [1, 2]]
        var state = WindowTrackingState()
        func update(_ visible: [TrackedWindow], existing: [TrackedWindow] = [], at time: TimeInterval,
                    apps: [Int32: Set<UInt32>] = [100: [1, 2]]) -> [TrackedWindow] {
            state.update(visible, applicationWindows: apps, existing: existing, display: display, now: time)
        }
        var result = update([suggestions, browser, otherBrowser], at: 0, apps: appWindows)
        expect(result.first { $0.id == 3 }?.isPopup == true && result.filter { !$0.isPopup }.count == 2,
               "a layer-zero popup is owned; two overlapping real browser windows stay independent")
        result = update([browser, otherBrowser], existing: [suggestions, browser, otherBrowser], at: 0.1)
        expect(!result.contains { $0.id == 3 }, "dismissed omnibox disappears immediately even if its CG window still exists")
        result = update([extensions, browser], at: 1)
        expect(result.first { $0.id == 4 }?.isPopup == true, "extensions panel is transient")
        result = update([browser], existing: [extensions, browser], at: 1.01)
        expect(result.count == 1 && result[0].id == 1, "closing the extensions panel leaves no frozen proxy")

        // Reused Chrome window IDs must be classified each time they reappear.
        result = update([suggestions, browser], at: 2)
        expect(result.first { $0.id == 3 }?.isPopup == true, "reopening the omnibox remains transient")
        result = update([browser], existing: [suggestions, browser], at: 50)
        expect(result.count == 1, "a maximized browser cannot indefinitely retain a dismissed popup")

        // Fullscreen capture still retains the positively identified parent, but an ordinary
        // maximized sibling must not keep a closed/minimized window alive forever.
        let video = window(5, display)
        result = update([video], existing: [browser, video], at: 51, apps: [100: []])
        expect(result.first { $0.id == 5 }?.isPopup == true && result.contains { $0.id == 1 && !$0.isPopup },
               "fullscreen child keeps its known parent when AX temporarily omits that parent")
        result = update([otherBrowser], existing: [browser, otherBrowser], at: 53)
        expect(result.count == 1 && result[0].id == 2, "a fullscreen-sized sibling is not a fullscreen child")
        let returned = window(2, CGRect(x: 0, y: 0, width: 1600, height: 900))
        result = update([], existing: [returned], at: 53.1)
        expect(result.isEmpty, "returning the parent to a physical monitor removes its host immediately")

        // AX failure must not poison retention state with a popup guessed to be a normal window.
        state = WindowTrackingState()
        _ = update([suggestions, browser], at: 0, apps: [:])
        result = update([browser], existing: [suggestions, browser], at: 0.1)
        expect(result.count == 1, "unverified windows cannot become retained owners during an AX failure")
        let unrelated = window(6, suggestions.frame, pid: 200)
        result = update([unrelated, browser], at: 1, apps: [100: [1], 200: []])
        expect(result.first { $0.id == 6 }?.isPopup == false, "ownership never crosses processes")
        print("✓ Chrome popup classification, dismissal/reopen, AX failure and fullscreen-owner lifecycle")
    }
}
