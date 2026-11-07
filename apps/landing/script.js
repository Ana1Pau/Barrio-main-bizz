const localPreview = ['127.0.0.1', 'localhost'].includes(location.hostname);
const localMap = localPreview ? 'http://127.0.0.1:4176/' : '/map/';
const prototype = localPreview ? 'http://127.0.0.1:4175/' : '/app/';
document.querySelectorAll('a[href="../prototype/index.html"]').forEach((link) => { link.href = prototype; });
document.querySelectorAll('a[href="../barrio-2/index.html"]').forEach((link) => { link.href = localMap; });
document.querySelectorAll('a[href="../barrio-2/index.html"]').forEach((link) => {
  link.addEventListener('pointerenter', () => {
    if (document.querySelector('link[data-map-warmup]')) return;
    const warmup = document.createElement('link');
    warmup.rel = 'prefetch'; warmup.as = 'document'; warmup.href = localMap;
    warmup.dataset.mapWarmup = 'true'; document.head.append(warmup);
  }, { once: true });
});
document.querySelectorAll('img[src="../prototype/assets/cdmx-barrio-map.png"]').forEach((image) => { image.src = 'assets/local-map.png'; });
const form = document.querySelector('#waitlist-form');
if (form) {
  const emailInput = document.querySelector('#email');
  const message = document.querySelector('#form-message');
  const endpoint = window.BARRIO_CONFIG?.waitlistEndpoint?.trim();
  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    const email = emailInput.value.trim();
    if (!emailInput.checkValidity() || !email) { message.textContent = 'Escribe un correo válido para continuar.'; message.className = 'form-message error'; return; }
    if (!endpoint) { message.textContent = 'La lista de espera todavía no está conectada.'; message.className = 'form-message error'; return; }
    try {
      const response = await fetch(endpoint, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, source: 'landing-barrio' }) });
      if (!response.ok) throw new Error();
      message.textContent = '¡Listo! Te avisaremos cuando BARRIO esté cerca de tu colonia.'; message.className = 'form-message success'; form.reset();
    } catch { message.textContent = 'No pudimos registrarte ahora. Intenta de nuevo más tarde.'; message.className = 'form-message error'; }
  });
}
