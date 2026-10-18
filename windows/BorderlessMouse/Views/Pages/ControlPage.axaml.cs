using Avalonia.Controls;
using Avalonia.Interactivity;

namespace BorderlessMouse.Views.Pages;

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
            "audio" => ("Dźwięk", "Dźwięk systemowy Maca grany na tym komputerze."),
            "clipboard" => ("Schowek", "Kopiuj na jednym komputerze, wklejaj na drugim."),
            _ => ("Klawiatura i mysz", "Jedna klawiatura i mysz dla obu komputerów."),
        };
        Localization.L10n.Apply(this);
    }

    private void OpenDisplays(object? sender, RoutedEventArgs e)
    {
        if (TopLevel.GetTopLevel(this) is MainWindow window) window.NavigateTo("displays");
    }
}
