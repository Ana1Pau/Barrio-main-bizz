import { normalizeClabeInput, isValidClabe } from './formats.mjs';

const API = '/api/v1';
const state = { token: sessionStorage.getItem('barrioToken'), roles: [], authMode: 'login', merchants: [], selectedMerchant: null, products: [], cart: new Map(), checkoutKey: null, paymentMode: 'unknown' };
const $ = (selector) => document.querySelector(selector);
const esc = (value) => String(value ?? '').replace(/[&<>"']/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]));

async function api(path, { method = 'GET', body, headers = {} } = {}) {
  const response = await fetch(`${API}${path}`, {
    method,
    headers: { ...(body ? { 'content-type': 'application/json' } : {}), ...(state.token ? { authorization: `Bearer ${state.token}` } : {}), ...headers },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data.error || `request_failed_${response.status}`);
  return data;
}

function message(target, text, error = false) {
  target.textContent = text;
  target.classList.toggle('error', error);
}

function setAuthMode(mode) {
  state.authMode = mode;
  document.querySelectorAll('[data-auth-mode]').forEach((button) => button.classList.toggle('selected', button.dataset.authMode === mode));
  $('#accountTypeField').classList.toggle('hidden', mode !== 'register');
  $('#displayNameField').classList.toggle('hidden', mode !== 'register');
  $('#authSubmit').textContent = mode === 'login' ? 'Entrar' : 'Crear cuenta';
  $('#authForm [name=password]').autocomplete = mode === 'login' ? 'current-password' : 'new-password';
  $('#authForm [name=password]').minLength = mode === 'register' ? 12 : 1;
  $('#authMessage').textContent = '';
}

function showOnly(view) {
  for (const id of ['authView', 'buyerView', 'merchantView']) $(`#${id}`).classList.toggle('hidden', id !== view);
}

function logout() {
  sessionStorage.removeItem('barrioToken');
  state.token = null; state.roles = []; state.selectedMerchant = null; state.products = []; state.cart.clear();
  $('#sessionActions').innerHTML = '';
  showOnly('authView');
  setAuthMode('login');
}

async function authenticate(event) {
  event.preventDefault();
  const form = new FormData(event.currentTarget);
  const body = Object.fromEntries(form.entries());
  const path = state.authMode === 'login' ? '/auth/login' : '/auth/register';
  try {
    const result = await api(path, { method: 'POST', body });
    state.token = result.token;
    state.roles = result.user.roles;
    sessionStorage.setItem('barrioToken', state.token);
    await enterApp();
  } catch (error) {
    message($('#authMessage'), error.message === 'invalid_credentials' ? 'El correo o la contraseña no coinciden.' : 'No se pudo completar el acceso. Revisa los datos e intenta de nuevo.', true);
  }
}

async function enterApp() {
  const user = await api('/auth/me');
  state.roles = user.roles;
  $('#sessionActions').innerHTML = '<button id="logoutButton" class="button text-button">Cerrar sesión</button>';
  $('#logoutButton').onclick = logout;
  if (state.roles.includes('Comercio')) {
    showOnly('merchantView');
    await Promise.all([loadMerchantProfile(), loadOrders(), loadBankStatus(false)]);
  } else {
    showOnly('buyerView');
    await loadMerchants();
  }
}

async function loadMerchants() {
  try {
    const result = await api('/merchants');
    state.merchants = result.items;
    $('#merchantList').innerHTML = state.merchants.length ? state.merchants.map((m) => `<button class="shop-option ${state.selectedMerchant?.id === m.id ? 'active' : ''}" data-merchant-id="${esc(m.id)}"><b>${esc(m.name)}</b><small>${esc(m.Colonia || 'Comercio local')}</small></button>`).join('') : '<p class="empty">Aún no hay comercios publicados.</p>';
    document.querySelectorAll('[data-merchant-id]').forEach((button) => button.onclick = () => selectMerchant(button.dataset.merchantId));
  } catch { $('#merchantList').innerHTML = '<p class="empty">No se pudieron cargar los comercios.</p>'; }
}

async function selectMerchant(merchantId) {
  state.selectedMerchant = state.merchants.find((m) => m.id === merchantId) || null;
  state.cart.clear();
  if (!state.selectedMerchant) return;
  try {
    const result = await api(`/merchants/${merchantId}/products`);
    state.products = result.items;
    $('#selectedShop').innerHTML = `<span class="eyebrow">TIENDA</span><h2>${esc(state.selectedMerchant.name)}</h2><p class="muted">${esc(state.selectedMerchant.description || 'Productos de este comercio')}</p><div class="product-grid">${state.products.map((product) => `<article class="product-card"><div><h3>${esc(product.name)}</h3><p>${esc(product.description || '')}</p></div><div class="product-bottom"><b>$${Number(product.priceMXN).toFixed(2)} MXN</b><button class="button small primary" data-add-product="${esc(product.id)}" ${product.stock < 1 ? 'disabled' : ''}>Agregar</button></div><small>${product.stock} disponibles</small></article>`).join('') || '<p class="empty">Este comercio todavía no publica productos.</p>'}</div>`;
    document.querySelectorAll('[data-add-product]').forEach((button) => button.onclick = () => addToCart(button.dataset.addProduct));
    $('#cartShopName').textContent = state.selectedMerchant.name;
    $('#merchantList').querySelectorAll('[data-merchant-id]').forEach((button) => button.classList.toggle('active', button.dataset.merchantId === merchantId));
    renderCart();
  } catch { $('#selectedShop').innerHTML = '<p class="empty">No se pudieron cargar los productos.</p>'; }
}

function addToCart(productId) {
  const product = state.products.find((item) => item.id === productId);
  if (!product) return;
  const current = state.cart.get(productId) || 0;
  if (current >= product.stock) return;
  state.cart.set(productId, current + 1);
  state.checkoutKey = null;
  renderCart();
}

function renderCart() {
  const rows = [...state.cart.entries()];
  $('#cartItems').innerHTML = rows.length ? rows.map(([productId, quantity]) => {
    const p = state.products.find((item) => item.id === productId);
    return `<div class="cart-row"><span>${esc(p.name)} <small>× ${quantity}</small></span><b>$${(Number(p.priceMXN) * quantity).toFixed(2)}</b><button class="remove-item" data-remove-product="${esc(productId)}" aria-label="Quitar producto">×</button></div>`;
  }).join('') : '<p class="muted">Aún no agregas productos.</p>';
  document.querySelectorAll('[data-remove-product]').forEach((button) => button.onclick = () => { state.cart.delete(button.dataset.removeProduct); state.checkoutKey = null; renderCart(); });
  const total = rows.reduce((sum, [id, count]) => sum + Number(state.products.find((p) => p.id === id)?.priceMXN || 0) * count, 0);
  $('#checkoutButton').disabled = !rows.length;
  $('#checkoutButton').textContent = rows.length ? `Continuar · $${total.toFixed(2)} MXN` : 'Continuar al pago';
}

async function checkout() {
  const deliveryMethod = $('#deliveryMethod').value;
  const deliveryAddress = $('#deliveryAddress').value.trim();
  if (deliveryMethod === 'ENTREGA_LOCAL' && !deliveryAddress) return message($('#checkoutMessage'), 'Escribe la dirección para la entrega local.', true);
  $('#checkoutButton').disabled = true;
  try {
    const result = await api('/orders/checkout', {
      method: 'POST',
      headers: { 'Idempotency-Key': state.checkoutKey || (state.checkoutKey = crypto.randomUUID()) },
      body: { merchantId: state.selectedMerchant.id, items: [...state.cart].map(([productId, quantity]) => ({ productId, quantity })), deliveryMethod, deliveryAddress: deliveryAddress || null },
    });
    if (result.simulation) {
      $('#paymentResult').innerHTML = `<div class="simulation-notice"><b>Modo de simulación</b><p>Se creó el pedido ${esc(result.orderNumber)} por $${Number(result.amountMXN).toFixed(2)} MXN. No se creó un cobro real.</p></div>`;
    } else {
      $('#paymentResult').innerHTML = `<p>Pedido ${esc(result.orderNumber)} · $${Number(result.amountMXN).toFixed(2)} MXN</p><img class="payment-qr" alt="Código QR CoDi para pagar" src="${esc(result.qrImageDataUrl)}" /><p class="muted">Escanea el código desde la aplicación de tu banco. La orden se confirmará cuando Pey notifique el pago.</p><p class="small-note">Estado: <span id="paymentStatus">pendiente</span></p>`;
      pollOrder(result.orderId);
    }
    $('#paymentDialog').classList.remove('hidden');
    state.cart.clear(); state.checkoutKey = null; renderCart(); message($('#checkoutMessage'), '');
  } catch (error) {
    message($('#checkoutMessage'), error.message === 'merchant_bank_account_not_active' ? 'Este comercio aún no puede recibir pagos CoDi.' : 'No se pudo iniciar el pedido. Intenta otra vez.', true);
  } finally { $('#checkoutButton').disabled = !state.cart.size; }
}

async function pollOrder(orderId) {
  const status = $('#paymentStatus');
  if (!status) return;
  for (let attempt = 0; attempt < 24; attempt++) {
    await new Promise((resolve) => setTimeout(resolve, 5000));
    if (!$('#paymentStatus')) return;
    try {
      const result = await api(`/orders/${orderId}`);
      const paymentStatus = result.order.EstadoPago;
      if (paymentStatus === 'CONFIRMADO') { $('#paymentStatus').textContent = 'pagado'; return; }
      if (['RECHAZADO', 'REEMBOLSADO'].includes(paymentStatus)) { $('#paymentStatus').textContent = 'vencido'; return; }
    } catch { return; }
  }
}

async function loadMerchantProfile() {
  try {
    const { merchant } = await api('/merchant/profile');
    $('#profileForm [name=name]').value = merchant.NombreNegocio || '';
    $('#profileForm [name=description]').value = merchant.Descripcion || '';
    $('#profileForm [name=name]').disabled = true;
    $('#profileForm [name=description]').disabled = true;
    $('#profileForm button').disabled = true;
    $('#profileMessage').textContent = 'Perfil del comercio cargado.';
  } catch (error) {
    $('#profileMessage').textContent = error.message === 'merchant_profile_required' ? 'Completa y guarda el perfil de tu comercio.' : 'No se pudo consultar el perfil.';
  }
}

async function loadBankStatus(showMessage = true) {
  try {
    const result = await api('/merchant/bank-account/status');
    if (showMessage) message($('#bankMessage'), `Cuenta ${result.clabeLast4}: ${result.status}`);
    $('#bankForm').classList.add('hidden');
  } catch (error) {
    if (error.message === 'pey_onboarding_disabled_in_simulation_mode') {
      $('#bankForm').classList.add('hidden');
      $('#checkBankStatus').classList.add('hidden');
      message($('#bankMessage'), 'La demo está en modo simulado. No ingreses una CLABE real; puedes probar pedidos sin pago.');
      return;
    }
    if (error.message === 'bank_account_not_registered') {
      $('#bankForm').classList.remove('hidden');
      return;
    }
    if (showMessage) message($('#bankMessage'), 'No se pudo consultar el estado de la cuenta.', true);
  }
}

async function loadOrders() {
  try {
    const result = await api('/orders');
    $('#ordersList').innerHTML = result.items.length ? result.items.map((order) => `<div class="order-row"><span><b>${esc(order.NumeroPedido)}</b><small>${esc(order.Comercio)}</small></span><span>${esc(order.EstadoPedido)} · ${esc(order.EstadoPago || 'sin pago')}<b>$${Number(order.Monto || 0).toFixed(2)}</b></span></div>`).join('') : '<p class="muted">Todavía no hay pedidos.</p>';
  } catch { $('#ordersList').innerHTML = '<p class="muted">No se pudieron consultar los pedidos.</p>'; }
}

async function submitProfile(event) {
  event.preventDefault();
  const form = new FormData(event.currentTarget);
  try {
    const result = await api('/merchant/profile', { method: 'POST', body: { name: form.get('name'), description: form.get('description') || null } });
    message($('#profileMessage'), `Perfil creado: ${result.name}`);
    $('#profileForm [name=name]').disabled = true;
    $('#profileForm [name=description]').disabled = true;
    $('#profileForm button').disabled = true;
  } catch (error) { message($('#profileMessage'), error.message === 'merchant_already_exists' ? 'Ya existe un perfil para esta cuenta.' : 'No se pudo guardar el perfil.', true); }
}

async function submitProduct(event) {
  event.preventDefault();
  const form = new FormData(event.currentTarget);
  try {
    await api('/merchant/products', { method: 'POST', body: { name: form.get('name'), description: form.get('description') || null, priceMXN: Number(form.get('priceMXN')), stock: Number(form.get('stock')) } });
    event.currentTarget.reset();
    message($('#productMessage'), 'Producto publicado.');
  } catch (error) { message($('#productMessage'), error.message === 'merchant_profile_required' ? 'Primero crea el perfil del comercio.' : 'No se pudo publicar el producto.', true); }
}

async function submitBankAccount(event) {
  event.preventDefault();
  const form = new FormData(event.currentTarget);
  const key = crypto.randomUUID();
  try {
    const result = await api('/merchant/bank-account', { method: 'POST', body: { clabe: form.get('clabe'), name: form.get('name'), entity: form.get('entity'), taxId: form.get('taxId') || null, alias: form.get('alias') || null, idempotencyKey: key } });
    event.currentTarget.classList.add('hidden');
    message($('#bankMessage'), `Cuenta vinculada (terminación ${result.clabeLast4}). Estado CoDi: ${result.status}.`);
  } catch (error) { message($('#bankMessage'), error.message === 'pey_onboarding_disabled_in_simulation_mode' ? 'El backend está en modo simulado; la CLABE no se envió.' : 'No se pudo vincular la cuenta. Si hubo un timeout, consulta el estado antes de volver a enviar.', true); }
}

document.querySelectorAll('[data-auth-mode]').forEach((button) => button.addEventListener('click', () => setAuthMode(button.dataset.authMode)));
$('#authForm').addEventListener('submit', authenticate);
$('#refreshBuyer').addEventListener('click', loadMerchants);
$('#checkoutButton').addEventListener('click', checkout);
$('#deliveryMethod').addEventListener('change', (event) => $('#deliveryAddressField').classList.toggle('hidden', event.target.value !== 'ENTREGA_LOCAL'));
$('#profileForm').addEventListener('submit', submitProfile);
$('#productForm').addEventListener('submit', submitProduct);
$('#bankForm').addEventListener('submit', submitBankAccount);
const clabeField = $('#bankForm [name=clabe]');
clabeField.addEventListener('input', () => {
  const original = clabeField.value;
  const cursor = clabeField.selectionStart ?? original.length;
  const normalized = normalizeClabeInput(original);
  if (normalized !== original) {
    const normalizedCursor = normalizeClabeInput(original.slice(0, cursor)).length;
    clabeField.value = normalized;
    clabeField.setSelectionRange(normalizedCursor, normalizedCursor);
  }
  clabeField.setCustomValidity(!normalized || isValidClabe(normalized) ? '' : 'La CLABE debe contener exactamente 18 dígitos.');
});
$('#checkBankStatus').addEventListener('click', () => loadBankStatus(true));
$('#closePayment').addEventListener('click', () => $('#paymentDialog').classList.add('hidden'));
$('#paymentDialog').addEventListener('click', (event) => { if (event.target === $('#paymentDialog')) $('#paymentDialog').classList.add('hidden'); });
$('#modeBadge').textContent = 'Preparado para operar con backend';

if (state.token) {
  enterApp().catch(logout);
} else {
  showOnly('authView');
}
