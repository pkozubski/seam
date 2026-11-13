using System.Net;
using System.Text.RegularExpressions;
using Seam.Localization;

/// <summary>Każdy angielski tekst z XAML musi mieć polskie tłumaczenie w słowniku <c>L10n</c>.</summary>
internal static partial class LocalizationChecks
{
    [GeneratedRegex("\\b(?:Text|Content|Header|Title|Subtitle|Watermark|Message|ToolTip\\.Tip|AutomationProperties\\.Name|PlaceholderText)=\"([^\"{][^\"]*)\"")]
    private static partial Regex TextAttribute();

    // Marka, nazwy własne i wzór kodu parowania są takie same w obu językach.
    private static readonly HashSet<string> SameInBothLanguages = ["seam", "System", "PRO", "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX-X", "SEAM-XXXXX-XXXXX-XXXXX-XXXXX"];

    public static void Run()
    {
        var root = FindSeamProject();
        var missing = new List<string>();
        foreach (var file in Directory.EnumerateFiles(root, "*.axaml", SearchOption.AllDirectories))
        {
            if (file.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}")) continue;
            foreach (Match match in TextAttribute().Matches(File.ReadAllText(file)))
            {
                var text = WebUtility.HtmlDecode(match.Groups[1].Value);
                // Glify ikon (Segoe Fluent) i numery kroków nie mają liter do tłumaczenia.
                if (!text.Any(char.IsAsciiLetter) || SameInBothLanguages.Contains(text)) continue;
                if (!L10n.HasPolish(text)) missing.Add($"{Path.GetFileName(file)}: {text}");
            }
        }
        if (missing.Count > 0)
            throw new InvalidOperationException("XAML texts without a Polish translation:\n  " + string.Join("\n  ", missing));
        Console.WriteLine("✓ Localization: every English XAML text has a Polish translation");
    }

    private static string FindSeamProject()
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
        {
            var candidate = Path.Combine(dir.FullName, "windows", "Seam");
            if (File.Exists(Path.Combine(candidate, "Seam.csproj"))) return candidate;
        }
        throw new InvalidOperationException("windows/Seam not found above " + AppContext.BaseDirectory);
    }
}
