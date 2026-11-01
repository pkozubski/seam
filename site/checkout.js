// Seam Pro: checkout Lemon Squeezy w nakładce (lemon.js). Skrypt sklepu ładuje się dopiero po kliknięciu
// „Buy Pro”, więc samo wejście na stronę nie łączy się z nikim poza tą domeną (spójnie z polityką prywatności).

// TODO(launch): PLACEHOLDER. Wstaw link checkoutu produktu Seam Pro (Lemon Squeezy → Products → Share →
// Checkout URL). Ten sam link musi mieć aplikacja: LicenseConfig.checkoutURL (Mac) i odpowiednik na Windows.
const CHECKOUT_URL = "https://seam.lemonsqueezy.com/buy/PLACEHOLDER-SEAM-PRO-CHECKOUT";

(() => {
  const buttons = document.querySelectorAll("[data-checkout]");
  if (!buttons.length) return;
  const pl = document.documentElement.lang === "pl";
  const TEXT = pl
    ? { soon: "Sklep ruszy razem z Seam 3.0.", thanks: "Dziękujemy! Klucz licencji jest już w drodze na Twój e-mail. Wpisz go w Seam → Ustawienia → Licencja." }
    : { soon: "The store opens with Seam 3.0.", thanks: "Thank you! Your license key is on its way to your email. Enter it in Seam → Settings → License." };
  const placeholder = CHECKOUT_URL.includes("PLACEHOLDER");
  const url = new URL(CHECKOUT_URL);
  url.searchParams.set("embed", "1"); // nakładka zamiast pełnej strony sklepu

  const say = text => document.querySelectorAll("[data-checkout-status]").forEach(el => { el.textContent = text; el.hidden = false; });

  let loading = null;
  const loadLemon = () => loading ??= new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.src = "https://app.lemonsqueezy.com/js/lemon.js";
    script.defer = true;
    script.onload = () => {
      window.createLemonSqueezy?.();
      window.LemonSqueezy.Setup({ eventHandler: e => { if (e.event === "Checkout.Success") say(TEXT.thanks); } });
      resolve(window.LemonSqueezy);
    };
    script.onerror = reject;
    document.head.append(script);
  });

  buttons.forEach(button => {
    // bez JS link prowadzi do cennika; z JS do sklepu (nowa karta po Cmd/Ctrl-kliknięciu)
    if (!placeholder) button.href = CHECKOUT_URL;
    button.addEventListener("click", e => {
      if (e.metaKey || e.ctrlKey || e.shiftKey) return;
      e.preventDefault();
      if (placeholder) {
        console.warn("Seam: CHECKOUT_URL w checkout.js to jeszcze placeholder.");
        say(TEXT.soon);
        return;
      }
      loadLemon()
        .then(lemon => lemon.Url.Open(url.href))
        .catch(() => { location.href = CHECKOUT_URL; }); // zablokowany skrypt: zwykła strona checkoutu
    });
  });
})();
