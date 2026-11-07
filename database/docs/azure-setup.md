# Despliegue en Azure — BARRIO

Esta guía cubre dos caminos, tal como se pidió: **(A) SQL Server 2025
Developer Edition en Azure** para desarrollo/pruebas sin costo de licencia,
y **(B) Azure SQL Database** como ruta recomendada para producción (y para
migrar más adelante a opciones más económicas).

## Opción A — SQL Server 2025 Developer Edition en una VM de Azure (dev/test)

La edición *Developer* de SQL Server es gratuita y funcionalmente idéntica a
Enterprise, pero su licencia **solo permite uso de desarrollo y pruebas, no
producción**. Es ideal para que el equipo desarrolle y valide el esquema
antes de promoverlo.

```bash
# 1) Grupo de recursos
az group create --name rg-barrio-dev --location mexicocentral

# 2) VM con SQL Server 2025 Developer preinstalado (imagen de Azure Marketplace)
az vm create \
  --resource-group rg-barrio-dev \
  --name vm-barrio-sql2025-dev \
  --image "MicrosoftSQLServer:sql2025-ws2025:sqldev-gen2:latest" \
  --admin-username barrioadmin \
  --generate-ssh-keys \
  --size Standard_D4s_v5

# 3) Abrir el puerto 1433 SOLO para las IP que lo necesiten (nunca 0.0.0.0/0)
az vm open-port --resource-group rg-barrio-dev --name vm-barrio-sql2025-dev \
  --port 1433 --priority 900 --source-address-prefixes <IP_DE_TU_OFICINA>/32
```

Después de aprovisionar la VM:

1. Conéctate con SSMS/Azure Data Studio/`sqlcmd` usando autenticación de
   Windows o un login SQL dedicado (nunca `sa` desde la app).
2. Ejecuta los scripts de `database/sql/` en orden (`deploy_all.sql`).
3. Habilita TDE y restringe el firewall de Windows a los orígenes de la API.
4. **No expongas la VM a Internet**: usa una VPN/Private Endpoint o un
   Azure Bastion para administración.

## Opción B — Azure SQL Database (recomendado desde el día 1 para producción)

Azure SQL Database es un servicio administrado (PaaS): sin parches de SO,
con TDE y backups automáticos, firewall integrado y escalado elástico. Es
la base sobre la que luego se migra a niveles más baratos.

```bash
az group create --name rg-barrio-prod --location mexicocentral

# Servidor lógico (recomendado: solo autenticación Azure AD, sin login SQL)
az sql server create \
  --name sql-barrio-prod \
  --resource-group rg-barrio-prod \
  --location mexicocentral \
  --enable-ad-only-auth \
  --external-admin-principal-type User \
  --external-admin-name "<tu-usuario>@tudominio.com" \
  --external-admin-sid "<object-id-de-microsoft-entra-id>"

# Base de datos en el nivel "General Purpose Serverless" (bajo costo, auto-pausa)
az sql db create \
  --resource-group rg-barrio-prod \
  --server sql-barrio-prod \
  --name BarrioDB \
  --edition GeneralPurpose \
  --family Gen5 \
  --compute-model Serverless \
  --capacity 2 \
  --auto-pause-delay 60

# Firewall: solo servicios de Azure y, opcionalmente, tu IP para administrar
az sql server firewall-rule create \
  --resource-group rg-barrio-prod --server sql-barrio-prod \
  --name AllowAzureServices --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0
```

Despliegue del esquema (con autenticación Azure AD, sin contraseñas):

```bash
cd database/sql
sqlcmd -S sql-barrio-prod.database.windows.net -d BarrioDB -G -i deploy_all.sql
```

### Identidad administrada para la API

En vez de usuario/contraseña SQL, crea un **Managed Identity** para tu App
Service/Container App y dale acceso a la base:

```sql
-- Ejecutar conectado como el admin de Azure AD del servidor
CREATE USER [app-barrio-api] FROM EXTERNAL PROVIDER;
ALTER ROLE role_app_api ADD MEMBER [app-barrio-api];
```

Esto elimina por completo la necesidad de guardar una contraseña de base de
datos en la aplicación.

### Azure Key Vault (si se usa autenticación SQL en algún ambiente)

```bash
az keyvault create --name kv-barrio --resource-group rg-barrio-prod --location mexicocentral
az keyvault secret set --vault-name kv-barrio --name BarrioDbPassword --value "<generada-con-un-gestor-de-contrasenas>"
```

La aplicación lee el secreto desde Key Vault en tiempo de ejecución (por
ejemplo con `DefaultAzureCredential` + `SecretClient`), nunca desde un
archivo de configuración versionado.

## Checklist de seguridad antes de ir a producción

- [ ] `Encrypt=True` y `TrustServerCertificate=False` en toda cadena de conexión.
- [ ] Autenticación Azure AD / Managed Identity (sin contraseñas SQL en la API).
- [ ] Firewall de Azure SQL limitado a los rangos de IP/VNet necesarios.
- [ ] TDE habilitado (por defecto en Azure SQL Database).
- [ ] Always Encrypted activo para `pay.Pagos.TokenPagoEncriptado`.
- [ ] Row-Level Security verificada (`seg.PedidosAccesoPolicy`).
- [ ] Auditoría de Azure SQL (`az sql db audit-policy update`) habilitada
      enviando logs a Log Analytics / Storage.
- [ ] Microsoft Defender for SQL habilitado para detección de amenazas.
- [ ] Backups geo-redundantes configurados (`--backup-storage-redundancy Geo`).
