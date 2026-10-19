using System.Net;
using System.Text.RegularExpressions;

namespace SearcheXtra.Windows;

public static class BookmarkImport
{
    public static bool Move(List<Bookmark> roots, IEnumerable<Guid> ids, Guid? folderId, int? index = null)
    {
        var wanted = ids.ToHashSet();
        Bookmark? folder = null;
        var invalidFolder = false;
        var selected = new List<Bookmark>();
        var parents = new Dictionary<Bookmark, List<Bookmark>>();
        void Visit(List<Bookmark> siblings, bool selectedAncestor)
        {
            foreach (var node in siblings)
            {
                var picked = wanted.Contains(node.Id);
                if (folder == null && node.Id == folderId && node.Children != null)
                {
                    folder = node;
                    invalidFolder = selectedAncestor || picked;
                }
                if (picked && !selectedAncestor) { selected.Add(node); parents[node] = siblings; }
                if (node.Children != null) Visit(node.Children, selectedAncestor || picked);
            }
        }
        Visit(roots, false);
        if (folderId != null && folder == null) return false;
        if (selected.Count == 0 || invalidFolder) return false;
        var target = folder?.Children ?? roots;
        var selectedSet = selected.ToHashSet();
        var at = Math.Clamp(index ?? target.Count, 0, target.Count);
        at -= target.Take(at).Count(selectedSet.Contains);
        foreach (var parent in parents.Values.Distinct()) parent.RemoveAll(selectedSet.Contains);
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
