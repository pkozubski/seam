import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

/// Tryb okien: osobny strumień obrazu dla każdego okna Maca na ekranie wirtualnym.
/// ScreenCaptureKit nagrywa okno niezależnie od jego pozycji i okien nad nim, więc
/// przy przesuwaniu nie widać tapety, a przezroczyste narożniki pozwalają odczytać
/// promień zaokrąglenia. Pasek menu ekranu wirtualnego to wycinek całego ekranu.
final class WindowStreams {
    private let queue = DispatchQueue(label: "blm.display.windowstreams", qos: .userInitiated)
    private let send: (VideoStream.Frame) -> Bool
    private let hasClient: () -> Bool
    private var pipelines: [UInt32: Pipeline] = [:]
    private var displayID: CGDirectDisplayID = 0
    private var active = false
    private var wantedWindows: [TrackedWindow] = []
    private var retryTimer: DispatchSourceTimer?

    init(send: @escaping (VideoStream.Frame) -> Bool, hasClient: @escaping () -> Bool) {
        self.send = send
        self.hasClient = hasClient
    }

    var framesDropped: UInt64 {
        queue.sync { pipelines.values.reduce(0) { $0 + $1.dropped } }
    }

    func start(displayID: CGDirectDisplayID) {
        queue.async {
            self.displayID = displayID
            self.active = true
            self.retryTimer?.cancel()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 1, repeating: .seconds(1))
            timer.setEventHandler { [weak self] in self?.reconcile() }
            self.retryTimer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.sync {
            active = false
            retryTimer?.cancel()
            retryTimer = nil
            wantedWindows = []
            pipelines.values.forEach { $0.stop() }
            pipelines.removeAll()
        }
    }

    /// Nowa lista okien: uruchamia, zatrzymuje i dopasowuje strumienie.
    func update(_ windows: [TrackedWindow]) {
        queue.async {
            guard self.active else { return }
            self.wantedWindows = windows
            self.reconcile()
        }
    }

    private func reconcile() {
        guard active else { return }
        let windows = wantedWindows
        let scale = WindowTracker.pixelScale(of: self.displayID)
        let wanted = Dictionary(windows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, pipeline) in self.pipelines where wanted[id] == nil {
            pipeline.stop()
            self.pipelines[id] = nil
        }
        for window in windows {
            let size = WindowTracker.pixelSize(of: window, scale: scale)
            if let pipeline = self.pipelines[window.id], !pipeline.isStopped {
                pipeline.resize(width: size.width, height: size.height, frame: window.frame)
            } else {
                let pipeline = Pipeline(window: window, width: size.width, height: size.height,
                                        displayID: self.displayID, send: self.send, hasClient: self.hasClient)
                self.pipelines[window.id] = pipeline
                pipeline.start()
            }
        }
    }

    /// Dla samotestu.
    static func measureCornerRadius(_ buffer: CVPixelBuffer) -> UInt16 { Pipeline.cornerRadius(of: buffer) }

    /// nil = wszystkie strumienie (np. po podłączeniu odbiorcy).
    func requestKeyframe(_ id: UInt32?) {
        queue.async {
            if let id { self.pipelines[id]?.forceKeyframe() } else { self.pipelines.values.forEach { $0.forceKeyframe() } }
        }
    }

    // MARK: - Jeden strumień

    private final class Pipeline {
        let id: UInt32
        let isMenuBar: Bool
        private let displayID: CGDirectDisplayID
        private let send: (VideoStream.Frame) -> Bool
        private let hasClient: () -> Bool
        private let lock = NSLock()
        private var capture: WindowCapture?
        private var encoder: VideoEncoder?
        private var width: Int
        private var height: Int
        private var frame: CGRect
        private var awaitingKeyframe = true
        private var lastPixelBuffer: CVPixelBuffer?
        private var cornerRadius: UInt16 = 0
        private var stopped = false
        private(set) var dropped: UInt64 = 0
        var isStopped: Bool { lock.withLock { stopped } }

        init(window: TrackedWindow, width: Int, height: Int, displayID: CGDirectDisplayID,
             send: @escaping (VideoStream.Frame) -> Bool, hasClient: @escaping () -> Bool) {
            id = window.id
            isMenuBar = window.isMenuBar
            self.width = width
            self.height = height
            frame = window.frame
            self.displayID = displayID
            self.send = send
            self.hasClient = hasClient
        }

        func start() {
            guard let encoder = try? VideoEncoder(width: Self.encodedSize(width), height: Self.encodedSize(height),
                                                  bitrate: Self.bitrate(width: width, height: height)) else { stop(); return }
            wire(encoder, width: width, height: height)
            lock.lock()
            self.encoder = encoder
            lock.unlock()
            let capture = WindowCapture()
            capture.onFrame = { [weak self] buffer, time in self?.handle(buffer, time) }
            capture.onStopped = { [weak self] in self?.stop() }
            self.capture = capture
            let (id, isMenuBar, displayID, frame, width, height) = (id, isMenuBar, displayID, frame, width, height)
            Task { [weak self] in
                do {
                    try await capture.start(windowID: isMenuBar ? nil : id, displayID: displayID, menuBarRect: frame,
                                            width: Self.encodedSize(width), height: Self.encodedSize(height))
                    self?.measureRadius(width: Self.encodedSize(width), height: Self.encodedSize(height))
                } catch {
                    NSLog("BorderlessMouse: nie można nagrać okna \(id): \(error.localizedDescription)")
                    self?.stop()
                }
            }
        }

        func stop() {
            lock.lock()
            stopped = true
            let capture = self.capture, encoder = self.encoder
            self.capture = nil
            self.encoder = nil
            lastPixelBuffer = nil
            lock.unlock()
            capture?.onFrame = nil
            capture?.onStopped = nil
            capture?.stop()
            encoder?.onFrame = nil
            encoder?.invalidate()
        }

        /// Zmiana rozmiaru wymaga nowego kodera (H.264 ma stały rozmiar strumienia).
        func resize(width: Int, height: Int, frame: CGRect) {
            lock.lock()
            guard !stopped else { lock.unlock(); return }
            let sameSize = Self.encodedSize(width) == encoder?.width && Self.encodedSize(height) == encoder?.height
            self.width = width
            self.height = height
            self.frame = frame
            lock.unlock()
            guard !sameSize else {
                if isMenuBar, let capture = self.capture {
                    capture.update(menuBarRect: frame, width: Self.encodedSize(width), height: Self.encodedSize(height))
                }
                return
            }
            guard let replacement = try? VideoEncoder(width: Self.encodedSize(width), height: Self.encodedSize(height),
                                                      bitrate: Self.bitrate(width: width, height: height)) else { return }
            wire(replacement, width: width, height: height)
            lock.lock()
            guard !stopped else { lock.unlock(); replacement.invalidate(); return }
            let old = encoder
            encoder = replacement
            awaitingKeyframe = true
            lastPixelBuffer = nil
            lock.unlock()
            measureRadius(width: Self.encodedSize(width), height: Self.encodedSize(height))
            old?.onFrame = nil
            old?.invalidate()
            capture?.update(menuBarRect: isMenuBar ? frame : nil,
                            width: Self.encodedSize(width), height: Self.encodedSize(height))
        }

        func forceKeyframe() {
            lock.lock()
            awaitingKeyframe = true
            let encoder = self.encoder, last = lastPixelBuffer
            lock.unlock()
            encoder?.requestKeyframe()
            if let encoder, let last, hasClient(),
               CVPixelBufferGetWidth(last) == encoder.width, CVPixelBufferGetHeight(last) == encoder.height {
                encoder.encode(last, presentationTime: CMClockGetTime(CMClockGetHostTimeClock()))
            }
        }

        private func handle(_ buffer: CVPixelBuffer, _ time: CMTime) {
            lock.lock()
            guard !stopped, let encoder,
                  CVPixelBufferGetWidth(buffer) == encoder.width, CVPixelBufferGetHeight(buffer) == encoder.height else {
                lock.unlock()
                return
            }
            lastPixelBuffer = buffer
            lock.unlock()
            guard hasClient() else { return }
            encoder.encode(buffer, presentationTime: time)
        }

        /// Promień z osobnego zrzutu – w strumieniu narożniki są już wypełnione kolorem.
        private func measureRadius(width: Int, height: Int) {
            guard !isMenuBar, let capture else { return }
            let id = self.id
            Task { [weak self] in
                let radius = await capture.measureCornerRadius(windowID: id, width: width, height: height)
                guard let self else { return }
                self.lock.withLock { self.cornerRadius = radius }
            }
        }

        private func wire(_ encoder: VideoEncoder, width: Int, height: Int) {
            encoder.onFrame = { [weak self, weak encoder] encoded in
                guard let self, let encoder else { return }
                self.lock.lock()
                // A delayed callback from the old encoder must never carry the new dimensions.
                guard !self.stopped, self.encoder === encoder else { self.lock.unlock(); return }
                if self.awaitingKeyframe && !encoded.isKeyframe {
                    self.dropped &+= 1
                    self.lock.unlock()
                    return
                }
                let radius = self.cornerRadius
                let frame = VideoStream.Frame(kind: .windowAccessUnit, flags: encoded.isKeyframe ? [.keyframe] : [],
                                              width: width, height: height,
                                              captureMicros: UInt64(max(0, CMTimeGetSeconds(encoded.presentationTime)) * 1_000_000),
                                              payload: encoded.annexB, streamID: self.id, cornerRadius: radius)
                let sent = self.send(frame)
                if sent {
                    if encoded.isKeyframe { self.awaitingKeyframe = false }
                } else {
                    self.dropped &+= 1
                    if !self.awaitingKeyframe {
                        self.awaitingKeyframe = true
                        encoder.requestKeyframe()
                    }
                }
                self.lock.unlock()
            }
            encoder.onError = { [weak self, weak encoder] _ in
                guard let self, let encoder else { return }
                self.lock.withLock {
                    if self.encoder === encoder { self.awaitingKeyframe = true }
                }
            }
        }

        /// H.264 wymaga wymiarów parzystych. Nie dopełniamy więcej niż trzeba: ScreenCaptureKit
        /// nie gwarantuje, w którym miejscu większej klatki położy obraz (pasek menu 30 px
        /// w klatce 64 px wychodził ucięty). VideoToolbox koduje nawet 2×2 px.
        static func encodedSize(_ value: Int) -> Int { max(16, (value + 1) & ~1) }

        static func bitrate(width: Int, height: Int) -> Int {
            Int(min(max(Double(width * height) * 60 * 0.18, 4_000_000), 60_000_000))
        }

        /// Promień narożnika z przezroczystości lewego górnego rogu (BGRA). Po przekątnej
        /// łuk o promieniu r zaczyna się w odległości r·(1 − 1/√2) ≈ 0,293·r od rogu.
        static func cornerRadius(of buffer: CVPixelBuffer) -> UInt16 {
            guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
                  CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return 0 }
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            let limit = min(CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), 40)
            var step = 0
            while step < limit, base[step * stride + step * 4 + 3] < 128 { step += 1 }
            guard step > 0, step < limit else { return 0 }
            return UInt16((Double(step) / (1 - 1 / 2.0.squareRoot())).rounded())
        }
    }
}

/// ScreenCaptureKit dla jednego okna (albo wycinka ekranu – pasek menu). Klatki BGRA
/// z kanałem alfa: narożniki okien są przezroczyste, co wykorzystujemy do zaokrągleń.
final class WindowCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?
    var onStopped: (() -> Void)?
    private let sampleQueue = DispatchQueue(label: "blm.display.windowcapture", qos: .userInteractive)
    private var stream: SCStream?
    private var displayBounds = CGRect.zero
    private let stateLock = NSLock()
    /// Okno (np. podpowiedź) zniknęło, zanim nagrywanie ruszyło – zatrzymujemy je od razu po starcie.
    private var stopRequested = false
    private var updateTask: Task<Void, Error>?
    private var desiredConfiguration: SCStreamConfiguration?

    func start(windowID: UInt32?, displayID: CGDirectDisplayID, menuBarRect: CGRect, width: Int, height: Int) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let filter: SCContentFilter
        displayBounds = CGDisplayBounds(displayID)
        if let windowID {
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw DisplayCapture.CaptureError.displayNotFound
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
        } else {
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw DisplayCapture.CaptureError.displayNotFound
            }
            filter = SCContentFilter(display: display, excludingWindows: [])
        }
        let initial = configuration(menuBarRect: windowID == nil ? menuBarRect : nil, width: width, height: height)
        let config = stateLock.withLock { desiredConfiguration ?? initial }
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        let early = stateLock.withLock { stopRequested }
        if early { return }
        try await stream.startCapture()
        let cancelled = stateLock.withLock {
            if !stopRequested {
                self.stream = stream
                // Resize may arrive while startCapture is suspended. Queue it before later updates.
                if let desiredConfiguration { enqueueUpdate(desiredConfiguration, stream: stream) }
            }
            return stopRequested
        }
        if cancelled { try? await stream.stopCapture() }
    }

    func update(menuBarRect: CGRect?, width: Int, height: Int) {
        let config = configuration(menuBarRect: menuBarRect, width: width, height: height)
        stateLock.lock()
        desiredConfiguration = config
        if !stopRequested, let stream { enqueueUpdate(config, stream: stream) }
        stateLock.unlock()
    }

    /// Called with stateLock held. ScreenCaptureKit updates must finish in request order.
    @discardableResult
    private func enqueueUpdate(_ config: SCStreamConfiguration, stream: SCStream) -> Task<Void, Error> {
        let previous = updateTask
        let task = Task { [weak self] in
            _ = try? await previous?.value
            guard let self else { return }
            let stopped = self.stateLock.withLock { self.stopRequested }
            guard !stopped else { return }
            do { try await stream.updateConfiguration(config) }
            catch {
                NSLog("BorderlessMouse: aktualizacja przechwytywania okna: \(error.localizedDescription)")
                self.onStopped?()
                throw error
            }
        }
        updateTask = task
        return task
    }

    func stop() {
        stateLock.lock()
        stopRequested = true
        let stream = self.stream
        self.stream = nil
        stateLock.unlock()
        stream?.stopCapture { _ in }
    }

    /// Kolor paska menu okna na Windowsie. Przezroczyste narożniki okna Maca dostają ten
    /// kolor (H.264 nie ma kanału alfa), więc styk paska z oknem jest niewidoczny.
    static let headerColor = CGColor(srgbRed: 41 / 255, green: 41 / 255, blue: 43 / 255, alpha: 1)

    /// Promień narożnika okna z jednego zrzutu z kanałem alfa (strumień ma narożniki wypełnione).
    func measureCornerRadius(windowID: UInt32, width: Int, height: Int) async -> UInt16 {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let window = content.windows.first(where: { $0.windowID == windowID }) else { return 0 }
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.scalesToFit = false
        if #available(macOS 14.0, *) { config.ignoreShadowsSingleWindow = true }
        guard let sample = try? await SCScreenshotManager.captureSampleBuffer(contentFilter: SCContentFilter(desktopIndependentWindow: window),
                                                                               configuration: config),
              let buffer = sample.imageBuffer else { return 0 }
        return WindowStreams.measureCornerRadius(buffer)
    }

    private func configuration(menuBarRect: CGRect?, width: Int, height: Int) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.backgroundColor = Self.headerColor
        config.width = width
        config.height = height
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 4
        config.showsCursor = false
        // Always fill the negotiated pixel size, including HiDPI and fullscreen transitions.
        // Child surfaces have their own owned Windows proxies; including them here duplicates them.
        config.scalesToFit = true
        config.preservesAspectRatio = true
        config.includeChildWindows = false
        config.captureResolution = .best
        config.ignoreGlobalClipSingleWindow = true
        if #available(macOS 14.0, *) { config.ignoreShadowsSingleWindow = true }
        if let menuBarRect {
            config.sourceRect = CGRect(x: menuBarRect.minX - displayBounds.minX, y: menuBarRect.minY - displayBounds.minY,
                                       width: menuBarRect.width, height: menuBarRect.height)
        }
        return config
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer else { return }
        onFrame?(pixelBuffer, sampleBuffer.presentationTimeStamp)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let notify = stateLock.withLock {
            guard !stopRequested else { return false }
            self.stream = nil
            return true
        }
        if notify { onStopped?() }
    }
}
