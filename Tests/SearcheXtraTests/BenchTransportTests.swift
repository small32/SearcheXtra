import AppKit
import Darwin
import XCTest
@testable import SearcheXtra

@MainActor
final class BenchTransportTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "bench-transport-\(getpid())", 1)
        super.setUp()
    }

    func testClientDisconnectDuringReplyDoesNotRaiseSIGPIPE() async throws {
        let (server, peer) = try sockets()
        let done = expectation(description: "disconnected client released")
        let client = Bench.Client(fd: server) { _, answer in
            answer(["blob": String(repeating: "x", count: 1_000_000)])
        } gone: { _ in done.fulfill() }
        defer { client.drop() }
        try sendRequest(peer)
        Darwin.close(peer)
        await fulfillment(of: [done], timeout: 2)
    }

    func testClientThatDoesNotReadCannotBlockTheMainQueueIndefinitely() async throws {
        let (server, peer) = try sockets()
        defer { Darwin.close(peer) }
        var small: Int32 = 1024
        XCTAssertEqual(setsockopt(server, SOL_SOCKET, SO_SNDBUF, &small, socklen_t(MemoryLayout<Int32>.size)), 0)
        let done = expectation(description: "blocked writer released")
        let heartbeat = expectation(description: "main queue still responds")
        var elapsed: TimeInterval?
        let client = Bench.Client(fd: server) { _, answer in
            let started = Date()
            DispatchQueue.main.async { elapsed = Date().timeIntervalSince(started); heartbeat.fulfill() }
            answer(["blob": String(repeating: "x", count: 4_000_000)])
        } gone: { _ in done.fulfill() }
        defer { client.drop() }
        try sendRequest(peer)
        await fulfillment(of: [done, heartbeat], timeout: 3)
        XCTAssertLessThan(try XCTUnwrap(elapsed), 2, "The UI queue must recover from EAGAIN")
    }

    func testLateAnswerAndRepeatedDropDoNotCloseTheConnectionTwice() async throws {
        let (server, peer) = try sockets()
        defer { Darwin.close(peer) }
        let received = expectation(description: "request received")
        var reply: (([String: Any]) -> Void)?
        var drops = 0
        let client = Bench.Client(fd: server) { _, answer in
            reply = answer
            received.fulfill()
        } gone: { _ in drops += 1 }
        defer { client.drop() }
        try sendRequest(peer)
        await fulfillment(of: [received], timeout: 2)
        client.drop()
        XCTAssertEqual(drops, 1)
        // A pending page callback can arrive after Bench.stop() dropped it.
        reply?(["ok": true])
        client.drop()
        XCTAssertEqual(drops, 1)
    }

    func testMalformedJSONReturnsOneErrorAndReleasesItsConnection() async throws {
        let (server, peer) = try sockets()
        defer { Darwin.close(peer) }
        XCTAssertNotEqual(fcntl(peer, F_SETFL, fcntl(peer, F_GETFL) | O_NONBLOCK), -1)
        let done = expectation(description: "bad request released")
        let client = Bench.Client(fd: server) { _, _ in
            XCTFail("Non-object JSON must not reach command handling")
        } gone: { _ in done.fulfill() }
        defer { client.drop() }
        let request = Array("[]\n".utf8)
        XCTAssertEqual(Darwin.write(peer, request, request.count), request.count)
        await fulfillment(of: [done], timeout: 2)
        var bytes = [UInt8](repeating: 0, count: 256)
        let count = Darwin.read(peer, &bytes, bytes.count)
        XCTAssertGreaterThan(count, 0)
        let result = try JSONSerialization.jsonObject(with: Data(bytes.prefix(max(0, count)))) as? [String: Any]
        XCTAssertEqual(result?["error"] as? String, "not a JSON object")
    }

    private func sockets() throws -> (Int32, Int32) {
        var descriptors: [Int32] = [-1, -1]
        guard Darwin.socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return (descriptors[0], descriptors[1])
    }

    private func sendRequest(_ peer: Int32) throws {
        let request = Array("{}\n".utf8)
        guard Darwin.write(peer, request, request.count) == request.count else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
}
