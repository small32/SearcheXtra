import SwiftUI
import UniformTypeIdentifiers

struct SuperDragSettingsPage: View {
    @ObservedObject private var settings=SuperDragSettings.shared
    let browser:Browser
    @State private var selected: Int?
    @State private var draft=SuperDragRule(object:"text",direction:"up",action:"copy")
    @State private var status=""
    @State private var exceptions=""
    @State private var translation=""
    @State private var imageService=""
    private func text(_ key:String)->String { L10n.text("superDrag."+key) }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Toggle(text("enabled"),isOn:$settings.config.enabled).toggleStyle(.switch)
            Text(text("instructions")).font(.system(size:12)).foregroundStyle(.secondary)
            Stepper(value:$settings.config.minDistance,in:1...200,step:1) { Text(text("distance")+": "+String(Int(settings.config.minDistance))) }
            Picker(text("directions"),selection:$settings.config.directionMode) { ForEach(SuperDrag.modes,id:\.self) { Text(text($0)).tag($0) } }
            Toggle(text("hints"),isOn:$settings.config.showHints).toggleStyle(.switch)
            Toggle(text("remote"),isOn:$settings.config.allowRemote).toggleStyle(.switch)
            Text(text("privacy")).font(.system(size:12)).foregroundStyle(.secondary)
            Text(text("translationService"));TextField("",text:$translation).onSubmit { var next=settings.config;next.translationTemplate=translation;commit(next) }
            Text(text("imageService"));TextField("",text:$imageService).onSubmit { var next=settings.config;next.imageSearchTemplate=imageService;commit(next) }
            Text(text("exceptions"))
            TextEditor(text:$exceptions).frame(height:85).onChange(of:exceptions) { _,value in
                var next=settings.config
                next.exceptions=Array(Set(value.components(separatedBy:CharacterSet(charactersIn:"\n,;")).map{$0.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()}.filter{!$0.isEmpty})).sorted()
                if (try? next.validate()) != nil { settings.config=next }
            }
            Button(text("exceptSite")) { if let host=browser.active?.address?.host { exceptions += (exceptions.isEmpty ? "":"\n")+host } }
            Text(text("rules")).font(.headline)
            ScrollView {
                VStack(alignment:.leading,spacing:8) {
                    ForEach(Array(settings.config.rules.enumerated()),id:\.offset) { index,rule in
                        Button { selected=index;draft=rule } label: {
                            Text("\(text(rule.object)) · \(text(rule.direction)) · \(text(rule.modifier)) · \(text(rule.region)) → \(text(rule.action))").font(.system(size:12)).frame(maxWidth:.infinity,alignment:.leading)
                        }.buttonStyle(.plain).padding(5).background(selected==index ? Color.primary.opacity(0.08):Color.clear)
                    }
                }
            }.frame(height:170)
            choice("object",$draft.object,SuperDrag.objects)
            choice("direction",$draft.direction,SuperDrag.directions)
            choice("modifier",$draft.modifier,SuperDrag.modifiers)
            choice("region",$draft.region,SuperDrag.regions)
            choice("action",$draft.action,SuperDrag.actions)
            HStack {
                Button(text("newRule")) { selected=nil }
                Button(text("saveRule")) {
                    var next=settings.config
                    if let selected,selected<next.rules.count { next.rules[selected]=draft } else { next.rules.append(draft) }
                    do { try next.validate();settings.config=next;status=text("saved") } catch { status=text("invalid") }
                }
                Button(text("remove")) { if let selected,selected<settings.config.rules.count { settings.config.rules.remove(at:selected);self.selected=nil } }.disabled(selected==nil)
            }
            HStack {
                Button(text("reset")) { settings.config=SuperDragConfig();exceptions=settings.config.exceptions.joined(separator:"\n");selected=nil }
                Button(text("import"),action:importConfig)
                Button(text("export")) { export(try? JSONEncoder().encode(settings.config),name:"super-drag") }
            }
            Button(text("diagnostics")) { export(try? JSONSerialization.data(withJSONObject:settings.diagnostics,options:.prettyPrinted),name:"super-drag-diagnostics") }
            Text(status).font(.system(size:12))
        }.onAppear { refreshFields() }
        .onChange(of:settings.config.translationTemplate) { _,value in translation=value }
        .onChange(of:settings.config.imageSearchTemplate) { _,value in imageService=value }
    }
    private func choice(_ key:String,_ binding:Binding<String>,_ values:[String])->some View {
        Picker(text(key),selection:binding) { ForEach(values,id:\.self) { Text(text($0)).tag($0) } }
    }
    private func commit(_ next:SuperDragConfig) { do {try next.validate();settings.config=next;status=text("saved")} catch {status=text("invalid")} }
    private func refreshFields() { exceptions=settings.config.exceptions.joined(separator:"\n");translation=settings.config.translationTemplate;imageService=settings.config.imageSearchTemplate }
    private func importConfig() {
        let panel=NSOpenPanel();panel.allowedContentTypes=[.json]
        guard panel.runModal() == .OK,let url=panel.url else {return}
        do {var next=try JSONDecoder().decode(SuperDragConfig.self,from:Data(contentsOf:url));next.allowRemote=settings.config.allowRemote;try next.validate();settings.config=next;exceptions=next.exceptions.joined(separator:"\n");selected=nil;status=text("saved")} catch {status=text("invalid")}
    }
    private func export(_ data:Data?,name:String) {
        let panel=NSSavePanel();panel.allowedContentTypes=[.json];panel.nameFieldStringValue=name+".json"
        guard let data,panel.runModal() == .OK,let url=panel.url else {return}
        do {try data.write(to:url,options:.atomic);status=text("saved")} catch {status=text("failed")}
    }
}
