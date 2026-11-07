/* ============================================================================
   12_seed_data.sql
   Datos de catalogo iniciales (no incluye datos personales ni de prueba
   con informacion real).
============================================================================ */

INSERT INTO lkp.Roles (RolId, Nombre) VALUES
    (1, N'Comprador'),
    (2, N'Comercio'),
    (3, N'Administrador');
GO

INSERT INTO lkp.Categorias (Nombre, Icono) VALUES
    (N'Cafeterias', N'coffee'),
    (N'Alimentos', N'food'),
    (N'Tiendas', N'store'),
    (N'Flores', N'flower'),
    (N'Belleza', N'beauty'),
    (N'Hogar', N'home'),
    (N'Servicios', N'service'),
    (N'Otros', N'other');
GO

INSERT INTO lkp.MetodosPago (MetodoPagoId, Codigo, Nombre, RequiereAntifraude) VALUES
    (1, N'TARJETA', N'Tarjeta de debito o credito', 0),
    (2, N'SPEI', N'Transferencia SPEI', 0),
    (3, N'EFECTIVO', N'Pago en efectivo', 0),
    (4, N'NFC', N'Pago sin contacto (NFC)', 0),
    (5, N'CRIPTO_HBAR', N'Criptomoneda (Red Hedera HBAR)', 1);
GO

INSERT INTO lkp.EstadosPedido (EstadoId, Codigo, Nombre, Orden) VALUES
    (1, N'NUEVO', N'Nuevo', 1),
    (2, N'PREPARANDO', N'Preparando', 2),
    (3, N'LISTO', N'Listo', 3),
    (4, N'COMPLETADO', N'Completado', 4),
    (5, N'CANCELADO', N'Cancelado', 5);
GO

INSERT INTO lkp.EstadosPago (EstadoPagoId, Codigo, Nombre) VALUES
    (1, N'PENDIENTE', N'Pendiente'),
    (2, N'AUTORIZADO', N'Autorizado'),
    (3, N'CONFIRMADO', N'Confirmado'),
    (4, N'RECHAZADO', N'Rechazado'),
    (5, N'EN_REVISION', N'En revision antifraude'),
    (6, N'REEMBOLSADO', N'Reembolsado');
GO

INSERT INTO lkp.Colonias (Nombre, Ciudad, Estado) VALUES
    (N'Roma Norte', N'CDMX', N'Ciudad de Mexico'),
    (N'Condesa', N'CDMX', N'Ciudad de Mexico'),
    (N'Del Valle', N'CDMX', N'Ciudad de Mexico'),
    (N'Coyoacan', N'CDMX', N'Ciudad de Mexico'),
    (N'Narvarte', N'CDMX', N'Ciudad de Mexico'),
    (N'Centro', N'CDMX', N'Ciudad de Mexico'),
    (N'Juarez', N'CDMX', N'Ciudad de Mexico');
GO
