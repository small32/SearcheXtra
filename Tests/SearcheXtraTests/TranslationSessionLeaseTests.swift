import AppKit
import Translation
import XCTest
@testable import SearcheXtra

@available(macOS 15, *)
@MainActor
final class TranslationSessionLeaseTests: XCTestCase {
    func testCancelWhileWaitingReleasesHostAndReturnsCancellation() async throws {
        let content = NSView()
        weak var hosted: NSView?
        let mounted = expectation(description: "host installed")
        let ended = expectation(description: "opening cancelled")
        var callback: (@MainActor (TranslationSession) async -> Void)?
        var cancelled = false
        let opening = Task {
            do {
                let lease = try await SessionLease.open(in: content) { receive in
                    callback = receive
                    let view = NSView()
                    hosted = view
                    mounted.fulfill()
                    return view
                }
                lease.close()
                XCTFail("A cancelled pending session must not open")
            } catch is CancellationError { cancelled = true }
            catch { XCTFail("Unexpected error: \(error)") }
            ended.fulfill()
        }
        await fulfillment(of: [mounted], timeout: 1)
        XCTAssertEqual(content.subviews.count, 1)
        opening.cancel()
        await fulfillment(of: [ended], timeout: 1)
        XCTAssertTrue(cancelled)
        XCTAssertTrue(content.subviews.isEmpty)
        XCTAssertNil(hosted)

        // The framework may deliver the callback after removal. No translation
        // is requested here, so a system language download is never started.
        #if compiler(>=6.2)
        if #available(macOS 26, *), let callback {
            let late = TranslationSession(installedSource: Locale.Language(identifier: "en"),
                                          target: Locale.Language(identifier: "fr"))
            await callback(late)
            XCTAssertTrue(content.subviews.isEmpty)
        }
        #endif
        callback = nil
    }

    func testAlreadyCancelledTaskNeverMountsAHost() async {
        let content = NSView()
        let ended = expectation(description: "pre-cancelled opening ended")
        Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                let lease = try await SessionLease.open(in: content) { _ in
                    XCTFail("No host should be created after cancellation")
                    return NSView()
                }
                lease.close()
                XCTFail("Expected cancellation")
            } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
            ended.fulfill()
        }
        await fulfillment(of: [ended], timeout: 1)
        XCTAssertTrue(content.subviews.isEmpty)
    }

    #if compiler(>=6.2)
    func testClosingDeliveredSessionFinishesFrameworkCallback() async throws {
        guard #available(macOS 26, *) else { throw XCTSkip("Constructing a session without a system sheet requires macOS 26") }
        let content = NSView()
        let mounted = expectation(description: "host installed")
        let released = expectation(description: "framework callback released")
        var callback: (@MainActor (TranslationSession) async -> Void)?
        let opening = Task {
            try await SessionLease.open(in: content) { receive in
                callback = receive
                mounted.fulfill()
                return NSView()
            }
        }
        await fulfillment(of: [mounted], timeout: 1)
        let receive = try XCTUnwrap(callback)
        let session = TranslationSession(installedSource: Locale.Language(identifier: "en"),
                                         target: Locale.Language(identifier: "fr"))
        Task { await receive(session); released.fulfill() }
        let lease = try await opening.value
        XCTAssertNotNil(lease.session)
        lease.close()
        lease.close()
        await fulfillment(of: [released], timeout: 1)
        XCTAssertNil(lease.session)
        XCTAssertTrue(content.subviews.isEmpty)
    }
    #endif
}
