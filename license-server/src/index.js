// Serwer licencji Seam Pro (api.seamdesk.app): klucze z webhooka Stripe, aktywacja na maks. MAX_DEVICES
// komputerach, walidacja z aplikacji co ~7 dni. Format odpowiedzi: tests/fixtures/license-api.json.
import { generateKey, normalizeKey } from "./keys.js";
import { verifyStripeSignature } from "./stripe.js";
import { licenseEmail, sendEmail } from "./email.js";

const RESEND_COOLDOWN_MS = 10 * 60 * 1000;
const MAX_BODY_BYTES = 64 * 1024;

export default {
  async fetch(request, env) {
    const site = siteCors(request, env);
    if (request.method === "OPTIONS") return new Response(null, { status: site ? 204 : 403, headers: site ?? {} });
    let response;
    try {
      response = await route(request, env);
    } catch (e) {
      if (e instanceof BadRequest) {
        response = error(400, "bad_request", e.message);
      } else {
        console.error(e);
        response = error(500, "server_error", "Server error.");
      }
    }
    // CORS tylko dla seamdesk.app (strona /license/); aplikacje go nie potrzebują
    return withHeaders(response, site);
  },
};

async function route(request, env) {
  const path = new URL(request.url).pathname.replace(/\/+$/, "");
  const { method } = request;
  if (method === "POST" && path === "/v1/stripe/webhook") return stripeWebhook(request, env);
  if (method === "POST" && path === "/v1/licenses/activate") return activate(request, env);
  if (method === "POST" && path === "/v1/licenses/validate") return validate(request, env);
  if (method === "POST" && path === "/v1/licenses/deactivate") return deactivate(request, env);
  if (method === "POST" && path === "/v1/licenses/resend") return resend(request, env);
  const checkout = path.match(/^\/v1\/checkout\/(cs_(?:live|test)_[A-Za-z0-9]{10,200})$/);
  if (method === "GET" && checkout) return checkoutLicense(checkout[1], env);
  if (method === "GET" && path === "") return json({ service: "seam-license" });
  return error(404, "not_found", "Not found.");
}

// ---------- API aplikacji ----------

async function activate(request, env) {
  const body = await readJson(request);
  const key = normalizeKey(body.license_key);
  const name = String(body.instance_name ?? "").trim().slice(0, 100) || "Computer";
  const license = await findLicense(env, key);
  if (!license) return error(404, "invalid_key", "This license key doesn't exist.", { activated: false });
  if (license.status !== "active") {
    return error(403, "license_disabled", "This license has been disabled (refund or chargeback).", {
      activated: false, license: licenseInfo(license),
    });
  }
  const now = new Date().toISOString();
  // Ta sama nazwa komputera (np. po ponownej instalacji) dostaje z powrotem swoje miejsce.
  const existing = await env.DB.prepare("SELECT id FROM instances WHERE license_key = ? AND name = ?").bind(license.key, name).first();
  let id = existing?.id;
  if (id) {
    await env.DB.prepare("UPDATE instances SET last_seen_at = ? WHERE id = ?").bind(now, id).run();
  } else {
    const limit = maxDevices(env);
    const { count } = await env.DB.prepare("SELECT COUNT(*) AS count FROM instances WHERE license_key = ?").bind(license.key).first();
    if (count >= limit) {
      return error(403, "device_limit", `This key is already active on ${limit} computers. Deactivate it on one of them first.`, {
        activated: false, license: licenseInfo(license),
      });
    }
    id = crypto.randomUUID();
    await env.DB.prepare("INSERT INTO instances (id, license_key, name, created_at, last_seen_at) VALUES (?, ?, ?, ?, ?)")
      .bind(id, license.key, name, now, now).run();
  }
  return json({ activated: true, instance: { id }, license: licenseInfo(license), customer_email: license.email });
}

async function validate(request, env) {
  const body = await readJson(request);
  const license = await findLicense(env, normalizeKey(body.license_key));
  if (!license) return error(404, "invalid_key", "This license key doesn't exist.", { valid: false, license: null });
  const instanceID = String(body.instance_id ?? "");
  const instance = instanceID
    ? await env.DB.prepare("SELECT id FROM instances WHERE id = ? AND license_key = ?").bind(instanceID, license.key).first()
    : null;
  if (instance) {
    await env.DB.prepare("UPDATE instances SET last_seen_at = ? WHERE id = ?").bind(new Date().toISOString(), instance.id).run();
  }
  const valid = license.status === "active" && instance !== null;
  return json({ valid, license: licenseInfo(license), customer_email: license.email });
}

async function deactivate(request, env) {
  const body = await readJson(request);
  const license = await findLicense(env, normalizeKey(body.license_key));
  if (!license) return error(404, "invalid_key", "This license key doesn't exist.", { deactivated: false });
  // Brak tej instancji to też sukces: miejsce i tak jest wolne.
  await env.DB.prepare("DELETE FROM instances WHERE id = ? AND license_key = ?").bind(String(body.instance_id ?? ""), license.key).run();
  return json({ deactivated: true });
}

// ---------- API strony ----------

/// Strona /license/ po zakupie: klucz zaraz po przekierowaniu ze Stripe (404 „pending”, dopóki webhook nie dojdzie).
async function checkoutLicense(sessionID, env) {
  const license = await env.DB.prepare("SELECT * FROM licenses WHERE checkout_session = ?").bind(sessionID).first();
  if (!license) return error(404, "pending", "The payment is still being processed.");
  return json({ license_key: license.key, customer_email: license.email, test: license.test === 1, status: license.status });
}

/// „Zgubiłem klucz”: zawsze ta sama odpowiedź, żeby nie zdradzać, kto kupił.
async function resend(request, env) {
  const body = await readJson(request);
  const email = String(body.email ?? "").trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254) throw new BadRequest("Enter a valid email address.");
  const lang = body.lang === "pl" ? "pl" : "en";
  const { results } = await env.DB.prepare("SELECT * FROM licenses WHERE email = ? AND status = 'active' ORDER BY created_at").bind(email).all();
  const now = Date.now();
  const recent = results.some(l => l.resent_at && now - Date.parse(l.resent_at) < RESEND_COOLDOWN_MS);
  if (results.length && !recent) {
    const stamp = new Date(now).toISOString();
    await env.DB.prepare("UPDATE licenses SET resent_at = ? WHERE email = ?").bind(stamp, email).run();
    await sendEmail(env, email, licenseEmail(env, results, lang));
  }
  return json({ sent: true });
}

// ---------- Webhook Stripe ----------

async function stripeWebhook(request, env) {
  const payload = await readText(request);
  const header = request.headers.get("Stripe-Signature");
  // Sekret testowy nie może wydać licencji produkcyjnej i odwrotnie.
  let livemode = null;
  if (await verifyStripeSignature(payload, header, env.STRIPE_WEBHOOK_SECRET)) livemode = true;
  else if (await verifyStripeSignature(payload, header, env.STRIPE_WEBHOOK_SECRET_TEST)) livemode = false;
  if (livemode === null) return error(400, "bad_signature", "Invalid signature.");
  let event;
  try {
    event = JSON.parse(payload);
  } catch {
    throw new BadRequest("Invalid JSON.");
  }
  if (event.livemode !== livemode) return error(400, "bad_signature", "Mode mismatch.");
  const object = event.data?.object ?? {};
  switch (event.type) {
    case "checkout.session.completed":
      // Metody z opóźnioną płatnością kończą się później zdarzeniem async_payment_succeeded;
      // „no_payment_required” to kod rabatowy na 100% (np. dla recenzentów).
      if (object.payment_status === "paid" || object.payment_status === "no_payment_required") {
        await issueLicense(env, object, livemode);
      }
      break;
    case "checkout.session.async_payment_succeeded":
      await issueLicense(env, object, livemode);
      break;
    case "charge.refunded":
      if (object.refunded === true) await disableByPayment(env, object.payment_intent, "refund");
      break;
    case "charge.dispute.created":
      await disableByPayment(env, object.payment_intent, "dispute");
      break;
  }
  return json({ received: true });
}

async function issueLicense(env, session, livemode) {
  if (session.mode !== "payment" || typeof session.id !== "string") return;
  const links = (env.PAYMENT_LINKS ?? "").split(",").map(s => s.trim()).filter(Boolean);
  if (links.length && !links.includes(session.payment_link)) return; // inny produkt na tym koncie Stripe
  const email = String(session.customer_details?.email ?? session.customer_email ?? "").trim().toLowerCase();
  const country = session.customer_details?.address?.country ?? null;
  await env.DB.prepare(`INSERT INTO licenses (key, email, status, test, checkout_session, payment_intent, country, created_at)
      VALUES (?, ?, 'active', ?, ?, ?, ?, ?) ON CONFLICT (checkout_session) DO NOTHING`)
    .bind(generateKey(), email, livemode ? 0 : 1, session.id, session.payment_intent ?? null, country, new Date().toISOString())
    .run();
  const license = await env.DB.prepare("SELECT * FROM licenses WHERE checkout_session = ?").bind(session.id).first();
  // Ponowiony webhook dośle mail, jeśli poprzednia próba się nie udała.
  if (license && license.email && !license.emailed_at) {
    const lang = country === "PL" || String(session.locale ?? "").startsWith("pl") ? "pl" : "en";
    const sent = await sendEmail(env, license.email, licenseEmail(env, [license], lang), `seam-license-${license.key}`);
    if (sent) await env.DB.prepare("UPDATE licenses SET emailed_at = ? WHERE key = ?").bind(new Date().toISOString(), license.key).run();
  }
}

async function disableByPayment(env, paymentIntent, reason) {
  if (typeof paymentIntent !== "string" || !paymentIntent) return;
  await env.DB.prepare("UPDATE licenses SET status = 'disabled', note = ? WHERE payment_intent = ?")
    .bind(`${reason} ${new Date().toISOString()}`, paymentIntent).run();
}

// ---------- Pomocnicze ----------

class BadRequest extends Error {}

async function findLicense(env, key) {
  if (!key) return null;
  return env.DB.prepare("SELECT * FROM licenses WHERE key = ?").bind(key).first();
}

function licenseInfo(license) {
  return { status: license.status, test: license.test === 1 };
}

function maxDevices(env) {
  const value = Number.parseInt(env.MAX_DEVICES ?? "3", 10);
  return Number.isFinite(value) && value > 0 ? value : 3;
}

async function readText(request) {
  const text = await request.text();
  if (text.length > MAX_BODY_BYTES) throw new BadRequest("Request too large.");
  return text;
}

async function readJson(request) {
  try {
    const value = JSON.parse(await readText(request));
    if (value && typeof value === "object" && !Array.isArray(value)) return value;
  } catch (e) {
    if (e instanceof BadRequest) throw e;
  }
  throw new BadRequest("Send a JSON object.");
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

function error(status, code, message, extra = {}) {
  return json({ ...extra, code, error: message }, status);
}

function siteCors(request, env) {
  const origin = request.headers.get("Origin");
  const allowed = (env.SITE_ORIGINS ?? "https://seamdesk.app,https://www.seamdesk.app").split(",").map(s => s.trim());
  if (!origin || !allowed.includes(origin)) return null;
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
}

function withHeaders(response, headers) {
  if (!headers) return response;
  for (const [name, value] of Object.entries(headers)) response.headers.set(name, value);
  return response;
}
