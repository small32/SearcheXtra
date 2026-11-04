import AppKit
import WebKit
import XCTest
@testable import SearcheXtra

@available(macOS 15.4, *)
@MainActor
final class ExtensionAsideTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "extension-aside-\(getpid())", 1)
        super.setUp()
    }

    func testWindowlessPageIsKnownToLateExtensionAndBecomesANewTabWhenKept() async throws {
        guard Store.testing else { throw XCTSkip("Run with SEARCH_PROBE=interface-tests") }
        _ = NSApplication.shared
        let owner = Extensions.shared
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        owner.attach(browser)
        let page = Tab()
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("aside-extension-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let manifest = #"{"manifest_version":3,"name":"Aside fixture","version":"1.0","permissions":["tabs"]}"#
        try Data(manifest.utf8).write(to: source.appendingPathComponent("manifest.json"))
        let id = Crx.unpackedID(for: source)
        defer {
            owner.remove(id)
            page.close()
            browser.closeAll()
            owner.detach(browser)
            try? FileManager.default.removeItem(at: source)
        }

        // A page already showing when an extension loads must be announced
        // to its new context, even though tabs.query must not list it.
        owner.openedAside(page)
        let aside = owner.adapter(for: page)
        let install = try XCTUnwrap(owner.installFolder(at: source, confirm: false))
        await install.value
        let context = try XCTUnwrap(owner.contexts[id])
        XCTAssertTrue(context.openTabs.contains(aside))
        XCTAssertNil(aside.window(for: context))
        XCTAssertEqual(aside.indexInWindow(for: context), NSNotFound)
        XCTAssertFalse(owner.visibleTabs(of: browser, for: context).contains { $0 === page })

        // Repeated registration must leave one lifetime/adapter, not another
        // tab or observer for each pass through the presenting view.
        owner.openedAside(page)
        XCTAssertTrue(owner.adapter(for: page) === aside)
        browser.insert(page, at: browser.tabs.count)
        let until = Date().addingTimeInterval(3)
        while owner.adapter(for: page) === aside && Date() < until {
            try await Task.sleep(for: .milliseconds(10))
        }
        let kept = owner.adapter(for: page)
        XCTAssertFalse(kept === aside)
        XCTAssertFalse(kept.aside)
        XCTAssertFalse(context.openTabs.contains(aside))
        XCTAssertTrue(context.openTabs.contains(kept))
        XCTAssertTrue(owner.visibleTabs(of: browser, for: context).contains { $0 === page })
    }

    func testClosingAWindowlessPageRetiresItsExtensionAdapter() throws {
        guard Store.testing else { throw XCTSkip("Run with SEARCH_PROBE=interface-tests") }
        _ = NSApplication.shared
        let owner = Extensions.shared
        let page = Tab()
        owner.openedAside(page)
        let adapter = owner.adapter(for: page)
        XCTAssertTrue(adapter.aside)
        page.close()
        owner.openedAside(page)
        XCTAssertFalse(owner.adapter(for: page) === adapter)
        owner.closedAside(page)
    }
}
