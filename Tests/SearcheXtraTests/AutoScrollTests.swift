import JavaScriptCore
import XCTest
@testable import SearcheXtra

final class AutoScrollTests: XCTestCase {
    func testDisablingStopsAnActiveScrollAndCancelsItsAnimation() throws {
        let js = try XCTUnwrap(JSContext())
        js.evaluateScript(#"""
        const window = {}, handlers = {};
        let animation, scheduled = 0, cancelled = 0, removed = false;
        const addEventListener = (name, handler) => handlers[name] = handler;
        const removeEventListener = name => delete handlers[name];
        const requestAnimationFrame = handler => { animation = handler; return ++scheduled; };
        const cancelAnimationFrame = () => ++cancelled;
        const ground = { style: { cursor: 'auto' }, appendChild() {}, scrollBy() {} };
        const document = {
          body: { closest: () => null }, documentElement: ground, scrollingElement: ground,
          addEventListener,
          createElement: () => ({ style: {}, attachShadow: () => ({}), remove: () => removed = true })
        };
        const performance = { now: () => 0 };
        """#)
        js.evaluateScript(AutoScroll.script)
        js.evaluateScript("handlers.mousedown({ button: 1, target: document.body, clientX: 10, clientY: 10, preventDefault() {} });")
        XCTAssertNil(js.exception?.toString())
        XCTAssertEqual(js.evaluateScript("scheduled")?.toInt32(), 1)
        js.evaluateScript(AutoScroll.off)
        js.evaluateScript("animation();")
        XCTAssertNil(js.exception?.toString())
        XCTAssertEqual(js.evaluateScript("cancelled")?.toInt32(), 1)
        XCTAssertEqual(js.evaluateScript("scheduled")?.toInt32(), 1, "A disabled scroll must not schedule another frame")
        XCTAssertEqual(js.evaluateScript("removed && ground.style.cursor === 'auto'")?.toBool(), true)
        XCTAssertEqual(js.evaluateScript("typeof handlers.mousemove")?.toString(), "undefined")
    }
}
