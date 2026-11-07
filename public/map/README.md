# BARRIO 2.0 · Demo hackathon

Sirve `apps/barrio-2` como raíz estática, por ejemplo `python3 -m http.server 8080` desde esta carpeta y abre `http://localhost:8080`.

## Datos y transparencia

`data/tianguis-cdmx-official.geojson` es una copia local del recurso oficial **Ubicación de Tianguis** de Datos Abiertos CDMX, descargada el 25 de octubre de 2026. El cliente normaliza puntos y conserva en memoria el identificador, atributos y geometría originales. El mapa etiqueta esta información como oficial; comerciantes, inventarios, ofertas y métricas operativas son demostración claramente marcada.

El adaptador actual usa el archivo local para una demo reproducible. Para modo live, implementa y configura un adaptador que consuma:

- `GET /api/tianguis`
- `GET /api/merchants`, `GET /api/merchants/:id`, `GET /api/merchants/:id/inventory`
- `GET /api/products`, `GET /api/offers`, `GET /api/city/summary`

No hay endpoints de escritura ni credenciales en el navegador. `BARRIO_WHATSAPP_URL` debe proporcionar el enlace público del asistente; en ausencia de configuración, la interfaz declara honestamente que no está configurado.

La acción “Simular registro” es exclusivamente demostrativa y actualiza el estado compartido en memoria: comerciante, panel e indicadores de ciudad.
