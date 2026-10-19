# Seam dla macOS: zasady dla Claude Code

Najpierw przeczytaj [../CLAUDE.md](../CLAUDE.md).

## Build

- `cd macos && ./build.sh` → `build/Seam.app`. Wystarczy `swiftc` z Command Line Tools; Xcode tylko opcjonalnie
  (`xcodegen generate`, projekt nie jest w repo). `xcodebuild` wymaga `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Wygląd zależy od SDK, z którym zlinkowano binarkę: SDK 26 daje szklane kontrolki Tahoe, starsze dają tryb
  kompatybilności. `build.sh` wybiera najnowszy SDK; CI wymusza `REQUIRE_SDK_MAJOR=26`.
- `APP_OUTPUT=/tmp/seam-preview.app ./build.sh` buduje osobny bundle, który nie podmienia działającej aplikacji.

## Podgląd UI

```sh
build/Seam.app/Contents/MacOS/Seam --ui-preview ../output/mac.png [--ui-section control] [--ui-settings general]
  [--ui-update <stan>] [--ui-onboarding] [--ui-menu] [--ui-light|--ui-dark] [--ui-compact] [--ui-full-windows]
```
Pokazuje prawdziwe okno przez około 1,5 s i robi zrzut (`UIPreview.swift`). Obejrzyj PNG narzędziem Read.

## Uprawnienia (TCC) i podpis

- Zgody (Dostępność, nagrywanie ekranu, nagrywanie dźwięku systemowego) są przypięte do podpisu. `build.sh` sam
  używa certyfikatu „Apple Development” z pęku kluczy, a gdy go nie ma, podpisuje ad hoc (zgody znikają po każdym buildzie).
- Kopia w `/Applications` ma podpis wydania (inny niż lokalny build): przełączanie się między nimi wymaga ponownych zgód,
  np. `tccutil reset AudioCapture com.borderlessmouse.mac`.
- Procesy uruchomione z terminala dziedziczą jego zgodę Dostępności: wstrzyknięte zdarzenia ruszają prawdziwym kursorem.
- `open -n -W --stdout f --stderr f build/Seam.app --args --display-selftest` uruchamia selftest jako aplikację
  (ze zgodą nagrywania ekranu), w przeciwieństwie do binarki odpalonej z terminala.
- Tap dźwięku (Core Audio process tap) blokuje się do odpowiedzi na systemowe okno zgody: nigdy nie uruchamiaj go w kolejce zdarzeń wejścia.
- Działająca zainstalowana kopia zajmuje port TCP 47800; nie zabijaj jej bez pytania.

## Zasady

- `NSApplication.shared`, nie `NSApp`, wewnątrz `App.init()` (tam `NSApp` jest nil).
- Prywatne `CGVirtualDisplay` jest słabo linkowane (`Sources/Display/CGVirtualDisplay.h`); aplikacja musi startować bez niego.
- Strony: `Sources/Views/*Page.swift`, sekcje paska bocznego w `SidebarSection`; macOS nie ma strony Ekrany
  (położenie Maca ustawia Windows).
