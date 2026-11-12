// Klucze licencji: SEAM- i 20 znaków alfabetu Crockforda (100 bitów losowości), w grupach po 5.
const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

export const KEY_PATTERN = /^SEAM(-[0-9A-HJKMNP-TV-Z]{5}){4}$/;

export function generateKey() {
  const bytes = crypto.getRandomValues(new Uint8Array(20));
  // 256 dzieli się przez 32, więc & 31 nie faworyzuje żadnego znaku
  const chars = Array.from(bytes, b => ALPHABET[b & 31]).join("");
  return "SEAM-" + chars.match(/.{5}/g).join("-");
}

/// Klucz wpisany ręcznie: wielkość liter, spacje i myślniki bez znaczenia, O→0 i I/L→1 jak u Crockforda.
export function normalizeKey(raw) {
  if (typeof raw !== "string") return "";
  const compact = raw.toUpperCase().replace(/[^0-9A-Z]/g, "");
  if (!compact.startsWith("SEAM")) return compact;
  const body = compact.slice(4).replace(/O/g, "0").replace(/[IL]/g, "1");
  if (!/^[0-9A-HJKMNP-TV-Z]{20}$/.test(body)) return "SEAM" + body;
  return "SEAM-" + body.match(/.{5}/g).join("-");
}
