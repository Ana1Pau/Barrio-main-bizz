# BARRIO — Base de datos

Modelo de base de datos completo para la aplicación **BARRIO** (app de
compradores + panel de comercios del vecindario, con pagos tradicionales y
cripto vía red Hedera/HBAR, mensajería, reseñas y antifraude).

## Contenido del repositorio

```
database/
├── sql/                         # Scripts T-SQL, en orden de ejecución
│   ├── 00_create_database.sql
│   ├── 01_lkp_catalogos.sql     # Catálogos de referencia
│   ├── 02_ident_identidad.sql   # Usuarios, perfiles, sesiones
│   ├── 03_biz_comercios.sql     # Comercios y su configuración
│   ├── 04_catalogo_productos.sql
│   ├── 05_ord_pedidos.sql       # Carritos y pedidos (con historial temporal)
│   ├── 06_pay_pagos.sql         # Pagos, pagos cripto HBAR, antifraude
│   ├── 07_soc_comunidad.sql     # Publicaciones, mensajes, reseñas, favoritos
│   ├── 08_aud_auditoria.sql     # Auditoría de cambios
│   ├── 09_app_views.sql         # Vistas de solo lectura para la API
│   ├── 10_app_procedures.sql    # Procedimientos almacenados (único punto de escritura)
│   ├── 11_security.sql          # Roles, RLS, Dynamic Data Masking, Always Encrypted, TDE
│   ├── 12_seed_data.sql         # Datos de catálogo iniciales
│   └── deploy_all.sql           # Orquesta la ejecución completa (sqlcmd)
├── connection-examples/
│   ├── dotnet/                  # Ejemplo de conexión segura en .NET
│   └── node/                    # Ejemplo de conexión segura en Node.js
└── docs/
    ├── azure-setup.md           # Cómo desplegar en SQL Server 2025 Developer y Azure SQL Database
    └── migracion-produccion.md  # Ruta de migración hacia opciones más económicas
```

## Modelo de datos (resumen)

- **ident**: cuentas de usuario (compradores/comercios), perfiles, roles,
  sesiones (refresh tokens hasheados) y verificación de identidad.
- **biz**: perfil público de cada comercio, categorías, métodos de pago que
  acepta y horarios.
- **catalogo**: productos publicados por cada comercio.
- **ord**: carritos y pedidos, con historial automático de cambios
  (tablas temporales `SYSTEM_VERSIONING`).
- **pay**: pagos (tarjeta, SPEI, efectivo, NFC, cripto HBAR), alertas de
  antifraude y la bitácora del coordinador de pagos.
- **soc**: comunidad — publicaciones, mensajería comercio↔cliente, reseñas,
  favoritos, notificaciones y sugerencias del agente de compras (que solo
  sugiere, nunca autoriza pagos).
- **aud**: auditoría genérica de cambios ejecutados por la aplicación.
- **app**: vistas y procedimientos almacenados — el único punto de acceso
  que debe usar el backend/API (nunca las tablas base directamente).

## Seguridad implementada

- Conexión siempre cifrada (TLS): `Encrypt=True; TrustServerCertificate=False`.
- Autenticación recomendada vía **Microsoft Entra ID / Managed Identity**
  (sin contraseñas SQL embebidas); modo de respaldo con contraseña SQL leída
  únicamente de variable de entorno / Key Vault.
- **Mínimo privilegio**: la API solo puede ejecutar procedimientos y leer
  vistas del esquema `app`; no tiene acceso directo a las tablas base.
- **Row-Level Security**: un comprador solo ve sus propios pedidos, un
  comercio solo ve los pedidos que recibió; el catálogo público (comercios y
  productos) permanece visible para cualquier usuario.
- **Dynamic Data Masking** sobre correo y teléfono.
- **Always Encrypted** (referencia) para el token de pago, cifrado del lado
  del cliente, nunca legible en el servidor.
- **TDE** (cifrado en reposo) y auditoría de cambios con triggers +
  tablas temporales.

Contraseñas y hashes nunca se guardan en texto plano: el backend calcula el
hash (Argon2id/bcrypt) antes de insertarlo, usando los procedimientos de
`app`.

## Cómo desplegar

Ver `database/docs/azure-setup.md` para los pasos detallados:

1. **Desarrollo/pruebas**: SQL Server 2025 Developer Edition (gratis, uso no
   productivo) en una VM de Azure o localmente.
2. **Producción**: Azure SQL Database (empezando en el nivel
   *General Purpose Serverless* para minimizar costo).
3. **Migración a opciones más económicas**: ver
   `database/docs/migracion-produccion.md`.

Despliegue rápido con `sqlcmd`:

```bash
cd database/sql
sqlcmd -S <tu-servidor>.database.windows.net -d BarrioDB -G -i deploy_all.sql
```

(`-G` fuerza autenticación con Microsoft Entra ID; usa `-U`/`-P` solo en
ambientes de desarrollo aislados, nunca en producción).

## Validación

Todo el esquema (12 scripts) fue ejecutado y verificado de punta a punta
contra un motor SQL Server real (Azure SQL Edge en contenedor), incluyendo:
registro de usuarios, creación de comercio/producto, flujo completo de
carrito→pedido→pago→alerta antifraude, y los 5 escenarios de Row-Level
Security (catálogo público visible sin sesión; pedido invisible sin
contexto; visible solo para el comprador dueño, el comercio receptor, o un
administrador).
