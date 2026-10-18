Wspólne wydanie testowe macOS (Apple Silicon i Intel) oraz Windows x64.

## Nowe w 2.1.16 — interfejs seam

- Wspólny grafitowy ekran główny macOS i Windows z grafiką szklanych okien.
- Osiem srebrnych ikon 3D i nowa ikona aplikacji.
- Okrągły status połączenia wystający poza dolną krawędź okna. Kliknięcie otwiera szczegóły połączenia; rozłączenie pozostaje osobną akcją.
- Szybkie przełączniki myszy i klawiatury, dźwięku oraz schowka; osobne sekcje Dźwięk, Schowek i Okna.
- Natywne kontrolki SwiftUI na macOS i kontrolki Fluent na Windowsie.
- Zachowane poprawki przesyłania okien z wersji 2.1.15. Identyfikator aplikacji, protokół parowania i klucze aktualizacji pozostają zgodne z poprzednim wydaniem.

To wydanie służy testom na obu komputerach. Szczególnie prosimy sprawdzić przesuwanie, minimalizowanie i przywracanie okna ze wskaźnikiem statusu, monitory o różnym DPI oraz pełny ekran.

## Aktualizacja

Aplikacje z kanału testowego `dev` wykryją tę wersję przez autoupdater: kontrola co 2 minuty, instalacja przy włączonych aktualizacjach podczas bezczynności. Można też użyć „Sprawdź teraz” w Ustawieniach. Wersje z kanału stabilnego wymagają jednorazowego zainstalowania załączonej wersji testowej.

Oba pliki mają sumy SHA-256 i podpisy ECDSA. Mac zachowuje stały podpis wydawcy. Darmowa beta nie ma notarizacji Apple ani publicznie zaufanego Authenticode; pierwsze uruchomienie może wymagać potwierdzenia systemowego. Nie wyłączaj globalnie Gatekeepera ani SmartScreen.
