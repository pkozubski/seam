import Darwin
import Foundation

/// Łącze Seam ↔ pomocnik aplikacji Windows (`SeamHost`) przez gniazdo Unix w katalogu tymczasowym
/// użytkownika. Ramka: `u32 length` (typ + treść), `u8 type`, treść. Wspólne dla obu programów.
enum WinHostMessage: UInt8 {
    // Seam → pomocnik
    /// Okna tej aplikacji: `f64 ×4` ekran Maca (globalne CG), potem treść WINVIEW_WINDOWS (tylko te okna).
    case layout = 1
    /// Klatka H.264 okna: `u32 id`, `u8 keyframe`, `u16 w`, `u16 h`, `u16 cornerRadius`, Annex B.
    case frame = 2
    /// Kształt kursora (jak CURSOR_SHAPE) – ustawia go aktywna aplikacja.
    case cursor = 3
    /// Okno tej aplikacji stało się aktywne na Windowsie – pomocnik ma być aktywną aplikacją Maca.
    case activate = 4
    /// Aplikacja nie ma już okien.
    case quit = 5

    // pomocnik → Seam
    /// `16 B token`, `i32 pid`, klucz aplikacji (UTF-8).
    case hello = 101
    /// Widoczne okna: `u8 count`, `count ×` (`u32 id`, `u32 windowNumber`).
    case numbers = 102
    /// Użytkownik wybrał aplikację (Dock, Cmd+Tab, menu Docka): `u32 id` okna (0 = najwyższe).
    case activated = 103
    /// Dekoder potrzebuje klatki kluczowej.
    case keyframe = 104
    /// Zakończ (menu, Dock): Windows ma zamknąć okna tej aplikacji.
    case closeRequested = 105
}

/// Jedno połączenie (dowolny wątek). Zapis na własnej kolejce; zbyt wiele zaległych klatek = odrzucenie.
final class WinHostConnection {
    static let maxMessage = 16 << 20
    var onMessage: ((WinHostMessage, [UInt8]) -> Void)?
    var onClosed: (() -> Void)?

    private let fd: Int32
    private let readQueue: DispatchQueue
    private let writeQueue: DispatchQueue
    private var readSource: DispatchSourceRead?
    private var buffer: [UInt8] = []
    private let lock = NSLock()
    private var pending = 0
    private var closed = false

    init(fd: Int32, label: String) {
        self.fd = fd
        readQueue = DispatchQueue(label: "\(label).read", qos: .userInteractive)
        writeQueue = DispatchQueue(label: "\(label).write", qos: .userInteractive)
        var size: Int32 = 4 << 20
        setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &size, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &size, socklen_t(MemoryLayout<Int32>.size))
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
    }

    /// Po ustawieniu `onMessage` i `onClosed`.
    func start() {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: readQueue)
        source.setEventHandler { [weak self] in self?.readAvailable() }
        source.setCancelHandler { [fd] in Darwin.close(fd) }
        readSource = source
        source.resume()
    }

    /// `droppable`: klatkę inną niż kluczowa można pominąć, gdy odbiorca nie nadąża. Zwraca false po pominięciu.
    @discardableResult
    func send(_ type: WinHostMessage, _ payload: [UInt8] = [], droppable: Bool = false) -> Bool {
        let accepted: Bool = lock.withLock {
            guard !closed, !(droppable && pending >= 8) else { return false }
            pending += 1
            return true
        }
        guard accepted else { return false }
        var out = [UInt8]()
        out.reserveCapacity(payload.count + 5)
        let length = UInt32(payload.count + 1)
        for i in 0..<4 { out.append(UInt8((length >> (8 * UInt32(i))) & 0xFF)) }
        out.append(type.rawValue)
        out.append(contentsOf: payload)
        writeQueue.async { [weak self] in
            guard let self else { return }
            let ok = out.withUnsafeBytes { raw -> Bool in
                var offset = 0
                while offset < raw.count {
                    let n = Darwin.write(self.fd, raw.baseAddress! + offset, raw.count - offset)
                    if n > 0 { offset += n } else if n < 0, errno == EINTR { continue } else { return false }
                }
                return true
            }
            self.lock.withLock { self.pending -= 1 }
            if !ok { self.close() }
        }
        return true
    }

    /// Czeka, aż wyjdą wiadomości wysłane wcześniej (przed zakończeniem procesu).
    func flush() { writeQueue.sync {} }

    func close() {
        let first: Bool = lock.withLock {
            guard !closed else { return false }
            closed = true
            return true
        }
        guard first else { return }
        // Zamyka tylko odczyt – deskryptor zamyka obsługa anulowania źródła.
        shutdown(fd, SHUT_RDWR)
        readQueue.async { [weak self] in
            self?.readSource?.cancel()
            self?.readSource = nil
            let handler = self?.onClosed
            self?.onClosed = nil
            self?.onMessage = nil
            handler?()
        }
    }

    private func readAvailable() {
        var chunk = [UInt8](repeating: 0, count: 256 * 1024)
        let n = chunk.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
        if n <= 0 {
            if n < 0, errno == EAGAIN || errno == EINTR { return }
            close()
            return
        }
        buffer.append(contentsOf: chunk[0..<n])
        var start = 0
        while buffer.count - start >= 5 {
            var length = 0
            for i in 0..<4 { length |= Int(buffer[start + i]) << (8 * i) }
            guard length >= 1, length <= Self.maxMessage else {
                close()
                return
            }
            guard buffer.count - start >= 4 + length else { break }
            let typeByte = buffer[start + 4]
            let payload = Array(buffer[(start + 5)..<(start + 4 + length)])
            start += 4 + length
            if let type = WinHostMessage(rawValue: typeByte) { onMessage?(type, payload) }
        }
        if start > 0 { buffer.removeFirst(start) }
    }

    // MARK: - Gniazda

    private static func address(_ path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, b) in bytes.enumerated() { raw[i] = b }
            raw[bytes.count] = 0
        }
        return addr
    }

    /// Pomocnik: połączenie z gniazdem Seam.
    static func connect(path: String) -> WinHostConnection? {
        guard var addr = address(path) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0 else {
            Darwin.close(fd)
            return nil
        }
        return WinHostConnection(fd: fd, label: "seam.host")
    }

    /// Seam: gniazdo nasłuchujące; `onAccept` na kolejce `queue`.
    final class Listener {
        let path: String
        private let fd: Int32
        private let source: DispatchSourceRead

        init?(path: String, queue: DispatchQueue, onAccept: @escaping (WinHostConnection) -> Void) {
            guard var addr = WinHostConnection.address(path) else { return nil }
            unlink(path)
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { return nil }
            let bound = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            // Tylko właściciel (katalog tymczasowy i tak jest prywatny).
            guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 8) == 0 else {
                Darwin.close(fd)
                unlink(path)
                return nil
            }
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
            self.path = path
            self.fd = fd
            source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler {
                while true {
                    let client = accept(fd, nil, nil)
                    guard client >= 0 else { return }
                    _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
                    onAccept(WinHostConnection(fd: client, label: "seam.hosts"))
                }
            }
            source.setCancelHandler { Darwin.close(fd) }
            source.resume()
        }

        func stop() {
            source.cancel()
            unlink(path)
        }
    }
}
