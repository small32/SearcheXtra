import Foundation
import XCTest
@testable import SearcheXtra

@available(macOS 15.4, *)
final class ExtensionPreparationTests: XCTestCase {
    private func package() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("extension-prepare-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func testAwaitingModulesAreChainedInOrderWithoutRewritingTheirSources() throws {
        let folder = try package()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = "export const ready = await Promise.resolve('ready');"
        let second = "import { ready } from './first.js'; document.body.textContent = ready;"
        try first.write(to: folder.appendingPathComponent("first.js"), atomically: true, encoding: .utf8)
        try second.write(to: folder.appendingPathComponent("second.js"), atomically: true, encoding: .utf8)
        let html = "<head><script type='module' blocking='render' src='first.js'></script><script type='module' src='second.js'></script></head>"
        let chained = try XCTUnwrap(ExtensionShims.chainModules(html, page: folder.appendingPathComponent("options.html"), folder: folder))
        XCTAssertTrue(chained.contains("blocking='render'"))
        XCTAssertTrue(chained.contains("search-modules-options.js"))
        XCTAssertFalse(chained.contains("src='second.js'"))
        let wrapper = try String(contentsOf: folder.appendingPathComponent("search-modules-options.js"), encoding: .utf8)
        let firstImport = try XCTUnwrap(wrapper.range(of: "import \"./first.js\";"))
        let secondImport = try XCTUnwrap(wrapper.range(of: "import \"./second.js\";"))
        XCTAssertLessThan(firstImport.lowerBound, secondImport.lowerBound)
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("first.js"), encoding: .utf8), first)
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("second.js"), encoding: .utf8), second)
    }

    func testAsynchronousOrExternalModuleTagsKeepTheirOwnLoadingBehavior() throws {
        let folder = try package()
        defer { try? FileManager.default.removeItem(at: folder) }
        try "await Promise.resolve();".write(to: folder.appendingPathComponent("first.js"), atomically: true, encoding: .utf8)
        try "void 0;".write(to: folder.appendingPathComponent("second.js"), atomically: true, encoding: .utf8)
        for other in ["<script type='module' async src='second.js'></script>",
                      "<script type='module' src='https://example.com/second.js'></script>"] {
            let html = "<script type='module' src='first.js'></script>" + other
            XCTAssertNil(ExtensionShims.chainModules(html, page: folder.appendingPathComponent("options.html"), folder: folder))
        }
    }

    func testUnicodeResourcesReceiveOneUTF8SignatureWithoutChangingHashbangOrBinaryFiles() throws {
        let folder = try package()
        defer { try? FileManager.default.removeItem(at: folder) }
        let manifest: [String: Any] = ["manifest_version": 3, "name": "Encoding", "version": "1"]
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appendingPathComponent("manifest.json"))
        let unicode = Data("const text = '中文'; const expression = /é/u;".utf8)
        let hashbang = Data("#!/usr/bin/env node\nconsole.log('中文');".utf8)
        let invalid = Data([0xFF, 0xFE, 0x81])
        try unicode.write(to: folder.appendingPathComponent("content.js"))
        try hashbang.write(to: folder.appendingPathComponent("tool.js"))
        try invalid.write(to: folder.appendingPathComponent("binary.js"))
        try ExtensionShims.prepare(folder)
        let signature = Data([0xEF, 0xBB, 0xBF])
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("content.js")), signature + unicode)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("tool.js")), hashbang)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("binary.js")), invalid)
        // A new preparation revision reads files again, without stacking signatures.
        try ExtensionShims.prepare(folder, workerGeneration: 1)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("content.js")), signature + unicode)
    }
}
