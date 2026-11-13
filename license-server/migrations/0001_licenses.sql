-- Licencje Seam Pro. Klucz wydaje webhook Stripe po zapłacie (albo ręcznie, patrz README).
CREATE TABLE licenses (
  key TEXT PRIMARY KEY,                 -- SEAM-XXXXX-XXXXX-XXXXX-XXXXX
  email TEXT NOT NULL,                  -- małymi literami
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disabled')),
  test INTEGER NOT NULL DEFAULT 0,      -- 1 = tryb testowy Stripe, przyjmują go tylko buildy kanału dev
  checkout_session TEXT UNIQUE,         -- cs_live_… / cs_test_…; NULL dla licencji wydanych ręcznie
  payment_intent TEXT,                  -- do zwrotów i sporów
  country TEXT,
  created_at TEXT NOT NULL,
  emailed_at TEXT,
  resent_at TEXT,
  note TEXT
);
CREATE INDEX licenses_email ON licenses (email);
CREATE INDEX licenses_payment_intent ON licenses (payment_intent);

-- Komputery z aktywną licencją (limit MAX_DEVICES na klucz).
CREATE TABLE instances (
  id TEXT PRIMARY KEY,
  license_key TEXT NOT NULL REFERENCES licenses (key) ON DELETE CASCADE,
  name TEXT NOT NULL,
  created_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL
);
CREATE INDEX instances_license ON instances (license_key);
