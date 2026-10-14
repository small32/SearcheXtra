using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Markup;
using Microsoft.UI.Xaml.Shapes;

namespace SearcheXtra.Windows;

public sealed partial class MainWindow
{
    private UIElement Glyph(string name)
    {
        var data = name switch
        {
            "general" => "M2,3H14V13H2Z M2,6H14 M4,4.5H4.1 M6,4.5H6.1",
            "tabs" => "M2,3H14V13H2Z M6,3V13 M10,3V13",
            "bookmarks" => "M4,2H12V14L8,11L4,14Z",
            "folder" => "M1,4V13Q1,14 2,14H14Q15,14 15,13V5Q15,4 14,4H7L5,2H2Q1,2 1,3Z",
            "shortcuts" => "M1.5,4H14.5V12H1.5Z M4,6H4.1 M7,6H7.1 M10,6H10.1 M12,6H12.1 M4,8H4.1 M7,8H7.1 M10,8H10.1 M4,10H12",
            "extensions" => "M2,2H6C4.5,-1 10,-1 8.5,2H13V6C16,4.5 16,10 13,8.5V13H9C10.5,16 5,16 6.5,13H2V9C-1,10.5 -1,5 2,6.5Z",
            "passwords" => "M7,6.5A3,3 0 1 0 7,6.6 M6,9L12,15 M9,12L11,10 M11,14L13,12",
            "downloads" => "M14.5,8A6.5,6.5 0 1 0 1.5,8A6.5,6.5 0 1 0 14.5,8 M8,4V11 M5,8L8,11L11,8",
            "privacy" => "M4,9V5Q4,3 5.5,5V8 M5.5,8V2Q5.5,0 7,2V8 M7,7V1Q7,-1 8.5,1V8 M8.5,7V2Q8.5,0 10,2V8 M10,7V4Q10,2 11.5,4V10Q11.5,15 7,15Q5,15 3,11L1,8Q1,6 2.5,7L4,9",
            "about" => "M14.5,8A6.5,6.5 0 1 0 1.5,8A6.5,6.5 0 1 0 14.5,8 M8,7V12 M8,4.5V4.6",
            "back" => "M10,3L5,8L10,13", "forward" => "M6,3L11,8L6,13",
            "reload" => "M12,4A5.5,5.5 0 1 0 13.5,8 M12,1V5H8",
            "home" => "M1,7L8,1L15,7 M3,6V14H13V6 M6,14V9H10V14",
            "reopen" => "M2,6H7 M2,6V1 M2,6A6,6 0 1 1 2.5,11",
            "sliders" => "M1,4H5 M9,4H15 M5,2V6 M1,8H9 M13,8H15 M9,6V10 M1,12H3 M7,12H15 M3,10V14",
            _ => "M3,8H13 M8,3V13"
        };
        var path = (Microsoft.UI.Xaml.Shapes.Path)XamlReader.Load("<Path xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\" Data=\"" + data + "\"/>");
        path.Stroke = Brush("Ink"); path.StrokeThickness = 1.15; path.StrokeLineJoin = Microsoft.UI.Xaml.Media.PenLineJoin.Round; path.StrokeStartLineCap = path.StrokeEndLineCap = Microsoft.UI.Xaml.Media.PenLineCap.Round;
        var canvas = new Canvas { Width = 16, Height = 16 }; canvas.Children.Add(path); return canvas;
    }
    private void SetupGlyphs()
    {
        BackButton.Content = Glyph("back"); ForwardButton.Content = Glyph("forward");
        ReloadButton.Content = Glyph("reload"); HomeButton.Content = Glyph("home"); ReopenButton.Content = Glyph("reopen");
        ToolTipService.SetToolTip(HomeButton, T("Home", "主页"));
        ToolTipService.SetToolTip(ReopenButton, T("Reopen last closed tab (Ctrl+Shift+T) · Right-click for history", "恢复上一个关闭的标签页（Ctrl+Shift+T）· 右键查看历史记录"));
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(HomeButton, T("Home", "主页"));
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(ReopenButton, T("Reopen last closed tab", "恢复上一个关闭的标签页")); SettingsButton.Content = Glyph("sliders"); TopSettings.Content = Glyph("sliders"); ExtensionsButton.Content = Glyph("extensions");
    }
}
