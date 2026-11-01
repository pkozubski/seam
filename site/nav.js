// Nawigacja: zachowanie globalnej nawigacji apple.com (globalheader.umd.js), wartości opisane w README.md.
(() => {
  const nav = document.getElementById("globalnav");
  if (!nav) return;
  const list = nav.querySelector(".globalnav-list");
  const content = nav.querySelector(".globalnav-content");
  const menuButton = nav.querySelector(".globalnav-menutrigger-button");
  const curtain = document.getElementById("globalnav-curtain");
  const items = [...nav.querySelectorAll(".globalnav-item-submenu")];
  const compact = matchMedia("(max-width: 833px)");
  const C = {
    open: "globalnav-item-flyout-open", closing: "globalnav-item-flyout-closing",
    next: "globalnav-item-flyout-change-next", prev: "globalnav-item-flyout-change-previous",
    withOpen: "globalnav-with-flyout-open", withClosing: "globalnav-with-flyout-closing",
    animating: "globalnav-animating", menuOpen: "globalnav-with-menu-open", subOpen: "globalnav-with-submenu-open",
  };
  let current = null, hoverTimer = 0, usesTouch = false;

  // Numeracja do opóźnień kaskady (_setSubMenuItemCounts): numer grupy, numer pozycji w grupie,
  // liczba pozycji w pierwszej grupie i liczba grup wyróżnionych.
  items.forEach(item => {
    const box = item.querySelector(".globalnav-submenu-content");
    let total = 0, elevated = 0;
    [...box.querySelectorAll(".globalnav-submenu-group")].forEach((group, g) => {
      group.style.setProperty("--r-globalnav-flyout-group-number", g);
      let n = 0;
      [group.querySelector(".globalnav-submenu-header"), ...group.querySelector(".globalnav-submenu-list").children].forEach(el => {
        el.style.setProperty("--r-globalnav-flyout-item-number", ++n);
        if (!g) total++;
      });
      if (group.classList.contains("globalnav-submenu-group-elevated")) elevated++;
    });
    box.style.setProperty("--r-globalnav-flyout-elevated-group-count", elevated);
    box.style.setProperty("--r-globalnav-flyout-item-total", total);
  });
  [...list.children].forEach((li, i) => li.style.setProperty("--r-globalnav-flyout-item-number", i));

  // Wysokość panelu = treść + pasek; tempo = min(480, max(240, treść / 2)) ms (_setFlyoutHeight)
  const setHeight = item => {
    const flyout = item.querySelector(".globalnav-submenu");
    const box = item.querySelector(".globalnav-submenu-content");
    const h = parseInt(getComputedStyle(box).height);
    flyout.style.setProperty("--r-globalnav-flyout-height", `${h + 44}px`);
    flyout.style.setProperty("--r-globalnav-flyout-rate", `${Math.min(480, Math.max(240, h / 2))}ms`);
  };
  const setHeights = () => items.forEach(setHeight);

  const onceEnd = (el, type, done) => {
    let fired = false;
    const finish = e => { if (e && e.target !== el.querySelector(".globalnav-submenu")) return; if (fired) return; fired = true; el.removeEventListener(type, finish); done(); };
    el.addEventListener(type, finish);
    setTimeout(() => finish(), 900); // zapas, gdy przejście nie wystąpi (np. ograniczony ruch)
  };
  const trigger = item => item.querySelector(".globalnav-submenu-trigger-button");

  function willOpen(item, change) {
    current = item;
    nav.classList.add(C.animating, C.subOpen);
    if (change) item.classList.add(C.next);
    else {
      item.classList.add(C.open);
      nav.classList.add(C.withOpen);
      addEventListener("scroll", onScrollClose, { passive: true });
    }
    trigger(item).setAttribute("aria-expanded", "true");
  }
  function opened(item, change) {
    nav.classList.remove(C.animating);
    if (change) { item.classList.add(C.open); item.classList.remove(C.next); }
  }
  function willClose(item, change) {
    nav.classList.add(C.withClosing, C.animating);
    nav.classList.remove(C.subOpen); // przy zmianie menu willOpen zaraz doda ją z powrotem
    item.classList.add(C.closing);
    item.classList.remove(C.open);
    if (change) item.classList.add(C.prev);
    else { nav.classList.remove(C.withOpen); current = null; removeEventListener("scroll", onScrollClose); }
    trigger(item).setAttribute("aria-expanded", "false");
  }
  function closed(item, change) {
    nav.classList.remove(C.withClosing, C.animating);
    item.classList.remove(C.closing);
    if (change) item.classList.remove(C.prev, C.open);
  }

  function openFlyout(item) {
    setHeight(item);
    if (current && current !== item) {
      const prev = current;
      nav.style.setProperty("--r-globalnav-next-flyout-height", getComputedStyle(item.querySelector(".globalnav-submenu")).getPropertyValue("--r-globalnav-flyout-height"));
      nav.style.setProperty("--r-globalnav-previous-flyout-height", getComputedStyle(prev.querySelector(".globalnav-submenu")).getPropertyValue("--r-globalnav-flyout-height"));
      willClose(prev, true);
      willOpen(item, true);
      onceEnd(item, "animationend", () => { opened(item, true); closed(prev, true); });
    } else if (!current) {
      willOpen(item, false);
      onceEnd(item, "transitionend", () => opened(item, false));
    }
  }
  function closeFlyout(item = current) {
    if (!item || item !== current) return;
    willClose(item, false);
    onceEnd(item, "transitionend", () => closed(item, false));
  }
  const onScrollClose = () => closeFlyout();

  // Najechanie: otwarcie po 120 ms (onMenuItemMouseOver); pozycja bez menu zamyka otwarte
  list.addEventListener("mouseover", ({ target }) => {
    if (usesTouch || compact.matches) return;
    const li = target.closest(".globalnav-list > .globalnav-item");
    clearTimeout(hoverTimer);
    hoverTimer = setTimeout(() => {
      if (!li || li === current) return;
      if (items.includes(li)) openFlyout(li); else closeFlyout();
    }, 120);
  });
  nav.addEventListener("mouseleave", () => { clearTimeout(hoverTimer); if (!compact.matches && !usesTouch) closeFlyout(); });
  list.addEventListener("touchstart", () => { usesTouch = true; }, { once: true, passive: true });

  // Dotyk lub klawiatura: przycisk ze strzałką przełącza menu
  items.forEach(item => {
    trigger(item).addEventListener("click", e => { e.preventDefault(); item === current ? closeFlyout() : openFlyout(item); });
    item.querySelector(".globalnav-submenu-trigger-link").addEventListener("click", e => {
      if (usesTouch && !compact.matches && item !== current) { e.preventDefault(); openFlyout(item); }
    });
  });
  // Kliknięcie linku w menu zamyka je od razu, bez animacji (jak przy przejściu na stronę)
  nav.addEventListener("click", e => {
    const a = e.target.closest("a[href^='#']");
    if (!a) return;
    if (compact.matches) toggleMenu(false);
    else if (current && a.closest(".globalnav-submenu")) { const it = current; willClose(it, false); closed(it, false); }
  });
  curtain.addEventListener("click", () => closeFlyout());
  document.addEventListener("keydown", e => {
    if (e.key !== "Escape") return;
    if (compact.matches) toggleMenu(false);
    else if (current) { const t = trigger(current); closeFlyout(); setTimeout(() => t.focus(), 300); }
  });
  nav.addEventListener("focusout", e => { if (current && e.relatedTarget && !nav.contains(e.relatedTarget)) closeFlyout(); });

  // Telefon: menu na cały ekran; tempo = min(480, max(240, wysokość okna / 2)) ms
  function toggleMenu(force) {
    const open = force ?? !nav.classList.contains(C.menuOpen);
    content.style.setProperty("--r-globalnav-flyout-rate", `${Math.min(480, Math.max(240, innerHeight / 2))}ms`);
    nav.classList.toggle(C.menuOpen, open);
    nav.classList.toggle(C.withOpen, open);
    document.documentElement.classList.toggle("globalnav-menu-locked", open);
    menuButton.setAttribute("aria-expanded", open);
    menuButton.setAttribute("aria-label", open ? (document.documentElement.lang === "pl" ? "Zamknij menu" : "Close menu") : "Menu");
  }
  menuButton.addEventListener("click", () => toggleMenu());
  compact.addEventListener("change", () => { toggleMenu(false); if (current) { const it = current; willClose(it, false); closed(it, false); } });

  // Nad tekstem hero pasek jest przezroczysty (klasa globalnav-over-hero)
  const heroCopy = document.querySelector(".hero__copy");
  const overHero = () => nav.classList.toggle("globalnav-over-hero", !!heroCopy && heroCopy.getBoundingClientRect().bottom > 44);
  overHero();
  addEventListener("scroll", overHero, { passive: true });

  addEventListener("resize", setHeights);
  document.fonts?.ready.then(setHeights);
  setHeights();
})();
