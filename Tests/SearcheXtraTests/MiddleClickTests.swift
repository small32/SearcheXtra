import AppKit
import XCTest
@testable import SearcheXtra

@MainActor
final class MiddleClickTests: XCTestCase {
    func testOnlyMiddleClickInsideTheTabClosesIt() throws {
        _ = NSApplication.shared
        let view = MiddleClick.Catch(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        defer { window.contentView = nil }
        var closed = 0
        view.act = { closed += 1 }

        func event(_ type: NSEvent.EventType, button: Int64 = 2, x: CGFloat = 50) throws -> NSEvent {
            let original = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 15),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
            let cg = try XCTUnwrap(original.cgEvent)
            cg.setIntegerValueField(.mouseEventButtonNumber, value: button)
            // The original CGEvent contains a screen position, but its
            // synthesized window number makes the bridge read local points.
            cg.location = original.locationInWindow
            return try XCTUnwrap(NSEvent(cgEvent: cg))
        }

        view.otherMouseUp(with: try event(.otherMouseUp))
        XCTAssertEqual(closed, 0, "A release without a press does not close")
        view.otherMouseDown(with: try event(.otherMouseDown, button: 3))
        view.otherMouseUp(with: try event(.otherMouseUp, button: 3))
        XCTAssertEqual(closed, 0, "Extra mouse buttons do not close tabs")
        view.otherMouseDown(with: try event(.otherMouseDown))
        view.otherMouseUp(with: try event(.otherMouseUp, x: 120))
        XCTAssertEqual(closed, 0, "Moving outside before release cancels closing")
        view.otherMouseDown(with: try event(.otherMouseDown))
        XCTAssertEqual(closed, 0, "macOS closes on release")
        view.otherMouseUp(with: try event(.otherMouseUp))
        XCTAssertEqual(closed, 1)
        view.otherMouseUp(with: try event(.otherMouseUp))
        XCTAssertEqual(closed, 1, "One click closes once")
    }
}
