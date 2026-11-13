# Serwer licencji Seam Pro

Cloudflare Worker z bazą D1 pod `https://api.seamdesk.app`. Wydaje klucze po zakupie w Stripe, pilnuje limitu
3 komputerów na klucz i odpowiada aplikacjom na aktywację, walidację (co ~7 dni) i dezaktywację. Bez zależności
npm: podpis webhooków Stripe to HMAC-SHA256 z Web Crypto, maile idą przez API Resend.

```
Stripe Payment Link ──zapłata──▶ webhook /v1/stripe/webhook ──▶ D1: licenses ──▶ mail z kluczem (Resend)
        │ przekierowanie                                            ▲
        ▼                                                           │
seamdesk.app/license/?session_id=cs_… ── GET /v1/checkout/cs_… ─────┘   (klucz od razu na stronie)
Seam (Mac/Windows) ── POST /v1/licenses/activate | validate | deactivate ──▶ D1: instances
```

## API

| Metoda i ścieżka | Kto woła | Co robi |
|---|---|---|
| `POST /v1/licenses/activate` `{license_key, instance_name}` | aplikacje | zajmuje miejsce (ta sama nazwa komputera wraca na swoje), 403 `device_limit` / `license_disabled`, 404 `invalid_key` |
| `POST /v1/licenses/validate` `{license_key, instance_id}` | aplikacje | `valid` + `license.status`; `valid: false` przy statusie `active` = komputer dezaktywowany gdzie indziej |
| `POST /v1/licenses/deactivate` `{license_key, instance_id}` | aplikacje | zwalnia miejsce (powtórka też zwraca sukces) |
| `GET /v1/checkout/cs_…` | `site/license.js` | klucz zakupu z tej sesji Stripe; 404 `pending`, dopóki webhook nie dojdzie |
| `POST /v1/licenses/resend` `{email, lang}` | `site/license.js` | wysyła wszystkie aktywne klucze adresu (raz na 10 min); zawsze `{sent: true}` |
| `POST /v1/stripe/webhook` | Stripe | `checkout.session.completed` (opłacone lub kod 100%), `checkout.session.async_payment_succeeded`, `charge.refunded` (pełny zwrot), `charge.dispute.created` |

Kształt odpowiedzi i to, jak czytają je aplikacje: `tests/fixtures/license-api.json` (testy serwera, Maca i Windows
sprawdzają te same wektory). Klucze: `SEAM-XXXXX-XXXXX-XXXXX-XXXXX`, alfabet Crockforda (100 bitów); wielkość liter,
spacje, O/0 i I/L/1 nie mają znaczenia przy wpisywaniu.

**Tryb testowy:** zakup w trybie testowym Stripe (karta `4242 4242 4242 4242`) daje licencję z `test: true`. Przyjmują
ją tylko buildy kanału dev (`LicenseConfig.acceptsTestLicenses`). Sekret webhooka testowego nie wyda licencji live.

## Testy

```sh
cd license-server && npm test     # node:test + node:sqlite (Node 22.13+), te same migracje co D1
```

## Uruchomienie (raz)

### 1. Stripe

1. Konto Stripe dla działalności w Polsce. **Settings → Managed Payments**: włącz (Stripe zostaje sprzedawcą, liczy
   i odprowadza VAT, wystawia potwierdzenia).
2. **Product catalog → Add product**: „Seam Pro”, cena jednorazowa **10 USD**, kod podatkowy z listy dozwolonych dla
   Managed Payments (oprogramowanie do pobrania).
3. **Coupons**: kupon 50% z kodem promocyjnym `BETA50` (dla dawnych testerów, `LicenseManager.testerCoupon`).
4. **Payment Links → New**: produkt Seam Pro, Managed Payments włączone, „Allow promotion codes”, **After payment →
   Redirect** na `https://seamdesk.app/license/?session_id={CHECKOUT_SESSION_ID}`.
5. To samo w **trybie testowym** (przełącznik Test mode): produkt, kupon, Payment Link z tym samym przekierowaniem.
6. **Developers → Webhooks → Add endpoint** (osobno w live i w test): `https://api.seamdesk.app/v1/stripe/webhook`,
   zdarzenia `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `charge.refunded`,
   `charge.dispute.created`. Zapisz oba sekrety `whsec_…`.

### 2. Resend (maile z kluczem)

Konto na resend.com → **Domains → Add domain** `seamdesk.app` → rekordy DNS dodaj w Cloudflare (strefa seamdesk.app)
→ **API Keys** → klucz z uprawnieniem „Sending access”. Nadawca: `EMAIL_FROM` w `wrangler.jsonc`
(`license@seamdesk.app`); odpowiedzi trafiają na `SUPPORT_EMAIL`. Bez klucza Resend serwer działa, ale klucz widać
tylko na stronie /license/ zaraz po zakupie.

### 3. Cloudflare

```sh
cd license-server
npx wrangler login
npx wrangler d1 create seam-licenses          # wpisz database_id do wrangler.jsonc (zamiast PLACEHOLDER)
npx wrangler d1 migrations apply seam-licenses --remote
npx wrangler deploy                           # pierwsze wdrożenie; tworzy też domenę api.seamdesk.app
npx wrangler secret put STRIPE_WEBHOOK_SECRET        # whsec_… z trybu live
npx wrangler secret put STRIPE_WEBHOOK_SECRET_TEST   # whsec_… z trybu test
npx wrangler secret put RESEND_API_KEY
```

Dalej wdraża CI (`.github/workflows/license-server.yml`): testy, `d1 migrations apply --remote`, `deploy` przy pushu
zmian w `license-server/`. Token `CLOUDFLARE_API_TOKEN` w sekretach GitHub potrzebuje oprócz „Edit Cloudflare Workers”
uprawnienia **Account → D1 → Edit**. Dopóki `database_id` to placeholder, CI tylko testuje.

Opcjonalnie `PAYMENT_LINKS` w `wrangler.jsonc`: identyfikatory `plink_…` (live i test) po przecinku. Wtedy licencję
dają tylko te linki, gdyby na koncie Stripe pojawiły się inne produkty.

### 4. Strona i aplikacje

1. `site/checkout.js`: `PAYMENT_LINK` (live) i `TEST_PAYMENT_LINK` (test) → push wdraża stronę.
2. Test na kanale dev: `LicenseConfig.testSales = true` w `macos/Seam/Sources/Licensing/LicenseConfig.swift`
   i `windows/Seam/Licensing/LicenseClient.cs` → push na `feature/virtual-display` → w aplikacji dev „Buy Pro”,
   karta 4242…, klucz ze strony /license/ → Aktywuj na Macu i PC, Dezaktywuj, zwrot w Stripe (test) → po
   „Check now” licencja wyłączona.
3. Start sprzedaży: `liveSales = true` na obu platformach i wydanie (`docs/RELEASE.md`). Od tej wersji wydania
   blokują Pro po 7-dniowym okresie próbnym.

## Obsługa ręczna

```sh
cd license-server
# licencje klienta
npx wrangler d1 execute seam-licenses --remote --command "SELECT key, status, test, created_at FROM licenses WHERE email = 'kupujacy@example.com'"
# komputery na kluczu / wyzerowanie miejsc
npx wrangler d1 execute seam-licenses --remote --command "SELECT name, last_seen_at FROM instances WHERE license_key = 'SEAM-…'"
npx wrangler d1 execute seam-licenses --remote --command "DELETE FROM instances WHERE license_key = 'SEAM-…'"
# licencja bez zakupu (recenzent, wymiana); klucz: node -e "import('./src/keys.js').then(m => console.log(m.generateKey()))"
npx wrangler d1 execute seam-licenses --remote --command "INSERT INTO licenses (key, email, created_at, note) VALUES ('SEAM-…', 'osoba@example.com', datetime('now'), 'recenzja')"
```

Zwrot zrób w Stripe (Payments → Refund): webhook `charge.refunded` sam wyłączy licencję. Ręcznie:
`UPDATE licenses SET status = 'disabled' WHERE key = 'SEAM-…'`.
