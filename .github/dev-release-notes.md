Wspólne wydanie testowe macOS (Apple Silicon i Intel) oraz Windows x64.

- Okna Windows na Macu: monitor wirtualny obejmuje tylko użyteczną część ekranu (bez paska menu i Docka), więc zmaksymalizowane okno nie gubi już kursora ani najechania.
- Naprawiony błąd NullReferenceException, który zatrzymywał strumień okien Windows na Macu; błąd jednego okna nie przerywa już pozostałych.
- Nowe przenoszenie okien Windows na Maca: każde okno ma własny strumień (Windows.Graphics.Capture, sprzętowy koder H.264), położenie idzie osobno od obrazu, a wirtualny monitor ma rozdzielczość Retina ze skalowaniem 200%. Koniec z tapetą przy krawędziach i rozmytym obrazem.
- Ostrzejsze okna Maca na Windowsie przy skalowaniu poniżej 150%: wirtualny monitor rysuje w HiDPI 2×, a obraz jest zmniejszany na Macu do pikseli monitora Windows.
- Menu aplikacji Maca na Windowsie przeniesione do paska tytułu, obok tytułu okna, na tle Mica; przyciski okna i Snap nadal systemowe.
- Poprawione rozpoznawanie podpowiedzi adresu i panelu rozszerzeń Chrome: popupy nie dostają osobnego paska tytułu, menu ani pozycji na pasku zadań.
- Zamknięte popupy są od razu usuwane, również przy zmaksymalizowanej przeglądarce. Kliknięcie popupu nie próbuje już aktywować go jako głównego okna.
- Usunięta przezroczysta szczelina pod paskiem tytułu okien Maca na Windowsie: natywne menu odzyskało powierzchnię rysowania.
- Natywna ramka, przyciski, menu, Snap i obsługa DPI dla okien Maca na Windowsie.
- Zachowanie proporcji i przekazywanie zmiany rozmiaru do aplikacji na Macu.
- Poprawki położenia okien między monitorami, popupów i pełnoekranowego wideo.
- Poprawki synchronizacji klatek po zmianie rozmiaru i przeciążeniu dekodera.
- Wspólny kanał testowy: obie aplikacje sprawdzają aktualizacje co 2 minuty i instalują je podczas bezczynności. Przeniesione okna i zdalne sterowanie opóźniają automatyczny restart.

Windows 2.1.4 z kanału testowego pobierze to wydanie automatycznie przy włączonych aktualizacjach. Starszy Mac, który pokazuje 1.0 i sprawdza wyłącznie wydania stabilne, wymaga jednorazowej instalacji załączonego ZIP-a; kolejne wydania testowe zainstalują się już automatycznie.

Oba pliki mają sumy SHA-256 i podpisy ECDSA. Mac zachowuje stały podpis wydawcy. Darmowa beta nie ma notarizacji Apple ani publicznie zaufanego Authenticode; pierwsze uruchomienie może wymagać potwierdzenia systemowego. Nie wyłączaj globalnie Gatekeepera ani SmartScreen.
