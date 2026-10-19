# Seam dla Windows: zasady dla Claude Code

Najpierw przeczytaj [../CLAUDE.md](../CLAUDE.md). Ten plik opisuje pracę nad `windows/Seam` na komputerze z Windowsem.

## Przygotowanie (raz)

- .NET 8 SDK (`winget install Microsoft.DotNet.SDK.8`), Git, PowerShell 7 (`winget install Microsoft.PowerShell`).
- Claude Code uruchamiaj z katalogu głównego repo (`claude` w `...\seam`).
- Do testów z Makiem: na Macu działa Seam z kanału dev, oba komputery w tej samej sieci.

## Podgląd aplikacji: jak agent widzi UI

Agent nie widzi ekranu, ale może czytać pliki PNG. Są dwa sposoby:

1. **Podgląd offline** (dane demo, bez sieci; to podstawowy sposób po każdej zmianie UI):
   ```powershell
   pwsh windows/scripts/preview.ps1                               # wszystkie strony → output/preview/seam*.png
   pwsh windows/scripts/preview.ps1 -Section displays             # jedna strona
   pwsh windows/scripts/preview.ps1 -Section windows -FullPage    # cała przewijana strona Okna
   ```
   Strony: `connection, displays, control, audio, clipboard, windows, settings, log`
   (`MainWindow.PageTags`). Skrypt wypisuje ścieżki PNG; obejrzyj je narzędziem Read.
   Pod spodem: `Seam.exe --screenshot plik.png [--screenshot-section tag] [--screenshot-full-page]`
   (`App.axaml.cs`, `HandleScreenshotFlag`), uruchamia `StartOffline()`: bez wykrywania, połączenia i dźwięku.
   Gdy dodajesz nową stronę lub stan, który ma być widoczny w podglądzie, dodaj dane demo w `StartOffline()`.
2. **Zrzut działającej aplikacji** (prawdziwe połączenie z Makiem):
   ```powershell
   pwsh windows/scripts/capture-window.ps1            # okno główne → output/preview/live.png
   pwsh windows/scripts/capture-window.ps1 -Restore   # gdy okno jest zminimalizowane
   ```
   Okno schowane w zasobniku trzeba najpierw otworzyć.
   Dziennik aplikacji (strona Dziennik) i `%LOCALAPPDATA%\BorderlessMouse\crash-previous.log` pokazują błędy.

Uruchamianie z kodu: `dotnet run --project windows/Seam/Seam.csproj -c Release --no-restore`.
Zainstalowana kopia może już działać: zamknij ją z zasobnika, zanim uruchomisz build, bo obie
korzystają z tych samych ustawień i parowania.

## Build i testy

```powershell
dotnet restore windows/ClipboardChecks/Seam.ClipboardChecks.csproj --locked-mode
dotnet build windows/Seam/Seam.csproj -c Release -warnaserror --no-restore
dotnet run --project windows/ClipboardChecks/Seam.ClipboardChecks.csproj -c Release --no-restore
dotnet run --project windows/ClipboardChecks/Seam.ClipboardChecks.csproj -c Release --no-restore -- --window-checks
# tylko na Windows z aktywnym pulpitem: otwiera na chwilę okna testowe (ramka, popupy, pełny ekran)
dotnet run --project windows/ClipboardChecks/Seam.ClipboardChecks.csproj -c Release --no-restore -- --native-viewer-checks
```

Na Windows testy dekodują też H.264 przez Media Foundation (na Macu ten krok jest pomijany).

**Pliki `packages.lock.json`:** restore zawsze w trybie Debug (bez `-c`) z `--locked-mode`, potem build/run
z `-c Release --no-restore`. `dotnet build -c Release` bez `--no-restore` przepisuje oba pliki lock
(znika `Avalonia.Diagnostics`, które jest tylko w Debug) i CI pada z NU1004. Jeśli się zmieniły, a nie
zmieniałeś pakietów: `git checkout -- windows/*/packages.lock.json`.

Publikacja jednego pliku exe (jak w CI):
```powershell
dotnet publish windows/Seam/Seam.csproj -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o publish
```
(`-r win-x64` robi własny restore dla RID; w CI release jest osobny `restore -r win-x64 --locked-mode`).

## Architektura

```
windows/Seam/
  App.axaml(.cs)       start, zasobnik, tryb --screenshot
  Program.cs           Main (STA), zapis awarii
  ViewModels/          MainViewModel – cały stan UI (CommunityToolkit.Mvvm), StartOffline() z danymi demo
  Views/               MainWindow (FluentAvalonia NavigationView), Pages/*.axaml, SettingRow, IconTile, diagramy
  Styles/Theme.axaml   kolory i style wspólne z macOS
  Net/                 ControlClient (TCP, szyfrowana sesja), Discovery (UDP), AudioReceiver, ClipboardSync, Updater
  Input/               LowLevelHooks, NativeInputWindow (Raw Input), InputCapture, NativeMethods (P/Invoke)
  Display/             DisplayViewer (Win32 + D3D11), H264Decoder/Encoder (Media Foundation, Vortice),
                       VideoReceiver, WinViewStreamer/Tracker (okna Windows na Macu), VirtualDisplayDriver
  Audio/               AudioPlayer (NAudio WASAPI), JitterBufferProvider
  Security/            PairingSecurity (DPAPI, HMAC/HKDF, AES-GCM), UpdateSignatureVerifier (ECDSA)
  Models/              Settings (%APPDATA%\BorderlessMouse\settings.json), Autostart (klucz Run)
  Localization/L10n.cs T("pl","en") + słownik tekstów XAML
```

## Zasady specyficzne dla Windows

- FluentAvaloniaUI zostaje na **2.4.0**, Avalonia na **11.3.12**: 2.5.x wymaga .NET 10. Bez migracji na .NET 10 nie podnoś wersji.
- `InvariantGlobalization` musi zostać wyłączone: FluentAvalonia z nim pada przy starcie.
- Kod tylko dla Windows oznaczaj `[SupportedOSPlatform("windows")]`; projekt musi się dalej kompilować na macOS (CI testów).
- `-warnaserror` w CI: zostaw build bez ostrzeżeń.
- Hooki niskiego poziomu i WASAPI wymagają wątku STA z pętlą komunikatów (zapewnia ją Avalonia), nie blokuj wątku UI.
- `SharpGen CppObject` nie ma finalizatora; wrapperów z `OutputDataBuffer.Sample` dla próbek dostarczonych
  przez wywołującego nie zwalniaj osobno.
- Sterownik wirtualnego ekranu (VDD, `C:\VirtualDisplayDriver`) instaluje się raz z uprawnieniami admina;
  monitor jest podłączany i odłączany przez `ChangeDisplaySettingsEx` bez admina.
- Skrót sterowania: Ctrl+Alt+Shift+B (użytkownik ma klawiaturę 68%, bez Scroll Lock/Pause).
- Updater wersji dev nadpisuje exe w miejscu (`swap.cmd`); nazwa pliku na dysku może dalej brzmieć `BorderlessMouse.exe`.
