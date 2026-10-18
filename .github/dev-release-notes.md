Wspólne wydanie testowe macOS (Apple Silicon i Intel) oraz Windows x64.

## Nowe w 2.1.17 — grafitowe tło i kafelki ikon (macOS)

- Okno ma jedno ciągłe grafitowe tło: chłodne światło od góry i delikatna poświata pod statusem połączenia. Pasek boczny jest lekko przyciemniony, a pasek tytułu przezroczysty.
- Ikony w pasku bocznym i przy przełącznikach stoją na grafitowych kafelkach z gradientem. Zaznaczona sekcja ma kafelek w kolorze akcentu.
- Wraca grafitowa ikona aplikacji z dwoma oknami z wersji 2.1.15. Ta sama ikona jest teraz logo w pasku bocznym.
- Windows bez zmian względem 2.1.16, poza numerem wersji.

Prosimy sprawdzić wygląd przy zmianie rozmiaru okna, ze zwiniętym paskiem bocznym i przy przewijaniu treści pod paskiem tytułu.

## Aktualizacja

Aplikacje z kanału testowego `dev` wykryją tę wersję przez autoupdater: kontrola co 2 minuty, instalacja przy włączonych aktualizacjach podczas bezczynności. Można też użyć „Sprawdź teraz” w Ustawieniach. Wersje z kanału stabilnego wymagają jednorazowego zainstalowania załączonej wersji testowej.

Oba pliki mają sumy SHA-256 i podpisy ECDSA. Mac zachowuje stały podpis wydawcy. Darmowa beta nie ma notarizacji Apple ani publicznie zaufanego Authenticode; pierwsze uruchomienie może wymagać potwierdzenia systemowego. Nie wyłączaj globalnie Gatekeepera ani SmartScreen.
