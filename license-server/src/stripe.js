// Podpis webhooków Stripe bez biblioteki: nagłówek „t=…,v1=…”, HMAC-SHA256 z „t.body” kluczem whsec_….
// https://docs.stripe.com/webhooks#verify-manually
const encoder = new TextEncoder();

export const SIGNATURE_TOLERANCE_SECONDS = 300;

export async function stripeSignature(payload, secret, timestamp) {
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = await crypto.subtle.sign("HMAC", key, encoder.encode(`${timestamp}.${payload}`));
  return Array.from(new Uint8Array(mac), b => b.toString(16).padStart(2, "0")).join("");
}

/// Czy nagłówek Stripe-Signature pasuje do treści i sekretu. Liczy się tylko schemat v1 (v0 to atrapa testowa).
export async function verifyStripeSignature(payload, header, secret, now = Date.now() / 1000) {
  if (typeof header !== "string" || !secret) return false;
  let timestamp = null;
  const signatures = [];
  for (const part of header.split(",")) {
    const at = part.indexOf("=");
    if (at < 0) continue;
    const name = part.slice(0, at).trim();
    const value = part.slice(at + 1).trim();
    if (name === "t") timestamp = value;
    else if (name === "v1") signatures.push(value);
  }
  if (!timestamp || !/^\d+$/.test(timestamp) || signatures.length === 0) return false;
  if (Math.abs(now - Number(timestamp)) > SIGNATURE_TOLERANCE_SECONDS) return false;
  const expected = await stripeSignature(payload, secret, timestamp);
  // każdą sygnaturę porównujemy w całości (stały czas), bez wczesnego wyjścia
  let match = false;
  for (const signature of signatures) match = constantTimeEqual(signature, expected) || match;
  return match;
}

function constantTimeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
