Wspólne wydanie testowe macOS (Apple Silicon i Intel) oraz Windows x64.

- Usunięta przezroczysta szczelina pod paskiem tytułu okien Maca na Windowsie: natywne menu odzyskało powierzchnię rysowania.
- Natywna ramka, przyciski, menu, Snap i obsługa DPI dla okien Maca na Windowsie.
- Zachowanie proporcji i przekazywanie zmiany rozmiaru do aplikacji na Macu.
- Poprawki położenia okien między monitorami, popupów i pełnoekranowego wideo.
- Poprawki synchronizacji klatek po zmianie rozmiaru i przeciążeniu dekodera.
- Wspólny kanał testowy: obie aplikacje sprawdzają aktualizacje co 2 minuty i instalują je podczas bezczynności. Przeniesione okna i zdalne sterowanie opóźniają automatyczny restart.

Windows 2.1.4 z kanału testowego pobierze to wydanie automatycznie przy włączonych aktualizacjach. Starszy Mac, który pokazuje 1.0 i sprawdza wyłącznie wydania stabilne, wymaga jednorazowej instalacji załączonego ZIP-a; kolejne wydania testowe zainstalują się już automatycznie.

Oba pliki mają sumy SHA-256 i podpisy ECDSA. Mac zachowuje stały podpis wydawcy. Darmowa beta nie ma notarizacji Apple ani publicznie zaufanego Authenticode; pierwsze uruchomienie może wymagać potwierdzenia systemowego. Nie wyłączaj globalnie Gatekeepera ani SmartScreen.
