// Seam Pro: zakup przez Stripe Payment Link (Managed Payments, Stripe jest sprzedawcą). Bez skryptu Stripe na
// tej stronie: przycisk to zwykły link do checkout.stripe.com / buy.stripe.com. Po zapłacie Stripe przekierowuje na
// /license/?session_id=… (pl: /pl/license/), gdzie license.js pokazuje klucz z api.seamdesk.app.
// Aplikacje otwierają /buy/ (wydania) i /buy/?test (kanał dev), więc link zmienia się tylko tutaj.

// TODO(launch): Stripe → Payment Links → link produktu Seam Pro (tryb live) i ten sam w trybie testowym.
// W obu ustaw „After payment → Redirect” na https://seamdesk.app/license/?session_id={CHECKOUT_SESSION_ID}.
const PAYMENT_LINK = "https://buy.stripe.com/PLACEHOLDER-LIVE";
const TEST_PAYMENT_LINK = "https://buy.stripe.com/test_6oU00ialu1I1cP73vVfbq00";

(() => {
  const pl = document.documentElement.lang === "pl";
  const ready = link => !link.includes("PLACEHOLDER");

  /// Link Stripe w języku strony (Stripe Checkout przyjmuje ?locale=).
  const checkoutUrl = link => {
    const url = new URL(link);
    url.searchParams.set("locale", pl ? "pl" : "en");
    return url.href;
  };

  // Strona /buy/ (otwierana z aplikacji): od razu do Stripe.
  const redirect = document.querySelector("[data-buy-redirect]");
  if (redirect) {
    const link = new URLSearchParams(location.search).has("test") ? TEST_PAYMENT_LINK : PAYMENT_LINK;
    if (ready(link)) {
      location.replace(link); // bez locale: Stripe weźmie język przeglądarki
    } else {
      redirect.querySelector("[data-buy-soon]").hidden = false;
      redirect.querySelector("[data-buy-going]").hidden = true;
    }
    return;
  }

  const soon = pl ? "Sklep ruszy razem z Seam 3.0." : "The store opens with Seam 3.0.";
  document.querySelectorAll("[data-checkout]").forEach(button => {
    if (ready(PAYMENT_LINK)) {
      // bez JS przycisk prowadzi do cennika, z JS prosto do Stripe
      button.href = checkoutUrl(PAYMENT_LINK);
      return;
    }
    button.addEventListener("click", e => {
      e.preventDefault();
      document.querySelectorAll("[data-checkout-status]").forEach(el => { el.textContent = soon; el.hidden = false; });
    });
  });
})();
