import AppKit
import SwiftUI
import WebKit
import UniformTypeIdentifiers

struct SuperDragRule: Codable, Equatable, Identifiable {
    var object: String
    var direction: String
    var modifier = "none"
    var action: String
    var region = "page"
    var id: String { "\(object)|\(direction)|\(modifier)|\(region)" }
    enum CodingKeys:String,CodingKey { case object,direction,modifier,action,region }
    init(object:String,direction:String,modifier:String="none",action:String,region:String="page") { self.object=object;self.direction=direction;self.modifier=modifier;self.action=action;self.region=region }
    init(from decoder:Decoder) throws { let c=try decoder.container(keyedBy:CodingKeys.self);object=try c.decode(String.self,forKey:.object);direction=try c.decode(String.self,forKey:.direction);action=try c.decode(String.self,forKey:.action);modifier=try c.decodeIfPresent(String.self,forKey:.modifier) ?? "none";region=try c.decodeIfPresent(String.self,forKey:.region) ?? "page" }
}
struct SuperDragConfig: Codable, Equatable {
    var version = 1
    var enabled = true
    var minDistance: Double = 10
    var directionMode = "8-way"
    var showHints = true
    var allowRemote = false
    var translationTemplate = "https://translate.google.com/?sl=auto&tl=zh-CN&text=%s&op=translate"
    var imageSearchTemplate = "https://lens.google.com/uploadbyurl?url=%s"
    var exceptions = ["maps.google.com","docs.google.com","drive.google.com","figma.com","canva.com","vscode.dev","onedrive.live.com","maps.baidu.com"]
    var rules = defaults
    static var defaults: [SuperDragRule] {
        let actions = ["text":["search","copy","translate","siteSearch"],"link":["openForegroundTab","openBackgroundTab","copy","download"],"image":["openForegroundTab","saveImage","copy","imageSearch"]]
        return ["text","link","image"].flatMap { object in zip(["up","down","left","right"],actions[object]!).map { SuperDragRule(object: object,direction: $0.0,action: $0.1) } }
    }
    // Missing fields from older exported files retain the current defaults.
    enum CodingKeys: String, CodingKey { case version,enabled,minDistance,directionMode,showHints,allowRemote,translationTemplate,imageSearchTemplate,exceptions,rules }
    init() {}
    init(from decoder: Decoder) throws {
        self.init(); let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self,forKey: .version) ?? version
        enabled = try c.decodeIfPresent(Bool.self,forKey: .enabled) ?? enabled
        minDistance = try c.decodeIfPresent(Double.self,forKey: .minDistance) ?? minDistance
        directionMode = try c.decodeIfPresent(String.self,forKey: .directionMode) ?? directionMode
        showHints = try c.decodeIfPresent(Bool.self,forKey: .showHints) ?? showHints
        allowRemote = try c.decodeIfPresent(Bool.self,forKey: .allowRemote) ?? allowRemote
        translationTemplate = try c.decodeIfPresent(String.self,forKey: .translationTemplate) ?? translationTemplate
        imageSearchTemplate = try c.decodeIfPresent(String.self,forKey: .imageSearchTemplate) ?? imageSearchTemplate
        exceptions = try c.decodeIfPresent([String].self,forKey: .exceptions) ?? exceptions
        rules = try c.decodeIfPresent([SuperDragRule].self,forKey: .rules) ?? rules
    }
    func validate() throws {
        guard version == 1, minDistance.isFinite, (1...200).contains(minDistance), SuperDrag.modes.contains(directionMode), rules.count <= 200, exceptions.count <= 200,
              Set(rules.map(\.id)).count == rules.count,
              [translationTemplate,imageSearchTemplate].allSatisfy({ $0.contains("%s") && SuperDrag.isWeb($0.replacingOccurrences(of:"%s",with:"test")) }),
              rules.allSatisfy({ SuperDrag.objects.contains($0.object) && SuperDrag.directions.contains($0.direction) && SuperDrag.modifiers.contains($0.modifier) && SuperDrag.actions.contains($0.action) && SuperDrag.regions.contains($0.region) }),
              exceptions.allSatisfy({ !$0.isEmpty && !$0.contains("/") && !$0.contains(" ") && URL(string:"https://"+$0)?.host != nil }) else { throw SuperDrag.Invalid() }
    }
}
struct SuperDragRequest: Codable {
    var phase: String
    var object: String
    var value: String
    var dx: Double
    var dy: Double
    var direction: String
    var modifier: String
    var region: String
    var screenX: Double
    var screenY: Double
}
enum SuperDrag {
    struct Invalid: Error {}
    static let objects = ["text","link","image","element"], directions = ["up","down","left","right","upLeft","upRight","downLeft","downRight"], modes = ["4-way","8-way"], regions = ["page","address","tabs","bookmarks","search"]
    static let modifiers = ["none","ctrl","alt","shift","meta","ctrl+alt","ctrl+shift","alt+shift","shift+meta","alt+meta","ctrl+meta","ctrl+alt+shift","alt+shift+meta","ctrl+shift+meta","ctrl+alt+meta","ctrl+alt+shift+meta"]
    static let actions = ["none","search","siteSearch","copy","translate","openForegroundTab","openBackgroundTab","download","saveImage","imageSearch","bookmark"]
    static func isWeb(_ value: String) -> Bool { guard let u = URL(string:value), let host = u.host, !host.isEmpty else { return false }; return ["http","https"].contains(u.scheme?.lowercased() ?? "") }
    static func enabled(_ config: SuperDragConfig, on page: URL?) -> Bool {
        guard config.enabled, let page, isWeb(page.absoluteString), let host = page.host?.lowercased(), !["chromewebstore.google.com","microsoftedge.microsoft.com"].contains(host) else { return false }
        return !config.exceptions.contains { host == $0.lowercased() || host.hasSuffix("."+$0.lowercased()) }
    }
    static func direction(_ dx: Double,_ dy: Double,mode: String) -> String {
        if mode == "4-way" { return abs(dx) > abs(dy) ? (dx > 0 ? "right":"left") : (dy > 0 ? "down":"up") }
        return ["right","downRight","down","downLeft","left","upLeft","up","upRight"][(Int(floor(atan2(dy,dx)/(.pi/4)+0.5))+8)%8]
    }
    static func resolve(_ config: SuperDragConfig,_ p: SuperDragRequest,page: URL?) -> SuperDragRule? {
        guard enabled(config,on:page),p.dx.isFinite,p.dy.isFinite,hypot(p.dx,p.dy)>=config.minDistance,!p.value.isEmpty,p.value.utf16.count<=32768,objects.contains(p.object),regions.contains(p.region),modifiers.contains(p.modifier), !["link","image"].contains(p.object) || isWeb(p.value) else { return nil }
        let d=direction(p.dx,p.dy,mode:config.directionMode)
        let exact=config.rules.first { $0.object==p.object && $0.direction==d && $0.modifier==p.modifier && $0.region==p.region }
        let fallback=config.rules.first { $0.object==p.object && $0.direction==direction(p.dx,p.dy,mode:"4-way") && $0.modifier==p.modifier && $0.region==p.region }
        let rule=exact ?? (d.contains(where: \.isUppercase) ? fallback:nil)
        return rule?.action == "none" ? nil:rule
    }
}
@MainActor final class SuperDragSettings: ObservableObject {
    static let shared = SuperDragSettings()
    @Published var config: SuperDragConfig { didSet {
        guard (try? config.validate()) != nil else { config=oldValue;return }
        if let data=try? JSONEncoder().encode(config) { Store.settings.set(data,forKey:"superDrag.config") }
    } }
    private(set) var diagnostics: [[String:String]]=[]
    init() {
        if let data=Store.settings.data(forKey:"superDrag.config"),let decoded=try? JSONDecoder().decode(SuperDragConfig.self,from:data),(try? decoded.validate()) != nil { config=decoded } else { config=SuperDragConfig() }
    }
    func record(_ action:String,success:Bool) { diagnostics.append(["time":ISO8601DateFormatter().string(from:Date()),"action":action,"success":String(success)]);if diagnostics.count>200 { diagnostics.removeFirst() } }
    var options: String {
        let labels=Dictionary(uniqueKeysWithValues:(SuperDrag.actions+SuperDrag.directions).map { ($0,L10n.text("superDrag."+$0)) })
        let value:[String:Any] = ["config":(try? JSONSerialization.jsonObject(with:JSONEncoder().encode(config))) ?? [:],"labels":labels]
        return String(data:try! JSONSerialization.data(withJSONObject:value),encoding:.utf8)!
    }
    static let source: String = (try? String(contentsOf:Bundle.module.url(forResource:"SuperDrag",withExtension:"js")!,encoding:.utf8)) ?? ""
    var script: String { SuperDragSettings.source+";sxInstallSuperDrag("+options+",p=>window.webkit.messageHandlers.officeSuperDrag.postMessage(p));" }
}
@MainActor final class SuperDragRelay: NSObject, WKScriptMessageHandler {
    static let name="officeSuperDrag"
    weak var tab: Tab?
    var pending: SuperDragRequest?
    private var started=Date.distantPast
    func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage) {
        guard message.frameInfo.isMainFrame,let tab,let web=tab.built,message.webView === web,
              let body=message.body as? [String:Any],let phase=body["phase"] as? String else { return }
        if phase=="cancel" { pending=nil;return }
        guard let data=try? JSONSerialization.data(withJSONObject:body),let request=try? JSONDecoder().decode(SuperDragRequest.self,from:data) else { return }
        if phase=="start" { if SuperDrag.enabled(SuperDragSettings.shared.config,on:tab.address),request.value.utf16.count<=32768 { pending=request;started=Date() };return }
        guard phase=="finish",let pending,pending.value==request.value,pending.object==request.object,Date().timeIntervalSince(started)<120 else { return }
        self.pending=nil; tab.onSuperDrag?(tab,request)
    }
    func take(_ region:String) -> SuperDragRequest? {
        guard var request=pending,Date().timeIntervalSince(started)<120,let screen=NSScreen.screens.first else { return nil }
        pending=nil
        let mouse=NSEvent.mouseLocation
        request.phase="finish";request.region=region;request.dx=mouse.x-request.screenX;request.dy=(screen.frame.maxY-mouse.y)-request.screenY
        let flags=NSEvent.modifierFlags
        let modifiers=[("ctrl",NSEvent.ModifierFlags.control),("alt",.option),("shift",.shift),("meta",.command)].filter{flags.contains($0.1)}.map(\.0)
        request.modifier=modifiers.isEmpty ? "none":modifiers.joined(separator:"+")
        if region=="address" && request.object=="text",let tab {
            var search=request;search.region="search"
            if SuperDrag.resolve(SuperDragSettings.shared.config,search,page:tab.address) != nil { request=search }
        }
        return request
    }
}
@MainActor extension Browser {
    func performSuperDrag(_ tab:Tab,_ request:SuperDragRequest) {
        guard let rule=SuperDrag.resolve(SuperDragSettings.shared.config,request,page:tab.address) else { return }
        let settings=SuperDragSettings.shared
        let remote=["search","siteSearch","translate","imageSearch"].contains(rule.action)
        if remote && !settings.config.allowRemote {
            let service=rule.action=="translate" ? settings.config.translationTemplate:rule.action=="imageSearch" ? settings.config.imageSearchTemplate:prefs.engine.template(custom:prefs.customEngine)
            let host=URL(string:service.replacingOccurrences(of:"%s",with:"x").replacingOccurrences(of:"{0}",with:"x"))?.host ?? ""
            let alert=NSAlert();alert.messageText=L10n.text("superDrag.title");alert.informativeText=L10n.text("superDrag.consent")+"\n"+host;alert.addButton(withTitle:L10n.text("superDrag.allow"));alert.addButton(withTitle:L10n.text("superDrag.cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return };settings.config.allowRemote=true
        }
        func finish(_ ok:Bool) { settings.record(rule.action,success:ok);let text=L10n.text(ok ? "superDrag.done":"superDrag.failed");announce(text);if settings.config.showHints,let web=tab.built,let data=try? JSONEncoder().encode(text),let encoded=String(data:data,encoding:.utf8) { web.evaluateJavaScript("window.__sxSuperDrag?.feedback("+encoded+")",in:nil,in:Web.world) { _ in } } }
        let value=request.value
        switch rule.action {
        case "copy": NSPasteboard.general.clearContents();NSPasteboard.general.setString(value,forType:.string);finish(true)
        case "search","siteSearch": guard let url=searchURL(for:rule.action=="siteSearch" ? "site:"+(tab.address?.host ?? "")+" "+value:value) else { finish(false);return };self.open(url,foreground:true,from:tab);finish(true)
        case "translate","imageSearch": let template=rule.action=="translate" ? settings.config.translationTemplate:settings.config.imageSearchTemplate;let escaped=value.addingPercentEncoding(withAllowedCharacters:.alphanumerics) ?? "";guard rule.action != "imageSearch" || request.object=="image",let url=URL(string:template.replacingOccurrences(of:"%s",with:escaped)),SuperDrag.isWeb(url.absoluteString) else { finish(false);return };self.open(url,foreground:true,from:tab);finish(true)
        case "openForegroundTab","openBackgroundTab": guard SuperDrag.isWeb(value),let url=URL(string:value) else { finish(false);return };self.open(url,foreground:rule.action=="openForegroundTab",from:tab,mayWait:true);finish(true)
        case "download","saveImage": guard SuperDrag.isWeb(value),let url=URL(string:value),let web=tab.built else { finish(false);return };web.startDownload(using:URLRequest(url:url)) { [weak self] download in self?.keep(download,from:web);finish(true) }
        case "bookmark": guard SuperDrag.isWeb(value) else { finish(false);return };_ = bookmarks.insert(Bookmark(title:value,url:value),into:nil);finish(true)
        default: break
        }
    }
}
struct SuperDragDropZone: ViewModifier {
    let browser:Browser
    let region:String
    func body(content:Content) -> some View {
        content.onDrop(of:[UTType.url,UTType.text],isTargeted:nil) { _ in
            guard let tab=browser.active,let pending=tab.superDragRelay.pending else { return false }
            guard SuperDrag.enabled(SuperDragSettings.shared.config,on:tab.address),SuperDragSettings.shared.config.rules.contains(where:{$0.object==pending.object && ($0.region==region || (region=="address" && pending.object=="text" && $0.region=="search"))}) else { return false }
            guard let request=tab.superDragRelay.take(region),SuperDrag.resolve(SuperDragSettings.shared.config,request,page:tab.address) != nil else { return false }
            DispatchQueue.main.async { browser.performSuperDrag(tab,request) };return true
        }
    }
}

@MainActor extension PageView {
    func addSuperDragMenu(_ menu:NSMenu) {
        guard let url,SuperDrag.isWeb(url.absoluteString) else {return}
        let settings=SuperDragSettings.shared
        let root=NSMenuItem(title:L10n.text("superDrag.title"),action:nil,keyEquivalent:"")
        let sub=NSMenu();root.submenu=sub
        let toggle=NSMenuItem(title:L10n.text("superDrag.enabled"),action:#selector(toggleSuperDrag),keyEquivalent:"");toggle.target=self;toggle.state=settings.config.enabled ? .on:.off;sub.addItem(toggle)
        let exclude=NSMenuItem(title:L10n.text("superDrag.exceptSite"),action:#selector(excludeSuperDragSite),keyEquivalent:"");exclude.target=self;exclude.isEnabled=url.host != nil;sub.addItem(exclude)
        let open=NSMenuItem(title:L10n.text("superDrag.settings"),action:#selector(openSuperDragSettings),keyEquivalent:"");open.target=self;sub.addItem(open)
        let rules=NSMenuItem(title:L10n.text("superDrag.rules"),action:nil,keyEquivalent:"");let list=NSMenu();rules.submenu=list
        for rule in settings.config.rules {let item=NSMenuItem(title:L10n.text("superDrag."+rule.object)+" · "+L10n.text("superDrag."+rule.direction)+" → "+L10n.text("superDrag."+rule.action),action:nil,keyEquivalent:"");item.isEnabled=false;list.addItem(item)}
        sub.addItem(rules);menu.addItem(root)
    }
    @objc private func toggleSuperDrag() { SuperDragSettings.shared.config.enabled.toggle() }
    @objc private func excludeSuperDragSite() {if let host=url?.host,!SuperDragSettings.shared.config.exceptions.contains(host){SuperDragSettings.shared.config.exceptions.append(host)}}
    @objc private func openSuperDragSettings() { onSuperDragSettings?() }
}
