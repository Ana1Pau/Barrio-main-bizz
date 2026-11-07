# BARRIO

Proyecto BARRIO: landing pública, demo de interfaz, backend web funcional y esquema SQL. Los pagos están desactivados por defecto; el modo simulado permite probar pedidos sin enviar cargos a Pey.

## Estructura

```text
apps/
  landing/      Landing estática y formulario de lista de espera
  prototype/    Demo local navegable de BARRIO
  api/          API Express, aplicación web, conexión SQL y adaptador Pey
  android/      Espacio reservado para la futura app nativa
database/
  sql/          Esquema completo de la base de datos (tablas, vistas, procedimientos, seguridad)
  connection-examples/  Ejemplos de conexión segura (.NET, Node.js)
  docs/         Guías de despliegue en Azure y migración a producción
```

Ver [`database/README.md`](database/README.md) para el detalle completo del modelo de datos y cómo desplegarlo.

## Probar la landing y la demo

No requiere instalación de paquetes ni servicios externos. Abre `apps/landing/index.html` en un navegador. El botón **Probar la demo** lleva al prototipo interactivo incluido.

Si prefieres servir la carpeta con un servidor estático local, usa cualquier servidor de archivos estáticos y apunta a `apps/landing/` como raíz. La demo vive en `apps/prototype/`.

## Lista de espera

El formulario valida el correo y está preparado para enviar un `POST` JSON a un endpoint externo configurado en `apps/landing/config.js`. Sin endpoint, muestra un aviso transparente y no afirma que la suscripción se haya guardado. No se almacena información localmente.

Para habilitar registros reales, elige un proveedor de lista de espera o mailing y coloca su endpoint seguro en la configuración. Revisa también su consentimiento de privacidad antes de publicar la landing. No incluyas claves privadas en archivos del frontend.

## App Android

`apps/android/` queda reservado para iniciar el cliente nativo Android. Se propone Kotlin con Jetpack Compose para la app. La integración con servidor, base de datos, seguridad y pagos se mantiene fuera de este alcance.

## Ejecutar el backend

Consulta [`apps/api/README-deploy.md`](apps/api/README-deploy.md) para iniciar la aplicación y SQL Server con Docker Compose, probar los flujos simulados y preparar un despliegue de producción.

## Alcance actual

- Diseño adaptable para celular y escritorio.
- Landing pública con enlaces a la demo y suscripción preparada para endpoint.
- Prototipo de interfaz completo con datos locales de ejemplo.
- Backend con autenticación, perfiles de comercio, productos, pedidos y modo de pago simulado.
- Integración Pey preparada para CLABE, QR CoDi y webhooks firmados; requiere credenciales aprobadas y un despliegue seguro para activar cargos reales.
- Sin despliegue en nube aprovisionado; la configuración de Azure queda documentada y requiere una suscripción del equipo.

