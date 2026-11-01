# Landing page seam

Statyczna strona bez kroku budowania (HTML, CSS, JS, `assets/` w webp). Plan treści i decyzje:
[docs/LANDING-PLAN.md](../docs/LANDING-PLAN.md); plan wydania komercyjnego 3.0 (Faza 4) opisuje wersje językowe, cennik
i deploy. Źródła PNG i prompty: `assets/landing/`; obiekty funkcji i ikona pochodzą z `assets/seam/`.

Podgląd lokalny:

```sh
python3 -m http.server 4173 --directory site
```

## Struktura

| Ścieżka | Co to |
|---|---|
| `index.html` | strona główna po angielsku (język główny) |
| `pl/index.html` | ta sama strona po polsku; wspólne CSS/JS/assety przez `../` |
| `legal/{privacy,eula,refunds,imprint}/index.html` | dokumenty prawne EN (adresy `/legal/eula/` itd.) |
| `pl/legal/.../index.html` | dokumenty prawne PL |
| `styles.css`, `nav.css`, `gallery.css`, `legal.css` | style; `legal.css` tylko na stronach prawnych i 404 |
| `main.js`, `nav.js`, `gallery.js` | zachowanie strony głównej; teksty dla czytników ekranu wg `<html lang>` |
| `lang.js` | przełącznik EN/PL i podpowiedź „Polska wersja?” |
| `checkout.js` | przycisk „Buy Pro” → nakładka Lemon Squeezy |
| `fonts/` | Inter (zmienna grubość, łacina + łacina rozszerzona) z `@fontsource-variable/inter` 5.3.0, licencja `OFL.txt` |
| `404.html` | strona błędu Cloudflare; ścieżki od korzenia, bo podawana pod dowolnym adresem |
| `_headers` | nagłówki bezpieczeństwa i cache czcionek (Cloudflare czyta, nie publikuje) |
| `wrangler.jsonc`, `.assetsignore` | deploy na Cloudflare Workers (static assets) |

Wszystkie odnośniki między stronami są względne, więc strona działa z `python3 -m http.server` i pod dowolną
domeną. Wyjątek: `canonical`, `hreflang` i `og:url` muszą mieć pełny adres.

## Wersje językowe

- Angielski pod `/`, polski pod `/pl/`, bez automatycznego przekierowania. Każda strona ma `hreflang` (en, pl,
  x-default) i przełącznik EN/PL na końcu nawigacji oraz w stopce.
- `lang.js`: na angielskiej stronie, gdy `navigator.languages` zawiera polski, u dołu pojawia się pigułka
  „Polska wersja? / Przejdź na polski / ×”. Wybór (przełącznik, przejście, zamknięcie) trafia do
  `localStorage["seam-lang"]` i podpowiedź już nie wraca. To jedyne, co strona zapisuje w przeglądarce.
- Kotwice: EN `#features #app #start #security #pricing #faq #download`, PL `#funkcje #aplikacja #start
  #bezpieczenstwo #cennik #pytania #pobierz`.
- Zmiana treści: popraw oba pliki (`index.html` i `pl/index.html`), układ jest identyczny linia w linię.

## Cennik i zakup

- Sekcja Pricing/Cennik: tabela Free vs Pro zgodna z podziałem w aplikacji (`LicenseSettingsPane.swift`,
  `ProGate.swift`): Free = klawiatura i mysz (+ układ ekranów) i tekst w schowku; Pro = obrazy w schowku, dźwięk
  Maca, okna Maca na PC, aplikacje Windows na Macu. $10 jednorazowo, 7 dni próby, do 3 komputerów, jedna licencja
  na parę, offline do 30 dni. Na telefonie przyciski są pod tabelą (`.compare__mobile-cta`).
- `checkout.js` ma stałą `CHECKOUT_URL` (**placeholder**). Dopóki zawiera `PLACEHOLDER`, kliknięcie „Buy Pro”
  pokazuje tylko „The store opens with Seam 3.0.”. Po wstawieniu prawdziwego linku przycisk ładuje `lemon.js`
  z `app.lemonsqueezy.com` (dopiero po kliknięciu, nie przy wejściu na stronę) i otwiera nakładkę
  `LemonSqueezy.Url.Open(url?embed=1)`; po `Checkout.Success` pod przyciskiem pojawia się podziękowanie. Gdy skrypt
  się nie załaduje, przeglądarka przechodzi do zwykłej strony checkoutu.

## Pobieranie

Przyciski wskazują `github.com/pkozubski/seam-releases/releases/latest/download/Seam-macOS.zip` i
`Seam-Windows-x64.exe` (publiczne repo wydań). Główny przycisk w hero wybiera `main.js` według systemu
odwiedzającego. Strona nie linkuje do repo źródłowego (będzie prywatne): dokumenty są w `legal/`, lista zmian
to strona wydań w `seam-releases`.

Zrzuty aplikacji w `assets/app-*.webp` pochodzą z `Seam --ui-preview <plik> --ui-section <sekcja>`; po zmianach
wyglądu aplikacji zrób je ponownie i przekonwertuj (maks. 1600 px szerokości). Na razie są polskie na obu wersjach.

## Strony prawne

Treść na bazie `docs/EULA-DRAFT.md` i `PRIVACY.md` (zaktualizowana o licencjonowanie). Pola do uzupełnienia przez
prawnika lub sprzedawcę są w `<mark class="todo">[…]</mark>` (żółte), a nad treścią jest ramka „Draft for legal
review” (`.legal__draft`, komentarz `TODO(launch)`). Po akceptacji usuń ramkę i znaczniki w obu językach.

## Deploy (Cloudflare Workers, static assets)

- `wrangler.jsonc`: worker `seam-site`, `assets.directory: "."`, `html_handling: "auto-trailing-slash"`
  (`/legal/eula` → `/legal/eula/`), `not_found_handling: "404-page"`. Bez skryptu Workera.
- `.assetsignore` pomija `wrangler.jsonc`, `README.md`, `.wrangler/`.
- `.github/workflows/site.yml`: `cloudflare/wrangler-action` uruchamia `wrangler deploy` w `site/` przy pushu na
  `main` ze zmianami w `site/**` (albo ręcznie). Sekrety: `CLOUDFLARE_API_TOKEN` (szablon „Edit Cloudflare
  Workers”), opcjonalnie `CLOUDFLARE_ACCOUNT_ID`.
- Sprawdzenie konfiguracji bez wysyłki: `cd site && npx wrangler deploy --dry-run` (potem usuń `site/.wrangler/`).

## Do uzupełnienia przed startem (`grep -rn "TODO(launch)\|seam.example\|PLACEHOLDER" site`)

1. `seam.example` → docelowa domena (canonical, hreflang, og:url, `support@seam.example`), trasa w `wrangler.jsonc`.
2. `CHECKOUT_URL` w `checkout.js` (ten sam link co `LicenseConfig.checkoutURL` w aplikacjach).
3. Pola `[…]` na stronach prawnych (sprzedawca, kontakt, okres zwrotu, prawo właściwe, rękojmia).
4. FAQ „Will macOS or Windows warn me…” mówi o podpisie Developer ID i Authenticode: prawdziwe dopiero po Fazie 5.
5. Angielskie zrzuty aplikacji (`assets/app-*.webp`, `stage-scene.webp`, `step-pairing-photo.webp`).

## Galeria funkcji (`gallery.css`, `gallery.js`)

Jasna wersja galerii „Co go wyróżnia.” z apple.com/pl/iphone-18-pro (komponenty `MediaCardGallery` i
`MediaCardGalleryControl`). Klasy jak w oryginale; wartości odczytane z `overview.built.css` i `main.built.js`
(listopad 2026), kolory z wariantu jasnego (`body`, `.theme-light`). Ikony play/pauza/od nowa są własne.

| Element | Wyzwalacz | Efekt | Wartości |
|---|---|---|---|
| Szerokość kropek | `--autoplay-progress` = scrollLeft / przesunięcie jednego slajdu (ostatni slajd z własnego zakresu) | `min-width = (48 − 8) · min(1 − |indeks − postęp|, 1) · --progress-intro + 8` | aktywna 48 px (≤734: 32), kropka 8 px, odstęp 8+8 px |
| Pasek postępu | klasa `.current` na kropce | `::after` szerokość 0 → 115% (start −15%, min 15%) | `--autoplay-persist-duration` 6,15 s, linear; `paused`/`ended` zatrzymują |
| Zmiana slajdu | koniec czasu slajdu, kropka, klik w kartę, strzałki | `scrollLeft` do środka slajdu, snap wyłączony na czas animacji | 1 s easeInOutQuad; bieżący slajd zmienia się w połowie |
| Autoplay | wejście galerii w widok | po 6,15 s od końca przejścia następny slajd; po ostatnim stan `ended` | klik w kropkę/kartę lub gest = pauza |
| Podpis karty | `--autoplay-progress` − `--progress` karty | przesunięcie `ease · 120px · −0,45`, przezroczystość `1 − (1 − (1 − |Δ|)³)` | `--transition-ease-factor` 3 |
| Wejście pigułki | 60% galerii w oknie (`a0t − 100vh + 60a0h`) | kropla → kółko → pigułka, bańki zjeżdżają do pozycji, kropki wjeżdżają z prawej | sprężyny (masa 1, krok 1/60 s), czasy niżej |
| Pigułka przy przewijaniu | `position: sticky; bottom: 32px` (≤734: 20) | pigułka pływa nad kartami, w spoczynku 46 px pod nimi | kontener absolutny na całą sekcję, `margin-bottom` 120/80/56 |

Kolejność wejścia (s od startu): 0 `activated`, kropla scale 1,3→0,8 · 0,03 pasek y 180→0 (k100 d8) ·
0,05 kropla x −15→−28, szer. 30→56 · 0,15 wys. 80→56 · 0,3 tło kropek scale 1,3→1 (0,3 s, bez odbicia) ·
0,5 kropki x→0, szer. tła 40→pełna (k100 d10) · 0,52 kropla znika · 0,54 przycisk x→0, scale 0→1 (0,65 s) ·
0,7 wysokości teł 36→56 · 0,74+0,02·n kropka n x 36→0 (k200 d20), `--progress-intro` 0→1 · 1,0 `--alpha` 0→1
(tło z pełnego na 72% z rozmyciem 7 px). CSS: kropki opacity 100 ms po 740 ms, przycisk opacity 100 ms i scale
200 ms po 940 ms.

## Nawigacja z mega menu (`nav.css`, `nav.js`)

Układ i zachowanie globalnej nawigacji apple.com (`globalheader.css`, `globalheader.umd.js`, listopad 2026), wariant
jasny „scrim”. Klasy jak w oryginale (`#globalnav`, `globalnav-submenu-*`). Zmiany: pasek `position: fixed` (u Apple
absolute + osobny pasek lokalny), ikona i nazwa Seam zamiast logo Apple, na telefonie bez podmenu (linki prowadzą do
sekcji), krzyżyk przycisku menu robiony w CSS zamiast animacji SVG (ten sam czas .24s).

| Element | Wyzwalacz | Efekt | Wartości |
|---|---|---|---|
| Pasek | — | matowe tło | `rgba(250,250,252,.8)`, `saturate(180%) blur(20px)`, 44 px, linki 12 px |
| Otwarcie menu | najechanie na pozycję | opóźnienie, potem panel rośnie od 44 px do treść + 44 px | 120 ms; czas = min(480, max(240, wys. treści / 2)) ms, `cubic-bezier(.4,0,.6,1)` |
| Pozycje menu | otwarcie | z opacity 0 i −4 px | .32s, opóźnienie = grupa + nr pozycji · 20 ms + 80 ms; grupa = min(wyróżnione · 80 ms + reszta · 40 ms, nr grupy · 80 ms) |
| Zamknięcie | zjechanie z paska, przewinięcie, Esc, kurtyna | pozycje znikają, potem panel zjeżdża | pozycje min(.16s + 20 ms · (suma − nr), .24s); panel z opóźnieniem .12s |
| Zmiana menu | najechanie na inną pozycję | wysokość poprzednia → nowa, treść przenika | .12s |
| Kurtyna | menu otwarte | rozmycie strony | `rgba(232,232,237,.4)`, `blur(20px)`, .32s z opóźnieniem 80 ms |
| Telefon (≤ 833 px) | przycisk menu | panel na cały ekran, duże linki 28 px | czas = min(480, max(240, wys. okna / 2)) ms; linki .24s, opóźnienie .2s + nr · 20 ms |
