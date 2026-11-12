// Maile z kluczem przez Resend (https://resend.com/docs/api-reference/emails/send-email).
// Bez RESEND_API_KEY nic nie wysyłamy: klucz i tak widać na stronie /license/ po zakupie.

const TEXT = {
  en: {
    subject: keys => (keys.length > 1 ? "Your Seam Pro license keys" : "Your Seam Pro license key"),
    intro: keys => (keys.length > 1 ? "Here are your Seam Pro license keys:" : "Thank you for buying Seam Pro! Here is your license key:"),
    howTo: "Open Seam → Settings → License, paste the key and click Activate. One key works on up to {devices} computers, and one licensed computer in a Mac–PC pair unlocks Pro for both.",
    lost: "Keep this email. If you lose the key, you can get it again at {site}/license/.",
    help: "Questions or a refund? Just reply to this email.",
    test: "TEST MODE: this key comes from a Stripe test purchase and works only in Seam dev builds.",
  },
  pl: {
    subject: keys => (keys.length > 1 ? "Twoje klucze licencji Seam Pro" : "Twój klucz licencji Seam Pro"),
    intro: keys => (keys.length > 1 ? "Oto Twoje klucze licencji Seam Pro:" : "Dziękujemy za zakup Seam Pro! Oto Twój klucz licencji:"),
    howTo: "Otwórz Seam → Ustawienia → Licencja, wklej klucz i kliknij Aktywuj. Jeden klucz działa na maksymalnie {devices} komputerach, a jeden komputer z licencją w parze Mac–PC odblokowuje Pro dla obu.",
    lost: "Zachowaj tego maila. Jeśli zgubisz klucz, odzyskasz go na {site}/pl/license/.",
    help: "Pytania albo zwrot? Po prostu odpowiedz na tego maila.",
    test: "TRYB TESTOWY: ten klucz pochodzi z testowego zakupu w Stripe i działa tylko w buildach dev Seam.",
  },
};

export function licenseEmail(env, licenses, lang = "en") {
  const t = TEXT[lang] ?? TEXT.en;
  const keys = licenses.map(l => l.key);
  const fill = s => s.replace("{devices}", env.MAX_DEVICES ?? "3").replace("{site}", env.SITE_URL ?? "https://seamdesk.app");
  const testNote = licenses.some(l => l.test) ? [t.test, ""] : [];
  const text = [...testNote, t.intro(keys), "", ...keys, "", fill(t.howTo), "", fill(t.lost), t.help, "", "seam"].join("\n");
  const esc = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const html = `<!doctype html><html lang="${lang}"><body style="margin:0;padding:32px 16px;background:#f5f5f7;font:15px/1.5 -apple-system,BlinkMacSystemFont,'Segoe UI',Inter,sans-serif;color:#1d1d1f">
<div style="max-width:520px;margin:0 auto;background:#fff;border-radius:16px;padding:32px">
<p style="margin:0 0 24px;font-weight:600;font-size:20px;letter-spacing:-.01em">seam</p>
${testNote.length ? `<p style="margin:0 0 16px;padding:10px 12px;border-radius:8px;background:#fff4d6;color:#7a5200">${esc(t.test)}</p>` : ""}
<p style="margin:0 0 16px">${esc(t.intro(keys))}</p>
${keys.map(k => `<p style="margin:0 0 12px;padding:14px 16px;border-radius:10px;background:#f5f5f7;font:600 17px/1.3 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;letter-spacing:.04em;user-select:all">${esc(k)}</p>`).join("")}
<p style="margin:16px 0">${esc(fill(t.howTo))}</p>
<p style="margin:0 0 8px;color:#6e6e73">${esc(fill(t.lost))}</p>
<p style="margin:0;color:#6e6e73">${esc(t.help)}</p>
</div></body></html>`;
  return { subject: t.subject(keys), text, html };
}

/// Wysyła mail; rzuca przy błędzie Resend, żeby Stripe ponowił webhook. Zwraca false, gdy maile są wyłączone.
export async function sendEmail(env, to, message, idempotencyKey) {
  if (!env.RESEND_API_KEY) return false;
  const headers = { Authorization: `Bearer ${env.RESEND_API_KEY}`, "Content-Type": "application/json" };
  if (idempotencyKey) headers["Idempotency-Key"] = idempotencyKey;
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers,
    body: JSON.stringify({
      from: env.EMAIL_FROM ?? "Seam <license@seamdesk.app>",
      to: [to],
      reply_to: env.SUPPORT_EMAIL ?? "support@seamdesk.app",
      subject: message.subject,
      text: message.text,
      html: message.html,
    }),
  });
  if (!response.ok) throw new Error(`Resend HTTP ${response.status}: ${(await response.text()).slice(0, 200)}`);
  return true;
}
