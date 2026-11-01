using Avalonia.Controls;

namespace Seam.Views.Pages;

public partial class AudioPage : UserControl
{
    public AudioPage()
    {
        InitializeComponent();
        Localization.L10n.Apply(this);
    }
}
