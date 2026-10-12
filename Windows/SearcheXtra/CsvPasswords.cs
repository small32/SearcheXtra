using System.Text;

namespace SearcheXtra.Windows;

public static class CsvPasswords
{
    public static List<Login> Parse(string csv)
    {
        var rows = new List<List<string>>(); var row = new List<string>(); var value = new StringBuilder(); var quoted = false;
        for (var i = 0; i < csv.Length; i++)
        {
            var c = csv[i];
            if (c == '"') { if (quoted && i + 1 < csv.Length && csv[i + 1] == '"') { value.Append('"'); i++; } else quoted = !quoted; }
            else if (!quoted && c == ',') { row.Add(value.ToString()); value.Clear(); }
            else if (!quoted && c is '\r' or '\n')
            {
                row.Add(value.ToString()); rows.Add(row); row = []; value.Clear();
                if (c == '\r' && i + 1 < csv.Length && csv[i + 1] == '\n') i++;
            }
            else value.Append(c);
        }
        if (value.Length > 0 || row.Count > 0) { row.Add(value.ToString()); rows.Add(row); }
        if (rows.Count == 0) return [];
        var header = rows[0].Select(s => s.Trim('\uFEFF').ToLowerInvariant()).ToList();
        var origin = header.FindIndex(s => s is "url" or "origin" or "website"); var user = header.FindIndex(s => s is "username" or "user" or "login"); var password = header.FindIndex(s => s == "password");
        if (origin < 0 || user < 0 || password < 0 || quoted) throw new InvalidDataException("Invalid password CSV. Required columns: url, username, password.");
        return rows.Skip(1).Where(r => r.Count > Math.Max(origin, Math.Max(user, password)) && AddressParser.IsWeb(r[origin]) && r[password].Length > 0).Select(r => new Login(new Uri(r[origin]).GetLeftPart(UriPartial.Authority), r[user], r[password])).ToList();
    }
}
