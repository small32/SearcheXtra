import Foundation
import XCTest
@testable import SearcheXtra

@MainActor
final class HistoryLifecycleTests: XCTestCase {
    func testFlushKeepsRecentVisitAndClearBeforeTheSaveDelay() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("search-history-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("history.json")
        let history = History(file: file)
        let url = URL(string: "https://history-lifecycle.example/")!
        history.record(url, title: "Recent visit")
        history.flush()
        XCTAssertEqual(History(file: file).everything().map(\.url), [url])

        history.forget()
        history.flush()
        XCTAssertTrue(History(file: file).everything().isEmpty)
    }

    func testHistoryLimitAlsoBoundsTheLiveMatcher() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("search-history-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("history.json")
        let history = History(file: file)
        let favorite = URL(string: "https://favorite.example/")!
        history.take(favorite, title: "Favorite", count: 100, last: Date())
        for index in 0..<2_025 {
            history.take(URL(string: "https://history-\(index).example/")!, title: "Page \(index)", count: 1, last: Date())
        }
        history.settle()
        history.flush()
        XCTAssertEqual(history.everything().count, 2_000)
        XCTAssertEqual(History(file: file).everything().count, 2_000)
        XCTAssertEqual(history.suggestions(for: "favorite").first?.url, favorite)
    }
}
