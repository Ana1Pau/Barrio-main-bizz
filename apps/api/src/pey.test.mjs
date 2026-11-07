import test from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { createQr, getBankAccount, registerBankAccount, verifyPeyWebhook } from './pey.mjs';

test('Pey adapter validates charge and account input without network access', async () => {
  await assert.rejects(createQr({ amount: -1 }, 'never-used'), /Invalid charge/);
  await assert.rejects(getBankAccount('bad-id', 'never-used'), /Invalid Pey bank/);
  await assert.rejects(registerBankAccount({ clabe: '123', name: 'A', entity: 'person' }, 'never-used'), /CLABE/);
  await assert.rejects(createQr({ amount: 20, concept: 'B', expiration: 600, numRef: '123', bankAccountId: 'account' }, 'never-used'), /Live Pey calls are disabled/);
});

test('Pey requests use a mocked transport and webhook signatures are checked', async () => {
  const calls = [];
  const fakeFetch = async (url, options) => {
    calls.push({ url, options });
    return { ok: true, json: async () => ({ id: 'qr-test', qrString: 'simulated-qr' }) };
  };
  const result = await createQr({ amount: 19.99, concept: 'pedido', expiration: 600, numRef: '1234567', bankAccountId: 'bank-test', metadata: { test: true } }, 'dummy-key', { fetchImpl: fakeFetch });
  assert.equal(result.id, 'qr-test');
  assert.equal(calls.length, 1);
  assert.match(calls[0].url, /\/codi\/qr$/);
  assert.equal(calls[0].options.headers.authorization, 'Bearer dummy-key');

  const rawBody = Buffer.from('{"type":"test"}');
  const secretBytes = Buffer.from('test-webhook-secret');
  const secret = `whsec_${secretBytes.toString('base64')}`;
  const webhookId = 'evt_test_123';
  const timestamp = '1700000000';
  const signature = createHmac('sha256', secretBytes).update(Buffer.concat([Buffer.from(`${webhookId}.${timestamp}.`), rawBody])).digest('base64');
  const headers = { rawBody, webhookId, timestamp, signature: `v1,${signature}` };
  assert.equal(verifyPeyWebhook(headers, secret, { now: 1700000000000 }), true);
  assert.equal(verifyPeyWebhook({ ...headers, rawBody: Buffer.from('tampered') }, secret, { now: 1700000000000 }), false);
  assert.equal(verifyPeyWebhook(headers, secret, { now: 1700001000000 }), false);
});
