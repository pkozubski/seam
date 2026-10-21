using Avalonia.Controls;

namespace Seam.Views.Pages;

public partial class SettingsPage : UserControl
{
    public SettingsPage()
    {
        InitializeComponent();
        Localization.L10n.Apply(this);
    }
}
