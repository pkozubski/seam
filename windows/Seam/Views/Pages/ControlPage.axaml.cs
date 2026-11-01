using Avalonia.Controls;
using Avalonia.Interactivity;

namespace Seam.Views.Pages;

public partial class ControlPage : UserControl
{
    public ControlPage()
    {
        InitializeComponent();
        Localization.L10n.Apply(this);
        // Jak na macOS: w wąskim oknie kolumna ustawień zwęża się z 420 do 340.
        SizeChanged += (_, e) => Layout.ColumnDefinitions[1].Width = new GridLength(e.NewSize.Width < 860 ? 340 : 420);
    }

    private void OpenDisplays(object? sender, RoutedEventArgs e)
    {
        if (TopLevel.GetTopLevel(this) is MainWindow window) window.NavigateTo("displays");
    }
}
