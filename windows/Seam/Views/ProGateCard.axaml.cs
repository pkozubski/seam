using Avalonia.Controls;
using Avalonia.Interactivity;

namespace Seam.Views;

public partial class ProGateCard : UserControl
{
    public ProGateCard()
    {
        InitializeComponent();
    }

    private void OpenLicense(object? sender, RoutedEventArgs e)
    {
        if (TopLevel.GetTopLevel(this) is MainWindow window) window.OpenSettings("license");
    }
}
