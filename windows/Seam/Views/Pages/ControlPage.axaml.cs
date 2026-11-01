using Avalonia.Controls;
using Avalonia.Interactivity;
using Seam.Localization;

namespace Seam.Views.Pages;

public partial class ControlPage : UserControl
{
    public ControlPage() : this("control") { }

    public ControlPage(string section)
    {
        InitializeComponent();
        InputSection.IsVisible = section == "control";
        AudioSection.IsVisible = section == "audio";
        ClipboardSection.IsVisible = section == "clipboard";
        (SectionTitle.Text, SectionSubtitle.Text) = section switch
        {
            "audio" => (L10n.T("Audio", pl: "Dźwięk"),
                        L10n.T("The Mac's system audio played on this computer.", pl: "Dźwięk systemowy Maca grany na tym komputerze.")),
            "clipboard" => (L10n.T("Clipboard", pl: "Schowek"),
                            L10n.T("Copy on one computer, paste on the other.", pl: "Kopiuj na jednym komputerze, wklejaj na drugim.")),
            _ => (L10n.T("Keyboard & mouse", pl: "Klawiatura i mysz"),
                  L10n.T("One keyboard and mouse for both computers.", pl: "Jedna klawiatura i mysz dla obu komputerów.")),
        };
        Localization.L10n.Apply(this);
    }

    private void OpenDisplays(object? sender, RoutedEventArgs e)
    {
        if (TopLevel.GetTopLevel(this) is MainWindow window) window.NavigateTo("displays");
    }
}
