import Foundation
import XCTest
@testable import SearcheXtra

@available(macOS 15.4, *)
final class ExtensionNativeTests: XCTestCase {
    private func host(_ script: String) throws -> (HostPipe, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("native-host-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let executable = folder.appendingPathComponent("host.sh")
        try ("#!/bin/sh\n" + script + "\n").write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        return (HostPipe(program: executable, origin: "chrome-extension://fixture/"), folder)
    }

    private func read(_ pipe: HostPipe) async throws -> Any? {
        let timeout = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { pipe.stop() }
        }
        defer { timeout.cancel() }
        return try await pipe.readOne()
    }

    func testFastReplyIsBufferedUntilReadAndExitIsRemembered() async throws {
        let (pipe, folder) = try host(#"printf '\013\000\000\000{"ok":true}'"#)
        defer { pipe.stop(); try? FileManager.default.removeItem(at: folder) }
        let exited = expectation(description: "Host stdout closed after its reply")
        pipe.onExit = { exited.fulfill() }
        try pipe.start()
        await fulfillment(of: [exited], timeout: 2)
        let response = try await read(pipe) as? [String: Bool]
        XCTAssertEqual(response?["ok"], true)
        do { _ = try await read(pipe); XCTFail("An exited host must fail subsequent reads") }
        catch { XCTAssertTrue(error is ExtensionNative.Refused) }
    }

    func testReplyIsDeliveredToHandlerRegisteredAfterHostExit() async throws {
        let (pipe, folder) = try host(#"printf '\013\000\000\000{"ok":true}'"#)
        defer { pipe.stop(); try? FileManager.default.removeItem(at: folder) }
        let exited = expectation(description: "Host exited")
        pipe.onExit = { exited.fulfill() }
        try pipe.start()
        await fulfillment(of: [exited], timeout: 2)
        var received: Bool?
        pipe.onMessage = { received = ($0 as? [String: Bool])?["ok"] }
        XCTAssertEqual(received, true)
    }

    func testExitResumesAnAlreadyWaitingReader() async throws {
        let (pipe, folder) = try host("sleep 0.05")
        defer { pipe.stop(); try? FileManager.default.removeItem(at: folder) }
        try pipe.start()
        do { _ = try await read(pipe); XCTFail("An empty exited host must fail its pending read") }
        catch { XCTAssertTrue(error is ExtensionNative.Refused) }
    }

    func testOversizedReplyHeaderStopsHostWithoutWaitingForItsBody() async throws {
        let (pipe, folder) = try host(#"printf '\377\377\377\377'; exec sleep 10"#)
        defer { pipe.stop(); try? FileManager.default.removeItem(at: folder) }
        let exited = expectation(description: "Oversized native reply was refused")
        pipe.onExit = { exited.fulfill() }
        try pipe.start()
        await fulfillment(of: [exited], timeout: 2)
        do { _ = try await read(pipe); XCTFail("An oversized native reply must close the host") }
        catch { XCTAssertTrue(error is ExtensionNative.Refused) }
    }
}
