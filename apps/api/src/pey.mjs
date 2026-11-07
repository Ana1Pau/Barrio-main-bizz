import { createHmac, timingSafeEqual } from 'node:crypto';
const BASE = 'https://api.pey.mx';

async function requestPey(path, apiKey, body, { allowProduction = false, fetchImpl = globalThis.fetch } = {}) {
  if (typeof apiKey !== 'string' || !apiKey) throw new Error('PEY_API_KEY is required');
  if (fetchImpl === globalThis.fetch && !allowProduction) throw new Error('Live Pey calls are disabled');
  const response = await fetchImpl(`${BASE}${path}`, {
    method: body ? 'POST' : 'GET',
    headers: { authorization: `Bearer ${apiKey}`, accept: 'application/json', ...(body ? { 'content-type': 'application/json' } : {}) },
    ...(body ? { body: JSON.stringify(body) } : {}),
    signal: AbortSignal.timeout(12000),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(`Pey request failed (${response.status})`);
    error.status = response.status;
    error.requestId = data?.error?.requestId;
    throw error;
  }
  return data;
}

export async function registerBankAccount(input, apiKey, options = {}) {
  if (!/^\d{18}$/.test(input.clabe || '')) throw new TypeError('CLABE must contain 18 digits');
  if (!input.name || !['business', 'person'].includes(input.entity)) throw new TypeError('Account owner details are required');
  return requestPey('/bank-account', apiKey, {
    clabe: input.clabe, name: input.name, entity: input.entity,
    ...(input.alias ? { alias: input.alias } : {}), ...(input.taxId ? { taxId: input.taxId } : {}),
  }, options);
}

export async function getBankAccount(id, apiKey, options = {}) {
  if (!/^[0-9A-HJKMNP-TV-Z]{26}$/i.test(id || '')) throw new TypeError('Invalid Pey bank account id');
  return requestPey(`/bank-account/${encodeURIComponent(id)}`, apiKey, undefined, options);
}

export async function createQr({ amount, concept, expiration, numRef, bankAccountId, metadata }, apiKey, options = {}) {
  if (!Number.isFinite(amount) || amount <= 0 || amount > 1000000) throw new TypeError('Invalid charge amount');
  if (!Number.isInteger(expiration) || expiration < 360) throw new TypeError('QR expiration must be at least 360 seconds');
  if (!/^[0-9]{1,7}$/.test(numRef)) throw new TypeError('Reference must have 1 to 7 digits');
  if (!bankAccountId) throw new TypeError('Merchant bank account is required');
  return requestPey('/codi/qr', apiKey, { amount, concept, expiration, numRef, bankAccountId, generateImage: false, metadata }, options);
}

export function verifyPeyWebhook({ rawBody, webhookId, timestamp, signature }, secret, {
  now = Date.now(), toleranceSeconds = 300,
} = {}) {
  if (!Buffer.isBuffer(rawBody) || !webhookId || !timestamp || !signature || !secret) return false;
  const timestampNumber = Number(timestamp);
  if (!Number.isInteger(timestampNumber) || Math.abs(Math.floor(now / 1000) - timestampNumber) > toleranceSeconds) return false;
  const encodedSecret = secret.startsWith('whsec_') ? secret.slice(6) : secret;
  const key = Buffer.from(encodedSecret, 'base64');
  if (!key.length) return false;
  const expected = createHmac('sha256', key).update(Buffer.concat([Buffer.from(`${webhookId}.${timestamp}.`), rawBody])).digest();
  return signature.split(/\s+/).some((entry) => {
    const [version, value] = entry.split(',', 2);
    if (version !== 'v1' || !value) return false;
    const actual = Buffer.from(value, 'base64');
    return actual.length === expected.length && timingSafeEqual(actual, expected);
  });
}
