# Sincronización de productos desde WhatsApp

El servidor local expone la app y el webhook en `http://127.0.0.1:4176`.

## Endpoint

`POST /api/merchant/:merchantId/products`

Autenticación: `Authorization: Bearer <BARRIO_WEBHOOK_TOKEN>`.
En desarrollo, si no se define `BARRIO_WEBHOOK_TOKEN`, el token es `barrio-dev-token`.

```json
{
  "source": "whatsapp",
  "products": [
    {
      "name": "Jitomate saladet",
      "priceMXN": 32,
      "unit": "kg",
      "stock": 42,
      "available": true
    }
  ]
}
```

Una respuesta `202` confirma la sincronización. La app recibe el evento `product.sync` mediante `GET /api/events` (SSE) y actualiza la ficha del comercio en tiempo real.

`GET /api/merchant/:merchantId/products` devuelve el último estado recibido.

Los datos se mantienen sólo en memoria para esta demo. En producción, sustituir el `Map` de `server.mjs` por una base de datos y establecer `BARRIO_WEBHOOK_TOKEN` como secreto del entorno.
