# Backend BARRIO: ejecución y despliegue

## Estado

La aplicación incluye una API Express, interfaz web, SQL Server con migración de pagos y un compose para ejecutar todo en una sola máquina. El modo predeterminado es `PAYMENTS_MODE=simulated`: crea pedidos de prueba y reserva inventario, pero nunca llama a Pey ni genera un QR bancario. Las pruebas usan un transporte ficticio.

Este compose sirve para desarrollo, demo y pruebas integradas locales. No es un despliegue de producción: expone los puertos solo en localhost, usa SQL Server Developer y una contraseña SQL local. Para producción despliega la imagen de `apps/api` en Azure Container Apps o App Service, usa Azure SQL Database, identidad administrada, TLS/HTTPS, Key Vault para secretos de Pey y almacenamiento de logs/alertas. `database/docs/azure-setup.md` contiene el diseño de Azure SQL.

## Ejecutar localmente

Requisitos: Docker Desktop con Compose y Node.js 20 o posterior para correr pruebas.

```sh
cd database/docker
cp .env.example .env
```

Edita `.env` y reemplaza cada texto `CAMBIA_...` por valores aleatorios únicos. No agregues `.env` al repositorio ni compartas los secretos. En particular, `JWT_SECRET` debe tener al menos 32 bytes y las contraseñas SQL deben ser fuertes. Conserva `PAYMENTS_MODE=simulated`, `PEY_LIVE_CHARGES_ENABLED=false` y las credenciales Pey vacías.

```sh
docker compose up --build
```

Abre <http://localhost:8080>. El primer inicio puede tomar varios minutos mientras SQL Server instala el esquema y carga datos. Comprueba `http://localhost:8080/healthz`; debe devolver `{"ok":true}`. Registra una cuenta tipo comercio, crea su perfil y productos, y registra una cuenta compradora para simular pedidos. Los pedidos de prueba reservan inventario por 20 minutos.

Para detener: `docker compose down`. Los datos continúan en el volumen local; para borrarlos de forma irreversible: `docker compose down -v`.

## Probar sin pagos

En `apps/api`:

```sh
node --test
```

Las pruebas verifican hash de contraseñas, firma y vencimiento de tokens, validación de CLABE/QR, verificación de firma Pey y adaptador con fetch simulado. No envían solicitudes a Pey ni mueven dinero.

## Para activar Pey en producción

Mantén `PAYMENTS_MODE=simulated` hasta que exista aprobación y credenciales de producción. El backend exige `NODE_ENV=production`, `PAYMENTS_MODE=pey`, `PEY_LIVE_CHARGES_ENABLED=true`, `PEY_API_KEY` y `PEY_WEBHOOK_SECRET`. Guarda estos secretos en un gestor de secretos; no en Git, imágenes, ni conversaciones.

Configura el webhook de Pey a `https://<dominio>/api/v1/webhooks/pey` y verifica firmas sobre el cuerpo HTTP original. La API acepta QR de CoDi; cualquier evento ajeno se conserva como ignorado en la bandeja de webhooks. Un timeout en alta de cuenta o creación de QR queda en estado incierto para conciliación manual; no reintentes una operación incierta a ciegas. Confirma que cada cuenta tenga estado `ACTIVE` antes de permitir cobros. Usa las APIs oficiales de consulta de Pey y conciliación bancaria antes del lanzamiento.

## Pendientes antes de operación comercial real

- Añadir recuperación de contraseña, verificación de correo/teléfono y protección contra abuso de registros.
- Crear roles de operación y una consola segura para resolver cuentas/QR inciertos y revisar webhooks en cuarentena.
- Añadir consultas/reporte de conciliación automática con el estado de cuenta de Pey y alertas por pagos no correlacionados.
- Definir políticas legales, fiscales, privacidad, retención de datos y soporte a reembolsos/cancelaciones.
- Integrar observabilidad, copias de seguridad y despliegue continuo; configurar dominio y certificado TLS.
- Ejecutar pruebas de integración contra una base de staging y pruebas de aceptación con Pey. Mantener simulación hasta recibir credenciales y autorización del proveedor.

La app no almacena la CLABE completa: solo se transmite a Pey al vincular y se conserva su terminación, el identificador que devuelve Pey y su estado.
