import test from 'node:test';
import assert from 'node:assert/strict';
import { createHmac, randomBytes } from 'node:crypto';
import { createCodiQr, verifyPeyWebhook } from './pey.mjs';

const activeAccount = { id: '01JTESTBANKACCOUNT000000000', codiStatus: 'ACTIVE' };

test('simulated QR sends fixed amount and the resolved active merchant account', async () => {
  let request;
  const fetchImpl = async (url, options) => {
    request = { url, options };
    return new Response(JSON.stringify({ id: 'QR-SIM-1', qrString: 'SIMULATED-QR' }), { status: 201 });
  };
  const result = await createCodiQr({ amount: 42.5, concept: 'Pedido BR-1001', expiration: 600, numRef: '1001', bankAccount: activeAccount }, {
    apiKey: 'test-key-never-sent-to-network', fetchImpl,
  });
  assert.deepEqual(result, { id: 'QR-SIM-1', qrString: 'SIMULATED-QR' });
  assert.equal(request.url, 'https://api.pey.mx/codi/qr');
  assert.equal(request.options.headers.authorization, 'Bearer test-key-never-sent-to-network');
  assert.deepEqual(JSON.parse(request.options.body), {
    amount: 42.5, concept: 'Pedido BR-1001', expiration: 600, numRef: '1001',
    generateImage: false, bankAccountId: activeAccount.id,
  });
});

test('QR creation rejects invalid amount, inactive account, and implicit live requests', async () => {
  const args = { amount: 10, concept: 'Pedido', numRef: '123', bankAccount: activeAccount };
  await assert.rejects(createCodiQr({ ...args, amount: 0 }, { apiKey: 'x', fetchImpl: async () => {} }), /amount/);
  await assert.rejects(createCodiQr({ ...args, bankAccount: { ...activeAccount, codiStatus: 'PENDING' } }, { apiKey: 'x', fetchImpl: async () => {} }), /not active/);
  await assert.rejects(createCodiQr(args, { apiKey: 'x' }), /production Pey requests are disabled/);
});

test('webhook signature verifies exact bytes and rejects tampering and stale timestamps', () => {
  const secret = `whsec_${randomBytes(32).toString('base64')}`;
  const rawBody = Buffer.from('{"type":"codi.qr.payment_received","amount":42.5}', 'utf8');
  const webhookId = 'msg_simulated_123';
  const timestamp = '1794078000';
  const now = Number(timestamp) * 1000;
  const key = Buffer.from(secret.slice(6), 'base64');
  const signature = createHmac('sha256', key).update(`${webhookId}.${timestamp}.`).update(rawBody).digest('base64');
  const headers = { rawBody, webhookId, timestamp, signature: `v1,${signature}` };

  assert.equal(verifyPeyWebhook(headers, secret, { now }), true);
  assert.equal(verifyPeyWebhook({ ...headers, rawBody: Buffer.from(`${rawBody.toString()} `) }, secret, { now }), false);
  assert.equal(verifyPeyWebhook(headers, secret, { now: now + 301_000 }), false);
  assert.equal(verifyPeyWebhook(headers, 'whsec_invalid', { now }), false);
});
