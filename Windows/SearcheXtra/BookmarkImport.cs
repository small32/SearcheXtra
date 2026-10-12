using System.Net;
using System.Text.RegularExpressions;

namespace SearcheXtra.Windows;

public static class BookmarkImport
{
    public static bool Move(List<Bookmark> roots, IEnumerable<Guid> ids, Guid? folderId, int? index = null)
    {
        var wanted = ids.ToHashSet();
        var all = Flatten(roots).ToList();
        var folder = folderId == null ? null : all.FirstOrDefault(node => node.Id == folderId && node.Children != null);
        if (folderId != null && folder == null) return false;
        var selected = all.Where(node => wanted.Contains(node.Id)).ToList();
        selected = selected.Where(node => !selected.Any(parent => parent != node && parent.Children != null && Flatten(parent.Children).Contains(node))).ToList();
        if (selected.Count == 0 || selected.Any(node => node == folder || node.Children != null && folder != null && Flatten(node.Children).Contains(folder))) return false;
        List<Bookmark>? Parent(Bookmark node, List<Bookmark> list) => list.Contains(node) ? list : list.Select(item => item.Children == null ? null : Parent(node, item.Children)).FirstOrDefault(list => list != null);
        var target = folder?.Children ?? roots;
        var at = Math.Clamp(index ?? target.Count, 0, target.Count);
        at -= target.Take(at).Count(selected.Contains);
        foreach (var node in selected) Parent(node, roots)!.Remove(node);
        target.InsertRange(at, selected);
        return true;
    }
    public static void SortByName(List<Bookmark> nodes)
    {
        var ordered = nodes.OrderBy(node => node.Title, StringComparer.CurrentCultureIgnoreCase).ToList();
        nodes.Clear();
        nodes.AddRange(ordered);
    }
    // Netscape bookmark exports from Edge/Chrome/Firefox/Safari preserve folder nesting.
    public static List<Bookmark> ParseHtml(string html)
    {
        List<Bookmark> root = [];
        var stack = new Stack<List<Bookmark>>();
        stack.Push(root);
        Bookmark? pending = null;
        foreach (Match token in Regex.Matches(html, @"<H3\b[^>]*>(.*?)</H3>|<A\b([^>]*)>(.*?)</A>|<DL\b[^>]*>|</DL\s*>", RegexOptions.IgnoreCase | RegexOptions.Singleline))
        {
            if (token.Value.StartsWith("<H3", StringComparison.OrdinalIgnoreCase))
            {
                pending = new() { Title = Plain(token.Groups[1].Value), Children = [] };
                stack.Peek().Add(pending);
            }
            else if (token.Value.StartsWith("<A", StringComparison.OrdinalIgnoreCase))
            {
                var href = Regex.Match(token.Groups[2].Value, "HREF\\s*=\\s*[\"']([^\"']+)[\"']", RegexOptions.IgnoreCase);
                var url = WebUtility.HtmlDecode(href.Groups[1].Value);
                if (AddressParser.IsWeb(url)) stack.Peek().Add(new() { Title = Plain(token.Groups[3].Value), Url = url });
            }
            else if (token.Value.StartsWith("</DL", StringComparison.OrdinalIgnoreCase)) { if (stack.Count > 1) stack.Pop(); }
            else if (pending != null) { stack.Push(pending.Children!); pending = null; }
        }
        return root;
    }
    private static string Plain(string html) => WebUtility.HtmlDecode(Regex.Replace(html, "<[^>]+>", "")).Trim();
    public static IEnumerable<Bookmark> Flatten(IEnumerable<Bookmark> bookmarks)
    {
        foreach (var node in bookmarks)
        {
            yield return node;
            if (node.Children != null) foreach (var child in Flatten(node.Children)) yield return child;
        }
    }
}
