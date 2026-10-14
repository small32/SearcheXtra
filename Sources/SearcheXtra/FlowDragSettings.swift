import SwiftUI
import UniformTypeIdentifiers
struct FlowDragSettingsPage:View {
    @ObservedObject private var settings=FlowDragSettings.shared
    let browser:Browser
    @State private var page = "overview"
    @State private var object = "text"
    @State private var newPattern = ""
    @State private var exceptions = ""
    @State private var status = ""
    @State private var customURLs:[String:String]=[:]
    @FocusState private var focusedURL:String?
    private func l(_ key:String)->String {L10n.text("flowDrag."+key)}
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            if page != "overview" {Button("← "+l(page=="rules" ? "configure":"exceptions")){page="overview"}.buttonStyle(.plain)}
            if page=="overview" {
                VStack(alignment:.leading,spacing:14) {
                    Toggle(l("enabled"),isOn:$settings.config.enabled).toggleStyle(.switch)
                    Toggle(l("hints"),isOn:$settings.config.showHints).toggleStyle(.checkbox)
                    Text(l("threshold"))
                    Slider(value:$settings.config.distanceThreshold,in:1...200,step:1)
                    HStack {Text(l("short"));Spacer();Text(l("long"))}.font(.caption)
                    Divider()
                    entry("configure","rules")
                    Divider()
                    entry("exceptions","exceptions")
                }.padding(14).background(Palette.wash,in:RoundedRectangle(cornerRadius:12))
                DisclosureGroup(l("advanced")) {
                    VStack(alignment:.leading,spacing:10) {
                        Toggle(l("trail"),isOn:$settings.config.showTrail)
                        Toggle(l("ignoreEditable"),isOn:$settings.config.ignoreEditable)
                        Toggle(l("enable.text"),isOn:$settings.config.enableText)
                        Toggle(l("enable.link"),isOn:$settings.config.enableLink)
                        Toggle(l("enable.image"),isOn:$settings.config.enableImage)
                        HStack {
                            Button(l("reset")){settings.config=FlowDragConfig()}
                            Button(l("import"),action:importConfig)
                            Button(l("export"),action:exportConfig)
                        }
                    }
                }
            } else if page=="exceptions" {
                Text(l("exceptionsHelp"))
                TextEditor(text:$exceptions).frame(height:140)
                    .onChange(of:exceptions){_,value in var next=settings.config;next.excludedSites=Array(Set(value.components(separatedBy:CharacterSet(charactersIn:"\n,;")).map{$0.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()}.filter{!$0.isEmpty})).sorted();commit(next)}
                Button(l("excludeCurrent")){if let host=browser.active?.address?.host {exceptions += (exceptions.isEmpty ? "":"\n")+host}}
            } else {
                Picker(l("object"),selection:$object){ForEach(FlowDrag.objects,id:\.self){Text(l("object."+$0)).tag($0)}}
                ForEach(patterns,id:\.self){ruleRow($0)}
                TextField(l("patternHelp"),text:$newPattern)
                Button(l("add")) {
                    guard FlowDrag.validPattern(newPattern) else{status=l("invalid");return}
                    if current(newPattern)==nil {var next=settings.config;next.rules.append(.init(object:object,pattern:newPattern,action:"none"));commit(next)}
                    newPattern=""
                }
            }
            Text(status).font(.caption)
        }.onAppear{exceptions=settings.config.excludedSites.joined(separator:"\n")}
    }
    private func entry(_ title:String,_ destination:String)->some View {Button{page=destination;if destination=="exceptions"{exceptions=settings.config.excludedSites.joined(separator:"\n")}}label:{HStack{Text(l(title));Spacer();Image(systemName:"chevron.right")}}.buttonStyle(.plain)}
    private var patterns:[String] {["↑","↓","←","→"]+settings.config.rules.filter{$0.object==object && !["↑","↓","←","→"].contains($0.pattern)}.map(\.pattern)}
    private func current(_ pattern:String)->FlowDragRule? {settings.config.rules.first{$0.object==object&&$0.pattern==pattern}}
    private func edit(_ pattern:String,_ change:(inout FlowDragRule)->Void) {
        var next=settings.config,varRule=current(pattern) ?? FlowDragRule(object:object,pattern:pattern,action:"none")
        change(&varRule);next.rules.removeAll{$0.id==varRule.id};next.rules.append(varRule);commit(next)
    }
    private func binding<T>(_ pattern:String,_ key:WritableKeyPath<FlowDragRule,T>)->Binding<T> {Binding(get:{(current(pattern) ?? FlowDragRule(object:object,pattern:pattern,action:"none"))[keyPath:key]},set:{value in edit(pattern){$0[keyPath:key]=value}})}
    private func ruleRow(_ pattern:String)->some View {
        let rule=current(pattern) ?? FlowDragRule(object:object,pattern:pattern,action:"none")
        let engines=FlowDrag.enginesFor(object)
        return VStack(alignment:.leading,spacing:10) {
            HStack(spacing:8) {
                Picker(l("actionOptions"),selection:binding(pattern,\.action)){ForEach(FlowDrag.actions(object),id:\.self){Text(l("action."+$0)).tag($0)}}.labelsHidden()
                Picker(l("engine.system"),selection:Binding(get:{current(pattern)?.engine ?? "system"},set:{engine in edit(pattern){r in r.engine=engine;if engine=="custom"&&r.url.isEmpty {r.url=FlowDrag.template("system",current:browser.prefs.engine.template(custom:browser.prefs.customEngine),custom:"",image:object=="image")}}})) {ForEach(engines,id:\.self){Text(l("engine."+$0)).tag($0)}}.labelsHidden().frame(width:140).disabled(!["search","imageSearch"].contains(rule.action))
                Text(pattern).font(.system(size:pattern.count>1 ? 14:20)).lineLimit(1).frame(width:CGFloat(min(96,max(26,pattern.count*16)))).help(pattern)
            }
            DisclosureGroup(l("actionOptions")) {
                if ["search","openTab","openImage","openLink","imageSearch"].contains(rule.action) {
                    Toggle(l("background"),isOn:Binding(get:{!(current(pattern)?.active ?? true)},set:{value in edit(pattern){$0.active = !value}}))
                    Picker(l("position"),selection:binding(pattern,\.position)){ForEach(FlowDrag.positions,id:\.self){Text(l("position."+$0)).tag($0)}}
                    Toggle(l("private"),isOn:binding(pattern,\.incognito))
                    if rule.action=="search" {Toggle(l("autoDetectUrl"),isOn:binding(pattern,\.autoDetectUrl))}
                    if rule.action=="openImage" {Toggle(l("preferLink"),isOn:binding(pattern,\.preferLink))}
                    if rule.engine=="custom" {
                        TextField(l("customUrl"),text:Binding(get:{customURLs[rule.id] ?? rule.url},set:{customURLs[rule.id]=$0}))
                            .focused($focusedURL,equals:rule.id)
                            .onSubmit {saveCustomURL(rule.id)}
                            .onChange(of:focusedURL){old,new in if old==rule.id,new != rule.id {saveCustomURL(rule.id)}}
                    }
                }
                if rule.action=="copyLinkAndText" {Toggle(l("markdown"),isOn:binding(pattern,\.asMarkdown))}
                if rule.action=="saveImage" {TextField(l("subdir"),text:binding(pattern,\.subdir))}
                if rule.action=="bookmarkLink" {
                    Picker(l("folder"),selection:binding(pattern,\.folderId)){
                        Text(l("rootFolder")).tag("")
                        ForEach(Bookmarks.folders(browser.bookmarks.roots),id:\.node.id){folder in Text(String(repeating:"  ",count:folder.depth)+folder.node.title).tag(folder.node.id.uuidString)}
                    }
                }
                Button(l("remove")){var next=settings.config;next.rules.removeAll{$0.object==object&&$0.pattern==pattern};commit(next)}
            }
        }.padding(10).background(Palette.wash,in:RoundedRectangle(cornerRadius:10))
    }
    private func commit(_ next:FlowDragConfig) {do{try next.validate();settings.config=next;status=l("saved")}catch{status=l("invalid")}}
    private func saveCustomURL(_ id:String) {guard let value=customURLs[id],let index=settings.config.rules.firstIndex(where:{$0.id==id}) else{return};var next=settings.config;next.rules[index].url=value.trimmingCharacters(in:.whitespacesAndNewlines);commit(next)}
    private func importConfig() {
        let panel=NSOpenPanel();panel.allowedContentTypes=[.json]
        guard panel.runModal() == .OK,let url=panel.url else{return}
        do{commit(try FlowDrag.importConfig(Data(contentsOf:url)))}catch{status=l("invalid")}
    }
    private func exportConfig() {
        let panel=NSSavePanel();panel.allowedContentTypes=[.json];panel.nameFieldStringValue="flow-drag.json"
        guard panel.runModal() == .OK,let url=panel.url else{return}
        do{try JSONEncoder().encode(settings.config).write(to:url,options:.atomic);status=l("saved")}catch{status=l("failed")}
    }
}
