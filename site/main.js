// seam: landing page. Bez zależności.
(() => {
  const root = document.documentElement;
  root.classList.remove("no-js");
  const pl = root.lang === "pl";

  // Główny przycisk wg systemu odwiedzającego.
  const ua = navigator.userAgent;
  const os = /Windows/i.test(ua) ? "windows" : /Mac OS X|Macintosh/i.test(ua) && !/iPhone|iPad/i.test(ua) ? "mac" : null;
  if (os && document.querySelector("[data-download-buttons]")) {
    const cta = document.querySelector("[data-download-buttons]");
    const mine = cta.querySelector(`[data-os="${os}"]`);
    const other = cta.querySelector(`[data-os]:not([data-os="${os}"])`);
    mine.className = "btn btn--light";
    other.className = "btn btn--ghost";
    cta.prepend(mine);
    document.querySelector(`[data-platform="${os}"]`)?.classList.add("is-mine");
  }

  // Zakładki ze zrzutami aplikacji (strzałki zmieniają zakładkę).
  const tabs = [...document.querySelectorAll('.showcase [role="tab"]')];
  const panel = document.getElementById("shot");
  const shot = panel?.querySelector("img");
  // zrzuty leżą obok bieżącego (strona PL jest w /pl/, więc nie ścieżka względem dokumentu)
  const shotURL = name => new URL(`${name}.webp`, shot.src).href;
  const caption = document.querySelector(".orbs-caption__label");
  const select = (tab, focus) => {
    tabs.forEach(t => {
      const on = t === tab;
      t.setAttribute("aria-selected", on);
      t.tabIndex = on ? 0 : -1;
    });
    panel.setAttribute("aria-labelledby", tab.id);
    if (focus) tab.focus();
    // podpis pod kulkami: nazwa strony i numer
    if (caption) caption.innerHTML = `<b>${tab.title}</b> · ${tabs.indexOf(tab) + 1} ${pl ? "z" : "of"} ${tabs.length}`;
    const src = shotURL(tab.dataset.shot);
    if (shot.src === src) return;
    shot.classList.add("is-fading");
    const next = new Image();
    next.onload = () => {
      shot.src = src;
      shot.alt = tab.dataset.alt;
      shot.classList.remove("is-fading");
    };
    next.src = src;
  };
  tabs.forEach((tab, i) => {
    tab.addEventListener("click", () => select(tab));
    tab.addEventListener("keydown", e => {
      const step = e.key === "ArrowRight" ? 1 : e.key === "ArrowLeft" ? -1 : 0;
      if (step) select(tabs[(i + step + tabs.length) % tabs.length], true);
    });
  });
  // Strzałki obok podpisu: poprzednia / następna strona
  document.querySelectorAll(".orbs-caption__step").forEach(btn => btn.addEventListener("click", () => {
    const i = tabs.findIndex(t => t.getAttribute("aria-selected") === "true");
    select(tabs[(i + +btn.dataset.dir + tabs.length) % tabs.length]);
  }));
  // Wstępne ładowanie pozostałych zrzutów, gdy sekcja się zbliża.
  const warm = new IntersectionObserver(entries => {
    if (!entries.some(e => e.isIntersecting)) return;
    tabs.forEach(t => { new Image().src = shotURL(t.dataset.shot); });
    warm.disconnect();
  }, { rootMargin: "600px" });
  if (panel) warm.observe(panel);

  // Pytania: przycisk otwiera i zamyka odpowiedź (kilka może być otwartych naraz).
  document.querySelectorAll(".qa__q").forEach(q => q.addEventListener("click", () => {
    const item = q.closest(".qa");
    const open = item.classList.toggle("is-open");
    q.setAttribute("aria-expanded", open);
    item.querySelector(".qa__a").inert = !open;
  }));

  // Wejście sekcji przy przewijaniu.
  const items = document.querySelectorAll(".reveal");
  if (!("IntersectionObserver" in window) || matchMedia("(prefers-reduced-motion: reduce)").matches) {
    items.forEach(el => el.classList.add("is-in"));
    return;
  }
  const io = new IntersectionObserver(entries => {
    entries.forEach(e => {
      if (!e.isIntersecting) return;
      e.target.classList.add("is-in");
      io.unobserve(e.target);
    });
  }, { threshold: 0.12, rootMargin: "0px 0px -40px 0px" });
  items.forEach(el => io.observe(el));
})();
