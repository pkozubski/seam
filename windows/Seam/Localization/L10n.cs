using System.Globalization;
using Avalonia.Controls;
using Avalonia.LogicalTree;
using Seam.Views;
using FluentAvalonia.UI.Controls;

namespace Seam.Localization;

/// <summary>
/// Lekka lokalizacja pierwszej bety. Polski pozostaje językiem źródłowym,
/// a każdy inny język systemu otrzymuje angielski. Dynamiczne komunikaty
/// powinny używać <see cref="T"/> bezpośrednio.
/// </summary>
public static class L10n
{
    public static bool IsPolish => CultureInfo.CurrentUICulture.TwoLetterISOLanguageName.Equals("pl", StringComparison.OrdinalIgnoreCase);
    public static string T(string polish, string english) => IsPolish ? polish : english;
    public static string ShowWindow => T("Pokaż okno", "Show window");
    public static string Quit => T("Zakończ", "Quit");
    public static string TranslateText(string value) => !IsPolish && English.TryGetValue(value, out var translated) ? translated : value;

    private static readonly IReadOnlyDictionary<string, string> English = new Dictionary<string, string>
    {
        ["Drugi komputer. Dodatkowy ekran."] = "Another computer. An extra display.",
        ["Przeciągnij dowolne okno za krawędź ekranu. Pojawi się na drugim urządzeniu — tak jak na dodatkowym monitorze."] = "Drag any window past the edge of your screen. It appears on the other device — just like on an extra monitor.",
        ["Okna Maca na tym komputerze"] = "Mac windows on this computer",
        ["Okna Windows na Macu"] = "Windows apps on the Mac",
        ["Przeciągnij. I pracuj dalej."] = "Drag it over. Keep working.",
        ["Chwyć okno za górny pasek i przenieś przez wspólną krawędź."] = "Grab the title bar and drag the window across the shared edge.",
        ["Przykład przeniesienia okna z Maca na Windows. Układ odpowiada ustawieniu w zakładce Ekrany."] = "Example of moving a window from Mac to Windows. The arrangement follows your Displays settings.",
        ["Okno przechodzi na drugi ekran. Aplikacja nadal działa na komputerze, na którym została otwarta."] = "The window moves to the other display. The app keeps running on the computer where you opened it.",
        ["Otwórz dowolne okno"] = "Open any window",
        ["Przeglądarka, dokument, komunikator — to, z czym pracujesz."] = "A browser, document or chat — whatever you are working on.",
        ["Przeciągnij za krawędź"] = "Drag across the edge",
        ["Chwyć górny pasek i przesuń okno w stronę drugiego ekranu."] = "Grab the title bar and move it towards the other display.",
        ["Pracuj na drugim ekranie"] = "Use the other display",
        ["Okno pojawi się na drugim urządzeniu. Możesz pracować dalej."] = "Your window appears on the other device. Carry on working.",
        ["Z której strony jest drugi ekran?"] = "Which side is your other display on?",
        ["Ustaw ekrany tak, jak stoją na biurku. To określa, przez którą krawędź przeciągniesz okno."] = "Arrange the displays as they sit on your desk. This decides which edge you move windows across.",
        ["Zmień układ ekranów"] = "Change display arrangement",
        ["Dowolne okno"] = "Any window",
        ["Przenosisz okna bezpośrednio z pulpitu, tak jak między dwoma monitorami."] = "Move windows directly from your desktop, just like between two monitors.",
        ["Z powrotem na pierwszy ekran"] = "Back to the first display",
        ["Przeciągnij okno przez wspólną krawędź w przeciwną stronę."] = "Drag the window back across the shared edge in the opposite direction.",
        ["Opcje wyświetlania"] = "Display options",
        ["Szczegóły połączenia"] = "Connection details",
        ["Klawiatura i mysz"] = "Keyboard & mouse",
        ["Ekrany"] = "Displays",
        ["Funkcje"] = "Features",
        ["Jedna klawiatura i mysz dla obu komputerów."] = "One keyboard and mouse for both computers.",
        ["Dźwięk systemowy Maca grany na tym komputerze."] = "The Mac's system audio played on this PC.",
        ["Kopiuj na jednym komputerze, wklejaj na drugim."] = "Copy on one computer, paste on the other.",
        ["Okna Maca na tym monitorze i okna Windows na Macu."] = "Mac windows on this monitor and Windows windows on the Mac.",
        ["KLAWIATURA"] = "KEYBOARD",
        ["MYSZ"] = "MOUSE",
        ["Skrót awaryjny"] = "Emergency shortcut",
        ["Położenie Maca"] = "Mac position",
        ["Krawędź, przez którą kursor przechodzi na Maca, ustawiasz w zakładce Ekrany."] = "Set the edge the pointer uses to reach the Mac under Displays.",
        ["Otwórz Ekrany"] = "Open Displays",
        ["Zamianę klawiszy Ctrl i Cmd oraz przewijanie ustawiasz w aplikacji na Macu."] = "Ctrl and Cmd swap and scrolling are set in the Mac app.",
        ["ODTWARZANIE"] = "PLAYBACK",
        ["OPÓŹNIENIE"] = "LATENCY",
        ["Synchronizuj schowek"] = "Sync clipboard",
        ["CO JEST PRZESYŁANE"] = "WHAT IS SHARED",
        ["Tekst"] = "Text",
        ["Zdjęcia i zrzuty ekranu"] = "Photos and screenshots",
        ["Obrazy do 32 MiB"] = "Images up to 32 MiB",
        ["W obie strony, tylko w sieci lokalnej, szyfrowane jak całe połączenie."] = "Both ways, local network only, encrypted like the whole connection.",
        ["Ustaw ekrany tak, jak stoją na biurku"] = "Arrange the screens the way they sit on your desk",
        ["Kliknij miejsce obok tego monitora, w którym stoi Mac. Kursor przechodzi na Maca przez tę krawędź."] = "Click the spot next to this monitor where the Mac sits. The pointer moves to the Mac across that edge.",
        ["UKŁAD EKRANÓW"] = "SCREEN LAYOUT",
        ["Ten komputer"] = "This PC",
        ["PRZEJŚCIE KURSORA"] = "POINTER HANDOFF",
        ["Przy kilku monitorach przejście prowadzi przez ten, który jest najdalej po wybranej stronie."] = "With several monitors, the handoff uses the one furthest towards the chosen side.",
        ["Dźwięk"] = "Audio",
        ["Schowek"] = "Clipboard",
        ["Okna"] = "Windows",
        ["Dwa komputery.\nJedna przestrzeń."] = "Two computers.\nOne space.",
        ["Mysz i klawiatura"] = "Mouse & keyboard",
        ["Dźwięk z Maca"] = "Audio from Mac",
        ["Wspólny schowek"] = "Shared clipboard",
        ["Przenieś okno"] = "Move a window",
        ["Rozłącz komputery"] = "Disconnect computers",
        ["Wszystko gotowe. Pracuj jak na jednym komputerze."] = "All set. Work as if it were one computer.",
        ["Parowanie i szczegóły połączenia"] = "Pairing and connection details",
        ["Połączenie"] = "Connection",
        ["Połączenie z Makiem"] = "Connect to Mac",
        ["Sterowanie"] = "Control",
        ["Ustawienia"] = "Settings",
        ["Dziennik"] = "Diagnostics",
        ["Wyczyść"] = "Clear",
        ["Pokaż okno"] = "Show window",
        ["Zakończ"] = "Quit",
        ["Połącz swoje biurko w trzech krokach"] = "Connect your desk in three steps",
        ["1. Uruchom aplikację na Macu.  2. Wpisz kod parowania poniżej.  3. Wybierz znalezionego Maca i połącz."] = "1. Open the app on your Mac.  2. Enter the pairing code below.  3. Select the discovered Mac and connect.",
        ["Rozumiem"] = "Got it",
        ["BEZPIECZNE PAROWANIE"] = "SECURE PAIRING",
        ["Przepisz kod widoczny w sekcji Połączenie na Macu. Kod nie jest zapisywany w zwykłych ustawieniach."] = "Enter the code shown on the Mac Connection page. The code is not stored in ordinary settings.",
        ["Zapisz kod"] = "Save code",
        ["Ten komputer jest sparowany"] = "This PC is paired",
        ["Chronione"] = "Protected",
        ["Usuń zaufanie"] = "Forget",
        ["MAKI W SIECI LOKALNEJ"] = "MACS ON YOUR LOCAL NETWORK",
        ["Na Macu musi działać Seam. Kliknij, aby wybrać adres."] = "Seam must be running on the Mac. Select it below.",
        ["Nie znaleziono jeszcze żadnego Maca – wpisz adres ręcznie poniżej."] = "No Mac found yet — enter its address manually below.",
        ["Adres IP Maca, np. 192.168.1.20"] = "Mac IP address, e.g. 192.168.1.20",
        ["Łącz automatycznie"] = "Connect automatically",
        ["Przy starcie i po utracie połączenia próbuj ponownie."] = "Reconnect at startup and after a connection loss.",
        ["STAN"] = "STATUS",
        ["Kursor"] = "Pointer",
        ["KLAWIATURA I MYSZ"] = "KEYBOARD AND MOUSE",
        ["EKRAN MACA"] = "MAC DISPLAY",
        ["Pokazuj ekran wirtualny Maca"] = "Show the Mac virtual display",
        ["Ten monitor staje się drugim ekranem Maca. Przeciągnij okno na Macu w stronę Windowsa, a pojawi się tutaj."] = "This monitor becomes a second Mac display. Drag a window on the Mac toward Windows and it appears here.",
        ["Pokazuj go przez cały czas sterowania Makiem"] = "Show it whenever you control the Mac",
        ["Tylko okna Maca"] = "Mac windows only",
        ["Okna Maca leżą na pulpicie Windows obok zwykłych okien. Wyłączone: cały pulpit Maca na monitorze."] = "Mac windows sit on the Windows desktop next to Windows apps. Off: the whole Mac desktop fills the monitor.",
        ["Tylko dla całego pulpitu. Wyłączone: pulpit Maca pojawia się dopiero, gdy przeciągniesz na niego okno."] = "Full desktop only. Off: the Mac desktop appears only when you drag a window onto it.",
        ["Stan ekranu"] = "Display status",
        ["OKNA WINDOWS NA MACU"] = "WINDOWS APPS ON THE MAC",
        ["Przenoś okna Windows na Maca"] = "Move Windows apps to the Mac",
        ["Przeciągnij okno za krawędź po stronie Maca – pojawi się na ekranie Maca i dalej działa w Windowsie."] = "Drag a window past the Mac-side edge. It appears on the Mac screen and keeps running in Windows.",
        ["Sterownik monitora wirtualnego"] = "Virtual monitor driver",
        ["Jednorazowa instalacja darmowego, podpisanego sterownika Virtual Display Driver (wymaga zgody administratora)."] = "One-time install of the free, signed Virtual Display Driver (requires administrator approval).",
        ["Stan"] = "Status",
        ["Uruchom ponownie"] = "Restart",
        ["Udostępniaj klawiaturę i mysz"] = "Share keyboard and mouse",
        ["Krawędź przełącza na Maca. Pełny ekran i przechwycona mysz blokują automatyczne przejście."] = "Cross the selected edge to control the Mac. Full-screen apps and captured pointer input block automatic switching.",
        ["Mac stoi względem tego ekranu"] = "Mac position relative to this display",
        ["Krawędź, przez którą kursor przechodzi na Maca."] = "The edge used to move the pointer to the Mac.",
        ["Awaryjny skrót klawiszowy"] = "Emergency shortcut",
        ["Czułość myszy na Macu"] = "Pointer speed on Mac",
        ["Ukrywaj kursor podczas sterowania Makiem"] = "Hide the Windows pointer while controlling Mac",
        ["Kursor zostaje przy krawędzi, przez którą wyszedł, i znika pod niewidocznym oknem."] = "The Windows pointer stays at the exit edge and is hidden.",
        ["DŹWIĘK"] = "AUDIO",
        ["Odbieraj dźwięk z Maca"] = "Play audio from Mac",
        ["Cały dźwięk systemowy Maca gra na wybranym urządzeniu przez szyfrowany strumień LAN."] = "Play all Mac system audio on the selected output using encrypted LAN streaming.",
        ["Urządzenie wyjściowe"] = "Output device",
        ["Słuchawki lub głośniki podłączone do Windowsa."] = "Headphones or speakers connected to Windows.",
        ["Odśwież listę urządzeń"] = "Refresh devices",
        ["Bufor sieciowy"] = "Network buffer",
        ["Tryb WASAPI exclusive"] = "WASAPI exclusive mode",
        ["Najniższe opóźnienie, ale blokuje kartę dla innych aplikacji. Przy braku wsparcia wraca do shared."] = "Lowest latency, but reserves the device. Falls back to shared mode when unavailable.",
        ["STAN STRUMIENIA"] = "STREAM STATUS",
        ["SCHOWEK"] = "CLIPBOARD",
        ["Synchronizuj schowek (tekst i zdjęcia)"] = "Sync clipboard text and images",
        ["Kopiuj i wklejaj tekst, zdjęcia oraz zrzuty ekranu w obie strony. Obrazy do 32 MiB."] = "Copy and paste text, images and screenshots in either direction. Images up to 32 MiB.",
        ["Ostatnia synchronizacja"] = "Last synchronization",
        ["OGÓLNE"] = "GENERAL",
        ["Nazwa tego komputera"] = "This PC name",
        ["Widoczna w aplikacji na Macu."] = "Shown in the Mac app.",
        ["Port TCP Maca"] = "Mac TCP port",
        ["Domyślnie 47800 – musi zgadzać się z ustawieniem na Macu."] = "Default 47800 — must match the Mac setting.",
        ["Port UDP audio (ten komputer)"] = "Audio UDP port on this PC",
        ["Domyślnie 47802. Zapora Windows musi go przepuszczać."] = "Default 47802. Windows Firewall must allow it.",
        ["URUCHAMIANIE"] = "STARTUP",
        ["Uruchamiaj przy logowaniu"] = "Launch at sign-in",
        ["Startuj zminimalizowany do zasobnika"] = "Start minimized to tray",
        ["Przy autostarcie okno pozostaje ukryte; kliknij ikonę w zasobniku, aby je otworzyć."] = "Keep the window hidden at startup; use the tray icon to open it.",
        ["AKTUALIZACJE"] = "UPDATES",
        ["Sprawdź teraz"] = "Check now",
        ["Zainstaluj"] = "Install",
        ["Zainstaluj i uruchom ponownie"] = "Install and restart",
        ["Sprawdzaj automatycznie"] = "Check automatically",
        ["Po starcie i co 6 godzin, przez GitHub Releases."] = "At startup and every six hours through GitHub Releases.",
        ["Dostępna aktualizacja"] = "Update available",
        ["Mac nie ma uprawnienia Dostępność"] = "Mac accessibility permission is missing",
        ["Sterowanie nie zadziała, dopóki na Macu nie nadasz Seam uprawnienia w Ustawieniach systemowych (Prywatność i ochrona, sekcja Dostępność)."] = "Control will not work until Seam has Accessibility permission in Mac System Settings (Privacy & Security, Accessibility).",
    };

    public static void Apply(Control root)
    {
        if (IsPolish) return;
        Translate(root);
        foreach (var control in root.GetLogicalDescendants().OfType<Control>()) Translate(control);
    }

    private static void Translate(Control control)
    {
        if (control is TextBlock text && text.Text is { } value && English.TryGetValue(value, out var translatedText))
            text.Text = translatedText;
        if (control is SettingRow row)
        {
            if (English.TryGetValue(row.Title ?? "", out var title)) row.Title = title;
            if (English.TryGetValue(row.Subtitle ?? "", out var subtitle)) row.Subtitle = subtitle;
        }
        if (control is ContentControl content && content.Content is string label && English.TryGetValue(label, out var translatedContent))
            content.Content = translatedContent;
        if (control is Expander expander && expander.Header is string header && English.TryGetValue(header, out var translatedHeader))
            expander.Header = translatedHeader;
        var accessibleName = Avalonia.Automation.AutomationProperties.GetName(control);
        if (accessibleName is not null && English.TryGetValue(accessibleName, out var translatedName))
            Avalonia.Automation.AutomationProperties.SetName(control, translatedName);
        if (control is TextBox box && box.Watermark is string watermark && English.TryGetValue(watermark, out var translatedWatermark))
            box.Watermark = translatedWatermark;
        if (control is InfoBar info)
        {
            if (English.TryGetValue(info.Title ?? "", out var title)) info.Title = title;
            if (English.TryGetValue(info.Message ?? "", out var message)) info.Message = message;
        }
        if (ToolTip.GetTip(control) is string tip && English.TryGetValue(tip, out var translatedTip))
            ToolTip.SetTip(control, translatedTip);
    }
}
