import XCTest
import AppKit
import WebKit
import JavaScriptCore
@testable import SearcheXtra
final class FlowDragTests:XCTestCase {
    func testImportFlowMouseDirectionsAndOptions() throws {
        let data=Data(#"{"enableHUD":false,"textDragGestures":[{"direction":"↑→","action":"search","active":false,"engine":"custom","url":"https://search.example/?q=%s"}],"imageDragGestures":[{"direction":"→","action":"openTab","preferLink":true}]}"#.utf8)
        let config=try FlowDrag.importConfig(data)
        XCTAssertFalse(config.showHints);XCTAssertEqual(config.rules[0].pattern,"↑→");XCTAssertFalse(config.rules[0].active)
        XCTAssertEqual(config.rules[1].action,"openImage");XCTAssertTrue(config.rules[1].preferLink)
        let restored=try FlowDrag.importConfig(JSONEncoder().encode(config));XCTAssertEqual(restored,config)
    }
    func testSpecificRuleOverridesWildcard() throws {
        var config=FlowDragConfig();config.rules.append(.init(object:"text",pattern:"*",action:"copy"));config.rules.append(.init(object:"text",pattern:"↓",action:"none"))
        let request=FlowDragRequest(phase:"perform",id:"fixture",object:"text",pattern:"↓",text:"words",linkUrl:"",imageUrl:"",linkText:"",pageUrl:"https://example.com")
        XCTAssertEqual(FlowDrag.resolve(config,request)?.action,"none")
        var other=request;other.pattern="↑→";XCTAssertEqual(FlowDrag.resolve(config,other)?.action,"copy")
        config.excludedSites=["example.com"];XCTAssertNil(FlowDrag.resolve(config,other))
    }
    @MainActor func testMouseDragCancellationPayloadDecodes() throws {
        let js=try XCTUnwrap(JSContext())
        js.evaluateScript(#"""
        const window={},location={href:'https://example.com/page',hostname:'example.com',protocol:'https:'};
        const handlers={},messages=[];
        const addEventListener=(name,handler)=>handlers[name]=handler;
        const getSelection=()=>({toString:()=> 'words',rangeCount:1,
          getRangeAt:()=>({getClientRects:()=>[{left:90,right:170,top:90,bottom:120}]})});
        const crypto={getRandomValues:values=>values.fill(12)};
        const document={createElement:()=>({setAttribute(){},style:{},remove(){}}),documentElement:{append(){}}};
        """#)
        js.evaluateScript(FlowDragSettings.source)
        js.evaluateScript(#"""
        sxInstallFlowDrag({config:{enabled:true,enableText:true,enableLink:true,enableImage:true,
          showHints:false,showTrail:false,ignoreEditable:true,distanceThreshold:20,excludedSites:[],
          rules:[{object:'text',pattern:'→',action:'search'}]},labels:{}},message=>messages.push(message));
        const target={tagName:'SPAN',getAttribute:()=>null,closest:()=>null};
        const event={target,isTrusted:true,button:0,buttons:1,clientX:100,clientY:100,defaultPrevented:false,
          composedPath:()=>[target],preventDefault(){this.defaultPrevented=true},stopImmediatePropagation(){}};
        handlers.mousedown(event);handlers.dragstart(event);
        handlers.mousemove({...event,clientX:150});handlers.keydown({key:'Escape'});
        """#)
        XCTAssertNil(js.exception?.toString())
        let value=try XCTUnwrap(js.evaluateScript("JSON.stringify(messages.find(message=>message.phase==='cancel'))")?.toString())
        let request=try JSONDecoder().decode(FlowDragRequest.self,from:Data(value.utf8))
        XCTAssertEqual(request.phase,"cancel")
        XCTAssertEqual(request.object,"text")
        XCTAssertEqual(request.text,"words")
        XCTAssertEqual(request.pageUrl,"https://example.com/page")
        XCTAssertFalse(request.id.isEmpty)
        XCTAssertFalse(try XCTUnwrap(js.evaluateScript("window.__sxFlowDrag.isDragging()")?.toBool()))
    }
    @MainActor func testSettingsEditsPersistAndUpdateScriptOptions() throws {
        guard Store.testing else{throw XCTSkip("Run with SEARCH_PROBE=interface-tests")}
        let settings=FlowDragSettings.shared,old=settings.config
        defer{settings.config=old}
        settings.config=FlowDragConfig()
        settings.config.enabled=false
        settings.config.rules[0].action="copy"
        let saved=try JSONDecoder().decode(FlowDragConfig.self,from:XCTUnwrap(Store.settings.data(forKey:"flowDrag.config")))
        XCTAssertFalse(saved.enabled)
        XCTAssertEqual(saved.rules[0].action,"copy")
        let options=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(FlowDragSettings.options.utf8)) as? [String:Any])
        XCTAssertEqual(Set(options.keys),Set(["config","labels"]))
        let injected=try JSONDecoder().decode(FlowDragConfig.self,from:JSONSerialization.data(withJSONObject:XCTUnwrap(options["config"])))
        XCTAssertEqual(injected,saved)
    }
    @MainActor func testLiveConfigurationUpdatesExistingDocument() async throws {
        guard Store.testing else{throw XCTSkip("Run with SEARCH_PROBE=interface-tests")}
        _=NSApplication.shared
        let settings=FlowDragSettings.shared,old=settings.config
        defer{settings.config=old}
        let configuration=WKWebViewConfiguration();configuration.websiteDataStore = .nonPersistent()
        let web=WKWebView(frame:.zero,configuration:configuration)
        defer{web.stopLoading()}
        let loaded=expectation(description:"Flow drag fixture document loaded")
        let navigation=FlowDragFixtureNavigation(loaded)
        web.navigationDelegate=navigation
        web.loadHTMLString("<html><body>Flow drag configuration fixture</body></html>",baseURL:nil)
        await fulfillment(of:[loaded],timeout:5)
        _=try await web.evaluateJavaScript("window.__sxFlowDrag={configure(value){window.flowDragFixture=value.config}};true",in:nil,contentWorld:Web.world)
        settings.config=FlowDragConfig()
        settings.config.rules[0].action="copy"
        settings.config.distanceThreshold=75
        FlowDragRelay().configure(web)
        let value=try await web.evaluateJavaScript("JSON.stringify(window.flowDragFixture)",in:nil,contentWorld:Web.world)
        let text=try XCTUnwrap(value as? String)
        let applied=try JSONDecoder().decode(FlowDragConfig.self,from:Data(text.utf8))
        XCTAssertEqual(applied,settings.config)
    }
    @MainActor func testBackgroundSearchStartsImmediately() throws {
        guard Store.testing else{throw XCTSkip("Run with SEARCH_PROBE=interface-tests")}
        _=NSApplication.shared
        let old=FlowDragSettings.shared.config,oldEngine=Shared.prefs.engine,oldTemplate=Shared.prefs.customEngine
        let browser=Browser(record:WindowRecord(),opensStartPage:false)
        defer{FlowDragSettings.shared.config=old;Shared.prefs.engine=oldEngine;Shared.prefs.customEngine=oldTemplate;browser.tabs.forEach{$0.close()};browser.dozing?.invalidate()}
        Shared.prefs.engine = .custom;Shared.prefs.customEngine="http://127.0.0.1:1/search?q=%s"
        let source=browser.open(URL(string:"http://127.0.0.1:1/source")!,foreground:true)
        var config=FlowDragConfig();config.rules=["↑","↓","←","→"].map{FlowDragRule(object:"text",pattern:$0,action:"search",active:false,autoDetectUrl:false)};FlowDragSettings.shared.config=config
        for direction in ["↑","↓","←","→"] {
            let before=Set(browser.tabs.map(\.id));let words="后台搜索 "+direction
            browser.performFlowDrag(source,.init(phase:"perform",id:"fixture",object:"text",pattern:direction,text:words,linkUrl:"",imageUrl:"",linkText:"",pageUrl:"http://127.0.0.1:1/source"))
            let result=try XCTUnwrap(browser.tabs.first{!before.contains($0.id)})
            XCTAssertEqual(browser.activeID,source.id);XCTAssertFalse(result.asleep);XCTAssertNotNil(result.built);XCTAssertEqual(result.address,browser.searchURL(for:words))
        }
    }
}

@MainActor private final class FlowDragFixtureNavigation:NSObject,WKNavigationDelegate {
    let loaded:XCTestExpectation
    init(_ loaded:XCTestExpectation){self.loaded=loaded}
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!){loaded.fulfill()}
}
