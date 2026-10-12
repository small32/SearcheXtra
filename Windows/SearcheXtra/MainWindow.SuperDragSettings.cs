using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using System.Text.Json;
using Windows.Storage;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace SearcheXtra.Windows;

public sealed partial class MainWindow
{
    private void BuildSuperDragSettings(StackPanel body)
    {
        body.Children.Clear();
        var c=Settings.SuperDrag;
        string Label(string key)=>strings.Key("superDrag."+key);
        var status=new TextBlock { TextWrapping=TextWrapping.Wrap,FontSize=12 };
        void Commit(Action<SuperDragConfig> edit) {
            try { var next=JsonSerializer.Deserialize<SuperDragConfig>(JsonSerializer.Serialize(c,SuperDrag.Json),SuperDrag.Json)!; edit(next); next.Validate(); Settings.SuperDrag=c=next; store.Notify(); ScheduleSave(); foreach (var window in App.Windows) foreach (var view in window.views.Values) { view.ApplySettings(); _=view.UpdateDocumentScriptAsync(); } status.Text=Label("saved"); }
            catch (FormatException) { status.Text=Label("invalid"); }
        }
        void Row(string label,UIElement control) { var row=new Grid { ColumnSpacing=12,Padding=new(0,6,0,6) };row.ColumnDefinitions.Add(new(){Width=new(1,GridUnitType.Star)});row.ColumnDefinitions.Add(new(){Width=GridLength.Auto});row.Children.Add(new TextBlock{Text=Label(label),TextWrapping=TextWrapping.Wrap,VerticalAlignment=VerticalAlignment.Center}); Grid.SetColumn((FrameworkElement)control,1);row.Children.Add(control);body.Children.Add(row); }
        void Toggle(string label,bool value,Action<SuperDragConfig,bool> set) {var box=new ToggleSwitch{IsOn=value,OnContent="",OffContent="",Width=40};box.Toggled+=(_,_)=>Commit(next=>set(next,box.IsOn));Row(label,box);}
        ComboBox Choice(string[] keys,string selected) {return new ComboBox { ItemsSource=keys.Select(Label).ToArray(),SelectedIndex=Array.IndexOf(keys,selected),MinWidth=150,MaxWidth=260 };}
        Toggle("enabled",c.Enabled,(n,v)=>n.Enabled=v);
        body.Children.Add(new TextBlock{Text=Label("instructions"),TextWrapping=TextWrapping.Wrap,Opacity=.65,FontSize=12});
        var distance=new NumberBox{Value=c.MinDistance,Minimum=1,Maximum=200,Width=100};distance.ValueChanged+=(_,e)=>{if(double.IsFinite(e.NewValue))Commit(n=>n.MinDistance=e.NewValue);};Row("distance",distance);
        var mode=Choice(SuperDrag.Modes,c.DirectionMode);mode.SelectionChanged+=(_,_)=>{if(mode.SelectedIndex>=0)Commit(n=>n.DirectionMode=SuperDrag.Modes[mode.SelectedIndex]);};Row("directions",mode);
        Toggle("hints",c.ShowHints,(n,v)=>n.ShowHints=v);
        Toggle("remote",c.AllowRemote,(n,v)=>n.AllowRemote=v);
        body.Children.Add(new TextBlock{Text=Label("privacy"),TextWrapping=TextWrapping.Wrap,Opacity=.65,FontSize=12});
        void Template(string key,string value,Action<SuperDragConfig,string> set) {body.Children.Add(new TextBlock{Text=Label(key)});var box=new TextBox{Text=value};box.LostFocus+=(_,_)=>Commit(n=>set(n,box.Text.Trim()));body.Children.Add(box);}
        Template("translationService",c.TranslationTemplate,(n,v)=>n.TranslationTemplate=v);
        Template("imageService",c.ImageSearchTemplate,(n,v)=>n.ImageSearchTemplate=v);
        var exceptions=new TextBox{Text=string.Join("\n",c.Exceptions),AcceptsReturn=true,Height=90};exceptions.LostFocus+=(_,_)=>Commit(n=>n.Exceptions=exceptions.Text.Split(['\n',',',';'],StringSplitOptions.RemoveEmptyEntries).ToList());Row("exceptions",exceptions);
        var except=QuietButton(Label("exceptSite"));except.Click+=(_,_)=>{if(active!=null&&AddressParser.IsWeb(active.Url)){Commit(n=>n.Exceptions.Add(new Uri(active.Url).Host));exceptions.Text=string.Join("\n",c.Exceptions);}};body.Children.Add(except);
        body.Children.Add(new TextBlock{Text=Label("rules"),FontSize=15});
        var list=new ListView{Height=190,SelectionMode=ListViewSelectionMode.Single};body.Children.Add(list);
        ComboBox objectBox=Choice(SuperDrag.Objects,"text"),direction=Choice(SuperDrag.Directions,"up"),modifier=Choice(SuperDrag.Modifiers,"none"),region=Choice(SuperDrag.Regions,"page"),action=Choice(SuperDrag.Actions,"copy");
        Row("object",objectBox);Row("direction",direction);Row("modifier",modifier);Row("region",region);Row("action",action);
        void Reload() {list.ItemsSource=c.Rules.Select(r=>$"{Label(r.Object)} · {Label(r.Direction)} · {Label(r.Modifier)} · {Label(r.Region)} → {Label(r.Action)}").ToList();}
        list.SelectionChanged+=(_,_)=>{if(list.SelectedIndex is var index && index>=0&&index<c.Rules.Count){var r=c.Rules[index];objectBox.SelectedIndex=Array.IndexOf(SuperDrag.Objects,r.Object);direction.SelectedIndex=Array.IndexOf(SuperDrag.Directions,r.Direction);modifier.SelectedIndex=Array.IndexOf(SuperDrag.Modifiers,r.Modifier);region.SelectedIndex=Array.IndexOf(SuperDrag.Regions,r.Region);action.SelectedIndex=Array.IndexOf(SuperDrag.Actions,r.Action);}};
        var buttons=new StackPanel{Orientation=Orientation.Horizontal,Spacing=8};
        void Button(string key,Action act) {var button=QuietButton(Label(key));button.Click+=(_,_)=>act();buttons.Children.Add(button);}
        Button("newRule",()=>list.SelectedIndex=-1);
        Button("saveRule",()=>{var index=list.SelectedIndex; var rule=new SuperDragRule(SuperDrag.Objects[objectBox.SelectedIndex],SuperDrag.Directions[direction.SelectedIndex],SuperDrag.Modifiers[modifier.SelectedIndex],SuperDrag.Actions[action.SelectedIndex],SuperDrag.Regions[region.SelectedIndex]);Commit(n=>{if(index>=0)n.Rules[index]=rule;else n.Rules.Add(rule);});Reload();});
        Button("remove",()=>{var index=list.SelectedIndex;if(index>=0){Commit(n=>n.Rules.RemoveAt(index));Reload();}});
        body.Children.Add(buttons);Reload();
        var restore=QuietButton(Label("reset"));restore.Click+=(_,_)=>{Settings.SuperDrag=new();store.Notify();ScheduleSave();foreach(var window in App.Windows)foreach(var view in window.views.Values){view.ApplySettings();_=view.UpdateDocumentScriptAsync();}BuildSuperDragSettings(body);};body.Children.Add(restore);
        var import=QuietButton(Label("import"));import.Click+=async(_,_)=>{try{var picker=new FileOpenPicker();picker.FileTypeFilter.Add(".json");InitializeWithWindow.Initialize(picker,WindowNative.GetWindowHandle(this));if(await picker.PickSingleFileAsync() is {} file){var next=JsonSerializer.Deserialize<SuperDragConfig>(await FileIO.ReadTextAsync(file),SuperDrag.Json)??throw new FormatException();next.AllowRemote=c.AllowRemote;next.Validate();Settings.SuperDrag=next;store.Notify();ScheduleSave();foreach(var window in App.Windows)foreach(var view in window.views.Values){view.ApplySettings();_=view.UpdateDocumentScriptAsync();}BuildSuperDragSettings(body);}}catch(Exception e) when(e is JsonException or FormatException or IOException){status.Text=Label("invalid");}};body.Children.Add(import);
        async Task Export(string name,string text) {var picker=new FileSavePicker{SuggestedFileName=name};picker.FileTypeChoices.Add("JSON",new List<string>{".json"});InitializeWithWindow.Initialize(picker,WindowNative.GetWindowHandle(this));if(await picker.PickSaveFileAsync() is {} file)await FileIO.WriteTextAsync(file,text);}
        var export=QuietButton(Label("export"));export.Click+=async(_,_)=>await Export("super-drag",JsonSerializer.Serialize(c,new JsonSerializerOptions(SuperDrag.Json){WriteIndented=true}));body.Children.Add(export);
        var diagnostics=QuietButton(Label("diagnostics"));diagnostics.Click+=async(_,_)=>await Export("super-drag-diagnostics",JsonSerializer.Serialize(superDragDiagnostics));body.Children.Add(diagnostics);
        body.Children.Add(status);
    }
}
