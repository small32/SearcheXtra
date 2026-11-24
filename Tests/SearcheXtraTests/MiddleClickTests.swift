import AppKit
import XCTest
@testable import SearcheXtra

@MainActor
final class MiddleClickTests: XCTestCase {
    func testOnlyMiddleClickInsideTheTabClosesIt() {
        _ = NSApplication.shared
        let view = MiddleClick.Catch(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
        let inside = NSPoint(x: 50, y: 15)
        let outside = NSPoint(x: 120, y: 15)
        var closed = 0
        view.act = { closed += 1 }

        view.release(button: 2, at: inside)
        XCTAssertEqual(closed, 0, "A release without a press does not close")
        view.press(button: 3)
        view.release(button: 3, at: inside)
        XCTAssertEqual(closed, 0, "Extra mouse buttons do not close tabs")
        view.press(button: 2)
        view.release(button: 2, at: outside)
        XCTAssertEqual(closed, 0, "Moving outside before release cancels closing")
        view.press(button: 2)
        XCTAssertEqual(closed, 0, "macOS closes on release")
        view.release(button: 2, at: inside)
        XCTAssertEqual(closed, 1)
        view.release(button: 2, at: inside)
        XCTAssertEqual(closed, 1, "One click closes once")
    }
}
