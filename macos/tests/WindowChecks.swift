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
}
