import XCTest
@testable import SearcheXtra

@available(macOS 15.4, *)
@MainActor
final class ExtensionBrowsingDataTests: XCTestCase {
    func testUnselectedUnsupportedTypesDoNotRejectSelectedCache() {
        XCTAssertNoThrow(try ExtensionShims.validateRemoval(["cache": true, "downloads": false, "passwords": false]))
        XCTAssertNoThrow(try ExtensionShims.validateRemoval(["appcache": true]))
        XCTAssertThrowsError(try ExtensionShims.validateRemoval(["cache": true, "downloads": true]))
    }

    func testUserScriptPackageCarriesOneIdentityContentScript() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("user-identity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let manifest = #"{"manifest_version":3,"name":"Identity fixture","version":"1.0","optional_permissions":["userScripts"]}"#
        try Data(manifest.utf8).write(to: folder.appendingPathComponent("manifest.json"))
        try ExtensionShims.prepare(folder)
        try ExtensionShims.prepare(folder)
        let prepared = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("manifest.json"))) as? [String: Any])
        let entries = try XCTUnwrap(prepared["content_scripts"] as? [[String: Any]])
        let identity = entries.filter { ($0["js"] as? [String] ?? []).contains("_search/user-script-identity.js") }
        XCTAssertEqual(identity.count, 1)
        XCTAssertEqual(identity.first?["all_frames"] as? Bool, true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("_search/user-script-identity.js").path))
    }
}
