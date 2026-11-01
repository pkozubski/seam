# Landing page seam: plan

## Cel strony

Jeden cel: **pobranie Seam na oba komputery**. Wszystko inne ma odpowiedzieć na trzy pytania, które zatrzymują
przed pobraniem:

1. **Co to robi?** Jedna klawiatura i mysz, wspólny schowek, dźwięk z Maca, okna w obie strony.
2. **Czy to dla mnie i czy łatwo zacząć?** Mac + PC w jednej sieci, trzy kroki, kod parowania.
3. **Czy mogę temu zaufać?** Tylko sieć lokalna, szyfrowanie, podpisane aktualizacje, bez konta i telemetrii.

Odbiorca: ktoś, kto ma na biurku Maca i PC z Windowsem (praca + granie, dev + design) i ma dość dwóch klawiatur.

## Co było nie tak w szkicu

| Problem | Decyzja |
|---|---|
| Ta sama grafika laptop + monitor 3 razy (hero, ekran w makiecie, karta Windows) | Hero: grafika na górze + scena w chmurach (urządzenia z prawdziwymi zrzutami); karta Windows bez niej |
| Pobieranie 4 razy (hero, sekcja Pobierz, „Gotowy na jedno biurko?”, stopka) | Hero + jedna sekcja Pobierz na końcu (scalona z finalnym CTA); w stopce tylko link |
| Bento funkcji i „Zobacz z bliska” pokazują tę samą mysz i te same treści | Bento = korzyść (3D obiekt + jedno zdanie + kierunek); „Zobacz z bliska” = **prawdziwe zrzuty aplikacji**, bez ponownego opisu |
| UI w makietach to grafika AI z nieczytelnym tekstem | Prawdziwe zrzuty z `--ui-preview` |
| Karta „Połączenie” w bento to nie funkcja, tylko krok konfiguracji | Treść przeniesiona do „Trzy kroki” (niebieski) |
| Odznaka „Bez sterowników” jest nieprawdziwa | Odznaki zostają pod sceną hero (decyzja po przeglądzie: scena + odznaki robią pierwsze wrażenie); „Bez sterowników” zastąpione „Tylko sieć lokalna” |
| Kroki 1-2-3 w kolorach niebieski / magenta / zielony mieszają kody kolorów funkcji | Wszystkie kroki niebieskie (kolor Połączenia) |
| FAQ porozrzucane schodkowo, część pytań dubluje Bezpieczeństwo | Jedna kolumna akordeonu, tylko pytania, których nie ma wyżej |
| Karty pobierania wyglądają jak dwa plany cenowe (biała vs niebieska) | Dwie równorzędne karty |

### Sprostowania faktów (wiarygodność)

- **„Bez sterowników”: usunięte.** Okna Windows na Macu instalują Virtual Display Driver (raz, za zgodą administratora).
- **„Za darmo”** → **„Bezpłatna beta”**: README zapowiada przyszłe wydanie komercyjne.
- **„Podpisane wydania”** → **„Podpisane aktualizacje”**: aktualizacje mają podpis ECDSA, ale aplikacje nie mają
  jeszcze Developer ID ani zaufanego podpisu Windows (system pokaże ostrzeżenie przy pierwszym uruchomieniu; mówi o tym FAQ).
- **„Kod źródłowy na GitHubie”** → **„Wydania na GitHubie”**: licencja jest zastrzeżona, „open source” byłoby nieprawdą.
- **„Nowość: okna w obie strony”** → z dopiskiem **beta** (README: eksperymentalne).
- Kierunki funkcji muszą być dokładne: sterowanie **Windows → Mac**, dźwięk **Mac → Windows**, schowek i okna **w obie strony**.

## Kolejność sekcji

Każda sekcja ma jedno zadanie. Kolor = funkcja (jak w aplikacji): niebieski Połączenie, magenta Klawiatura i mysz,
fiolet Dźwięk, bursztyn Schowek, zieleń Okna, grafit Bezpieczeństwo.

### 0. Nawigacja
`seam` · Funkcje · Jak zacząć · Bezpieczeństwo · Pytania · **[Pobierz]** (przewija do sekcji 6)

### 1. Hero: obietnica
- Tło: `bg-hero` (niebieskie niebo z wstęgami światła, chmury przechodzą w jasne tło strony).
- Grafika: `hero-devices` (laptop i monitor złączone szwem światła, kursor przechodzi przez krawędź). To jedyne miejsce tej grafiki.
- Pigułka: „Nowość (beta): okna w obie strony”
- H1: **Mac i PC. Jedno biurko.**
- Lead: Jedna klawiatura i mysz, wspólny schowek, dźwięk z Maca i okna w obie strony. W sieci lokalnej, bez konta.
- CTA: **Pobierz na Maca** / **Pobierz na Windows** (główny przycisk wg systemu odwiedzającego).
- Pod spodem: macOS 14.2+ · Windows 10/11 · bezpłatna beta
- Scena: `stage-scene` (jeden render: laptop i monitor pod kątem na świecącej tafli schowanej w chmurach, ekrany to
  prawdziwe zrzuty wklejone w perspektywie przez `assets/landing/compose_stage_scene.py`), wtopiona maską w niebo hero,
  pod spodem `stage-clouds`.
- Odznaki: Bez konta · Bez chmury · Tylko sieć lokalna · AES-256-GCM · Podpisane aktualizacje.

### 2. Funkcje: co dostajesz (galeria z pigułką, `#funkcje`)
Przewijana galeria kart z autoplayem i pigułką kropek (jasna wersja galerii „Co go wyróżnia.” z apple.com;
wartości i opis w [site/README.md](../site/README.md)). Treść kart jak niżej, podpis w lewym górnym rogu.

H2: **Biurko, którego brakowało Twojemu Macowi** · podtytuł: Cztery funkcje, jedna aplikacja na obu komputerach.

| Karta | Tło | Obiekt (z aplikacji) | Kierunek | Jedno zdanie |
|---|---|---|---|---|
| Klawiatura i mysz (duża) | `bg-input-magenta` | `hero-control-mouse` + `hero-control-key` | Windows → Mac | Kursor przechodzi przez krawędź ekranu. Ctrl działa jak ⌘, jeśli chcesz. |
| Schowek | `bg-clipboard-amber` | `hero-clipboard-board` + `-text` + `-photo` | w obie strony | Tekst, zdjęcia i zrzuty ekranu. Kopiujesz tu, wklejasz tam. |
| Dźwięk | `bg-audio-violet` | `hero-audio-headphones` | Mac → Windows | Cały dźwięk Maca w słuchawkach podłączonych do PC. |
| Okna (szeroka, beta) | `bg-windows-green` | `hero-windows-window` | w obie strony | Okna Maca na pasku zadań Windows, aplikacje Windows w Docku Maca. |

Bez mini-UI w kartach (przełączniki z makiety wyglądały na grafikę, nie na produkt).

### 3. Zobacz z bliska: dowód (`#aplikacja`)
H2: **Tak wygląda Seam** · podtytuł: Każda funkcja ma swoją stronę w aplikacji.
- Jedno okno aplikacji (prawdziwy zrzut z Maca), pod nim 4 kropki/zakładki: Klawiatura i mysz, Schowek, Dźwięk, Okna
  (ta sama kolejność co w bento).
- Bez akapitów opisu: tylko nazwa zakładki. Opisy są w sekcji 2.
- Pliki: `app-control`, `app-clipboard`, `app-audio`, `app-windows`. **`app-connection` nie wchodzi:** ma w środku
  tę samą grafikę laptop + monitor co hero, więc byłaby powtórzeniem. Zostaje jako zapas, np. na obrazek do udostępniania.

### 4. Jak zacząć (`#start`, niebieski)
H2: **Trzy kroki do jednego biurka** · podtytuł: Instalacja zajmuje minutę. Bez konta.
1. `step-download`: **Pobierz Seam** na Maca i na PC.
2. `step-pairing`: **Połącz kodem**: wpisz na Windowsie kod pokazany na Macu.
3. `step-cursor`: **Przesuń kursor** za krawędź ekranu i już jesteś na drugim komputerze.

### 5. Bezpieczeństwo (`#bezpieczenstwo`, grafit)
Tło `bg-security-graphite`, obiekt `security-lock`. H2: **Twoje dane nie wychodzą z domu.**
- Tylko sieć lokalna: bez serwerów, konta i chmury.
- Parowanie jednorazowym kodem; sekret w Pęku kluczy macOS i DPAPI Windows.
- Sterowanie, schowek i dźwięk szyfrowane AES-256-GCM, chronione przed powtórzeniem.
- Aktualizacje sprawdzane sumą SHA-256 i podpisem ECDSA.
- Bez reklam, analityki i telemetrii. Link: Polityka prywatności.

### 6. Pytania (`#pytania`)
Akordeon w jednej kolumnie:
- Czy działa przez Wi-Fi? (Tak; kabel daje najmniejsze opóźnienie.)
- Jakich uprawnień potrzebuje Mac? (Dostępność oraz Nagrywanie dźwięku systemowego; do okien także Nagrywanie ekranu.)
- Dlaczego system ostrzega przy pierwszym uruchomieniu? (Beta bez Developer ID / podpisu Windows; jak otworzyć bezpiecznie.)
- Co zrobić, gdy kursor zostanie na drugim ekranie? (Skrót Ctrl+Alt+Shift+B na Windowsie.)
- Jak działają aktualizacje? (Same, z weryfikacją podpisu; można wyłączyć.)
- Czy przeniosę okna między komputerami? (Tak, beta; aplikacje Windows na Macu wymagają jednorazowej instalacji wirtualnego monitora.)

### 7. Pobierz: jedyny finalny CTA (`#pobierz`)
Tło `bg-cta-clouds` (jasne chmury przechodzą w głęboki błękit stopki). Ikona aplikacji `seam-icon`.
H2: **Pobierz Seam na oba komputery** · Bezpłatna beta. Bez konta. Bez chmury.
Dwie równe karty:
- **macOS**: 14.2 lub nowszy · Apple Silicon i Intel · aktualizuje się sam → Pobierz na Maca (`Seam-macOS.zip`)
- **Windows**: 10 i 11 (x64) · jeden plik, bez instalatora · aktualizuje się sam → Pobierz na Windows (`Seam-Windows-x64.exe`)
Pod kartami: Wszystkie wydania i sumy kontrolne na GitHubie.

### 8. Stopka
Logo + „Mac i PC. Jedno biurko.” · Produkt (Funkcje, Pobierz, Zmiany) · Pomoc (Pytania, Zgłoś problem) ·
Informacje (Prywatność, Bezpieczeństwo, GitHub) · © 2026 Seam · ogromny napis „seam” na dole.

## Assety

Źródła PNG są w `assets/landing/`, wersje na stronę w `assets/landing/web/*.webp` (razem ok. 1 MB), a prompty
w `assets/landing/prompts.txt`. Obiekty funkcji i ikona pochodzą z `assets/seam/` (te same co w aplikacji, więc
strona i produkt wyglądają spójnie).

| Sekcja | Asset | Źródło | Samokontrola |
|---|---|---|---|
| Hero | `bg-hero` | nowy | **Wygenerowany drugi raz.** Za pierwszym razem chmury sięgały połowy wysokości i biały H1 leżał na białym. Teraz błękit zajmuje górne 75%. |
| Hero | `hero-devices` | nowy | OK: szew światła i kursor czytelne, bez logo marek, przezroczyste tło. |
| Funkcje | `bg-input-magenta`, `bg-clipboard-amber`, `bg-audio-violet`, `bg-windows-green` | nowe | OK w złożeniu z obiektami: lewa strona spokojna pod tekst; w zieleni pionowy szew świeci zza okna. |
| Funkcje | mysz + ⌘, schowek + karty, słuchawki, okno z kursorem | `assets/seam/hero-*` | OK, te same obiekty co w aplikacji. |
| Zobacz z bliska | `app/app-control`, `-clipboard`, `-audio`, `-windows` | prawdziwe zrzuty `--ui-preview` | OK. Dane przykładowe z trybu podglądu (MacBook Pro ↔ PC-BIURO, 192.168.1.42), bez prawdziwych adresów. |
| Jak zacząć | `step-download`, `step-pairing`, `step-cursor` | nowe | OK. Kod parowania pokazany kropkami, bez zmyślonych cyfr. |
| Bezpieczeństwo | `bg-security-graphite`, `security-lock` | nowe | OK. Kłódka bardziej srebrna niż szklana, pasuje do srebrnych ikon aplikacji. |
| Pobierz | `bg-cta-clouds` + `assets/seam/seam-icon.png` | nowy + istniejący | OK. H2 i przyciski w jasnym górnym pasie, stopka na głębokim błękicie. |

Uwagi do wdrożenia:
- Hero: tło przypięte do góry (`background-position: top`), lead zawinięty w 2 wiersze (maks. ok. 620 px), żeby nie
  dochodził do chmur po bokach.
- Brakuje obrazka do udostępniania (OG, 1200×630). Lepiej złożyć go w kodzie z `bg-hero`, `hero-devices` i
  nagłówka niż generować, bo tekst w grafice AI wychodzi niepewnie.
- Favicon i ikona: `assets/seam/seam-icon.png`.
