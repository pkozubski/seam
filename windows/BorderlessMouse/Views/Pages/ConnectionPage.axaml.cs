using Avalonia.Controls;
using Avalonia.Interactivity;

namespace BorderlessMouse.Views.Pages;

public partial class ConnectionPage : UserControl
{
    private void OpenWindows_OnClick(object? sender, RoutedEventArgs e)
    {
        if (TopLevel.GetTopLevel(this) is MainWindow window) window.NavigateTo("windows");
    }

    public void ShowDetails()
    {
        ConnectionDetails.IsExpanded = true;
        ConnectionDetails.UpdateLayout();
        ConnectionDetails.BringIntoView();
    }

    public ConnectionPage()
    {
        InitializeComponent();
        Localization.L10n.Apply(this);
    }
}
