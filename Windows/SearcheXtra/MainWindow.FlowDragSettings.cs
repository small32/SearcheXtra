using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using System.Text.Json;
using Windows.Storage.Pickers;
using WinRT.Interop;
namespace SearcheXtra.Windows;
public sealed partial class MainWindow
{
    private void BuildFlowDragSettings(StackPanel body,Action<string> settingsRender)
    {
        string L(string key)=>strings.Key("flowDrag."+key);
        var c=Settings.FlowDrag;var type="text";var page="overview";
        var status=new TextBlock {FontSize=12,TextWrapping=TextWrapping.Wrap};
        void Refresh(){store.Notify();ScheduleSave();foreach(var window in App.Windows)foreach(var view in window.views.Values){view.ApplySettings();_=view.UpdateDocumentScriptAsync();}}
        void Commit(Action<FlowDragConfig> change){try{var next=JsonSerializer.Deserialize<FlowDragConfig>(JsonSerializer.Serialize(c,FlowDrag.Json),FlowDrag.Json)!;change(next);next.Validate();Settings.FlowDrag=c=next;Refresh();status.Text=L("saved");}catch(FormatException){status.Text=L("invalid");}}
        StackPanel Card(StackPanel parent){var panel=new StackPanel {Spacing=10,Padding=new(12)};parent.Children.Add(new Border {CornerRadius=new(12),BorderBrush=Brush("Hairline"),BorderThickness=new(1),Child=panel});return panel;}
        void Row(StackPanel panel,string label,UIElement control){var row=new Grid {ColumnSpacing=10};row.ColumnDefinitions.Add(new(){Width=new(1,GridUnitType.Star)});row.ColumnDefinitions.Add(new(){Width=GridLength.Auto});row.Children.Add(new TextBlock {Text=label,TextWrapping=TextWrapping.Wrap,VerticalAlignment=VerticalAlignment.Center});Grid.SetColumn((FrameworkElement)control,1);row.Children.Add(control);panel.Children.Add(row);}
        void Toggle(StackPanel panel,string label,bool value,Action<bool> set){var control=new ToggleSwitch {IsOn=value,OnContent="",OffContent="",Width=40};control.Toggled+=(_,_)=>set(control.IsOn);Row(panel,label,control);}
        ComboBox Choice(string[] values,string selected,Func<string,string> label,Action<string> set){var box=new ComboBox {ItemsSource=values.Select(label).ToArray(),SelectedIndex=Array.IndexOf(values,selected),HorizontalAlignment=HorizontalAlignment.Stretch,MinWidth=0,MaxDropDownHeight=450};box.SelectionChanged+=(_,_)=>{if(box.SelectedIndex>=0)set(values[box.SelectedIndex]);};return box;}
        void Field(StackPanel panel,string label,string value,Action<string> set){var input=new TextBox {Header=label,Text=value};input.LostFocus+=(_,_)=>set(input.Text.Trim());panel.Children.Add(input);}
        void Navigate(StackPanel panel,string key,string target){var button=QuietButton(L(key)+"  ›");button.Name="FlowDrag_"+target;button.HorizontalAlignment=HorizontalAlignment.Stretch;button.HorizontalContentAlignment=HorizontalAlignment.Left;button.Click+=(_,_)=>Render(target);panel.Children.Add(button);}
        void Edit(string pattern,Func<FlowDragRule,FlowDragRule> edit){Commit(n=>{var original=n.Rules.FirstOrDefault(r=>r.Object==type&&r.Pattern==pattern)??new(type,pattern,"none");n.Rules.RemoveAll(r=>r.Object==type&&r.Pattern==pattern);n.Rules.Add(edit(original));});}
        void Render(string selected) {
            page=selected;body.Children.Clear();status.Text="";
            var back=QuietButton("←  "+L(page=="overview"?"title":page=="rules"?"configure":"exceptions"));back.Name="FlowDragBack";back.HorizontalAlignment=HorizontalAlignment.Left;back.Click+=(_,_)=>{if(page=="overview")settingsRender("tabs");else Render("overview");};body.Children.Add(back);
            if(page=="overview") {
                var main=Card(body);Toggle(main,L("enabled"),c.Enabled,v=>Commit(n=>n.Enabled=v));
                var hints=new CheckBox {Name="FlowDragHints",Content=L("hints"),IsChecked=c.ShowHints};hints.Checked+=(_,_)=>Commit(n=>n.ShowHints=true);hints.Unchecked+=(_,_)=>Commit(n=>n.ShowHints=false);main.Children.Add(hints);
                main.Children.Add(new TextBlock {Text=L("threshold")});
                var slider=new Slider {Name="FlowDragThreshold",Minimum=1,Maximum=200,StepFrequency=1,Value=c.DistanceThreshold};slider.ValueChanged+=(_,e)=>Commit(n=>n.DistanceThreshold=e.NewValue);main.Children.Add(slider);
                var ends=new Grid();ends.Children.Add(new TextBlock {Text=L("short")});ends.Children.Add(new TextBlock {Text=L("long"),HorizontalAlignment=HorizontalAlignment.Right});main.Children.Add(ends);
                Navigate(main,"configure","rules");Navigate(main,"exceptions","exceptions");
                var extra=new StackPanel {Spacing=10};body.Children.Add(new Expander {Header=L("advanced"),Content=extra,HorizontalAlignment=HorizontalAlignment.Stretch});
                Toggle(extra,L("trail"),c.ShowTrail,v=>Commit(n=>n.ShowTrail=v));Toggle(extra,L("ignoreEditable"),c.IgnoreEditable,v=>Commit(n=>n.IgnoreEditable=v));
                foreach(var name in FlowDrag.Objects){var key=name;Toggle(extra,L("enable."+key),key=="text"?c.EnableText:key=="link"?c.EnableLink:c.EnableImage,v=>Commit(n=>{if(key=="text")n.EnableText=v;else if(key=="link")n.EnableLink=v;else n.EnableImage=v;}));}
                var commands=new StackPanel {Orientation=Orientation.Horizontal,Spacing=6};extra.Children.Add(commands);
                foreach(var (key,operation) in new[]{("reset",(Action)(()=>{Settings.FlowDrag=c=new();Refresh();Render("overview");})),("import",(Action)(async()=>{try{var picker=new FileOpenPicker();picker.FileTypeFilter.Add(".json");InitializeWithWindow.Initialize(picker,WindowNative.GetWindowHandle(this));if(await picker.PickSingleFileAsync() is {} file){var next=FlowDrag.Import(await global::Windows.Storage.FileIO.ReadTextAsync(file));next.Validate();Settings.FlowDrag=c=next;Refresh();Render(page);}}catch(Exception e)when(e is JsonException or FormatException or IOException){status.Text=L("invalid");}})),("export",(Action)(async()=>{var picker=new FileSavePicker {SuggestedFileName="flow-drag"};picker.FileTypeChoices.Add("JSON",new List<string>{".json"});InitializeWithWindow.Initialize(picker,WindowNative.GetWindowHandle(this));if(await picker.PickSaveFileAsync() is {} file)await global::Windows.Storage.FileIO.WriteTextAsync(file,JsonSerializer.Serialize(c,new JsonSerializerOptions(FlowDrag.Json){WriteIndented=true}));}))}){var button=QuietButton(L(key));button.Click+=(_,_)=>operation();commands.Children.Add(button);}
            } else if(page=="exceptions") {
                var card=Card(body);var input=new TextBox {Name="FlowDragExcludedSites",AcceptsReturn=true,Height=140,Text=string.Join("\n",c.ExcludedSites),Header=L("exceptionsHelp")};
                input.LostFocus+=(_,_)=>Commit(n=>n.ExcludedSites=input.Text.Split(['\n',',',';'],StringSplitOptions.RemoveEmptyEntries).ToList());card.Children.Add(input);
                var add=QuietButton(L("excludeCurrent"));add.Click+=(_,_)=>{if(active!=null&&AddressParser.IsWeb(active.Url)){Commit(n=>n.ExcludedSites.Add(new Uri(active.Url).Host));input.Text=string.Join("\n",c.ExcludedSites);}};card.Children.Add(add);
            } else {
                body.Children.Add(Choice(FlowDrag.Objects,type,k=>L("object."+k),v=>{type=v;Render("rules");}));
                var patterns=new[]{"↑","↓","←","→"}.Concat(c.Rules.Where(r=>r.Object==type).Select(r=>r.Pattern)).Distinct().ToArray();
                foreach(var pattern in patterns) {
                    var current=c.Rules.FirstOrDefault(r=>r.Object==type&&r.Pattern==pattern)??new(type,pattern,"none");
                    var suffix=string.Join("_",pattern.Select(p=>p switch{'↑'=>"up",'↓'=>"down",'←'=>"left",'→'=>"right",_=>"any"}));
                    var card=Card(body);var row=new Grid {ColumnSpacing=8};row.ColumnDefinitions.Add(new(){Width=new(1,GridUnitType.Star)});row.ColumnDefinitions.Add(new(){Width=new(1,GridUnitType.Star)});row.ColumnDefinitions.Add(new(){Width=new(Math.Min(96,Math.Max(24,pattern.Length*16)))});card.Children.Add(row);
                    var action=Choice(FlowDrag.Actions(type),current.Action,a=>L("action."+a),v=>{Edit(pattern,r=>r with{Action=v});Render("rules");});action.Name="FlowDragAction_"+suffix;action.Tag=pattern;row.Children.Add(action);
                    var engines=FlowDrag.EnginesFor(type);
                    var engine=Choice(engines,current.Engine,e=>L("engine."+e),v=>{Edit(pattern,r=>r with{Engine=v,Url=v=="custom"&&r.Url.Length==0?FlowDrag.Template("system",Settings.SearchTemplate,"",type=="image").Replace("{0}","%s"):r.Url});Render("rules");});engine.IsEnabled=current.Action is "search" or "imageSearch";engine.Name="FlowDragEngine_"+suffix;Grid.SetColumn(engine,1);row.Children.Add(engine);
                    var arrow=new TextBlock {Text=pattern,FontSize=pattern.Length>1?14:20,TextTrimming=TextTrimming.CharacterEllipsis,VerticalAlignment=VerticalAlignment.Center};ToolTipService.SetToolTip(arrow,pattern);Grid.SetColumn(arrow,2);row.Children.Add(arrow);
                    var options=new StackPanel {Spacing=8};card.Children.Add(new Expander {Header=L("actionOptions"),Content=options,HorizontalAlignment=HorizontalAlignment.Stretch});
                    if(current.Action is "search" or "openTab" or "openImage" or "openLink" or "imageSearch") {
                        Toggle(options,L("background"),!current.Active,v=>Edit(pattern,r=>r with{Active=!v}));
                        Row(options,L("position"),Choice(FlowDrag.Positions,current.Position,k=>L("position."+k),v=>Edit(pattern,r=>r with{Position=v})));
                        Toggle(options,L("private"),current.Incognito,v=>Edit(pattern,r=>r with{Incognito=v}));
                        if(current.Action=="search")Toggle(options,L("autoDetectUrl"),current.AutoDetectUrl,v=>Edit(pattern,r=>r with{AutoDetectUrl=v}));
                        if(type=="image"&&current.Action=="openImage")Toggle(options,L("preferLink"),current.PreferLink,v=>Edit(pattern,r=>r with{PreferLink=v}));
                        if(current.Engine=="custom")Field(options,L("customUrl"),current.Url,v=>Edit(pattern,r=>r with{Url=v}));
                    }
                    if(current.Action=="copyLinkAndText")Toggle(options,L("markdown"),current.AsMarkdown,v=>Edit(pattern,r=>r with{AsMarkdown=v}));
                    if(current.Action=="saveImage")Field(options,L("subdir"),current.Subdir,v=>Edit(pattern,r=>r with{Subdir=v}));
                    if(current.Action=="bookmarkLink"){var folders=new[]{new Bookmark{Title=L("rootFolder")}}.Concat(BookmarkImport.Flatten(store.Bookmarks).Where(b=>b.Children!=null)).ToArray();var choices=new ComboBox {ItemsSource=folders.Select(f=>f.Title).ToArray(),SelectedIndex=Math.Max(0,Array.FindIndex(folders,f=>f.Id.ToString()==current.FolderId))};choices.SelectionChanged+=(_,_)=>{if(choices.SelectedIndex>=0)Edit(pattern,r=>r with{FolderId=choices.SelectedIndex==0?"":folders[choices.SelectedIndex].Id.ToString()});};Row(options,L("folder"),choices);}
                    var remove=QuietButton(L("remove"));remove.Click+=(_,_)=>{Commit(n=>n.Rules.RemoveAll(r=>r.Object==type&&r.Pattern==pattern));Render("rules");};options.Children.Add(remove);
                }
                var addRow=new StackPanel {Spacing=8};body.Children.Add(addRow);var custom=new TextBox {Name="FlowDragNewPattern",Header=L("patternHelp"),PlaceholderText="↑→ / *"};
                addRow.Children.Add(custom);var add=QuietButton(L("add"));add.Click+=(_,_)=>{var pattern=custom.Text.Trim();if(!FlowDrag.ValidPattern(pattern)){status.Text=L("invalid");return;}if(!c.Rules.Any(r=>r.Object==type&&r.Pattern==pattern))Commit(n=>n.Rules.Add(new(type,pattern,"none")));Render("rules");};addRow.Children.Add(add);
            }
            body.Children.Add(status);
        }
        Render("overview");
    }
}
