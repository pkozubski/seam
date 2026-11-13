// Strona /license/ (pl: /pl/license/): klucz zaraz po zakupie (Stripe przekierowuje tu z ?session_id=cs_…)
// i formularz „Wyślij mi klucz ponownie”. Dane z serwera licencji (license-server/, api.seamdesk.app).
(() => {
  const API = "https://api.seamdesk.app/v1";
  const pl = document.documentElement.lang === "pl";
  const params = new URLSearchParams(location.search);
  const session = params.get("session_id");

  // Payment Link ma jeden adres powrotu (angielski); kto wybrał polski, wraca na /pl/license/.
  if (!pl && session) {
    let lang = null;
    try { lang = localStorage.getItem("seam-lang"); } catch {}
    if (lang === "pl" || (!lang && (navigator.languages ?? []).some(l => l.toLowerCase().startsWith("pl")))) {
      location.replace("../pl/license/" + location.search);
      return;
    }
  }

  const TEXT = pl
    ? { waiting: "Czekamy na potwierdzenie płatności…", slow: "Płatność jeszcze się przetwarza. Klucz przyjdzie mailem, gdy tylko się zakończy.",
        failed: "Nie udało się pobrać klucza. Przyjdzie mailem; jeśli nie dotrze, użyj formularza niżej.", copy: "Kopiuj", copied: "Skopiowano",
        test: "Klucz testowy: działa tylko w testowych wersjach Seam.", sent: "Jeśli ten adres kupił Seam Pro, klucz jest już w drodze. Sprawdź też spam.",
        error: "Nie udało się wysłać. Spróbuj za chwilę albo napisz na support@seamdesk.app." }
    : { waiting: "Waiting for the payment confirmation…", slow: "The payment is still processing. Your key will arrive by email as soon as it completes.",
        failed: "Couldn't load your key. It will arrive by email; if it doesn't, use the form below.", copy: "Copy", copied: "Copied",
        test: "Test key: works only in test builds of Seam.", sent: "If this address bought Seam Pro, the key is on its way. Check your spam folder too.",
        error: "Couldn't send it. Try again in a moment or write to support@seamdesk.app." };

  // ---------- klucz po zakupie ----------
  const purchase = document.querySelector("[data-purchase]");
  if (purchase && session && /^cs_(live|test)_[A-Za-z0-9]+$/.test(session)) {
    purchase.hidden = false;
    const status = purchase.querySelector("[data-purchase-status]");
    const keyBox = purchase.querySelector("[data-purchase-key]");
    status.textContent = TEXT.waiting;
    let attempt = 0;
    const poll = async () => {
      attempt += 1;
      try {
        const response = await fetch(`${API}/checkout/${session}`, { cache: "no-store" });
        if (response.ok) {
          const data = await response.json();
          keyBox.querySelector("code").textContent = data.license_key;
          keyBox.hidden = false;
          const email = purchase.querySelector("[data-purchase-email]");
          if (data.customer_email) email.textContent = data.customer_email;
          else email.closest("p").hidden = true;
          status.textContent = data.test ? TEXT.test : "";
          status.hidden = !data.test;
          return;
        }
        if (response.status !== 404) throw new Error(`HTTP ${response.status}`);
      } catch {
        if (attempt >= 3) { status.textContent = TEXT.failed; return; }
      }
      // webhook Stripe zwykle dochodzi w kilka sekund; potem rzadziej, a po ~2 min zostaje mail
      if (attempt < 30) setTimeout(poll, attempt < 10 ? 1500 : 5000);
      else status.textContent = TEXT.slow;
    };
    poll();

    const copy = keyBox.querySelector("button");
    copy.addEventListener("click", async () => {
      try {
        await navigator.clipboard.writeText(keyBox.querySelector("code").textContent);
        copy.textContent = TEXT.copied;
        setTimeout(() => { copy.textContent = TEXT.copy; }, 2000);
      } catch {}
    });
  }

  // ---------- ponowne wysłanie ----------
  const form = document.querySelector("[data-resend]");
  form?.addEventListener("submit", async e => {
    e.preventDefault();
    const button = form.querySelector("button");
    const result = form.querySelector("[data-resend-status]");
    button.disabled = true;
    try {
      const response = await fetch(`${API}/licenses/resend`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: form.email.value, lang: pl ? "pl" : "en" }),
      });
      result.textContent = response.ok ? TEXT.sent : TEXT.error;
    } catch {
      result.textContent = TEXT.error;
    }
    result.hidden = false;
    button.disabled = false;
  });
})();
