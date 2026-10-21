Wspólne wydanie testowe macOS (Apple Silicon i Intel) oraz Windows x64.

## Nowe w 2.1.23: BorderlessMouse to teraz Seam

- Nowa nazwa aplikacji: `Seam.app` na Macu i `Seam.exe` na Windowsie, nowe repozytorium github.com/pkozubski/seam.
- Ustawienia, sparowanie, uprawnienia macOS i autostart zostają bez zmian, a zainstalowane wersje aktualizują się same.
- Na Macu aktualizacja zmienia nazwę `BorderlessMouse.app` na `Seam.app` przy kolejnej instalacji.
- Działanie aplikacji i protokół pozostają zgodne z 2.1.22.

## Aktualizacja

Aplikacje z kanału testowego `dev` wykryją tę wersję przez autoupdater: kontrola co 2 minuty, instalacja przy włączonych aktualizacjach podczas bezczynności. Można też użyć „Sprawdź teraz” w Ustawieniach. Wersje z kanału stabilnego wymagają jednorazowego zainstalowania załączonej wersji testowej.

Pliki `Seam-*` i ich kopie `BorderlessMouse-*` (dla wersji sprzed zmiany nazwy) mają sumy SHA-256 i podpisy ECDSA. Mac zachowuje stały podpis wydawcy. Darmowa beta nie ma notarizacji Apple ani publicznie zaufanego Authenticode; pierwsze uruchomienie może wymagać potwierdzenia systemowego. Nie wyłączaj globalnie Gatekeepera ani SmartScreen.
