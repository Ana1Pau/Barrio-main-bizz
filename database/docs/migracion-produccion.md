# Ruta de migración hacia opciones más económicas

Esta guía describe cómo pasar de **SQL Server 2025 Developer** (gratis,
solo dev/test) a **Azure SQL Database** (producción recomendada) y, desde
ahí, a alternativas de menor costo cuando el proyecto lo requiera. El
esquema de `database/sql/` es portable entre todas estas opciones porque
usa T-SQL estándar (sin extensiones exclusivas de una sola edición).

## 1. Developer (gratis) → Azure SQL Database (producción)

1. Exporta un **BACPAC** desde la instancia Developer (SSMS: *Tasks → Export
   Data-tier Application*, o `SqlPackage.exe /Action:Export`).
2. Importa el BACPAC a Azure SQL Database:
   ```bash
   az sql db import \
     --resource-group rg-barrio-prod --server sql-barrio-prod --name BarrioDB \
     --storage-key-type StorageAccessKey --storage-key <key> \
     --storage-uri https://<cuenta>.blob.core.windows.net/backups/BarrioDB.bacpac \
     --admin-user <admin> --admin-password <password>
   ```
3. Vuelve a aplicar `11_security.sql` (roles, RLS, Dynamic Data Masking) si
   el import no preserva políticas de seguridad a nivel de base.
4. Verifica Always Encrypted: las claves (CMK/CEK) deben re-registrarse
   apuntando al Azure Key Vault de producción.

## 2. Reducir costo dentro de Azure SQL Database

Antes de migrar a otro motor, Azure SQL Database ya ofrece niveles baratos:

| Nivel | Cuándo usarlo | Costo aproximado |
|---|---|---|
| **General Purpose Serverless** (auto-pausa) | Tráfico intermitente, demos, MVP | Solo pagas cómputo cuando hay actividad |
| **Basic / Standard (DTU)** | Cargas pequeñas y predecibles | Desde ~5 USD/mes |
| **General Purpose Gen5, 2 vCore** | Producción con tráfico constante moderado | Costo medio, rendimiento estable |

Recomendación: empezar en **Serverless** y subir de nivel solo si el
monitoreo (Azure Monitor / Query Performance Insight) muestra que se
necesita más cómputo sostenido.

## 3. Migrar a motores más baratos fuera de Azure SQL

Si más adelante se busca bajar aún más el costo, las opciones compatibles
con el mismo modelo relacional son:

- **Azure SQL Managed Instance → Azure SQL DB**: ya cubierto arriba.
- **PostgreSQL (Azure Database for PostgreSQL Flexible Server, nivel
  Burstable)**: requiere traducir el esquema T-SQL específico
  (`UNIQUEIDENTIFIER`→`uuid`, `SYSTEM_VERSIONING`→extensión `temporal_tables`
  o tablas de auditoría manuales, Always Encrypted→`pgcrypto` +
  cifrado de aplicación, RLS→`CREATE POLICY` nativo de Postgres, que de
  hecho es muy similar en concepto a lo ya implementado aquí).
- **MySQL (Azure Database for MySQL Flexible Server, Burstable)**: más
  económico, pero sin soporte nativo de RLS ni Always Encrypted; esas
  protecciones tendrían que moverse a la capa de aplicación.
- **SQL Server en un contenedor (Azure Container Apps / VM pequeña)**: útil
  solo si se cuenta con licencia propia (Developer sigue sin ser válido
  para producción).

Dado que el diseño ya separa claramente "tablas base" (acceso restringido)
de "vistas/procedimientos app.*" (único punto de acceso de la API), migrar
de motor en el futuro solo exige:

1. Recrear los mismos nombres de esquema/vista/procedimiento (la API no
   cambia sus llamadas).
2. Traducir tipos de datos y las extensiones específicas del motor.
3. Volver a validar RLS y cifrado con el nuevo motor.

## 4. Resumen de decisión

```
Desarrollo/pruebas  -> SQL Server 2025 Developer Edition (gratis, en VM Azure o local)
Producción inicial  -> Azure SQL Database, General Purpose Serverless
Producción estable  -> Azure SQL Database, General Purpose Gen5 (vCore reservado = ahorro)
Costo mínimo futuro -> Azure Database for PostgreSQL Flexible Server (Burstable)
                       (requiere adaptar el script 11_security.sql a RLS nativo de Postgres)
```
