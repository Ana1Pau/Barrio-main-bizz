import express from 'express';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import QRCode from 'qrcode';
import { fileURLToPath } from 'node:url';
import { loadConfig } from './config.mjs';
import { closePool, execute, query, sql } from './db.mjs';
import { hashPassword, verifyPassword, issueAccessToken, verifyAccessToken } from './security.mjs';
import { createQr, getBankAccount, registerBankAccount, verifyPeyWebhook } from './pey.mjs';

const config = loadConfig();
const app = express();
app.disable('x-powered-by');
app.set('trust proxy', config.nodeEnv === 'production' ? 1 : false);
app.use(helmet({ contentSecurityPolicy: { directives: { imgSrc: ["'self'", 'data:'] } } }));
app.use(express.static(fileURLToPath(new URL('../public/', import.meta.url)), { maxAge: config.nodeEnv === 'production' ? '1h' : 0 }));
app.use((req, res, next) => {
  const origin = req.headers.origin;
  if (!origin) return next();
  if (!config.corsOrigins.includes(origin)) return res.status(403).json({ error: 'origin_not_allowed' });
  res.setHeader('Access-Control-Allow-Origin', origin);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Headers', 'authorization,content-type,idempotency-key');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  if (req.method === 'OPTIONS') return res.status(204).end();
  next();
});

const authLimiter = rateLimit({ windowMs: 15 * 60 * 1000, limit: 20, standardHeaders: 'draft-8', legacyHeaders: false });
const jsonParser = express.json({ limit: '64kb', type: 'application/json' });
app.get('/healthz', async (_req, res) => {
  try { await query(config.db, 'SELECT 1 AS ok'); res.json({ ok: true }); }
  catch { res.status(503).json({ ok: false }); }
});

function bearer(req, res, next) {
  const token = req.headers.authorization?.match(/^Bearer (.+)$/)?.[1];
  const claims = verifyAccessToken(token, config.jwtSecret);
  if (!claims) return res.status(401).json({ error: 'unauthorized' });
  req.user = claims;
  next();
}
function requireRole(role) {
  return (req, res, next) => req.user.roles.includes(role) ? next() : res.status(403).json({ error: 'forbidden' });
}
const id = (value) => /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value || '');

app.post('/api/v1/auth/register', authLimiter, jsonParser, async (req, res, next) => {
  try {
    const { email, phone, password, displayName, accountType = 'buyer' } = req.body || {};
    if (typeof email !== 'string' || !/^\S+@\S+\.\S+$/.test(email) || email.length > 256) return res.status(422).json({ error: 'valid_email_required' });
    if (typeof password !== 'string' || password.length < 12 || password.length > 128) return res.status(422).json({ error: 'password_must_be_12_to_128_characters' });
    if (typeof displayName !== 'string' || !displayName.trim() || displayName.length > 100) return res.status(422).json({ error: 'display_name_required' });
    if (!['buyer', 'merchant'].includes(accountType)) return res.status(422).json({ error: 'invalid_account_type' });
    const { salt, hash } = await hashPassword(password);
    const result = await execute(config.db, 'app.sp_RegistrarUsuario', (r, t) => r
      .input('Correo', t.NVarChar(256), email.toLowerCase())
      .input('Telefono', t.NVarChar(20), phone || null)
      .input('HashContrasena', t.VarBinary(256), hash)
      .input('SalContrasena', t.VarBinary(64), salt)
      .input('TipoUso', t.TinyInt, accountType === 'buyer' ? 1 : 2)
      .input('NombreMostrar', t.NVarChar(100), displayName.trim())
      .input('ColoniaId', t.Int, null)
      .output('UsuarioId', t.UniqueIdentifier));
    const userId = result.output.UsuarioId;
    const roles = accountType === 'buyer' ? ['Comprador'] : ['Comercio'];
    return res.status(201).json({ token: issueAccessToken(userId, roles, config.jwtSecret), user: { userId, roles } });
  } catch (err) { next(err); }
});

app.post('/api/v1/auth/login', authLimiter, jsonParser, async (req, res, next) => {
  try {
    const email = typeof req.body?.email === 'string' ? req.body.email.toLowerCase() : '';
    const password = req.body?.password;
    if (!email || typeof password !== 'string') return res.status(422).json({ error: 'email_and_password_required' });
    const result = await execute(config.db, 'app.sp_ObtenerCredencialLogin', (r, t) => r.input('Correo', t.NVarChar(256), email));
    const record = result.recordset?.[0];
    if (!record || !await verifyPassword(password, record.SalContrasena, record.HashContrasena)) return res.status(401).json({ error: 'invalid_credentials' });
    const roles = String(record.RolesCsv || '').split(',').filter(Boolean);
    return res.json({ token: issueAccessToken(record.UsuarioId, roles, config.jwtSecret), user: { userId: record.UsuarioId, roles } });
  } catch (err) { next(err); }
});

app.get('/api/v1/auth/me', bearer, (req, res) => res.json({ userId: req.user.sub, roles: req.user.roles }));

app.get('/api/v1/merchants', async (_req, res, next) => {
  try {
    const result = await query(config.db, 'SELECT TOP (200) ComercioId AS id, NombreNegocio AS name, Descripcion AS description, Colonia, Latitud AS latitude, Longitud AS longitude FROM app.PerfilPublicoComercio ORDER BY NombreNegocio');
    res.json({ items: result.recordset });
  } catch (err) { next(err); }
});
app.get('/api/v1/merchants/:merchantId/products', async (req, res, next) => {
  try {
    if (!id(req.params.merchantId)) return res.status(400).json({ error: 'invalid_merchant_id' });
    const result = await query(config.db, `SELECT ProductoId AS id, ComercioId AS merchantId, Nombre AS name, DescripcionCorta AS description, Precio AS priceMXN, Existencias AS stock FROM app.ProductosPublicos WHERE ComercioId=@merchantId AND Existencias>0 ORDER BY Nombre`, (r, t) => r.input('merchantId', t.UniqueIdentifier, req.params.merchantId));
    res.json({ items: result.recordset });
  } catch (err) { next(err); }
});

app.post('/api/v1/merchant/profile', bearer, requireRole('Comercio'), jsonParser, async (req, res, next) => {
  try {
    const { name, description = null, neighborhoodId = null } = req.body || {};
    if (typeof name !== 'string' || !name.trim() || name.length > 150) return res.status(422).json({ error: 'valid_business_name_required' });
    if (description !== null && (typeof description !== 'string' || description.length > 500)) return res.status(422).json({ error: 'invalid_description' });
    if (neighborhoodId !== null && (!Number.isInteger(neighborhoodId) || neighborhoodId < 1)) return res.status(422).json({ error: 'invalid_neighborhood_id' });
    const result = await execute(config.db, 'app.sp_CrearComercioPropio', (r, t) => r
      .input('UsuarioId', t.UniqueIdentifier, req.user.sub)
      .input('NombreNegocio', t.NVarChar(150), name.trim())
      .input('Descripcion', t.NVarChar(500), description)
      .input('ColoniaId', t.Int, neighborhoodId)
      .output('ComercioId', t.UniqueIdentifier));
    res.status(201).json({ merchantId: result.output.ComercioId, name: name.trim() });
  } catch (err) { next(err); }
});

app.get('/api/v1/merchant/profile', bearer, requireRole('Comercio'), async (req, res, next) => {
  try {
    const result = await execute(config.db, 'app.sp_ObtenerComercioPropio', (r, t) => r.input('UsuarioId', t.UniqueIdentifier, req.user.sub));
    const merchant = result.recordset?.[0];
    if (!merchant) return res.status(404).json({ error: 'merchant_profile_required' });
    res.json({ merchant });
  } catch (err) { next(err); }
});

app.post('/api/v1/merchant/products', bearer, requireRole('Comercio'), jsonParser, async (req, res, next) => {
  try {
    const { name, description = null, priceMXN, stock } = req.body || {};
    if (typeof name !== 'string' || !name.trim() || name.length > 150 || !Number.isFinite(priceMXN) || priceMXN <= 0 || !Number.isInteger(stock) || stock < 0) return res.status(422).json({ error: 'invalid_product' });
    if (description !== null && (typeof description !== 'string' || description.length > 160)) return res.status(422).json({ error: 'invalid_description' });
    const merchant = await execute(config.db, 'app.sp_ObtenerComercioPropio', (r, t) => r.input('UsuarioId', t.UniqueIdentifier, req.user.sub));
    const merchantId = merchant.recordset?.[0]?.ComercioId;
    if (!merchantId) return res.status(409).json({ error: 'merchant_profile_required' });
    const created = await execute(config.db, 'app.sp_GuardarProductoPropio', (r, t) => r
      .input('UsuarioId', t.UniqueIdentifier, req.user.sub)
      .input('ComercioId', t.UniqueIdentifier, merchantId)
      .input('Nombre', t.NVarChar(150), name.trim())
      .input('DescripcionCorta', t.NVarChar(160), description)
      .input('Precio', t.Decimal(10, 2), priceMXN)
      .input('Existencias', t.Int, stock)
      .output('ProductoId', t.UniqueIdentifier));
    res.status(201).json({ productId: created.output.ProductoId, merchantId });
  } catch (err) { next(err); }
});

app.post('/api/v1/merchant/bank-account', bearer, requireRole('Comercio'), authLimiter, jsonParser, async (req, res, next) => {
  try {
    if (config.paymentMode !== 'pey') return res.status(503).json({ error: 'pey_onboarding_disabled_in_simulation_mode' });
    const { clabe, name, entity, taxId, alias, idempotencyKey } = req.body || {};
    if (!/^\d{18}$/.test(clabe || '') || typeof name !== 'string' || !name.trim() || !['business', 'person'].includes(entity)) return res.status(422).json({ error: 'invalid_bank_account' });
    if (typeof idempotencyKey !== 'string' || idempotencyKey.length < 16 || idempotencyKey.length > 100) return res.status(422).json({ error: 'idempotency_key_required' });
    if (taxId != null && (typeof taxId !== 'string' || taxId.length > 20)) return res.status(422).json({ error: 'invalid_tax_id' });
    if (alias != null && (typeof alias !== 'string' || alias.length > 100)) return res.status(422).json({ error: 'invalid_alias' });
    const started = await execute(config.db, 'app.sp_IniciarAltaCuentaPey', (r, t) => r
      .input('UsuarioId', t.UniqueIdentifier, req.user.sub)
      .input('IdempotencyKey', t.NVarChar(100), idempotencyKey)
      .input('ClabeUltimos4', t.Char(4), clabe.slice(-4)));
    const attempt = started.recordset?.[0];
    if (!attempt?.DebeRegistrar) {
      if (attempt?.PeyBankAccountId) return res.status(200).json({ bankAccountId: attempt.PeyBankAccountId, status: attempt.CodiStatus, clabeLast4: attempt.ClabeUltimos4 });
      return res.status(409).json({ error: 'bank_account_registration_requires_reconciliation', status: attempt?.Estado || 'UNKNOWN' });
    }
    let account;
    try {
      account = await registerBankAccount({ clabe, name: name.trim(), entity, taxId, alias }, config.peyApiKey, { allowProduction: config.paymentMode === 'pey' });
    } catch (providerError) {
      await execute(config.db, 'app.sp_MarcarAltaCuentaPeyIncierta', (r, t) => r
        .input('ComercioId', t.UniqueIdentifier, attempt.ComercioId)
        .input('IdempotencyKey', t.NVarChar(100), idempotencyKey));
      throw providerError;
    }
    if (!account.id) {
      await execute(config.db, 'app.sp_MarcarAltaCuentaPeyIncierta', (r, t) => r
        .input('ComercioId', t.UniqueIdentifier, attempt.ComercioId)
        .input('IdempotencyKey', t.NVarChar(100), idempotencyKey));
      return res.status(502).json({ error: 'pey_invalid_response' });
    }
    const saved = await execute(config.db, 'app.sp_GuardarCuentaPeyComercio', (r, t) => r
      .input('UsuarioId', t.UniqueIdentifier, req.user.sub)
      .input('ComercioId', t.UniqueIdentifier, attempt.ComercioId)
      .input('IdempotencyKey', t.NVarChar(100), idempotencyKey)
      .input('PeyBankAccountId', t.NVarChar(40), account.id)
      .input('ClabeUltimos4', t.Char(4), clabe.slice(-4))
      .input('CodiStatus', t.NVarChar(20), String(account.codiStatus || 'PENDING').toUpperCase())
      );
    res.status(202).json({ bankAccountId: account.id, status: saved.recordset?.[0]?.CodiStatus || account.codiStatus || 'PENDING', clabeLast4: clabe.slice(-4) });
  } catch (err) { next(err); }
});

app.get('/api/v1/merchant/bank-account/status', bearer, requireRole('Comercio'), async (req, res, next) => {
  try {
    if (config.paymentMode !== 'pey') return res.status(503).json({ error: 'pey_onboarding_disabled_in_simulation_mode' });
    const result = await execute(config.db, 'app.sp_ObtenerCuentaPeyPropia', (r, t) => r.input('UsuarioId', t.UniqueIdentifier, req.user.sub));
    const account = result.recordset?.[0];
    if (!account) return res.status(404).json({ error: 'bank_account_not_registered' });
    const latest = await getBankAccount(account.PeyBankAccountId, config.peyApiKey, { allowProduction: config.paymentMode === 'pey' });
    const status = String(latest.codiStatus || account.CodiStatus).toUpperCase();
    await execute(config.db, 'app.sp_ActualizarEstadoCuentaPey', (r, t) => r
      .input('UsuarioId', t.UniqueIdentifier, req.user.sub)
      .input('PeyBankAccountId', t.NVarChar(40), account.PeyBankAccountId)
      .input('CodiStatus', t.NVarChar(20), status));
    res.json({ bankAccountId: account.PeyBankAccountId, clabeLast4: account.ClabeUltimos4, status });
  } catch (err) { next(err); }
});

app.post('/api/v1/orders/checkout', bearer, requireRole('Comprador'), jsonParser, async (req, res, next) => {
  try {
    const { merchantId, items, deliveryMethod = 'RECOGER', deliveryAddress = null } = req.body || {};
    const key = req.get('Idempotency-Key');
    if (!id(merchantId) || !Array.isArray(items) || items.length < 1 || items.length > 50 || items.some((x) => !id(x.productId) || !Number.isInteger(x.quantity) || x.quantity < 1 || x.quantity > 100)) return res.status(422).json({ error: 'invalid_checkout' });
    if (!key || key.length < 16 || key.length > 100) return res.status(422).json({ error: 'idempotency_key_required' });
    if (!['RECOGER', 'ENTREGA_LOCAL'].includes(deliveryMethod)) return res.status(422).json({ error: 'invalid_delivery_method' });
    const created = await execute(config.db, 'app.sp_CrearPedidoPey', (r, t) => r
      .input('UsuarioId', t.UniqueIdentifier, req.user.sub)
      .input('ComercioId', t.UniqueIdentifier, merchantId)
      .input('ItemsJson', t.NVarChar(sql.MAX), JSON.stringify(items))
      .input('MetodoEntrega', t.NVarChar(20), deliveryMethod)
      .input('DireccionEntrega', t.NVarChar(300), deliveryAddress)
      .input('IdempotencyKey', t.NVarChar(100), key)
      .input('ModoSimulado', t.Bit, config.paymentMode === 'simulated'));
    const payment = created.recordset?.[0];
    if (!payment) return res.status(409).json({ error: 'checkout_not_available' });
    if (config.paymentMode === 'simulated') return res.status(202).json({ orderId: payment.PedidoId, orderNumber: payment.NumeroPedido, paymentId: payment.PagoId, amountMXN: payment.Total, paymentStatus: 'PENDIENTE', simulation: true });
    if (payment.CodiStatus !== 'ACTIVE') return res.status(409).json({ error: 'merchant_bank_account_not_active', orderId: payment.PedidoId });
    const attached = await execute(config.db, 'app.sp_AdjuntarQrPey', (r, t) => r
      .input('PagoId', t.UniqueIdentifier, payment.PagoId)
      .input('UsuarioId', t.UniqueIdentifier, req.user.sub)
      .input('PeyBankAccountId', t.NVarChar(40), payment.PeyBankAccountId)
      .output('DebeCrearQr', t.Bit));
    if (!attached.output.DebeCrearQr) {
      const prior = attached.recordset?.[0];
      if (prior?.QrString) return res.status(200).json({ orderId: payment.PedidoId, paymentId: payment.PagoId, amountMXN: payment.Total, qrString: prior.QrString, qrImageDataUrl: await QRCode.toDataURL(prior.QrString), paymentStatus: 'PENDIENTE' });
      return res.status(409).json({ error: 'payment_requires_reconciliation', paymentId: payment.PagoId });
    }
    try {
      const qr = await createQr({ amount: Number(payment.Total), concept: `BARRIO ${payment.NumeroPedido}`, expiration: 600, numRef: payment.PagoReferencia, bankAccountId: payment.PeyBankAccountId, metadata: { barrioPaymentId: payment.PagoId } }, config.peyApiKey, { allowProduction: config.paymentMode === 'pey' });
      await execute(config.db, 'app.sp_GuardarQrPey', (r, t) => r
        .input('PagoId', t.UniqueIdentifier, payment.PagoId)
        .input('PeyQrId', t.NVarChar(100), qr.id)
        .input('QrString', t.NVarChar(sql.MAX), qr.qrString));
      return res.status(201).json({ orderId: payment.PedidoId, orderNumber: payment.NumeroPedido, paymentId: payment.PagoId, amountMXN: payment.Total, qrImageDataUrl: await QRCode.toDataURL(qr.qrString), paymentStatus: 'PENDIENTE' });
    } catch (providerError) {
      await execute(config.db, 'app.sp_MarcarCreacionQrIncierta', (r, t) => r.input('PagoId', t.UniqueIdentifier, payment.PagoId));
      throw providerError;
    }
  } catch (err) { next(err); }
});

app.get('/api/v1/orders/:orderId', bearer, async (req, res, next) => {
  try {
    if (!id(req.params.orderId)) return res.status(400).json({ error: 'invalid_order_id' });
    const result = await execute(config.db, 'app.sp_ObtenerPedidoPropio', (r, t) => r.input('UsuarioId', t.UniqueIdentifier, req.user.sub).input('PedidoId', t.UniqueIdentifier, req.params.orderId));
    const order = result.recordset?.[0];
    if (!order) return res.status(404).json({ error: 'not_found' });
    res.json({ order });
  } catch (err) { next(err); }
});

app.get('/api/v1/orders', bearer, async (req, res, next) => {
  try {
    const result = await execute(config.db, 'app.sp_ListarPedidosPropios', (r, t) => r.input('UsuarioId', t.UniqueIdentifier, req.user.sub));
    res.json({ items: result.recordset || [] });
  } catch (err) { next(err); }
});

app.post('/api/v1/webhooks/pey', express.raw({ type: 'application/json', limit: '128kb' }), async (req, res, next) => {
  try {
    const headers = { rawBody: req.body, webhookId: req.get('webhook-id'), timestamp: req.get('webhook-timestamp'), signature: req.get('webhook-signature') };
    if (!verifyPeyWebhook(headers, config.peyWebhookSecret, { toleranceSeconds: config.webhookToleranceSeconds })) return res.status(401).json({ error: 'invalid_signature' });
    let event;
    try { event = JSON.parse(req.body.toString('utf8')); } catch { return res.status(400).json({ error: 'invalid_json' }); }
    if (!event || typeof event.type !== 'string') return res.status(400).json({ error: 'invalid_event' });
    await execute(config.db, 'app.sp_ProcesarWebhookPey', (r, t) => r
      .input('WebhookId', t.NVarChar(200), headers.webhookId)
      .input('EventType', t.NVarChar(100), event.type)
      .input('PayloadJson', t.NVarChar(sql.MAX), JSON.stringify(event)));
    res.status(202).json({ received: true });
  } catch (err) { next(err); }
});

app.use((err, _req, res, _next) => {
  const status = err.status || (err instanceof TypeError ? 422 : ([2601, 2627, 50102, 50104, 50108, 50109, 50111].includes(err.number) ? 409 : ([50101, 50103, 50105].includes(err.number) ? 403 : ([50112, 50114, 50119, 50122].includes(err.number) ? 409 : 500))));
  if (status >= 500) console.error(JSON.stringify({ event: 'api_error', name: err.name, message: err.message, requestId: err.requestId }));
  res.status(status).json({ error: status >= 500 ? 'internal_error' : 'request_failed', ...(err.requestId ? { providerRequestId: err.requestId } : {}) });
});

const server = app.listen(config.port, '0.0.0.0', () => console.log(`BARRIO API listening on ${config.port}; payments=${config.paymentMode}`));
const reservationSweep = setInterval(() => {
  execute(config.db, 'app.sp_LiberarReservasPeyVencidas').catch((err) => console.error(JSON.stringify({ event: 'reservation_sweep_failed', name: err.name })));
}, 60_000);
reservationSweep.unref();
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, async () => {
  clearInterval(reservationSweep);
  server.close(); await closePool(); process.exit(0);
});
