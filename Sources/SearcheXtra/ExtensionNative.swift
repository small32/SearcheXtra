import Foundation
import Darwin
import WebKit

// Chrome's native messaging, for the extensions that talk to an app on this
// Mac — a password manager unlocking with its desktop app, a clipper handing
// a page to a notes app.
//
// Those apps register with Chrome by leaving a small JSON file in Chrome's
// NativeMessagingHosts folder: a name, the program to run, and which
// extensions may run it. Search reads the same files, runs the same program
// with the same argument, and speaks the same protocol — each message a
// four-byte length and a line of JSON, over the program's stdin and stdout.
// A host that lists the extension's id among its allowed origins is run;
// any other is not. Some hosts also check which browser is calling and may
// refuse one they don't know; that is theirs to decide.

@available(macOS 15.4, *)
enum ExtensionNative {
    struct Refused: LocalizedError {
        let why: String
        var errorDescription: String? { why }
    }

    /// Where Chromium browsers look, per user and for the whole Mac.
    private static var folders: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let support = home.appendingPathComponent("Library/Application Support")
        return [
            support.appendingPathComponent("Google/Chrome/NativeMessagingHosts"),
            support.appendingPathComponent("Chromium/NativeMessagingHosts"),
            support.appendingPathComponent("Microsoft Edge/NativeMessagingHosts"),
            support.appendingPathComponent("BraveSoftware/Brave-Browser/NativeMessagingHosts"),
            support.appendingPathComponent("Arc/User Data/NativeMessagingHosts"),
            URL(fileURLWithPath: "/Library/Google/Chrome/NativeMessagingHosts"),
            URL(fileURLWithPath: "/Library/Application Support/Chromium/NativeMessagingHosts"),
            URL(fileURLWithPath: "/Library/Microsoft/Edge/NativeMessagingHosts"),
            // Read last: a host of the same name that Chrome or the system knows comes first.
            support.appendingPathComponent("Vivaldi/NativeMessagingHosts"),
            support.appendingPathComponent("com.operasoftware.Opera/NativeMessagingHosts"),
        ]
    }

    /// The program for `name`, if one is registered and lets this extension in.
    private static func host(_ name: String, for extensionID: String) throws -> URL {
        guard name.range(of: #"^[a-z0-9_]+(\.[a-z0-9_]+)*$"#, options: .regularExpression) != nil else {
            throw Refused(why: "Invalid native messaging host name")
        }
        let origin = "chrome-extension://\(extensionID)/"
        for folder in folders {
            let file = folder.appendingPathComponent(name + ".json")
            guard let data = try? Data(contentsOf: file),
                  let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let path = manifest["path"] as? String
            else { continue }
            let allowed = manifest["allowed_origins"] as? [String] ?? []
            guard allowed.contains(origin) else {
                throw Refused(why: "Access to the specified native messaging host is forbidden.")
            }
            let program = path.hasPrefix("/") ? URL(fileURLWithPath: path) : folder.appendingPathComponent(path)
            guard FileManager.default.isExecutableFile(atPath: program.path) else {
                throw Refused(why: "Specified native messaging host not found.")
            }
            return program
        }
        throw Refused(why: "Specified native messaging host not found.")
    }

    /// `runtime.sendNativeMessage`: run, send one, read one, stop.
    static func send(_ message: Any, to name: String, from extensionID: String) async throws -> Any? {
        let program = try host(name, for: extensionID)
        let pipe = HostPipe(program: program, origin: "chrome-extension://\(extensionID)/")
        try pipe.start()
        defer { pipe.stop() }
        try pipe.write(message)
        return try await pipe.readOne()
    }

    /// `runtime.connectNative`: run, and keep the two talking until either
    /// end lets go.
    @MainActor
    static func connect(_ port: WKWebExtension.MessagePort, from extensionID: String) throws {
        guard let name = port.applicationIdentifier else { throw Refused(why: "No host named") }
        let program = try host(name, for: extensionID)
        // A new port is often a worker starting over; the one before may
        // have left its host behind.
        stopOrphans()
        let pipe = HostPipe(program: program, origin: "chrome-extension://\(extensionID)/")
        pipe.onMessage = { message in
            DispatchQueue.main.async { port.sendMessage(message, completionHandler: nil) }
        }
        pipe.onExit = {
            DispatchQueue.main.async { if !port.isDisconnected { port.disconnect() } }
        }
        var beating: Timer?
        port.messageHandler = { message, _ in
            guard let message else { return }
            // A worker's shim asking whether the port has arrived (see the
            // shim, after its WebSocket): answered here, never passed on.
            if let asked = message as? [String: Any], let word = asked["__searchNative"] {
                // The shim's answer to "alive" (below) is only the worker
                // keeping itself: nothing to say back.
                guard (word as? String) == "here?" else { return }
                port.sendMessage(["__searchNative": "here"], completionHandler: nil)
                // Asked, it is a worker's port, and WebKit unloads a worker
                // that hasn't posted on a port for two minutes: iCloud
                // Passwords then forgets it was paired and asks for a code
                // again. Chrome keeps a worker with a port to an app alive;
                // here a word on the port now and then, heard only by the
                // shim, has the worker answer on it, which is what WebKit
                // counts.
                if beating == nil {
                    beating = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { timer in
                        guard !port.isDisconnected else { timer.invalidate(); beating = nil; return }
                        port.sendMessage(["__searchNative": "alive"], completionHandler: nil)
                    }
                }
                return
            }
            try? pipe.write(message)
        }
        port.disconnectHandler = { _ in beating?.invalidate(); beating = nil; pipe.stop() }
        Live.keep(pipe, for: port)
        try pipe.start()
    }

    /// WebKit doesn't always say when a port goes: an extension unloaded —
    /// taken up afresh, turned off, removed — leaves its worker's ports
    /// disconnected without calling their disconnect handlers. Each host
    /// would run on, with any code prompt it had open, until the browser
    /// quit: iCloud Passwords left a helper behind at every restart. So the
    /// hosts of ports that have gone are stopped here; a port still
    /// connected keeps its own.
    @MainActor
    static func stopOrphans() {
        for (pipe, port) in Live.pipes.values where port.isDisconnected { pipe.stop() }
    }

    /// Hosts that are connected, held until they end.
    private enum Live {
        nonisolated(unsafe) static var pipes: [ObjectIdentifier: (pipe: HostPipe, port: WKWebExtension.MessagePort)] = [:]
        static func keep(_ pipe: HostPipe, for port: WKWebExtension.MessagePort) {
            pipes[ObjectIdentifier(pipe)] = (pipe, port)
            let previous = pipe.onExit
            pipe.onExit = {
                previous?()
                DispatchQueue.main.async { pipes[ObjectIdentifier(pipe)] = nil }
            }
        }
    }
}

/// One host program and the framing Chrome uses to talk to it.
@available(macOS 15.4, *)
final class HostPipe: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let reading = DispatchQueue(label: "SearcheXtra.native-host.read")
    private var buffer = Data()
    private let lock = NSLock()
    private var messages: [Any] = []
    private var finished = false
    private var messageHandler: ((Any) -> Void)?
    private var exitHandler: (() -> Void)?
    var onMessage: ((Any) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return messageHandler }
        set {
            lock.lock()
            messageHandler = newValue
            let queued = newValue == nil ? [] : messages
            if newValue != nil { messages = [] }
            lock.unlock()
            queued.forEach { newValue?($0) }
        }
    }
    var onExit: (() -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return exitHandler }
        set {
            lock.lock()
            let exited = finished
            exitHandler = exited ? nil : newValue
            lock.unlock()
            if exited { newValue?() }
        }
    }
    private var waiters: [CheckedContinuation<Any?, Error>] = []

    init(program: URL, origin: String) {
        process.executableURL = program
        process.arguments = [origin]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        // A host that is already gone — refused to run, killed as it
        // started — would take the browser with it: writing to its closed
        // pipe raises SIGPIPE. Refused, the write only fails.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
    }

    func start() throws {
        let descriptor = output.fileHandleForReading.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        output.fileHandleForReading.readabilityHandler = { [weak self] _ in
            guard let self else { return }
            self.reading.async { [weak self] in self?.drain() }
        }
        process.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.reading.async { [weak self] in
                guard let self else { return }
                // Termination may arrive before the stdout callback. Drain
                // its final reply first, then fail any unanswered reader.
                drain()
                finish()
            }
        }
        do { try process.run() }
        catch { output.fileHandleForReading.readabilityHandler = nil; finish(); throw error }
    }

    private func drain() {
        var bytes = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = bytes.withUnsafeMutableBytes {
                Darwin.read(output.fileHandleForReading.fileDescriptor, $0.baseAddress!, $0.count)
            }
            if count > 0 { take(Data(bytes.prefix(count))) }
            else if count == 0 {
                output.fileHandleForReading.readabilityHandler = nil
                finish()
                return
            } else if errno == EINTR { continue }
            else {
                if errno != EAGAIN && errno != EWOULDBLOCK { finish() }
                return
            }
        }
    }

    func stop() {
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        finish()
    }

    func write(_ message: Any) throws {
        let json = try JSONSerialization.data(withJSONObject: message, options: [.fragmentsAllowed])
        guard json.count <= 1 << 20 else { throw ExtensionNative.Refused(why: "Message too long for a native host") }
        var length = UInt32(json.count).littleEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(json)
        try input.fileHandleForWriting.write(contentsOf: frame)
    }

    func readOne() async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            let result: Result<Any?, Error>?
            if !messages.isEmpty { result = .success(messages.removeFirst()) }
            else if finished { result = .failure(ExtensionNative.Refused(why: "Native host has exited.")) }
            else { waiters.append(continuation); result = nil }
            lock.unlock()
            if let result { continuation.resume(with: result) }
        }
    }

    private func take(_ chunk: Data) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        buffer.append(chunk)
        var messages: [Any] = []
        while buffer.count >= 4 {
            let length = Int(buffer.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian })
            guard length <= 1 << 20 else {
                buffer.removeAll()
                lock.unlock()
                stop()
                return
            }
            guard buffer.count >= 4 + length else { break }
            let body = buffer.subdata(in: 4..<(4 + length))
            buffer.removeSubrange(0..<(4 + length))
            if let message = try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed]) {
                messages.append(message)
            }
        }
        var handed: [(CheckedContinuation<Any?, Error>, Any)] = []
        var delivered: [Any] = []
        let handler = messageHandler
        for message in messages {
            if !waiters.isEmpty { handed.append((waiters.removeFirst(), message)) }
            else if handler != nil { delivered.append(message) }
            else { self.messages.append(message) }
        }
        lock.unlock()
        handed.forEach { $0.0.resume(returning: $0.1) }
        delivered.forEach { handler?($0) }
    }

    private func finish() {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let pending = waiters
        waiters = []
        let exited = exitHandler
        exitHandler = nil
        lock.unlock()
        pending.forEach { $0.resume(throwing: ExtensionNative.Refused(why: "Native host has exited.")) }
        exited?()
    }
}
