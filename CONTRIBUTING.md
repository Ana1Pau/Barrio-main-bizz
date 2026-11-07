# Colaborar en BARRIO

## Preparar el entorno

1. Clona el repositorio de GitHub y crea una rama por cambio, por ejemplo `feat/api-checkout` o `fix/webhook-idempotency`.
2. Lee `apps/api/README-deploy.md` antes de iniciar el stack local.
3. Copia `database/docker/.env.example` a `.env` solo para desarrollo local y conserva el modo `simulated`.
4. Antes de abrir un pull request, ejecuta `cd apps/api && node --test` y valida la sintaxis de los módulos modificados.

## Reglas del proyecto

- No guardes secretos, CLABEs completas ni datos personales de prueba en GitHub.
- No habilites cobros reales en pruebas ni CI.
- Los cambios de esquema van en una migración nueva; no reescribas migraciones ya aplicadas.
- Los webhooks solo deben cambiar estados después de verificar la firma y correlacionar el monto, cuenta y QR.
- Abre un pull request para que otra persona revise los cambios antes de integrarlos a la rama principal.
