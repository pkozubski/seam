using Avalonia.Controls;

namespace BorderlessMouse.Views.Pages;

public partial class ControlPage : UserControl
{
    public ControlPage() : this("control") { }

    public ControlPage(string section)
    {
        InitializeComponent();
        InputSection.IsVisible = section == "control";
        DisplaySection.IsVisible = WindowsSection.IsVisible = section == "windows";
        AudioSection.IsVisible = AudioStatusSection.IsVisible = section == "audio";
        ClipboardSection.IsVisible = section == "clipboard";
        SectionTitle.Text = section switch { "audio" => "Dźwięk", "clipboard" => "Schowek", "windows" => "Okna", _ => "Sterowanie" };
        Localization.L10n.Apply(this);
    }
}
