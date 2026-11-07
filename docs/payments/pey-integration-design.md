# Integración de pey con cobros directos por comercio

## Estado del repositorio

BARRIO es actualmente una landing y un prototipo. `apps/barrio-2/server.mjs` sincroniza productos en memoria; no implementa autenticación de usuarios, órdenes, persistencia ni pagos. El esquema SQL contiene órdenes y pagos, pero no representa cuentas pey por comercio ni eventos de proveedor. Se añadió un adaptador aislado (`apps/barrio-2/payments/pey.mjs`) con validación de QR y firma Standard Webhooks, junto con pruebas de transporte simulado. No se conectó a rutas de la demo ni habilitó pagos reales.

## Arquitectura

El cliente llama al backend autenticado de BARRIO. El backend crea/consulta órdenes y pagos en SQL, resuelve el comercio propietario de la orden y su cuenta pey activa, y llama a `https://api.pey.mx`. La CLABE de cada comercio queda asociada a un `bankAccountId` con `codiStatus=ACTIVE`; no se acepta que el cliente seleccione una cuenta destino. El dinero se liquida directamente en la cuenta bancaria del comercio.

```text
Comprador → API BARRIO → orden/pago en SQL → adaptador pey → QR CoDi
                                  ↑                         ↓
                           inbox durable ← webhook firmado ← pey
```

Una API key de pey y su secreto de webhook viven exclusivamente en el backend/secret manager. La documentación indica una sola configuración de webhook por API key, por lo que un endpoint compartido debe enrutar eventos con las relaciones persistidas por BARRIO.

## Modelo de datos a incorporar mediante migración revisada

- `pay.CuentasPeyComercio`: `ComercioId` (FK y único), `PeyBankAccountId` (único), CLABE cifrada/tokenizada, estado pey (`PENDING`, `PROCESSING`, `ACTIVE`, `ERROR`), fecha de verificación y marcas de auditoría. No devolver CLABE completa al cliente.
- `pay.Pagos`: ampliar con proveedor, clave idempotente interna, monto esperado, moneda, `PeyQrId`, `PeyTransactionId` (único cuando exista), destino `PeyBankAccountId`, expiración y estado de conciliación. La unicidad actual de `PedidoId` ya limita a un pago por orden; confirmar el requisito de reintentos antes de alterarla.
- `pay.PeyWebhookInbox`: identificador Standard Webhooks/evento, tipo, hash del cuerpo, estado de procesamiento, timestamps y error saneado. Clave única por `webhook-id`; conservar el cuerpo solo si política de datos lo permite y con retención definida.
- El historial de conciliación debe registrar coincidencias y discrepancias sin guardar secretos ni CLABEs sin protección.

No agregar estas tablas al `deploy_all.sql` hasta acordar el entorno SQL, cifrado y política de retención.

## Flujos

### Alta y activación bancaria

1. Un usuario con rol de propietario inicia el alta desde un endpoint autenticado; el servidor resuelve `ComercioId` desde su identidad y valida CLABE de 18 dígitos, titular/RFC requeridos y consentimiento.
2. El servidor registra la cuenta usando `POST /bank-account` con la API key. Guarda inmediatamente el `id` devuelto y estado `PENDING`; nunca registra la CLABE en logs.
3. Actualiza estado por `GET` de cuenta y webhook `bank.account.updated`. Solo `ACTIVE` permite generar cobros. Los estados intermedios/error requieren consulta, no inferir activación.

### Orden y cobro QR

1. El backend valida propiedad del carrito, disponibilidad, precios y monto; genera la orden y el pago pendiente de manera transaccional.
2. Resuelve la cuenta pey activa mediante `ComercioId` de la orden; no usa IDs enviados por el frontend. Genera un QR por importe fijo, concepto acotado, referencia numérica de hasta siete dígitos y metadatos mínimos con identificador opaco de pago.
3. Persiste `PeyQrId` y respuesta necesaria (`qrString`; imagen solo si se solicita) antes de devolver el QR. No declarar pagada la orden a partir de una redirección o respuesta del navegador.
4. Reintentos de la API de BARRIO reutilizan el pago/QR persistido. La referencia de Pey no documenta garantía de idempotencia para `POST /codi/qr`; tras timeout ambiguo se reconcilia/consulta antes de crear otro QR.

### Webhook y conciliación

1. Leer el cuerpo crudo con límite de tamaño. Verificar Standard Webhooks con el secreto dedicado y SDK compatible, antes de parsear o actuar. Rechazar firmas inválidas, timestamps fuera de ventana y eventos repetidos; comparar de forma segura.
2. Insertar el evento en inbox con unicidad; responder éxito solo tras guardarlo durablemente. Procesar asíncronamente e idempotentemente.
3. Para `codi.qr.payment_received`, resolver el pago por QR/referencia persistidos y comprobar firma, tipo, importe exacto en MXN, `bankAccountId`, estado previo e identidad del QR. Verificar el `transactionId` mediante consulta a Pey cuando el endpoint/contrato lo permita.
4. En una transacción SQL, marcar evento procesado, pago pagado y orden confirmada una sola vez. Un pago duplicado o con importe/cuenta incorrectos queda en revisión y genera alerta; nunca se asigna a otra orden por metadata proporcionada externamente.
5. Un proceso de conciliación compara periódicamente pagos pendientes y transacciones Pey; las discrepancias se ponen en cola para operación manual.

## Controles

- Autorización por comercio en todos los endpoints y en base de datos; sin confiar en `merchantId` del body.
- Monto calculado por servidor y moneda fija `MXN`; límites y expiración de QR.
- API key y secreto en secret manager; rotación, TLS, redacción de cabeceras/cuerpos sensibles.
- Firmas Standard Webhooks sobre bytes originales, ventana anti-replay, inbox/outbox durable y restricciones únicas.
- Máquina de estados explícita y transiciones permitidas; nunca pasar de `PAID` a pendiente por eventos atrasados.
- Límites de tasa, tamaño de body, alertas y trazas con IDs internos, sin PII financiera.
- Pruebas con transporte HTTP falso y firmas/eventos de fixture: firma válida/inválida, replay, importe/cuenta/QR incorrectos, duplicados, timeout, carrera de eventos, cuenta pendiente y reintentos. No apuntar pruebas a `api.pey.mx`.

## Contratos Pey relevantes y límite de pruebas

- `POST /bank-account`: crea cuenta `PENDING`; activación puede tardar hasta cinco días hábiles; solo `ACTIVE` cobra.
- `POST /codi/qr`: crea QR; admite `amount`, `concept`, `expiration`, `numRef`, `generateImage`, `bankAccountId` y `metadata`. Referencia de 1–7 dígitos; expiración configurada mínima de 360 segundos.
- Webhooks firmados con Standard Webhooks; eventos de pago QR incluyen `transactionId`, `codiQrId`, importe y `bankAccountId` cuando se especificó.
- La documentación consultada indica que el entorno de pruebas dedicado aún no está disponible y recomienda pruebas en producción. Este repositorio no debe hacer esa recomendación como paso automático: los tests deben ser totalmente simulados; cualquier smoke test con dinero real requeriría una decisión operativa separada.

## Siguiente corte de implementación

El adaptador y sus pruebas son una base aislada, no una integración end-to-end: faltan backend autenticado/persistente, onboarding, inbox durable, transiciones SQL, deduplicación/conciliación y controles operativos. Implementar esos componentes antes de conectar rutas; mantener apagada la integración real por configuración hasta revisión operativa. Ejecutar las simulaciones con `node --test apps/barrio-2/payments/pey.test.mjs`. La demo `server.mjs` no debe recibir secretos ni webhooks financieros.
