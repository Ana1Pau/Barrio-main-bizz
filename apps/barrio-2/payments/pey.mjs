import { createHmac, timingSafeEqual } from 'node:crypto';

const API_BASE = 'https://api.pey.mx';

/**
 * Create a CoDi QR using an account already resolved by trusted server code.
 * Live requests require allowProduction=true. Inject fetchImpl for simulations.
 * Persist an internal idempotency key and this response in the caller's DB;
 * pey's documented QR endpoint does not promise idempotent creation.
 */
export async function createCodiQr({ amount, concept, expiration = 600, numRef, bankAccount }, {
  apiKey,
  allowProduction = false,
  fetchImpl = globalThis.fetch,
} = {}) {
  if (!Number.isFinite(amount) || amount <= 0) throw new TypeError('amount must be positive');
  if (typeof concept !== 'string' || !concept.trim() || concept.length > 100) throw new TypeError('concept is invalid');
  if (!Number.isInteger(expiration) || expiration < 360) throw new TypeError('expiration must be at least 360 seconds');
  if (typeof numRef !== 'string' || !/^[0-9]{1,7}$/.test(numRef)) throw new TypeError('numRef must contain 1 to 7 digits');
  if (!bankAccount || bankAccount.codiStatus !== 'ACTIVE' || !bankAccount.id) throw new TypeError('merchant bank account is not active');
  if (typeof apiKey !== 'string' || !apiKey) throw new Error('PEY_API_KEY is required');
  if (fetchImpl === globalThis.fetch && !allowProduction) throw new Error('production Pey requests are disabled');

  const response = await fetchImpl(`${API_BASE}/codi/qr`, {
    method: 'POST',
    headers: { authorization: `Bearer ${apiKey}`, 'content-type': 'application/json', accept: 'application/json' },
    body: JSON.stringify({ amount, concept: concept.trim(), expiration, numRef, generateImage: false, bankAccountId: bankAccount.id }),
  });
  const payload = await response.json();
  if (!response.ok) {
    const error = new Error(`Pey QR request failed (${response.status})`);
    error.status = response.status;
    error.requestId = payload?.error?.requestId;
    throw error;
  }
  if (typeof payload?.id !== 'string' || typeof payload?.qrString !== 'string') {
    throw new Error('Pey returned an invalid QR response');
  }
  return { id: payload.id, qrString: payload.qrString };
}

/** Verify Standard Webhooks headers against the exact raw request body. */
export function verifyPeyWebhook({ rawBody, webhookId, timestamp, signature }, secret, {
  now = Date.now(), toleranceSeconds = 300,
} = {}) {
  if (!Buffer.isBuffer(rawBody)) throw new TypeError('rawBody must be the original Buffer');
  if (!webhookId || !timestamp || !signature || !secret) return false;
  const time = Number(timestamp);
  if (!Number.isInteger(time) || Math.abs(Math.floor(now / 1000) - time) > toleranceSeconds) return false;

  const encodedSecret = secret.startsWith('whsec_') ? secret.slice(6) : secret;
  let key;
  try { key = Buffer.from(encodedSecret, 'base64'); } catch { return false; }
  if (!key.length) return false;
  const signedContent = Buffer.concat([
    Buffer.from(`${webhookId}.${timestamp}.`, 'utf8'),
    rawBody,
  ]);
  const expected = createHmac('sha256', key).update(signedContent).digest('base64');
  return signature.split(/\s+/).some((entry) => {
    const [version, value] = entry.split(',', 2);
    if (version !== 'v1' || !value) return false;
    const actualBytes = Buffer.from(value);
    const expectedBytes = Buffer.from(expected);
    return actualBytes.length === expectedBytes.length && timingSafeEqual(actualBytes, expectedBytes);
  });
}
