using System.Globalization;
using Avalonia.Controls;
using Avalonia.LogicalTree;
using Seam.Models;
using Seam.Views;
using FluentAvalonia.UI.Controls;

namespace Seam.Localization;

/// <summary>
/// Angielski jest językiem źródłowym, polski tłumaczeniem. Język wybiera się w Ustawieniach
/// (<see cref="Settings.Language"/>), domyślnie idzie za językiem Windows; zmiana działa po restarcie.
/// Dynamiczne komunikaty używają <see cref="T"/>, teksty z XAML tłumaczy <see cref="Apply"/>.
/// </summary>
public static class L10n
{
    /// <summary>Raz na uruchomienie, tak jak na Macu: język zmienia się dopiero po restarcie.</summary>
    public static readonly bool IsPolish = Settings.Load().Language switch
    {
        AppLanguage.Polish => true,
        AppLanguage.English => false,
        _ => CultureInfo.CurrentUICulture.TwoLetterISOLanguageName.Equals("pl", StringComparison.OrdinalIgnoreCase),
    };

    public static string T(string english, string pl) => IsPolish ? pl : english;
    public static string ShowWindow => T("Show window", pl: "Pokaż okno");
    public static string Quit => T("Quit", pl: "Zakończ");
    public static string TranslateText(string value) => IsPolish && Polish.TryGetValue(value, out var translated) ? translated : value;

    /// <summary>Dla testu, że każdy tekst z XAML ma polskie tłumaczenie.</summary>
    internal static bool HasPolish(string english) => Polish.ContainsKey(english);

    /// <summary>Teksty z XAML (angielskie) → polskie.</summary>
    private static readonly IReadOnlyDictionary<string, string> Polish = new Dictionary<string, string>
    {
        ["App language"] = "Język aplikacji",
        ["LICENSE"] = "LICENCJA",
        ["License key"] = "Klucz licencji",
        ["From the purchase email. One license covers up to 3 computers."] = "Z e-maila po zakupie. Jedna licencja obejmuje do 3 komputerów.",
        ["Activate"] = "Aktywuj",
        ["Deactivate"] = "Dezaktywuj",
        ["Enter license key"] = "Wpisz klucz licencji",
        ["Free: keyboard and mouse, text in the clipboard. Pro: Mac audio, windows in both directions, images in the clipboard. Pro works on both computers when either of them has a license or a trial."] = "Za darmo: klawiatura i mysz, tekst w schowku. Pro: dźwięk z Maca, okna w obie strony, obrazy w schowku. Pro działa na obu komputerach, gdy licencję albo okres próbny ma którykolwiek z nich.",
        ["Two computers.\nOne space."] = "Dwa komputery.\nJedna przestrzeń.",
        ["Window moving"] = "Przenoszenie okien",
        ["Restart"] = "Uruchom ponownie",
        ["Mac windows on this computer"] = "Okna Maca na tym komputerze",
        ["Windows apps on the Mac"] = "Okna Windows na Macu",
        ["Open any window"] = "Otwórz dowolne okno",
        ["A browser, document or chat — whatever you are working on."] = "Przeglądarka, dokument, komunikator — to, z czym pracujesz.",
        ["Drag across the edge"] = "Przeciągnij za krawędź",
        ["Grab the title bar and move it towards the other display."] = "Chwyć górny pasek i przesuń okno w stronę drugiego ekranu.",
        ["Use the other display"] = "Pracuj na drugim ekranie",
        ["Your window appears on the other device. Drag it back across the same edge."] = "Okno pojawi się na drugim urządzeniu. Wróci tą samą krawędzią w przeciwną stronę.",
        ["Your apps, on both computers."] = "Twoje aplikacje na obu komputerach.",
        ["Move any window"] = "Przenieś dowolne okno",
        ["Drag an app to the edge of your screen. It appears on your other computer."] = "Przeciągnij aplikację do krawędzi ekranu. Pojawi się na drugim komputerze.",
        ["See how"] = "Zobacz jak",
        ["Connection settings"] = "Ustawienia połączenia",
        ["Choose your screen arrangement"] = "Wybierz układ ekranów",
        ["Match the layout to the devices on your desk."] = "Dopasuj układ do urządzeń na biurku.",
        ["Arrange screens"] = "Ustaw ekrany",
        ["Connection help"] = "Pomoc z połączeniem",
        ["HOW IT WORKS"] = "JAK TO DZIAŁA",
        ["DISPLAY OPTIONS"] = "OPCJE WYŚWIETLANIA",
        ["Install driver"] = "Zainstaluj sterownik",
        ["Video stream"] = "Strumień obrazu",
        ["Restart it if the picture freezes or lags behind."] = "Uruchom ponownie, gdy obraz się zatrzyma albo nie nadąża.",
        ["Keyboard & mouse"] = "Klawiatura i mysz",
        ["Displays"] = "Ekrany",
        ["Features"] = "Funkcje",
        ["Local network only"] = "Tylko w sieci lokalnej",
        ["One keyboard and mouse for both computers."] = "Jedna klawiatura i mysz dla obu komputerów.",
        ["KEYBOARD"] = "KLAWIATURA",
        ["MOUSE"] = "MYSZ",
        ["Emergency shortcut"] = "Skrót awaryjny",
        ["Mac position"] = "Położenie Maca",
        ["Set the edge the pointer uses to reach the Mac under Displays."] = "Krawędź, przez którą kursor przechodzi na Maca, ustawiasz w zakładce Ekrany.",
        ["Open Displays"] = "Otwórz Ekrany",
        ["Ctrl and Cmd swap and scrolling are set in the Mac app."] = "Zamianę klawiszy Ctrl i Cmd oraz przewijanie ustawiasz w aplikacji na Macu.",
        ["PLAYBACK"] = "ODTWARZANIE",
        ["LATENCY"] = "OPÓŹNIENIE",
        ["Sync clipboard"] = "Synchronizuj schowek",
        ["WHAT IS SHARED"] = "CO JEST PRZESYŁANE",
        ["Text"] = "Tekst",
        ["Photos and screenshots"] = "Zdjęcia i zrzuty ekranu",
        ["Images up to 32 MiB"] = "Obrazy do 32 MiB",
        ["Both ways, local network only, encrypted like the whole connection."] = "W obie strony, tylko w sieci lokalnej, szyfrowane jak całe połączenie.",
        ["Arrange the screens the way they sit on your desk"] = "Ustaw ekrany tak, jak stoją na biurku",
        ["Click the spot next to this monitor where the Mac sits. The pointer moves to the Mac across that edge."] = "Kliknij miejsce obok tego monitora, w którym stoi Mac. Kursor przechodzi na Maca przez tę krawędź.",
        ["SCREEN LAYOUT"] = "UKŁAD EKRANÓW",
        ["This PC"] = "Ten komputer",
        ["POINTER HANDOFF"] = "PRZEJŚCIE KURSORA",
        ["With several monitors, the handoff uses the one furthest towards the chosen side."] = "Przy kilku monitorach przejście prowadzi przez ten, który jest najdalej po wybranej stronie.",
        ["Audio"] = "Dźwięk",
        ["Clipboard"] = "Schowek",
        ["Windows"] = "Okna",
        ["Mouse & keyboard"] = "Mysz i klawiatura",
        ["Audio from Mac"] = "Dźwięk z Maca",
        ["Shared clipboard"] = "Wspólny schowek",
        ["Move a window"] = "Przenieś okno",
        ["All set. Work as if it were one computer."] = "Wszystko gotowe. Pracuj jak na jednym komputerze.",
        ["Pairing and connection details"] = "Parowanie i szczegóły połączenia",
        ["Connection"] = "Połączenie",
        ["Settings"] = "Ustawienia",
        ["Diagnostics"] = "Dziennik",
        ["Clear"] = "Wyczyść",
        ["Connect your desk in three steps"] = "Połącz swoje biurko w trzech krokach",
        ["1. Open the app on your Mac.  2. Enter the pairing code below.  3. Select the discovered Mac and connect."] = "1. Uruchom aplikację na Macu.  2. Wpisz kod parowania poniżej.  3. Wybierz znalezionego Maca i połącz.",
        ["Got it"] = "Rozumiem",
        ["SECURE PAIRING"] = "BEZPIECZNE PAROWANIE",
        ["Enter the code shown on the Mac Connection page. The code is not stored in ordinary settings."] = "Przepisz kod widoczny w sekcji Połączenie na Macu. Kod nie jest zapisywany w zwykłych ustawieniach.",
        ["Save code"] = "Zapisz kod",
        ["This PC is paired"] = "Ten komputer jest sparowany",
        ["Protected"] = "Chronione",
        ["Forget"] = "Usuń zaufanie",
        ["MACS ON YOUR LOCAL NETWORK"] = "MAKI W SIECI LOKALNEJ",
        ["Seam must be running on the Mac. Select it below."] = "Na Macu musi działać Seam. Kliknij, aby wybrać adres.",
        ["No Mac found yet — enter its address manually below."] = "Nie znaleziono jeszcze żadnego Maca – wpisz adres ręcznie poniżej.",
        ["Mac IP address, e.g. 192.168.1.20"] = "Adres IP Maca, np. 192.168.1.20",
        ["Connect automatically"] = "Łącz automatycznie",
        ["Reconnect at startup and after a connection loss."] = "Przy starcie i po utracie połączenia próbuj ponownie.",
        ["STATUS"] = "STAN",
        ["Pointer"] = "Kursor",
        ["Show it whenever you control the Mac"] = "Pokazuj go przez cały czas sterowania Makiem",
        ["Mac windows only"] = "Tylko okna Maca",
        ["Mac windows sit on the Windows desktop next to Windows apps. Off: the whole Mac desktop fills the monitor."] = "Okna Maca leżą na pulpicie Windows obok zwykłych okien. Wyłączone: cały pulpit Maca na monitorze.",
        ["Full desktop only. Off: the Mac desktop appears only when you drag a window onto it."] = "Tylko dla całego pulpitu. Wyłączone: pulpit Maca pojawia się dopiero, gdy przeciągniesz na niego okno.",
        ["One-time install of the free, signed Virtual Display Driver (requires administrator approval)."] = "Jednorazowa instalacja darmowego, podpisanego sterownika Virtual Display Driver (wymaga zgody administratora).",
        ["Restart"] = "Uruchom ponownie",
        ["Share keyboard and mouse"] = "Udostępniaj klawiaturę i mysz",
        ["Pointer speed on Mac"] = "Czułość myszy na Macu",
        ["Hide the Windows pointer while controlling Mac"] = "Ukrywaj kursor podczas sterowania Makiem",
        ["The Windows pointer stays at the exit edge and is hidden."] = "Kursor zostaje przy krawędzi, przez którą wyszedł, i znika pod niewidocznym oknem.",
        ["Play audio from Mac"] = "Odbieraj dźwięk z Maca",
        ["Output device"] = "Urządzenie wyjściowe",
        ["Headphones or speakers connected to Windows."] = "Słuchawki lub głośniki podłączone do Windowsa.",
        ["Refresh devices"] = "Odśwież listę urządzeń",
        ["Network buffer"] = "Bufor sieciowy",
        ["WASAPI exclusive mode"] = "Tryb WASAPI exclusive",
        ["Lowest latency, but reserves the device. Falls back to shared mode when unavailable."] = "Najniższe opóźnienie, ale blokuje kartę dla innych aplikacji. Przy braku wsparcia wraca do shared.",
        ["GENERAL"] = "OGÓLNE",
        ["This PC name"] = "Nazwa tego komputera",
        ["Shown in the Mac app."] = "Widoczna w aplikacji na Macu.",
        ["Mac TCP port"] = "Port TCP Maca",
        ["Default 47800 — must match the Mac setting."] = "Domyślnie 47800 – musi zgadzać się z ustawieniem na Macu.",
        ["Audio UDP port on this PC"] = "Port UDP audio (ten komputer)",
        ["Default 47802. Windows Firewall must allow it."] = "Domyślnie 47802. Zapora Windows musi go przepuszczać.",
        ["STARTUP"] = "URUCHAMIANIE",
        ["Launch at sign-in"] = "Uruchamiaj przy logowaniu",
        ["Start minimized to tray"] = "Startuj zminimalizowany do zasobnika",
        ["Keep the window hidden at startup; use the tray icon to open it."] = "Przy autostarcie okno pozostaje ukryte; kliknij ikonę w zasobniku, aby je otworzyć.",
        ["UPDATES"] = "AKTUALIZACJE",
        ["Check now"] = "Sprawdź teraz",
        ["Install"] = "Zainstaluj",
        ["Install and restart"] = "Zainstaluj i uruchom ponownie",
        ["Check automatically"] = "Sprawdzaj automatycznie",
        ["At startup and every six hours through GitHub Releases."] = "Po starcie i co 6 godzin, przez GitHub Releases.",
        ["Update available"] = "Dostępna aktualizacja",
        ["Mac accessibility permission is missing"] = "Mac nie ma uprawnienia Dostępność",
        ["Control will not work until Seam has Accessibility permission in Mac System Settings (Privacy & Security, Accessibility)."] = "Sterowanie nie zadziała, dopóki na Macu nie nadasz Seam uprawnienia w Ustawieniach systemowych (Prywatność i ochrona, sekcja Dostępność).",
    };

    public static void Apply(Control root)
    {
        if (!IsPolish) return;
        Translate(root);
        foreach (var control in root.GetLogicalDescendants().OfType<Control>()) Translate(control);
    }

    private static void Translate(Control control)
    {
        if (control is TextBlock text && text.Text is { } value && Polish.TryGetValue(value, out var translatedText))
            text.Text = translatedText;
        if (control is SettingRow row)
        {
            if (Polish.TryGetValue(row.Title ?? "", out var title)) row.Title = title;
            if (Polish.TryGetValue(row.Subtitle ?? "", out var subtitle)) row.Subtitle = subtitle;
        }
        if (control is ContentControl content && content.Content is string label && Polish.TryGetValue(label, out var translatedContent))
            content.Content = translatedContent;
        if (control is Expander expander && expander.Header is string header && Polish.TryGetValue(header, out var translatedHeader))
            expander.Header = translatedHeader;
        var accessibleName = Avalonia.Automation.AutomationProperties.GetName(control);
        if (accessibleName is not null && Polish.TryGetValue(accessibleName, out var translatedName))
            Avalonia.Automation.AutomationProperties.SetName(control, translatedName);
        if (control is TextBox box && box.Watermark is string watermark && Polish.TryGetValue(watermark, out var translatedWatermark))
            box.Watermark = translatedWatermark;
        if (control is InfoBar info)
        {
            if (Polish.TryGetValue(info.Title ?? "", out var title)) info.Title = title;
            if (Polish.TryGetValue(info.Message ?? "", out var message)) info.Message = message;
        }
        if (ToolTip.GetTip(control) is string tip && Polish.TryGetValue(tip, out var translatedTip))
            ToolTip.SetTip(control, translatedTip);
    }
}
