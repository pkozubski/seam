using Avalonia.Controls;
using Avalonia.Interactivity;
using Seam.ViewModels;

namespace Seam.Views.Pages;

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
        // Adres, ping i kursor w szczegółach odświeża licznik statystyk tylko, gdy szczegóły są rozwinięte.
        ConnectionDetails.PropertyChanged += (_, e) =>
        {
            if (e.Property == Expander.IsExpandedProperty) ReportDetailsVisibility();
        };
        DataContextChanged += (_, _) => ReportDetailsVisibility();
    }

    private void ReportDetailsVisibility() =>
        (DataContext as MainViewModel)?.SetConnectionDetailsVisible(ConnectionDetails.IsExpanded);
}
