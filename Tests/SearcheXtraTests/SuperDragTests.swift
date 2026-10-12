import XCTest
@testable import SearcheXtra

final class SuperDragTests: XCTestCase {
    func testDefaultActionsThresholdAndModifiers() throws {
        let config=SuperDragConfig();try config.validate()
        let page=URL(string:"https://example.com")
        var request=SuperDragRequest(phase:"finish",object:"link",value:"https://target.example/",dx:0,dy:40,direction:"down",modifier:"none",region:"page",screenX:0,screenY:0)
        XCTAssertEqual(SuperDrag.resolve(config,request,page:page)?.action,"openBackgroundTab")
        request.object="text";request.value="hello";request.dy = -40
        XCTAssertEqual(SuperDrag.resolve(config,request,page:page)?.action,"search")
        request.object="image";request.value="https://target.example/image.png";request.dy=40
        XCTAssertEqual(SuperDrag.resolve(config,request,page:page)?.action,"saveImage")
        request.dy=9;XCTAssertNil(SuperDrag.resolve(config,request,page:page))
        request.dy=40;request.modifier="shift";XCTAssertNil(SuperDrag.resolve(config,request,page:page))
    }
    func testDirectionsExclusionsAndDisable() {
        let vectors:[(Double,Double,String)]=[(0,-40,"up"),(40,-40,"upRight"),(40,0,"right"),(40,40,"downRight"),(0,40,"down"),(-40,40,"downLeft"),(-40,0,"left"),(-40,-40,"upLeft")]
        for (dx,dy,d) in vectors { XCTAssertEqual(SuperDrag.direction(dx,dy,mode:"8-way"),d) }
        var config=SuperDragConfig()
        XCTAssertFalse(SuperDrag.enabled(config,on:URL(string:"https://sub.docs.google.com/path")))
        XCTAssertTrue(SuperDrag.enabled(config,on:URL(string:"https://docs.google.com.evil.example")))
        config.enabled=false;XCTAssertFalse(SuperDrag.enabled(config,on:URL(string:"https://example.com")))
    }
    func testJSONRoundTripAndMissingFieldsMigration() throws {
        let original=SuperDragConfig();let decoded=try JSONDecoder().decode(SuperDragConfig.self,from:JSONEncoder().encode(original));XCTAssertEqual(decoded,original)
        let minimal=Data(#"{"enabled":true,"rules":[{"object":"text","direction":"up","action":"copy"}]}"#.utf8)
        let imported=try JSONDecoder().decode(SuperDragConfig.self,from:minimal);try imported.validate();XCTAssertEqual(imported.rules.first?.region,"page")
        var invalid=original;invalid.rules.append(invalid.rules[0]);XCTAssertThrowsError(try invalid.validate())
    }
}
