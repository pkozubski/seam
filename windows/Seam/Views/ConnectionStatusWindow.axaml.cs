using Avalonia.Controls;
using Avalonia.Interactivity;

namespace Seam.Views;

/// <summary>Owned transparent window: the circular status crosses the native frame.</summary>
public partial class ConnectionStatusWindow : Window
{
    public event Action? DetailsRequested;
    public ConnectionStatusWindow() => InitializeComponent();
    private void ShowDetails_OnClick(object? sender, RoutedEventArgs e) => DetailsRequested?.Invoke();
}
