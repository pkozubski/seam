import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import worker from "../src/index.js";
import { generateKey, normalizeKey, KEY_PATTERN } from "../src/keys.js";
import { stripeSignature, verifyStripeSignature } from "../src/stripe.js";
import { createD1 } from "./d1.js";

const fixture = JSON.parse(readFileSync(new URL("../../tests/fixtures/license-api.json", import.meta.url), "utf8"));
const LIVE_SECRET = "whsec_live_secret";
const TEST_SECRET = "whsec_test_secret";

let env;
let sentEmails;
let realFetch;

beforeEach(() => {
  env = {
    DB: createD1(),
    STRIPE_WEBHOOK_SECRET: LIVE_SECRET,
    STRIPE_WEBHOOK_SECRET_TEST: TEST_SECRET,
    RESEND_API_KEY: "re_test",
    MAX_DEVICES: "3",
    PAYMENT_LINKS: "",
  };
  sentEmails = [];
  realFetch = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    assert.equal(url, "https://api.resend.com/emails");
    sentEmails.push(JSON.parse(init.body));
    return new Response(JSON.stringify({ id: "email" }), { status: 200 });
  };
});

afterEach(() => {
  globalThis.fetch = realFetch;
});

// ---------- pomocnicze ----------

async function call(method, path, body, headers = {}) {
  const init = { method, headers: { "Content-Type": "application/json", ...headers } };
  if (body !== undefined) init.body = typeof body === "string" ? body : JSON.stringify(body);
  const response = await worker.fetch(new Request(`https://api.seamdesk.app${path}`, init), env);
  const text = await response.text();
  return { status: response.status, body: text ? JSON.parse(text) : null, headers: response.headers };
}

async function webhook(event, secret = LIVE_SECRET, timestamp = Math.floor(Date.now() / 1000)) {
  const payload = JSON.stringify(event);
  const signature = await stripeSignature(payload, secret, timestamp);
  return call("POST", "/v1/stripe/webhook", payload, { "Stripe-Signature": `t=${timestamp},v1=${signature},v0=deadbeef` });
}

function checkoutCompleted(id, overrides = {}) {
  return {
    id: `evt_${id}`,
    type: "checkout.session.completed",
    livemode: !id.startsWith("cs_test_"),
    data: {
      object: {
        id,
        object: "checkout.session",
        mode: "payment",
        payment_status: "paid",
        payment_intent: `pi_${id}`,
        payment_link: "plink_seam",
        customer_details: { email: "Buyer@Example.com", address: { country: "DE" } },
        ...overrides,
      },
    },
  };
}

async function buy(id = "cs_live_a1b2c3d4e5f6g7h8") {
  assert.equal((await webhook(checkoutCompleted(id), id.startsWith("cs_test_") ? TEST_SECRET : LIVE_SECRET)).status, 200);
  const { body } = await call("GET", `/v1/checkout/${id}`);
  return body.license_key;
}

const activate = (key, name) => call("POST", "/v1/licenses/activate", { license_key: key, instance_name: name });
const validate = (key, id) => call("POST", "/v1/licenses/validate", { license_key: key, instance_id: id });
const deactivate = (key, id) => call("POST", "/v1/licenses/deactivate", { license_key: key, instance_id: id });

/// Kształt odpowiedzi (klucze, rekurencyjnie) do porównania z wektorami w tests/fixtures/license-api.json.
function shape(value) {
  if (value === null || typeof value !== "object") return value === null ? "null" : typeof value;
  return Object.fromEntries(Object.keys(value).sort().map(k => [k, shape(value[k])]));
}

function assertFixtureShape(name, actual) {
  const item = fixture.cases.find(c => c.name === name);
  assert.ok(item, `fixture case ${name}`);
  assert.deepEqual(shape(actual.body), shape(item.body), `${name}: shape`);
  assert.equal(actual.status, item.http, `${name}: HTTP status`);
}

// ---------- klucze ----------

test("generated keys match the shared pattern and are unique", () => {
  const pattern = new RegExp(fixture.keyPattern);
  const keys = new Set(Array.from({ length: 500 }, generateKey));
  assert.equal(keys.size, 500);
  for (const key of keys) {
    assert.match(key, pattern);
    assert.match(key, KEY_PATTERN);
  }
});

test("typed keys are normalized", () => {
  assert.equal(normalizeKey(" seam-abcde-fghjk-mnpqr-stvwx\n"), "SEAM-ABCDE-FGHJK-MNPQR-STVWX");
  assert.equal(normalizeKey("SEAM ABCDE FGHJK MNPQR STVWX"), "SEAM-ABCDE-FGHJK-MNPQR-STVWX");
  assert.equal(normalizeKey("SEAM-ABCDE"), "SEAMABCDE", "too short stays unknown");
  assert.equal(normalizeKey("SEAM-0O1IL-AAAAA-BBBBB-CCCCC"), "SEAM-00111-AAAAA-BBBBB-CCCCC");
  assert.equal(normalizeKey(42), "");
});

// ---------- podpis Stripe ----------

test("Stripe signature: valid, wrong secret, tampered, expired, v0 only", async () => {
  const payload = '{"id":"evt_1"}';
  const now = 1_800_000_000;
  const v1 = await stripeSignature(payload, LIVE_SECRET, now);
  assert.equal(await verifyStripeSignature(payload, `t=${now},v1=${v1}`, LIVE_SECRET, now), true);
  assert.equal(await verifyStripeSignature(payload, `t=${now},v1=bad,v1=${v1}`, LIVE_SECRET, now), true, "rolled secret: any v1 matches");
  assert.equal(await verifyStripeSignature(payload, `t=${now},v1=${v1}`, TEST_SECRET, now), false);
  assert.equal(await verifyStripeSignature(payload + " ", `t=${now},v1=${v1}`, LIVE_SECRET, now), false);
  assert.equal(await verifyStripeSignature(payload, `t=${now},v1=${v1}`, LIVE_SECRET, now + 301), false);
  assert.equal(await verifyStripeSignature(payload, `t=${now},v0=${v1}`, LIVE_SECRET, now), false);
  assert.equal(await verifyStripeSignature(payload, null, LIVE_SECRET, now), false);
  assert.equal(await verifyStripeSignature(payload, `t=${now},v1=${v1}`, undefined, now), false);
});

// ---------- webhook ----------

test("paid checkout issues one license and one email, also on webhook retries", async () => {
  const id = "cs_live_a1b2c3d4e5f6g7h8";
  assert.equal((await webhook(checkoutCompleted(id))).status, 200);
  assert.equal((await webhook(checkoutCompleted(id))).status, 200);
  const { status, body } = await call("GET", `/v1/checkout/${id}`);
  assert.equal(status, 200);
  assert.match(body.license_key, KEY_PATTERN);
  assert.equal(body.customer_email, "buyer@example.com");
  assert.equal(body.test, false);
  assert.equal(sentEmails.length, 1);
  assert.deepEqual(sentEmails[0].to, ["buyer@example.com"]);
  assert.ok(sentEmails[0].text.includes(body.license_key));
  assert.equal(sentEmails[0].subject, "Your Seam Pro license key");
  const { results } = await env.DB.prepare("SELECT * FROM licenses").all();
  assert.equal(results.length, 1);
});

test("Polish buyers get the Polish email", async () => {
  await webhook(checkoutCompleted("cs_live_polishbuyer01", { customer_details: { email: "kupujacy@example.pl", address: { country: "PL" } } }));
  assert.equal(sentEmails[0].subject, "Twój klucz licencji Seam Pro");
});

test("failed email is retried by the next webhook delivery", async () => {
  const id = "cs_live_emailretry0001";
  globalThis.fetch = async () => new Response("down", { status: 503 });
  assert.equal((await webhook(checkoutCompleted(id))).status, 500);
  globalThis.fetch = async (_, init) => { sentEmails.push(JSON.parse(init.body)); return new Response("{}", { status: 200 }); };
  assert.equal((await webhook(checkoutCompleted(id))).status, 200);
  assert.equal(sentEmails.length, 1);
  const { results } = await env.DB.prepare("SELECT * FROM licenses").all();
  assert.equal(results.length, 1, "retry keeps the same key");
});

test("unpaid checkout waits for async_payment_succeeded", async () => {
  const id = "cs_live_sepapayment001";
  await webhook(checkoutCompleted(id, { payment_status: "unpaid" }));
  assert.equal((await call("GET", `/v1/checkout/${id}`)).status, 404);
  const succeeded = checkoutCompleted(id);
  succeeded.type = "checkout.session.async_payment_succeeded";
  await webhook(succeeded);
  assert.equal((await call("GET", `/v1/checkout/${id}`)).status, 200);
});

test("100% coupon (no_payment_required) still issues a license", async () => {
  const id = "cs_live_freecoupon0001";
  await webhook(checkoutCompleted(id, { payment_status: "no_payment_required", payment_intent: null }));
  assert.equal((await call("GET", `/v1/checkout/${id}`)).status, 200);
});

test("other payment links are ignored when PAYMENT_LINKS is set", async () => {
  env.PAYMENT_LINKS = "plink_other";
  await webhook(checkoutCompleted("cs_live_otherproduct01"));
  assert.equal((await call("GET", "/v1/checkout/cs_live_otherproduct01")).status, 404);
  env.PAYMENT_LINKS = "plink_other, plink_seam";
  await webhook(checkoutCompleted("cs_live_seamproduct001"));
  assert.equal((await call("GET", "/v1/checkout/cs_live_seamproduct001")).status, 200);
});

test("bad signatures and mode mismatches are rejected", async () => {
  const event = checkoutCompleted("cs_live_forged00000001");
  const payload = JSON.stringify(event);
  const forged = await call("POST", "/v1/stripe/webhook", payload, { "Stripe-Signature": "t=1,v1=00" });
  assert.equal(forged.status, 400);
  // sekret testowy nie wyda licencji produkcyjnej
  assert.equal((await webhook(event, TEST_SECRET)).status, 400);
  const testEvent = checkoutCompleted("cs_test_testmode000001");
  assert.equal((await webhook(testEvent, LIVE_SECRET)).status, 400);
  assert.equal((await env.DB.prepare("SELECT COUNT(*) AS n FROM licenses").first("n")), 0);
});

test("test-mode purchases are marked as test licenses", async () => {
  const key = await buy("cs_test_testmode000002");
  const { body } = await activate(key, "Dev Mac");
  assert.equal(body.license.test, true);
  assert.ok(sentEmails[0].text.includes("TEST MODE"));
});

// ---------- aktywacja ----------

test("activation: device limit, same name reuses its slot, deactivation frees one", async () => {
  const key = await buy();
  const mac = await activate(key, "MacBook");
  assertFixtureShape("activate: ok", mac);
  const again = await activate(key.toLowerCase().replace(/-/g, " "), "MacBook");
  assert.equal(again.body.instance.id, mac.body.instance.id, "reinstall keeps the slot");
  const pc = await activate(key, "Gaming PC");
  await activate(key, "Office PC");
  const fourth = await activate(key, "Laptop");
  assertFixtureShape("activate: device limit", fourth);
  assert.equal(fourth.body.code, "device_limit");

  assertFixtureShape("deactivate: ok", await deactivate(key, pc.body.instance.id));
  assert.equal((await deactivate(key, pc.body.instance.id)).status, 200, "deactivating twice is fine");
  assert.equal((await activate(key, "Laptop")).status, 200);
  assertFixtureShape("validate: deactivated on another computer", await validate(key, pc.body.instance.id));
  assertFixtureShape("validate: ok", await validate(key, mac.body.instance.id));
});

test("unknown keys", async () => {
  assertFixtureShape("activate: unknown key", await activate("SEAM-AAAAA-BBBBB-CCCCC-DDDDD", "Mac"));
  assertFixtureShape("validate: unknown key", await validate("SEAM-AAAAA-BBBBB-CCCCC-DDDDD", "x"));
  assertFixtureShape("deactivate: unknown key", await deactivate("SEAM-AAAAA-BBBBB-CCCCC-DDDDD", "x"));
});

test("refund and dispute disable the license", async () => {
  const id = "cs_live_refunded000001";
  const key = await buy(id);
  const mac = await activate(key, "Mac");
  await webhook({ id: "evt_r", type: "charge.refunded", livemode: true, data: { object: { refunded: false, payment_intent: `pi_${id}` } } });
  assert.equal((await validate(key, mac.body.instance.id)).body.valid, true, "partial refund keeps the license");
  await webhook({ id: "evt_r2", type: "charge.refunded", livemode: true, data: { object: { refunded: true, payment_intent: `pi_${id}` } } });
  assertFixtureShape("validate: refunded", await validate(key, mac.body.instance.id));
  assert.equal((await validate(key, mac.body.instance.id)).body.license.status, "disabled");
  assertFixtureShape("activate: refunded license", await activate(key, "PC"));

  const disputed = await buy("cs_live_disputed000001");
  await webhook({ id: "evt_d", type: "charge.dispute.created", livemode: true, data: { object: { payment_intent: "pi_cs_live_disputed000001" } } });
  assert.equal((await activate(disputed, "PC")).body.code, "license_disabled");
});

test("bad requests", async () => {
  const notJson = await call("POST", "/v1/licenses/activate", "nope");
  assertFixtureShape("activate: unexpected code keeps the server message", notJson);
  assert.equal((await call("GET", "/v1/checkout/not-a-session")).status, 404);
  assert.equal((await call("POST", "/v1/licenses/activate", "x".repeat(70_000))).status, 400);
});

// ---------- strona ----------

test("resend: same answer for everyone, one email per 10 minutes", async () => {
  await buy("cs_live_resendbuyer001");
  await buy("cs_live_resendbuyer002");
  sentEmails.length = 0;
  assert.deepEqual((await call("POST", "/v1/licenses/resend", { email: "nobody@example.com" })).body, { sent: true });
  assert.equal(sentEmails.length, 0);
  assert.deepEqual((await call("POST", "/v1/licenses/resend", { email: " BUYER@example.com ", lang: "pl" })).body, { sent: true });
  assert.equal(sentEmails.length, 1);
  assert.equal(sentEmails[0].subject, "Twoje klucze licencji Seam Pro");
  assert.equal(sentEmails[0].text.match(/SEAM-/g).length, 2);
  await call("POST", "/v1/licenses/resend", { email: "buyer@example.com" });
  assert.equal(sentEmails.length, 1, "cooldown");
  assert.equal((await call("POST", "/v1/licenses/resend", { email: "not an email" })).status, 400);
});

test("CORS only for the site", async () => {
  const site = await call("GET", "/v1/checkout/cs_live_unknown0000001", undefined, { Origin: "https://seamdesk.app" });
  assert.equal(site.headers.get("Access-Control-Allow-Origin"), "https://seamdesk.app");
  const other = await call("GET", "/v1/checkout/cs_live_unknown0000001", undefined, { Origin: "https://evil.example" });
  assert.equal(other.headers.get("Access-Control-Allow-Origin"), null);
  const preflight = await worker.fetch(new Request("https://api.seamdesk.app/v1/licenses/resend", {
    method: "OPTIONS", headers: { Origin: "https://www.seamdesk.app" },
  }), env);
  assert.equal(preflight.status, 204);
});
