Wspólne wydanie testowe macOS (Apple Silicon i Intel) oraz Windows x64.

## Nowe w 2.1.21 — zakładka Okna

- Nowy, przewijany widok pokazuje działanie drugiego urządzenia jako dodatkowego monitora: przeciągasz dowolne okno za wspólną krawędź ekranów.
- Duża wizualizacja przejścia, instrukcja w trzech krokach, podgląd układu ekranów i przeniesienia okna z powrotem. macOS ma także przycisk odtwarzający przykład.
- Dwa nowe tła ekranów, dołączone do aplikacji; okna, strzałki i podpisy są rysowane natywnie.
- Grafiki reagują na położenie ekranów po lewej, po prawej, nad i pod drugim urządzeniem. Na Macu bez aktywnego drugiego ekranu układ jest oznaczony jako przykład.
- Działające przełączniki i statusy, komunikaty o wymaganych uprawnieniach oraz skrócony pasek boczny. Windows zachowuje osobne przełączniki obu kierunków, instalację sterownika, restart i opcje wyświetlania.
- Mechanizm przenoszenia okien i protokół pozostają zgodne z 2.1.20.

## Aktualizacja

Aplikacje z kanału testowego `dev` wykryją tę wersję przez autoupdater: kontrola co 2 minuty, instalacja przy włączonych aktualizacjach podczas bezczynności. Można też użyć „Sprawdź teraz” w Ustawieniach. Wersje z kanału stabilnego wymagają jednorazowego zainstalowania załączonej wersji testowej.

Oba pliki mają sumy SHA-256 i podpisy ECDSA. Mac zachowuje stały podpis wydawcy. Darmowa beta nie ma notarizacji Apple ani publicznie zaufanego Authenticode; pierwsze uruchomienie może wymagać potwierdzenia systemowego. Nie wyłączaj globalnie Gatekeepera ani SmartScreen.
