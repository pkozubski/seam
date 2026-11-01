using Avalonia.Controls;

namespace Seam.Views.Pages;

public partial class ClipboardPage : UserControl
{
    public ClipboardPage()
    {
        InitializeComponent();
        Localization.L10n.Apply(this);
        // Jak na macOS: w wąskim oknie kolumna ustawień zwęża się z 420 do 340.
        SizeChanged += (_, e) => Layout.ColumnDefinitions[1].Width = new GridLength(e.NewSize.Width < 860 ? 340 : 420);
    }
}
