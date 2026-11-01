using Avalonia.Controls;
using Avalonia.Interactivity;

namespace Seam.Views.Pages;

/// <summary>Panele okna Ustawień; <see cref="Show"/> zostawia widoczne karty jednej strony.</summary>
public partial class SettingsPage : UserControl
{
    // Adresy w jednym miejscu (jak AppLinks na macOS): po starcie strony zmienią się tylko tutaj.
    private const string ChangelogUrl = "https://github.com/pkozubski/seam/blob/main/CHANGELOG.md";
    private const string IssuesUrl = "https://github.com/pkozubski/seam/issues";
    private const string PrivacyUrl = "https://github.com/pkozubski/seam/blob/main/PRIVACY.md";

    public SettingsPage()
    {
        InitializeComponent();
        Localization.L10n.Apply(this);
        Show("general");
    }

    public void Show(string pane)
    {
        LicenseCard.IsVisible = pane == "license";
        GeneralCard.IsVisible = pane == "general";
        StartupCard.IsVisible = pane == "general";
        LanguageCard.IsVisible = pane == "language";
        UpdatesCard.IsVisible = pane == "updates";
        AdvancedCard.IsVisible = pane == "advanced";
        AboutCard.IsVisible = pane == "about";
    }

    private void OpenChangelog(object? sender, RoutedEventArgs e) => Open(ChangelogUrl);
    private void OpenIssues(object? sender, RoutedEventArgs e) => Open(IssuesUrl);
    private void OpenPrivacy(object? sender, RoutedEventArgs e) => Open(PrivacyUrl);

    private async void Open(string url)
    {
        if (TopLevel.GetTopLevel(this) is { } top) await top.Launcher.LaunchUriAsync(new Uri(url));
    }
}
