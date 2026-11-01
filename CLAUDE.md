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
bash macos/tests/license-check.sh
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

- Angielski jest językiem źródłowym, polski tłumaczeniem. Swift: `L10n.text("English", pl: "Polski")`, a literały
  w `Text`/`Button`/komponentach z `LocalizedStringKey` po angielsku z tłumaczeniem w
  `macos/Seam/Resources/pl.lproj/Localizable.strings`; język wybiera się w Ustawieniach → Ogólne (`L10n.language`).
  Windows: C# `T("English", pl: "Polski")`, XAML po angielsku z polskim odpowiednikiem w słowniku
  `windows/Seam/Localization/L10n.cs` (ClipboardChecks pilnuje, by żadnego nie brakowało); język w Ustawieniach
  (`Settings.Language`). Powody w ramce REJECT to stałe protokołu (`RejectReason`), nie tłumaczymy ich.
- Komentarze w kodzie po polsku, zwięzłe; nazwy typów i API po angielsku.
- Wygląd obu aplikacji jest wspólny (ciemny grafit, srebrne ikony z `assets/seam/`, marka „seam” małymi literami).
  Windows (inspiracja: CleanMyMac): jedno tło pod paskiem tytułu, paskiem bocznym i treścią, szklane karty, pasek
  boczny z ikonami `nav-*` bez płytek, zaznaczenie w szklanej pigułce i kropka stanu na ikonie Połączenie.
  Kolory stron są wspólne dla obu platform. **Zielona jest tylko zakładka Okna** (zieleń liści,
  `hero-windows-laptop/-monitor/-window` składane w `WindowsHero`, `tile-windows-lime`, `OknaTokens` w `OknaStyle.swift`), **niebieska tylko
  zakładka Połączenie** (grafika `hero-connection`, kafelki `tile-*`, `ConnectionTokens` w `ConnectionStyle.swift`), **magentowa
  tylko Klawiatura i mysz** (`hero-control-mouse` + `hero-control-key`, `tile-input`, `ControlTokens` w `ControlStyle.swift`),
  **fioletowa tylko Dźwięk** (spokojny fiolet jak CleanMyMac: `hero-audio-headphones`, `tile-audio-violet`, `AudioTokens`
  w `AudioStyle.swift`), **bursztynowa tylko Schowek** (`hero-clipboard-board` + `-text` + `-photo` składane w `ClipboardHero`,
  `tile-clipboard-amber`, `ClipboardTokens` w `ClipboardStyle.swift`), **turkusowa tylko Ekrany** (tylko Windows: `PageTheme.Teal`,
  przeciągany układ `ScreenArrangement`); reszta (Ustawienia, Dziennik) grafitowa. Ustawienia na obu platformach są
  w osobnym oknie (Mac: scena `Settings`, `SettingsWindow.swift`; Windows: `Views/SettingsWindow.axaml` + panele `SettingsPage.Show`).
  Mac: karty `TintedGlassCard`, kula Połączono pod oknem w kolorze strony (`ConnectionStatusButton.Accent`).
  Windows: te same tokeny w `Views/PageTheme.cs` (kolor strony z `PageTheme.ForTag`, `Apply` podmienia zasoby kart, tekstu
  i przełączników strony), tła w `SeamBackdrop.PageColor`, kula `StatusOrb` na dole treści (strony mają pod nią margines 110),
  grafiki `AudioWave`/`AudioBarMeter` (`AudioArt.cs`), `ClipboardHero` i `WindowsHero.axaml`; przyciski Pro
  `ProPrimaryButton`/`ProGlassButton`/`LinkButton` (Theme.axaml); strony `ControlPage`, `AudioPage`, `ClipboardPage`.
  Zmieniając kolor strony, zmień oba pliki (`*Style.swift` i `PageTheme.cs`). Styl kolorowych grafik: błyszczące szkło 3D w gradiencie (prompty w `assets/seam/hero-prompts.txt`).
  Pasek boczny: jedna strona na sekcję, każda strona funkcji zaczyna się kartą z głównym przełącznikiem.
  Użytkownik odrzucił: podzakładki na stronach i `SettingsExpander` (Windows).
- Najpierw makieta/zrzut do akceptacji przy większych zmianach UI; użytkownik ocenia wygląd ze zrzutów.
- **Seam Pro** (płatne funkcje): dźwięk, okna w obie strony, obrazy w schowku; za darmo klawiatura, mysz i tekst.
  Logika uprawnień `Licensing/Entitlement.swift` ↔ `Licensing/Entitlement.cs` (wspólne wektory
  `tests/fixtures/entitlement.json`), licencja w Lemon Squeezy (`LicenseConfig`: dopóki `storeID`/`productID` = 0,
  blokady są wyłączone). Pro działa, gdy uprawniona jest którakolwiek strona pary (STATUS bajt 1 bit 1 i `PEER_STATUS`).
  Nową funkcję płatną blokuj po obu stronach (nadawca i odbiorca) i pokaż na jej stronie `ProGateCard`.
  Podgląd stanów: Mac `--ui-license free|trial|expired|pro`, Windows `--screenshot-license …`.
