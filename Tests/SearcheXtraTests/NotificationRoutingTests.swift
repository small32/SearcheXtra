import AppKit
import WebKit
import XCTest
@testable import SearcheXtra

@MainActor
final class NotificationRoutingTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "notification-routing-\(getpid())", 1)
        super.setUp()
    }

    func testDeliveredNotificationsResolveTheirPartitionWithoutAnInMemoryEntry() throws {
        guard Store.testing else { throw XCTSkip("Needs a probe data store") }
        _ = NSApplication.shared
        let original = Spaces.read()
        defer { Spaces.write(original) }
        let first = Space(id: UUID(), name: "First", colour: 0, sharesSignIns: false)
        let second = Space(id: UUID(), name: "Second", colour: 1, sharesSignIns: false)
        Spaces.write(original + [first, second])
        let a = Spaces.store(for: first.id), b = Spaces.store(for: second.id)
        let aKey = try XCTUnwrap(SiteNotifications.storeKey(a))
        let bKey = try XCTUnwrap(SiteNotifications.storeKey(b))
        XCTAssertNotEqual(aKey, bKey)
        // A fresh router has no old notification-to-store table, as on relaunch.
        let router = SiteNotifications()
        XCTAssertEqual(router.store(for: ["search.store": aKey])?.identifier, a.identifier)
        XCTAssertEqual(router.store(for: ["search.store": bKey])?.identifier, b.identifier)
        XCTAssertNil(router.store(for: ["search.key": "old-unroutable-notification"]))
        XCTAssertNil(router.store(for: ["search.store": UUID().uuidString]))
        Spaces.write(original + [first])
        XCTAssertNil(router.store(for: ["search.store": bKey]), "A removed partition must not fall back to Personal")
    }

    func testPrivateStoresHaveNoPersistentNotificationRoute() {
        XCTAssertNil(SiteNotifications.storeKey(.nonPersistent()))
    }
}
