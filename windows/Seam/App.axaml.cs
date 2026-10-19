using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using Avalonia.Media.Imaging;
using Avalonia.Threading;
using Seam.ViewModels;
using Seam.Views;

namespace Seam;

public partial class App : Application
{
    private MainViewModel? _viewModel;
    private MainWindow? _mainWindow;
    public bool IsExiting { get; private set; }

    public override void Initialize()
    {
        AvaloniaXamlLoader.Load(this);
    }

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            desktop.ShutdownMode = ShutdownMode.OnExplicitShutdown;
            _viewModel = new MainViewModel();
            _mainWindow = new MainWindow { DataContext = _viewModel };
            desktop.MainWindow = _mainWindow;
            desktop.ShutdownRequested += (_, _) => _viewModel.Shutdown();
            var background = desktop.Args?.Contains(Models.Autostart.BackgroundArgument) == true
                             && _viewModel.StartMinimized;
            var screenshot = desktop.Args?.Contains("--screenshot") == true;
            if (!background) _mainWindow.Show();
            if (screenshot)
            {
                // zrzut interfejsu: żadnej sieci, żeby nie dotykać działających instancji
                _viewModel.StartOffline();
            }
            else
            {
                _viewModel.AttachClipboard(_mainWindow.Clipboard);
                _viewModel.Start();
                if (background) _viewModel.LogBackgroundStart();
            }
            HandleScreenshotFlag(desktop.Args);
        }

        base.OnFrameworkInitializationCompleted();
    }

    /// <summary>Tryb diagnostyczny: `--screenshot plik.png` renderuje okno do PNG i kończy działanie (CI / podgląd UI).</summary>
    private void HandleScreenshotFlag(string[]? args)
    {
        if (args is null || _mainWindow is null || args.Contains("--ui-interactive")) return;
        if (!_mainWindow.IsVisible) _mainWindow.Show();
        var idx = Array.IndexOf(args, "--screenshot");
        if (idx < 0 || idx + 1 >= args.Length) return;
        var path = args[idx + 1];
        var sectionIndex = Array.IndexOf(args, "--screenshot-section");
        var section = sectionIndex >= 0 && sectionIndex + 1 < args.Length ? args[sectionIndex + 1] : null;
        if (section is not null) _mainWindow.NavigateTo(section);
        DispatcherTimer.RunOnce(() =>
        {
            try
            {
                if (section is not null)
                {
                    if (args.Contains("--screenshot-full-page") && _mainWindow.CurrentPage is Views.Pages.WindowsPage windows)
                    {
                        var guide = windows.FullGuide;
                        using var full = new RenderTargetBitmap(new PixelSize((int)Math.Ceiling(guide.Bounds.Width * 2),
                            (int)Math.Ceiling(guide.Bounds.Height * 2)), new Vector(192, 192));
                        full.Render(guide);
                        using var composite = new RenderTargetBitmap(full.PixelSize, new Vector(192, 192));
                        using (var drawing = composite.CreateDrawingContext())
                        {
                            drawing.DrawRectangle(Avalonia.Media.Brush.Parse("#103735"), null, new Rect(guide.Bounds.Size));
                            drawing.DrawImage(full, new Rect(0, 0, full.PixelSize.Width, full.PixelSize.Height), new Rect(guide.Bounds.Size));
                        }
                        composite.Save(path);
                    }
                    else Capture(path);
                    return;
                }
                // pierwsza strona pod podaną nazwą, pozostałe strony paska bocznego z sufiksem
                var stem = Path.ChangeExtension(path, null);
                var ext = Path.GetExtension(path);
                foreach (var (tag, i) in MainWindow.PageTags.Select((t, i) => (t, i)))
                {
                    _mainWindow.NavigateTo(tag);
                    _mainWindow.UpdateLayout();
                    Capture(i == 0 ? path : $"{stem}-{tag}{ext}");
                }
            }
            finally
            {
                ExitApplication();
            }
        }, TimeSpan.FromSeconds(2));
    }

    private void Capture(string path)
    {
        if (_mainWindow is null) return;
        var size = new PixelSize((int)_mainWindow.Bounds.Width * 2, (int)_mainWindow.Bounds.Height * 2);
        using var bitmap = new RenderTargetBitmap(size, new Vector(192, 192));
        bitmap.Render(_mainWindow);
        var status = _mainWindow.StatusWindow;
        if (status is null || !status.IsVisible) { bitmap.Save(path); return; }
        status.UpdateLayout();
        using var orb = new RenderTargetBitmap(new PixelSize(252, 252), new Vector(192, 192));
        orb.Render(status);
        var scale = OperatingSystem.IsMacOS() ? 1 : _mainWindow.RenderScaling;
        var offsetX = (status.Position.X - _mainWindow.Position.X) / scale;
        var offsetY = (status.Position.Y - _mainWindow.Position.Y) / scale;
        var height = Math.Max(_mainWindow.Bounds.Height, offsetY + 126);
        using var composite = new RenderTargetBitmap(new PixelSize(size.Width, (int)Math.Ceiling(height * 2)), new Vector(192, 192));
        using (var drawing = composite.CreateDrawingContext())
        {
            drawing.DrawImage(bitmap, new Rect(0, 0, bitmap.PixelSize.Width, bitmap.PixelSize.Height), new Rect(0, 0, _mainWindow.Bounds.Width, _mainWindow.Bounds.Height));
            drawing.DrawImage(orb, new Rect(0, 0, 252, 252), new Rect(offsetX, offsetY, 126, 126));
        }
        composite.Save(path);
    }

    public void ShowMainWindow()
    {
        if (_mainWindow is null) return;
        _mainWindow.Show();
        _mainWindow.WindowState = WindowState.Normal;
        _mainWindow.Activate();
    }

    public void ExitApplication()
    {
        IsExiting = true;
        _viewModel?.Shutdown();
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            desktop.Shutdown();
        }
    }

    private void TrayIcon_OnClicked(object? sender, EventArgs e) => ShowMainWindow();
    private void ShowWindow_OnClick(object? sender, EventArgs e) => ShowMainWindow();
    private void Exit_OnClick(object? sender, EventArgs e) => ExitApplication();
}
