import AppKit
import SwiftUI
import WebKit
struct FlowDragRule: Codable,Equatable,Identifiable {
    var object:String
    var pattern:String
    var action:String
    var engine="system"
    var url=""
    var active=true
    var position="right"
    var incognito=false
    var autoDetectUrl=true
    var preferLink=false
    var asMarkdown=false
    var folderId=""
    var subdir=""
    var id:String {object+"|"+pattern}
}
struct FlowDragConfig: Codable,Equatable {
    var enabled=true,enableText=true,enableLink=true,enableImage=true,showHints=true,showTrail=false,ignoreEditable=true
    var distanceThreshold:Double=20
    var excludedSites:[String]=[]
    var rules:[FlowDragRule]=[.init(object:"text",pattern:"→",action:"search"),.init(object:"link",pattern:"→",action:"openTab"),.init(object:"image",pattern:"→",action:"openImage")]
    func validate() throws {
        let validRules = rules.allSatisfy { rule in
            let validEngine = rule.engine != "custom" || (
                rule.url.contains("%s") && FlowDrag.web(rule.url.replacingOccurrences(of: "%s", with: "x"))
            )
            let validSubdirectory = !rule.subdir.hasPrefix("/") && !rule.subdir.contains(":") &&
                !rule.subdir.components(separatedBy: CharacterSet(charactersIn: "/\\")).contains(where: { $0 == ".." || $0 == "." })
            return FlowDrag.objects.contains(rule.object) && FlowDrag.validPattern(rule.pattern) &&
                FlowDrag.actions(rule.object).contains(rule.action) && FlowDrag.positions.contains(rule.position) &&
                FlowDrag.engines.contains(rule.engine) && validEngine && validSubdirectory
        }
        let validSites = excludedSites.allSatisfy { site in
            !site.isEmpty && !site.contains("/") && !site.contains(" ") && URL(string: "https://" + site)?.host != nil
        }
        guard distanceThreshold.isFinite, (1...200).contains(distanceThreshold), rules.count <= 200,
              Set(rules.map(\.id)).count == rules.count, validRules, validSites
        else { throw FlowDrag.Invalid() }
    }
}
struct FlowDragRequest: Codable,Equatable {
    var phase:String
    var id:String
    var object:String
    var pattern:String
    var text:String
    var linkUrl:String
    var imageUrl:String
    var linkText:String
    var pageUrl:String
}
enum FlowDrag {
    struct Invalid:Error {}
    static let objects=["text","link","image"],positions=["current","left","right","first","last"],engines=["system","baidu","google","google_translate","bing","bing_translate","360","sogou","duckduckgo","yahoo","yahoo_jp","naver","seznam","tineye","yandex","saucenao","iqdb","trace","custom"]
    static func enginesFor(_ type:String)->[String] {type=="image" ? ["system","google","bing","tineye","yandex","saucenao","iqdb","trace","custom"]:engines.filter{!["tineye","saucenao","iqdb","trace"].contains($0)}}
    static func actions(_ type:String)->[String] {type=="text" ? ["none","search","copy"]:type=="link" ? ["none","openTab","copyLink","copyLinkText","copyLinkAndText","bookmarkLink"]:["none","openImage","openLink","copyImageUrl","saveImage","imageSearch"]}
    static func validPattern(_ value:String)->Bool {value=="*" || !value.isEmpty&&value.count<=32&&value.allSatisfy{"↑↓←→".contains($0)}}
    static func enabled(_ c:FlowDragConfig,_ p:FlowDragRequest)->Bool {
        guard c.enabled,objects.contains(p.object),p.object=="text" ? c.enableText:p.object=="link" ? c.enableLink:c.enableImage,let u=URL(string:p.pageUrl),["http","https"].contains(u.scheme ?? ""),let host=u.host else{return false}
        return !c.excludedSites.contains{host==$0 || host.hasSuffix("."+$0)}
    }
    static func resolve(_ c:FlowDragConfig,_ p:FlowDragRequest)->FlowDragRule? {enabled(c,p)&&validPattern(p.pattern) ? c.rules.first{$0.object==p.object&&$0.pattern==p.pattern} ?? c.rules.first{$0.object==p.object&&$0.pattern=="*"}:nil}
    static func web(_ value:String)->Bool {URL(string:value).map{["http","https"].contains($0.scheme ?? "") && $0.host != nil} ?? false}
    static func template(_ engine:String,current:String,custom:String,image:Bool=false)->String {
        switch engine {
        case "custom":return custom
        case "baidu":return "https://www.baidu.com/s?wd=%s"
        case "google":return image ? "https://lens.google.com/uploadbyurl?url=%s":"https://www.google.com/search?q=%s"
        case "bing":return image ? "https://www.bing.com/images/searchbyimage?cbir=sbi&imgurl=%s":"https://www.bing.com/search?q=%s"
        case "360":return "https://www.so.com/s?q=%s"
        case "sogou":return "https://www.sogou.com/web?query=%s"
        case "duckduckgo":return "https://duckduckgo.com/?q=%s"
        case "google_translate":return "https://translate.google.com/?sl=auto&text=%s"
        case "bing_translate":return "https://www.bing.com/translator/?text=%s"
        case "yahoo":return "https://search.yahoo.com/search?p=%s"
        case "yahoo_jp":return "https://search.yahoo.co.jp/search?p=%s"
        case "naver":return "https://search.naver.com/search.naver?query=%s"
        case "seznam":return "https://search.seznam.cz/?q=%s"
        case "tineye":return "https://tineye.com/search?url=%s"
        case "yandex":return image ? "https://yandex.com/images/search?rpt=imageview&url=%s":"https://yandex.com/search/?text=%s"
        case "saucenao":return "https://saucenao.com/search.php?url=%s"
        case "iqdb":return "https://iqdb.org/?url=%s"
        case "trace":return "https://trace.moe/?url=%s"
        default:return image ? "https://lens.google.com/uploadbyurl?url=%s":current
        }
    }
}
@MainActor final class FlowDragSettings:ObservableObject {
    static let shared=FlowDragSettings()
    @Published var config=FlowDragConfig() {didSet {if let data=try? JSONEncoder().encode(config){Store.settings.set(data,forKey:"flowDrag.config")};for browser in Browsers.all {for tab in browser.tabs + browser.parkedTabs + [browser.peekTab].compactMap({$0}) + LittleWindow.tabs(for: browser) {tab.refreshFlowDrag()}}}}
    init() {if let data=Store.settings.data(forKey:"flowDrag.config"),let value=try? JSONDecoder().decode(FlowDragConfig.self,from:data),(try? value.validate()) != nil {config=value}}
    static var source:String {L10n.resourceBundle.url(forResource:"FlowDrag",withExtension:"js").flatMap{try? String(contentsOf:$0,encoding:.utf8)} ?? ""}
    static var options:String {
        let labels=Dictionary(uniqueKeysWithValues:FlowDrag.objects.flatMap(FlowDrag.actions).reduce(into:Set<String>()){$0.insert($1)}.map{($0,L10n.text("flowDrag.action."+$0))})
        guard let data=try? JSONSerialization.data(withJSONObject:["config":JSONSerialization.jsonObject(with:JSONEncoder().encode(shared.config)),"labels":labels,"pointerDrag":true]),let text=String(data:data,encoding:.utf8) else{return "{}"}
        return text
    }
    static var script:String {"(function(){"+source+";sxInstallFlowDrag("+options+",p=>webkit.messageHandlers.officeFlowDrag.postMessage(p));})();"}
}
final class FlowDragRelay:NSObject,WKScriptMessageHandler {
    static let name="officeFlowDrag"
    weak var tab:Tab?
    private var pending:FlowDragRequest?
    private var started=Date()
    private var frames:[WKFrameInfo]=[]
    func userContentController(_ controller:WKUserContentController,didReceive message:WKScriptMessage) {
        MainActor.assumeIsolated {
            guard let tab,let body=message.body as? [String:Any],let data=try? JSONSerialization.data(withJSONObject:body),let p=try? JSONDecoder().decode(FlowDragRequest.self,from:data) else{return}
            if p.phase=="cancel" {if pending?.id==p.id {pending=nil};return}
            guard let page=URL(string:p.pageUrl),let origin=page.host,origin==message.frameInfo.securityOrigin.host else{return}
            if p.phase=="ready" {
                if message.frameInfo.isMainFrame {frames.removeAll()}
                frames.append(message.frameInfo)
                // Settings may have changed while this document was loading.
                // Its document-start script is a snapshot; refresh each frame
                // after the installed bridge announces that it is ready.
                if let web=tab.built {configure(web,in:message.frameInfo)}
                return
            }
            guard FlowDrag.enabled(FlowDragSettings.shared.config,p) else{return}
            if p.phase=="begin" {pending=p;started=Date();return}
            guard p.phase=="perform",var previous=pending,Date().timeIntervalSince(started)<120 else{return}
            var current=p;previous.phase="";previous.pattern="";current.phase="";current.pattern=""
            guard current==previous else{return};pending=nil
            tab.onFlowDrag?(tab,p)
        }
    }
    @MainActor func configure(_ web:WKWebView) {
        configure(web,in:nil)
        for frame in frames where !frame.isMainFrame {configure(web,in:frame)}
    }
    @MainActor private func configure(_ web:WKWebView,in frame:WKFrameInfo?) {
        let script="window.__sxFlowDrag?.configure("+FlowDragSettings.options+")"
        web.evaluateJavaScript(script,in:frame,in:Web.world){_ in}
    }
}
extension Browser {
    func performFlowDrag(_ source:Tab,_ p:FlowDragRequest) {
        let inRow = tabs.contains { $0 === source }
        let inPeek = peekTab === source
        let inLittle = LittleWindow.tabs(for: self).contains { $0 === source }
        guard inRow || inPeek || inLittle,let r=FlowDrag.resolve(FlowDragSettings.shared.config,p),r.action != "none" else{return}
        var target:URL?,copy:String?
        switch r.action {
        case "search":target=r.autoDetectUrl ? Address.url(from:p.text).flatMap{FlowDrag.web($0.absoluteString) ? $0:nil}:nil;if target==nil {target=Engine.url(for:p.text,template:FlowDrag.template(r.engine,current:prefs.engine.template(custom:prefs.customEngine),custom:r.url))}
        case "openTab":target=URL(string:p.linkUrl)
        case "openImage":target=URL(string:r.preferLink&&FlowDrag.web(p.linkUrl) ? p.linkUrl:p.imageUrl)
        case "openLink":target=URL(string:FlowDrag.web(p.linkUrl) ? p.linkUrl:p.imageUrl)
        case "imageSearch":target=Engine.url(for:p.imageUrl,template:FlowDrag.template(r.engine,current:"",custom:r.url,image:true))
        case "copy":copy=p.text
        case "copyLink":copy=p.linkUrl
        case "copyImageUrl":copy=p.imageUrl
        case "copyLinkText":copy=p.linkText
        case "copyLinkAndText":copy=r.asMarkdown ? "["+p.linkText.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"[",with:"\\[").replacingOccurrences(of:"]",with:"\\]")+"]("+p.linkUrl+")":p.linkText+"\n"+p.linkUrl
        case "bookmarkLink":if let u=URL(string:p.linkUrl),FlowDrag.web(p.linkUrl),let node=bookmarks.add(u,title:p.linkText),let folder=UUID(uuidString:r.folderId){bookmarks.move(node.id,into:folder)}
        case "saveImage":if let u=URL(string:p.imageUrl),FlowDrag.web(p.imageUrl){saveFlowDragImage(u,source:source,subdir:r.subdir)};return
        default:break
        }
        if let copy {NSPasteboard.general.clearContents();NSPasteboard.general.setString(copy,forType:.string)}
        if let target,FlowDrag.web(target.absoluteString) {
            let privately=source.shy || r.incognito
            if r.position=="current",privately==source.shy {
                if inRow {select(source)}
                source.go(to:target)
            }
            else {
                let anchor = inRow ? source : active
                // A fresh private context lets open keep a background action in
                // the background, without selecting a tab outside the row.
                let opener = r.incognito && !source.shy ? Tab(shy: true) : source
                let opened = open(target,foreground:r.active,from:opener,mayWait:false)
                placeFlowDragTab(opened, position: r.position, relativeTo: anchor)
                if r.active {
                    if inPeek {closePeek()}
                    if inLittle, !Store.testing {window?.makeKeyAndOrderFront(nil)}
                }
            }
        }
        announce(L10n.text("flowDrag.done"))
    }
    /// Use displayed positions so a split stays together and ordinary tabs
    /// never try to land among the pinned squares.
    private func placeFlowDragTab(_ opened: Tab, position: String, relativeTo source: Tab?) {
        let shown = displayedTabs
        guard let from = shown.firstIndex(where: { $0 === opened }),
              let first = shown.firstIndex(where: { $0.pin == nil }),
              let last = shown.lastIndex(where: { $0.pin == nil }) else { return }
        let destination: Int
        if position == "first" { destination = first }
        else if position == "last" { destination = last }
        else if let source,
                let anchor = shown.firstIndex(where: { $0.id == (split(for: source)?.left ?? source.id) }) {
            destination = position == "left" ? anchor - (from < anchor ? 1 : 0) : anchor + (from > anchor ? 1 : 0)
        } else { return }
        moveDisplayedTab(opened, to: min(last, max(first, destination)))
    }
    private func saveFlowDragImage(_ url:URL,source:Tab,subdir:String) {
        if subdir.isEmpty {if let web=source.built {downloadImage(at:url,from:web)};return}
        // Capture the source window's folder before cookies or the network
        // return: the user may switch spaces while this image downloads.
        let directory = downloadsFolder.appendingPathComponent(subdir,isDirectory:true)
        source.store.httpCookieStore.getAllCookies { [weak self] cookies in
            Task { @MainActor in
                guard let self else{return}
                do {
                    let configuration=URLSessionConfiguration.ephemeral
                    cookies.forEach{configuration.httpCookieStorage?.setCookie($0)}
                    let session=URLSession(configuration:configuration);defer{session.finishTasksAndInvalidate()}
                    let (data,response)=try await session.data(for:URLRequest(url:url))
                    guard let http=response as? HTTPURLResponse,(200..<300).contains(http.statusCode) else{throw FlowDrag.Invalid()}
                    var name=URL(fileURLWithPath:response.suggestedFilename ?? url.lastPathComponent).lastPathComponent;if name.isEmpty||name=="."||name==".." {name="image"}
                    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
                    var destination=directory.appendingPathComponent(name);var i=1
                    while FileManager.default.fileExists(atPath:destination.path){destination=directory.appendingPathComponent((name as NSString).deletingPathExtension+" (\(i))"+((name as NSString).pathExtension.isEmpty ? "":"."+(name as NSString).pathExtension));i+=1}
                    try data.write(to:destination,options:.withoutOverwriting)
                    self.announce(L10n.text("flowDrag.done"))
                } catch {self.announce(L10n.text("flowDrag.failed"))}
            }
        }
    }
}
