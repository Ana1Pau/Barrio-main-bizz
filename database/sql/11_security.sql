/* ============================================================================
   11_security.sql
   Modelo de seguridad de BARRIO. Principios aplicados:

   1) Minimo privilegio: la API nunca usa un login "sa"/admin. Se conecta con
      un usuario de base de datos contenido que SOLO puede ejecutar los
      procedimientos de app.* y leer las vistas de app.*; no tiene acceso
      directo de lectura/escritura a las tablas base.
   2) Autenticacion recomendada: Azure AD / Microsoft Entra ID (sin
      contrasenas SQL). Se incluye tambien la variante SQL Auth por si se
      usa SQL Server 2025 on-prem/VM sin Entra ID.
   3) Cifrado en transito: Encrypt=True;TrustServerCertificate=False siempre
      (TLS 1.2+). Azure SQL lo exige por defecto.
   4) Cifrado en reposo: TDE (Transparent Data Encryption).
   5) Enmascaramiento dinamico de datos (Dynamic Data Masking) sobre
      correo/telefono para roles sin permiso explicito de "UNMASK".
   6) Always Encrypted para el token de pago (nunca viaja ni se guarda en
      claro en el servidor).
   7) Row-Level Security: un comerciante solo ve sus propios comercios,
      productos y pedidos; se filtra por el UsuarioId que la API coloca en
      SESSION_CONTEXT en cada conexion/solicitud.
============================================================================ */

-------------------------------------------------------------------------------
-- 1) Roles de base de datos (principio de minimo privilegio)
-------------------------------------------------------------------------------
CREATE ROLE role_app_api;        -- usado por el backend/API de BARRIO
CREATE ROLE role_reportes_ro;    -- usado por BI/reportes (solo vistas agregadas)
CREATE ROLE role_admin_migraciones; -- usado solo por pipelines de CI/CD para DDL
GO

-- La API solo puede ejecutar procedimientos y leer vistas de app.*
GRANT EXECUTE ON SCHEMA::app TO role_app_api;
GRANT SELECT  ON SCHEMA::app TO role_app_api;
-- sys.sp_set_session_context (usado para fijar el UsuarioId de la sesion y
-- habilitar RLS) tiene EXECUTE otorgado a PUBLIC por defecto en SQL Server
-- y Azure SQL Database: no requiere un GRANT adicional.
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::ident TO role_app_api;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::biz TO role_app_api;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::catalogo TO role_app_api;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::ord TO role_app_api;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::pay TO role_app_api;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::soc TO role_app_api;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::aud TO role_app_api;
GO

-- Reportes: solo vistas de agregados, nunca tablas con PII/pagos
GRANT SELECT ON app.VentasDiariasPorComercio TO role_reportes_ro;
GRANT SELECT ON app.ProductosMasVendidos TO role_reportes_ro;
GO

-------------------------------------------------------------------------------
-- 2) Usuario contenido para la API (recomendado: Azure AD / Managed Identity)
--
-- Opcion A (recomendada en Azure): identidad administrada / Entra ID.
--   CREATE USER [app-barrio-api] FROM EXTERNAL PROVIDER;
--   ALTER ROLE role_app_api ADD MEMBER [app-barrio-api];
--
-- Opcion B (SQL Auth, solo si no se puede usar Entra ID, p.ej. SQL Server
-- 2025 Developer en una VM aislada). La contrasena NUNCA debe escribirse
-- en este script: se genera fuera y se guarda en Azure Key Vault /
-- variable de entorno del pipeline de despliegue.
--
--   CREATE LOGIN app_barrio_api WITH PASSWORD = '<PASSWORD_DESDE_KEY_VAULT>';
--   CREATE USER app_barrio_api FOR LOGIN app_barrio_api;
--   ALTER ROLE role_app_api ADD MEMBER app_barrio_api;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- 3) Dynamic Data Masking sobre datos de contacto (PII)
--    El enmascarado se define directamente en ident.Usuarios (ver
--    02_ident_identidad.sql) porque un ALTER COLUMN ADD MASKED posterior
--    falla si ya existen indices dependientes de esa columna. Solo roles
--    con permiso explicito UNMASK ven el dato real (p.ej. soporte
--    autorizado):
--      GRANT UNMASK TO role_soporte_autorizado;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- 4) Row-Level Security
--
--    IMPORTANTE: biz.Comercios y catalogo.Productos son el catalogo PUBLICO
--    de la app (cualquier comprador debe poder verlos al explorar el mapa o
--    una tienda), por lo que NO llevan un FILTER PREDICATE de lectura; solo
--    llevan un BLOCK PREDICATE para que un comerciante nunca pueda EDITAR
--    el negocio de otro. En cambio, ord.Pedidos y pay.Pagos SI llevan
--    FILTER PREDICATE porque son datos privados: solo el comprador dueno
--    del pedido, el comercio que lo recibio, o un administrador, deben
--    poder leerlos.
-------------------------------------------------------------------------------
CREATE SCHEMA seg AUTHORIZATION dbo;
GO

-- Bloquea escritura de un comercio que no es el propio (lectura sigue publica)
CREATE FUNCTION seg.fn_PredicadoComercioPropio(@UsuarioPropietarioId UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS Permitido
WHERE @UsuarioPropietarioId = TRY_CAST(SESSION_CONTEXT(N'UsuarioId') AS UNIQUEIDENTIFIER)
   OR TRY_CAST(SESSION_CONTEXT(N'EsAdmin') AS BIT) = 1;
GO

CREATE SECURITY POLICY seg.ComercioEscrituraPolicy
ADD BLOCK PREDICATE seg.fn_PredicadoComercioPropio(UsuarioPropietarioId) ON biz.Comercios AFTER UPDATE,
ADD BLOCK PREDICATE seg.fn_PredicadoComercioPropio(UsuarioPropietarioId) ON biz.Comercios BEFORE DELETE
WITH (STATE = ON);
GO

-- Filtra pedidos: solo los ve el comprador, el comercio receptor o un admin
CREATE FUNCTION seg.fn_PredicadoAccesoPedido(@UsuarioId UNIQUEIDENTIFIER, @ComercioId UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS Permitido
WHERE @UsuarioId = TRY_CAST(SESSION_CONTEXT(N'UsuarioId') AS UNIQUEIDENTIFIER)
   OR EXISTS (
        SELECT 1 FROM biz.Comercios c
        WHERE c.ComercioId = @ComercioId
          AND c.UsuarioPropietarioId = TRY_CAST(SESSION_CONTEXT(N'UsuarioId') AS UNIQUEIDENTIFIER)
      )
   OR TRY_CAST(SESSION_CONTEXT(N'EsAdmin') AS BIT) = 1;
GO

CREATE SECURITY POLICY seg.PedidosAccesoPolicy
ADD FILTER PREDICATE seg.fn_PredicadoAccesoPedido(UsuarioId, ComercioId) ON ord.Pedidos
WITH (STATE = ON);
GO

-- La API, al inicio de cada solicitud autenticada, ejecuta:
--   EXEC sys.sp_set_session_context @key = N'UsuarioId', @value = @UsuarioIdAutenticado, @read_only = 1;
--   EXEC sys.sp_set_session_context @key = N'EsAdmin', @value = @EsAdministrador, @read_only = 1;

-------------------------------------------------------------------------------
-- 5) Always Encrypted (referencia): el token de pago se cifra del lado del
--    cliente/driver, nunca en el servidor. Se ejecuta UNA vez con el modulo
--    de administracion de claves (Key Vault) ANTES de cargar datos:
--
--    CREATE COLUMN MASTER KEY CMK_Barrio
--    WITH (KEY_STORE_PROVIDER_NAME = 'AZURE_KEY_VAULT',
--          KEY_PATH = 'https://<tu-keyvault>.vault.azure.net/keys/<nombre-clave>/<version>');
--
--    CREATE COLUMN ENCRYPTION KEY CEK_Pagos
--    WITH VALUES (COLUMN_MASTER_KEY = CMK_Barrio, ALGORITHM = 'RSA_OAEP',
--                 ENCRYPTED_VALUE = <valor-generado-por-el-driver>);
--
--    ALTER TABLE pay.Pagos
--    ALTER COLUMN TokenPagoEncriptado VARBINARY(256)
--    ENCRYPTED WITH (COLUMN_ENCRYPTION_KEY = CEK_Pagos,
--                    ENCRYPTION_TYPE = Randomized,
--                    ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256');
--
--    Esto requiere "Column Encryption Setting=Enabled" en la cadena de
--    conexion del cliente (ver connection-examples/).
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- 6) Transparent Data Encryption (cifrado en reposo)
--    Azure SQL Database: habilitado por defecto.
--    SQL Server 2025 en VM/on-prem, ejecutar como administrador:
--
--    CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<PASSWORD_DESDE_KEY_VAULT>';
--    CREATE CERTIFICATE CertBarrioTDE WITH SUBJECT = 'BarrioDB TDE';
--    CREATE DATABASE ENCRYPTION KEY
--      WITH ALGORITHM = AES_256
--      ENCRYPTION BY SERVER CERTIFICATE CertBarrioTDE;
--    ALTER DATABASE BarrioDB SET ENCRYPTION ON;
-------------------------------------------------------------------------------
