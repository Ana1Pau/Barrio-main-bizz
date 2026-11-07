## Qué cambia

<!-- Resume el cambio y el motivo. -->

## Cómo se verificó

- [ ] `cd apps/api && node --test`
- [ ] `node --check apps/api/src/server.mjs`
- [ ] `docker compose --env-file database/docker/.env.example -f database/docker/docker-compose.yml config --quiet`
- [ ] Probado en modo simulado; no se hicieron cobros reales

## Seguridad y datos

- [ ] No incluye `.env`, CLABEs completas, API keys ni secretos
- [ ] Cambios SQL revisados y documentados
- [ ] Si cambia un endpoint, se actualizó la documentación

## Pendientes / riesgos

<!-- Indica lo que necesita configuración, revisión de otra persona o pruebas de staging. -->
