using Avalonia.Controls;

namespace Seam.Views.Pages;

public partial class LogPage : UserControl
{
    public LogPage()
    {
        InitializeComponent();
        Localization.L10n.Apply(this);
    }
}
