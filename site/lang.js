// Język strony: przełącznik EN/PL zapamiętuje wybór, a angielska strona podpowiada polską wersję
// osobom z polskim językiem przeglądarki. Bez automatycznego przekierowania.
(() => {
  const KEY = "seam-lang";
  const read = () => { try { return localStorage.getItem(KEY); } catch { return null; } };
  const save = value => { try { localStorage.setItem(KEY, value); } catch { /* tryb prywatny */ } };

  document.querySelectorAll("[data-lang-switch]").forEach(a => a.addEventListener("click", () => save(a.dataset.langSwitch)));

  const target = document.querySelector('[data-lang-switch="pl"]');
  const prefersPolish = (navigator.languages || [navigator.language]).some(l => /^pl\b/i.test(l || ""));
  if (document.documentElement.lang !== "en" || !target || !prefersPolish || read()) return;

  const hint = document.createElement("aside");
  hint.className = "lang-hint";
  hint.lang = "pl";
  hint.setAttribute("aria-label", "Wersja polska");
  hint.innerHTML = `<span class="lang-hint__text">Polska wersja?</span>
    <a class="lang-hint__go" href="${target.getAttribute("href")}" hreflang="pl">Przejdź na polski</a>
    <button class="lang-hint__close" type="button" aria-label="Zostań przy angielskim"><svg viewBox="0 0 20 20" aria-hidden="true"><path d="M5.5 5.5l9 9m0-9-9 9"/></svg></button>`;
  hint.querySelector(".lang-hint__go").addEventListener("click", () => save("pl"));
  hint.querySelector(".lang-hint__close").addEventListener("click", () => {
    save("en");
    hint.classList.remove("is-in");
    setTimeout(() => hint.remove(), 300);
  });
  document.body.append(hint);
  requestAnimationFrame(() => requestAnimationFrame(() => hint.classList.add("is-in")));
})();
