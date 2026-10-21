# Seam: zasady pracy z Claude Code

Seam (dawniej BorderlessMouse) łączy Maca i PC z Windowsem w sieci lokalnej: wspólna klawiatura i mysz, schowek,
dźwięk z Maca, okna i wirtualne ekrany w obie strony. Dwie natywne aplikacje mówią tym samym protokołem
([docs/PROTOCOL.md](docs/PROTOCOL.md)):

| Katalog | Platforma | Stos | Szczegóły |
|---|---|---|---|
| `macos/Seam/` | macOS 14.2+ | Swift + SwiftUI, build `swiftc` (bez Xcode) | [macos/CLAUDE.md](macos/CLAUDE.md) |
| `windows/Seam/` | Windows 10/11 x64 | .NET 8, Avalonia 11.3 + FluentAvalonia 2.4 | [windows/CLAUDE.md](windows/CLAUDE.md) |
| `windows/ClipboardChecks/` | obie | testy C# (protokół, schowek, okna, wideo) | |
| `tests/fixtures/` | obie | wspólne wektory protokołu (JSON) | |
| `assets/seam/` | obie | ikony, grafiki, prompty źródłowe | |

**Pracuj na tej platformie, na której działa dany kod.** Zmiany w aplikacji Windows rób i testuj na Windowsie,
zmiany w aplikacji Mac na Macu. Na drugim systemie projekt się kompiluje, ale nie da się tam uruchomić hooków,
WASAPI, Media Foundation ani ScreenCaptureKit.

## Pętla pracy

1. Przeczytaj plik CLAUDE.md platformy, na której pracujesz.
2. Zmiana kodu, potem build i testy (polecenia niżej).
3. **Zmiana w UI: zawsze zrób zrzut ekranu i obejrzyj go** (narzędzie Read na pliku PNG), zanim zgłosisz koniec.
   Windows: `pwsh windows/scripts/preview.ps1`. Mac: `macos/build/Seam.app/Contents/MacOS/Seam --ui-preview out.png`.
   Zrzuty zapisuj w `output/` (katalog jest w `.gitignore`).
4. Zmiana protokołu: zaktualizuj obie implementacje, `docs/PROTOCOL.md` i wektory w `tests/fixtures/`.
   Zachowaj zgodność wstecz (bity możliwości w STATUS), bo Mac i PC aktualizują się niezależnie.
5. Commit po angielsku, w trybie rozkazującym, jak w historii (`Keep transfer window proportions…`).
   Wpis w `CHANGELOG.md` dla zmian widocznych dla użytkownika.

## Build i testy

```sh
# Windows (PowerShell, z katalogu repo)
dotnet restore windows/ClipboardChecks/Seam.ClipboardChecks.csproj --locked-mode
dotnet build windows/Seam/Seam.csproj -c Release -warnaserror --no-restore
dotnet run --project windows/ClipboardChecks/Seam.ClipboardChecks.csproj -c Release --no-restore
dotnet run --project windows/ClipboardChecks/Seam.ClipboardChecks.csproj -c Release --no-restore -- --window-checks

# macOS
cd macos && ./build.sh            # → macos/build/Seam.app
bash macos/tests/clipboard-check.sh; bash macos/tests/window-check.sh
bash macos/tests/update-check.sh;    bash macos/tests/security-check.sh
```

CI (`.github/workflows/ci.yml`) robi to samo na `windows-latest` i `macos-26`.

## Identyfikatory, których NIE zmieniamy

Nazwa zmieniła się z BorderlessMouse na Seam w wersji 2.1.23. Te identyfikatory zostają, bo od nich zależą
zgody systemowe, zapisane ustawienia, sparowane urządzenia i aktualizacje już zainstalowanych kopii:

- bundle ID `com.borderlessmouse.mac` (zgody TCC, UserDefaults, podpis wydania), etykieta LaunchAgenta, logger;
- usługa Pęku kluczy `com.borderlessmouse.pairing`;
- napisy kryptograficzne `BorderlessMouse/v2/...` (HMAC, HKDF, entropia DPAPI) i wektory testowe z nazwą;
- Windows: `%APPDATA%\BorderlessMouse\` (settings.json, pairing.key), `%LOCALAPPDATA%\BorderlessMouse\` (crash.log),
  wartość autostartu `BorderlessMouse` w `HKCU\...\Run`;
- kopie artefaktów `BorderlessMouse-macOS.zip` / `BorderlessMouse-Windows-x64.exe` (+ `.sig`) w wydaniach
  oraz `Contents/Resources/BorderlessMouse.entitlements`: szukają ich updatery sprzed zmiany nazwy.

## Wydania i aktualizacje

- Repozytorium: https://github.com/pkozubski/seam (dawny adres przekierowuje).
- **Kanał testowy:** każdy push na `feature/virtual-display` uruchamia `dev-build.yml`, który publikuje wydanie
  `dev-build` (tytuł `Seam dev 2.1.<run>`). Aplikacje z kanału dev sprawdzają je co 2 minuty i instalują się same,
  więc po pushu wystarczy poczekać, bez ręcznego pobierania.
- **Stabilne:** `git tag v2.x.y && git push origin v2.x.y` → `release.yml`. Szczegóły w [docs/RELEASE.md](docs/RELEASE.md).
- Artefakty są podpisane kluczem ECDSA (`security/update-signing-public.pem`); klucz prywatny i certyfikat
  wydania Maca są tylko w sekretach GitHub (środowisko `production-release`). Nigdy nie commituj kluczy ani tokenów.

## Konwencje

- Interfejs po polsku z angielskim tłumaczeniem: Swift `L10n.text("pl", "en")`, C# `T("pl", "en")`; teksty
  w XAML są po polsku, a ich angielskie odpowiedniki są w słowniku w `windows/Seam/Localization/L10n.cs`.
- Komentarze w kodzie po polsku, zwięzłe; nazwy typów i API po angielsku.
- Wygląd obu aplikacji jest wspólny (ciemny grafit, srebrne ikony z `assets/seam/`, marka „seam” małymi literami).
  Windows (inspiracja: CleanMyMac): jedno tło pod paskiem tytułu, paskiem bocznym i treścią, szklane karty, pasek
  boczny z ikonami `nav-*` bez płytek, zaznaczenie w szklanej pigułce i kropka stanu na ikonie Połączenie.
  **Zielona jest tylko zakładka Okna** (tokeny z projektu w `WindowsPage.axaml`, `SeamBackdrop.IsGreen`), reszta grafitowa.
  Pasek boczny: jedna strona na sekcję, każda strona funkcji zaczyna się kartą z głównym przełącznikiem.
  Użytkownik odrzucił: podzakładki na stronach i `SettingsExpander` (Windows).
- Najpierw makieta/zrzut do akceptacji przy większych zmianach UI; użytkownik ocenia wygląd ze zrzutów.
