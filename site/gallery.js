// Galeria funkcji: zachowanie galerii „Co go wyróżnia.” z apple.com/pl/iphone-18-pro
// (MediaCardGallery + MediaCardGalleryControl). Wartości i wzory z main.built.js, opis w README.md.
(() => {
  const root = document.querySelector("[data-media-card-gallery]");
  if (!root) return;
  const html = document.documentElement;
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  html.classList.add("enhanced");
  html.classList.toggle("reduced-motion", reducedMotion);
  if (!("ontouchstart" in html)) html.classList.add("no-touch");

  const section = root.closest(".section-highlights");
  const scroller = root.querySelector(".media-gallery");
  const items = [...root.querySelectorAll(".gallery-item")];
  const dotItems = [...root.querySelectorAll(".dotnav-item")];
  const dotLinks = [...root.querySelectorAll(".dotnav-link")];
  const aap = root.querySelector(".all-access-pass");
  const intro = aap.querySelector(".all-access-pass__intro-element");
  const timedDotNav = aap.querySelector(".aap-media-card-gallery__timed-dotnav");
  const playPauseWrapper = aap.querySelector(".play-pause-button-wrapper");
  const button = aap.querySelector(".play-pause-button");
  const css = getComputedStyle(root);
  const DURATION = (parseFloat(css.getPropertyValue("--shared-media-gallery-transition-duration")) || 1) * 1000;
  const PERSIST = (parseFloat(css.getPropertyValue("--autoplay-persist-duration")) || 6.15) * 1000;
  const LABELS = document.documentElement.lang === "pl"
    ? { play: "Odtwórz galerię funkcji", pause: "Wstrzymaj galerię funkcji", replay: "Odtwórz ponownie galerię funkcji" }
    : { play: "Play the feature gallery", pause: "Pause the feature gallery", replay: "Replay the feature gallery" };

  // Szerokość paska przewijania (oryginał: getScrollBarWidth -> --global-scrollbar-width)
  const setScrollbar = () => section.style.setProperty("--global-scrollbar-width", `${innerWidth - html.clientWidth}px`);
  setScrollbar();

  // ---------- Sprężyny: port SpringLayer (krok 1/60 s, masa 1, interpolacja) ----------
  const springs = new Set();
  let rafId = 0, lastTime = 0;
  const TRANSFORM = ["x", "y", "z", "scale"];
  class Spring {
    constructor(el, props) {
      this.el = el;
      this.props = props;
      for (const k in props) {
        const p = props[k];
        p.velocity = 0;
        if (p.bounce !== undefined && p.duration !== undefined) {
          p.stiffness = (2 * Math.PI / p.duration) ** 2;
          p.damping = (1 - p.bounce) * (4 * Math.PI) / p.duration;
        }
      }
      this.prev = structuredClone(props);
      this.render = structuredClone(props);
      this.acc = 0;
    }
    near(k) { return Math.abs(this.render[k].position - this.props[k].target) < 0.001 && Math.abs(this.props[k].velocity) < 0.001; }
    update(dt) {
      const step = 1 / 60;
      this.acc += Math.min(1 / 30, dt);
      while (this.acc >= step) {
        this.prev = structuredClone(this.props);
        for (const k in this.props) {
          const p = this.props[k];
          if (this.near(k)) { p.position = p.target; p.velocity = 0; continue; }
          p.velocity += (-p.stiffness * (p.position - p.target) - p.damping * p.velocity) * step;
          p.position += p.velocity * step;
        }
        this.acc -= step;
      }
      const t = this.acc / step;
      for (const k in this.props) {
        this.render[k].position = this.props[k].position * t + this.prev[k].position * (1 - t);
        this.render[k].velocity = this.props[k].velocity * t + this.prev[k].velocity * (1 - t);
      }
    }
    draw() {
      let done = true;
      for (const k in this.props) {
        if (this.near(k)) { this.props[k].position = this.render[k].position = this.props[k].target; this.props[k].velocity = 0; }
        else done = false;
        this.apply(k);
      }
      return done;
    }
    apply(k, value = this.render[k].position) {
      if (k === "width" || k === "height") this.el.style[k] = `${value}px`;
      else if (TRANSFORM.includes(k)) {
        const v = n => (this.render[n] ? this.render[n].position : n === "scale" ? 1 : 0);
        this.el.style.transform = `translate3d(${v("x")}px, ${v("y")}px, ${v("z")}px) scale(${v("scale")})`;
      } else if (k.startsWith("--")) this.el.style.setProperty(k, `${value}`);
      else this.el.style[k] = `${value}`;
    }
    snap(k, value) {
      for (const s of [this.props, this.prev, this.render]) { s[k].target = value; s[k].position = value; s[k].velocity = 0; }
      this.apply(k, +value.toFixed(5));
    }
    to(k, value) { this.props[k].target = value; springs.add(this); run(); }
  }
  function run() {
    if (rafId) return;
    lastTime = performance.now();
    const tick = now => {
      const dt = (now - lastTime) / 1000;
      lastTime = now;
      for (const s of springs) { s.update(dt); if (s.draw()) springs.delete(s); }
      rafId = springs.size ? requestAnimationFrame(tick) : 0;
    };
    rafId = requestAnimationFrame(tick);
  }
  const at = (seconds, fn) => setTimeout(fn, seconds * 1000);

  // ---------- Pozycje slajdów i --autoplay-progress ----------
  let offsets = [];
  const measure = () => {
    const max = scroller.scrollWidth - scroller.clientWidth;
    offsets = items.map(item => {
      const start = getComputedStyle(item).scrollSnapAlign.includes("start");
      const pad = parseFloat(getComputedStyle(scroller).scrollPaddingInlineStart) || 0;
      const raw = start ? item.offsetLeft - pad : item.offsetLeft + item.offsetWidth / 2 - scroller.clientWidth / 2;
      return Math.max(0, Math.min(max, Math.round(raw)));
    });
  };
  // Wzór z _onUpdateTotalProgress: ostatni slajd liczony z własnego zakresu
  const updateProgress = () => {
    if (!offsets.length) measure();
    if (reducedMotion) { root.style.setProperty("--autoplay-progress", current); return; }
    const last = items.length - 1;
    const single = offsets[1], final = offsets[last], penult = offsets[last - 1], range = final - penult;
    const x = scroller.scrollLeft;
    const p = x > penult ? last - Math.round(final - x) / Math.round(range) : Math.round(x) / single;
    root.style.setProperty("--autoplay-progress", p);
  };

  // ---------- Stan bieżącego slajdu ----------
  let current = 0;
  const setCurrent = i => {
    current = i;
    items.forEach((item, n) => {
      item.classList.toggle("current", n === i);
      item.setAttribute("aria-hidden", n === i ? "false" : "true");
    });
    dotItems.forEach((li, n) => li.classList.toggle("current", n === i));
    dotLinks.forEach((a, n) => {
      a.classList.toggle("current", n === i);
      a.setAttribute("aria-selected", n === i);
      a.tabIndex = n === i ? 0 : -1;
    });
  };

  // ---------- Odtwarzanie: playing / paused / ended ----------
  let ignoreUntil = 0; // zdarzenia scroll z własnych zmian scrollLeft
  let state = "paused", timer = 0, timerStart = 0, remaining = PERSIST, visible = false, animating = false;
  const setState = s => {
    state = s;
    root.classList.remove("playing", "paused", "ended");
    root.classList.add(s);
    button.setAttribute("aria-label", LABELS[s === "playing" ? "pause" : s === "ended" ? "replay" : "play"]);
  };
  const stopTimer = () => { if (timer) { clearTimeout(timer); timer = 0; remaining -= performance.now() - timerStart; } };
  const startTimer = () => {
    clearTimeout(timer);
    if (state !== "playing" || !visible || animating) { timer = 0; return; }
    timerStart = performance.now();
    timer = setTimeout(onTimeout, Math.max(0, remaining));
  };
  const resetTimer = () => { clearTimeout(timer); timer = 0; remaining = PERSIST; };
  function onTimeout() {
    timer = 0;
    if (current < items.length - 1) animateTo(current + 1, "auto");
    else setState("ended"); // ostatni slajd: galeria się kończy, przycisk pokazuje „od nowa”
  }
  const play = () => { setState("playing"); startTimer(); };
  const pause = () => { stopTimer(); setState("paused"); };

  // ---------- Przejście: scrollLeft po easeInOutQuad, zmiana bieżącego w połowie ----------
  const easeInOutQuad = t => (t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t);
  function animateTo(i, interaction) {
    if (animating || i === current || i < 0 || i >= items.length) return;
    measure();
    stopTimer();
    if (interaction !== "auto" && state !== "ended") pause();
    const from = scroller.scrollLeft, to = offsets[i];
    if (reducedMotion) { ignoreUntil = performance.now() + 150; scroller.scrollLeft = to; setCurrent(i); updateProgress(); resetTimer(); startTimer(); return; }
    animating = true;
    scroller.classList.add("animating");
    scroller.style.scrollSnapType = "none";
    let switched = false;
    const t0 = performance.now();
    const frame = now => {
      const t = Math.min(1, (now - t0) / DURATION);
      scroller.scrollLeft = from + (to - from) * easeInOutQuad(t);
      if (!switched && t >= 0.5) { switched = true; setCurrent(i); }
      if (t < 1) return requestAnimationFrame(frame);
      scroller.style.scrollSnapType = "";
      scroller.classList.remove("animating");
      animating = false;
      ignoreUntil = performance.now() + 150;
      resetTimer();
      startTimer();
    };
    requestAnimationFrame(frame);
  }

  // ---------- Wejście pigułki (playIntroAnimation, 2 bańki) ----------
  const bubbles = [
    { element: timedDotNav, background: timedDotNav.querySelector(".all-access-pass__background") },
    { element: playPauseWrapper, background: playPauseWrapper.querySelector(".all-access-pass__background") },
  ];
  let introSpring, aapSpring, dotSprings = [];
  const createSprings = () => {
    introSpring = new Spring(intro, {
      x: { position: -15, target: -15, stiffness: 100, damping: 8 },
      scale: { position: 1.3, target: 1.3, duration: 0.5, bounce: 0 },
      height: { position: 80, target: 80, stiffness: 100, damping: 8 },
      width: { position: 30, target: 30, stiffness: 100, damping: 8 },
    });
    aapSpring = new Spring(aap, { y: { position: 180, target: 180, stiffness: 100, damping: 8 } });
    bubbles[0].elementSpring = new Spring(timedDotNav, {
      x: { position: 0, target: 0, stiffness: 100, damping: 20 },
      "--alpha": { position: 0, target: 0, stiffness: 100, damping: 20 },
      "--progress-intro": { position: 1, target: 1, stiffness: 200, damping: 20 },
    });
    bubbles[0].backgroundSpring = new Spring(bubbles[0].background, {
      height: { position: 56, target: 56, stiffness: 100, damping: 10 },
      width: { position: 56, target: 56, stiffness: 100, damping: 10 },
      "--scale": { position: 1.3, target: 1.3, duration: 0.3, bounce: 0 },
    });
    bubbles[1].elementSpring = new Spring(playPauseWrapper, {
      x: { position: 0, target: 0, stiffness: 100, damping: 20 },
      "--alpha": { position: 0, target: 0, stiffness: 100, damping: 20 },
    });
    bubbles[1].backgroundSpring = new Spring(bubbles[1].background, {
      height: { position: 56, target: 56, stiffness: 100, damping: 10 },
      width: { position: 56, target: 56, stiffness: 100, damping: 10 },
      "--scale": { position: 0, target: 0, duration: 0.65, bounce: 0 },
    });
    dotSprings = dotItems.map(li => new Spring(li, { x: { position: 0, target: 0, stiffness: 200, damping: 20 } }));
  };

  function playIntroAnimation() {
    createSprings();
    // granice baniek mierzone w spoczynku (oryginał: mounted())
    aap.style.transform = "none";
    bubbles.forEach(b => { b.element.style.transform = "none"; b.bounds = b.element.getBoundingClientRect(); });

    // część MediaCardGalleryControl
    bubbles[0].elementSpring.snap("--progress-intro", 0);
    dotSprings.forEach(s => s.snap("x", 36));
    // część bazowa AllAccessPass
    intro.style.opacity = "0";
    introSpring.snap("scale", 1.3);
    introSpring.snap("x", -15);
    introSpring.snap("width", 30);
    introSpring.snap("height", 80);
    aapSpring.snap("y", 180);
    aap.classList.remove("activated");
    bubbles.forEach((b, e) => {
      b.elementSpring.snap("x", 0.5 * innerWidth - 0.5 * b.bounds.width - b.bounds.x);
      b.elementSpring.snap("--alpha", 0);
      b.backgroundSpring.snap("width", e === 0 ? 40 : 80);
      b.backgroundSpring.snap("height", 36);
      b.backgroundSpring.snap("--scale", e === 0 ? 1.3 : 0);
    });

    requestAnimationFrame(() => { aap.classList.add("activated"); intro.style.opacity = "1"; });
    introSpring.to("scale", 0.8);
    at(0.03, () => aapSpring.to("y", 0));
    at(0.05, () => { introSpring.to("x", -28); introSpring.to("width", 56); });
    at(0.15, () => introSpring.to("height", 56));
    at(0.3, () => bubbles[0].backgroundSpring.to("--scale", 1));
    at(0.5, () => { bubbles[0].elementSpring.to("x", 0); bubbles[0].backgroundSpring.to("width", bubbles[0].bounds.width); });
    at(0.52, () => requestAnimationFrame(() => { intro.style.opacity = "0"; }));
    at(0.54, () => { bubbles[1].elementSpring.to("x", 0); bubbles[1].backgroundSpring.to("--scale", 1); });
    at(0.7, () => {
      bubbles[0].backgroundSpring.to("height", bubbles[0].bounds.height);
      bubbles[1].backgroundSpring.to("width", bubbles[1].bounds.width);
      bubbles[1].backgroundSpring.to("height", bubbles[1].bounds.height);
    });
    at(1, () => bubbles.forEach(b => b.elementSpring.to("--alpha", 1)));
    dotSprings.forEach((s, t) => at(0.74 + 0.02 * t, () => {
      if (t === 0) bubbles[0].elementSpring.to("--progress-intro", 1);
      s.to("x", 0);
    }));
  }

  // Start: gdy widać 60% galerii (keyframe "a0t - 100vh + 60a0h")
  let entered = false;
  const checkEnter = () => {
    const r = scroller.getBoundingClientRect();
    visible = r.bottom > 0 && r.top < innerHeight;
    root.classList.toggle("offscreen", !visible);
    if (!entered && r.top <= innerHeight - 0.6 * r.height && r.bottom > 0) {
      entered = true;
      aap.classList.remove("inactive");
      if (reducedMotion) { aap.classList.add("activated"); return; }
      playIntroAnimation();
      play();
      return;
    }
    if (visible) { if (!timer) startTimer(); } else stopTimer();
  };

  // ---------- Zdarzenia ----------
  dotLinks.forEach((a, i) => {
    a.addEventListener("click", e => { e.preventDefault(); animateTo(i, "click"); });
    a.addEventListener("keydown", e => {
      const step = e.key === "ArrowRight" ? 1 : e.key === "ArrowLeft" ? -1 : 0;
      if (!step) return;
      e.preventDefault();
      const n = Math.max(0, Math.min(items.length - 1, current + step));
      animateTo(n, "click");
      dotLinks[n].focus();
    });
  });
  items.forEach((item, i) => item.addEventListener("click", () => { if (i !== current) animateTo(i, "click"); }));
  button.addEventListener("click", () => {
    if (state === "playing") pause();
    else if (state === "ended") { setState("playing"); remaining = PERSIST; current === 0 ? startTimer() : (animateTo(0, "auto")); }
    else play();
  });

  // Przewijanie ręczne (gest, gładzik): pauza, a po zatrzymaniu bieżący = najbliższy
  let settle = 0;
  scroller.addEventListener("scroll", () => {
    updateProgress();
    if (animating || performance.now() < ignoreUntil) return;
    if (state === "playing") pause();
    clearTimeout(settle);
    settle = setTimeout(() => {
      measure();
      const x = scroller.scrollLeft;
      const nearest = offsets.reduce((best, o, n) => (Math.abs(o - x) < Math.abs(offsets[best] - x) ? n : best), 0);
      if (nearest !== current) { setCurrent(nearest); resetTimer(); }
    }, 120);
  }, { passive: true });

  addEventListener("scroll", checkEnter, { passive: true });
  let resizeT = 0;
  addEventListener("resize", () => {
    clearTimeout(resizeT);
    resizeT = setTimeout(() => {
      setScrollbar();
      measure();
      ignoreUntil = performance.now() + 150;
      scroller.scrollLeft = offsets[current];
      updateProgress();
    }, 100);
  });

  setCurrent(0);
  setState("paused");
  requestAnimationFrame(() => { measure(); ignoreUntil = performance.now() + 150; scroller.scrollLeft = offsets[0]; updateProgress(); checkEnter(); });
})();
