/* ============================================================================
   BARRIO - 00_create_database.sql
   Crea la base de datos y los esquemas logicos.
   Compatible con:
     - SQL Server 2025 (Developer Edition, IaaS en Azure VM o local)
     - Azure SQL Database (PaaS)
   Ejecutar conectado a la instancia/servidor como administrador.
============================================================================ */

-- En Azure SQL Database la base ya existe tras crearla desde Azure Portal/CLI
-- (no se puede ejecutar CREATE DATABASE dentro de la misma conexion).
-- Este bloque solo aplica cuando se ejecuta contra SQL Server 2025 (VM/local).
IF DB_ID(N'BarrioDB') IS NULL
BEGIN
    PRINT 'Creando base de datos BarrioDB (modo SQL Server en VM/local)...';
    EXEC('CREATE DATABASE BarrioDB');
END
GO

-- A partir de aqui, conectarse/usar BarrioDB (en Azure SQL Database esto ya
-- es el contexto de conexion, por lo que el USE se ignora o se omite segun
-- la herramienta de despliegue).
IF DB_ID(N'BarrioDB') IS NOT NULL AND DB_NAME() <> N'BarrioDB'
BEGIN
    PRINT 'Recuerda conectarte a BarrioDB antes de ejecutar los siguientes scripts.';
END
GO

-- Forzar nivel de compatibilidad alto (disponible en SQL Server 2025 y Azure SQL)
IF DB_ID(N'BarrioDB') IS NOT NULL
BEGIN
    DECLARE @sql nvarchar(400) = N'ALTER DATABASE BarrioDB SET COMPATIBILITY_LEVEL = 160';
    EXEC(@sql);
END
GO

/* ---------------------------------------------------------------------------
   Esquemas logicos (separan responsabilidades y facilitan permisos/RLS)
   ident     -> cuentas, perfiles, sesiones, verificaciones de identidad
   lkp       -> catalogos de referencia (colonias, categorias, estados...)
   biz       -> comercios y su configuracion
   catalogo  -> productos del comercio
   ord       -> carritos y pedidos
   pay       -> pagos, antifraude y coordinador de pagos
   soc       -> comunidad: publicaciones, mensajes, resenas, favoritos
   aud       -> auditoria
   app       -> vistas y procedimientos de acceso para la aplicacion (API)
--------------------------------------------------------------------------- */
CREATE SCHEMA ident AUTHORIZATION dbo;
GO
CREATE SCHEMA lkp AUTHORIZATION dbo;
GO
CREATE SCHEMA biz AUTHORIZATION dbo;
GO
CREATE SCHEMA catalogo AUTHORIZATION dbo;
GO
CREATE SCHEMA ord AUTHORIZATION dbo;
GO
CREATE SCHEMA pay AUTHORIZATION dbo;
GO
CREATE SCHEMA soc AUTHORIZATION dbo;
GO
CREATE SCHEMA aud AUTHORIZATION dbo;
GO
CREATE SCHEMA app AUTHORIZATION dbo;
GO
