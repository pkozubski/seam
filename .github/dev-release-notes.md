Wspólne wydanie testowe macOS (Apple Silicon i Intel) oraz Windows x64.

## Nowe w 2.1.20 — ustawienia i aktualizacje (macOS)

- Ustawienia przejmują okno: panel boczny zamienia się w listę stron Ogólne, Aktualizacje i Zaawansowane, z wyszukiwarką i przyciskiem **Wstecz**. Otwiera je ⌘, albo „Ustawienia” w panelu bocznym, zamyka Esc.
- Strona Aktualizacje: przycisk wersji w nagłówku zmienia się w „Zaktualizuj i uruchom ponownie”, a podczas instalacji w pasek postępu.
- Pasek przechodzi przez pobieranie (z rozmiarem w MB), sprawdzanie podpisu i instalację, i nigdy się nie cofa.
- Po aktualizacji uruchomionej ręcznie aplikacja wraca na stronę Aktualizacje, dokańcza pasek i pokazuje, co się zmieniło.
- Kropka przy „Ustawieniach” oznacza czekającą aktualizację.
- Windows bez zmian względem 2.1.19, poza numerem wersji.

Nowy pasek pojawi się przy następnej aktualizacji: samo 2.1.20 instaluje się jeszcze dotychczasowym mechanizmem.

## 2.1.19 — osobne strony funkcji

- Każda sekcja panelu bocznego to osobna strona; „Sterowanie” nazywa się teraz „Klawiatura i mysz”.
- Strony funkcji zaczynają się kartą z głównym przełącznikiem i stanem na żywo.
- macOS: panel boczny podzielony na Funkcje i System; brakujące uprawnienie pokazuje baner z przyciskiem nadania.
- Windows: nowa strona Ekrany do ustawienia położenia Maca.

## Aktualizacja

Aplikacje z kanału testowego `dev` wykryją tę wersję przez autoupdater: kontrola co 2 minuty, instalacja przy włączonych aktualizacjach podczas bezczynności. Można też użyć „Sprawdź teraz” w Ustawieniach. Wersje z kanału stabilnego wymagają jednorazowego zainstalowania załączonej wersji testowej.

Oba pliki mają sumy SHA-256 i podpisy ECDSA. Mac zachowuje stały podpis wydawcy. Darmowa beta nie ma notarizacji Apple ani publicznie zaufanego Authenticode; pierwsze uruchomienie może wymagać potwierdzenia systemowego. Nie wyłączaj globalnie Gatekeepera ani SmartScreen.
