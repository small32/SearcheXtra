import AppKit
import XCTest
@testable import SearcheXtra

@MainActor
final class AddressFieldUnicodeTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "address-unicode-\(getpid())", 1)
        super.setUp()
    }

    func testCompletionSelectionPreservesEmojiAndCombiningCharacters() throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        let coordinator = AddressField.Coordinator(browser: browser)
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 500, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let field = AddressField.Field(frame: NSRect(x: 20, y: 20, width: 450, height: 24))
        field.delegate = coordinator
        try XCTUnwrap(window.contentView).addSubview(field)
        defer {
            browser.closeAll()
            window.close()
        }
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)

        for prefix in ["😀", "e\u{301}", "👩🏽‍💻", "中文😀"] {
            let suffix = " café😀"
            field.stringValue = prefix + suffix
            editor.string = field.stringValue
            coordinator.select(from: prefix.utf16.count, in: field)
            XCTAssertEqual(editor.selectedRange(), NSRange(location: prefix.utf16.count, length: suffix.utf16.count), prefix)
            editor.insertText("!", replacementRange: editor.selectedRange())
            XCTAssertEqual(editor.string, prefix + "!", "Replacing a completion must keep the complete typed prefix")
        }
    }

    func testReturningToUnicodeDraftPlacesCaretAfterTheWholeDraft() throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        browser.typed = "👩🏽‍💻e\u{301}"
        let coordinator = AddressField.Coordinator(browser: browser)
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 500, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let field = AddressField.Field(frame: NSRect(x: 20, y: 20, width: 450, height: 24))
        field.stringValue = browser.typed
        field.delegate = coordinator
        try XCTUnwrap(window.contentView).addSubview(field)
        defer {
            browser.closeAll()
            window.close()
        }
        coordinator.focus(field)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: browser.typed.utf16.count, length: 0))
    }
}
