/* ============================================================================
   09_app_views.sql
   Vistas de solo lectura expuestas a la aplicacion (API). La aplicacion NO
   debe leer directamente de las tablas base en produccion; debe usar estas
   vistas y los procedimientos de 10_app_procedures.sql (ver 11_security.sql
   para los permisos que hacen cumplir esta regla).
============================================================================ */

CREATE OR ALTER VIEW app.PerfilPublicoComercio AS
SELECT
    c.ComercioId,
    c.NombreNegocio,
    c.Descripcion,
    c.FotoPerfilUrl,
    c.FotoPortadaUrl,
    c.CalificacionPromedio,
    c.TotalResenas,
    co.Nombre AS Colonia,
    c.DireccionLinea,
    c.Latitud,
    c.Longitud,
    c.EstaActivo,
    c.EstaVerificado
FROM biz.Comercios c
LEFT JOIN lkp.Colonias co ON co.ColoniaId = c.ColoniaId
WHERE c.EstaActivo = 1;
GO

CREATE OR ALTER VIEW app.VentasDiariasPorComercio AS
SELECT
    p.ComercioId,
    CAST(p.CreadoUtc AS DATE) AS Fecha,
    COUNT(DISTINCT p.PedidoId) AS TotalPedidos,
    SUM(p.Total) AS VentasTotales
FROM ord.Pedidos p
INNER JOIN lkp.EstadosPedido e ON e.EstadoId = p.EstadoId AND e.Codigo = N'COMPLETADO'
GROUP BY p.ComercioId, CAST(p.CreadoUtc AS DATE);
GO

CREATE OR ALTER VIEW app.ProductosMasVendidos AS
SELECT
    pr.ComercioId,
    pi.ProductoId,
    pi.NombreProductoSnapshot AS NombreProducto,
    SUM(pi.Cantidad) AS UnidadesVendidas,
    SUM(pi.Importe) AS IngresosGenerados
FROM ord.PedidoItems pi
INNER JOIN ord.Pedidos pd ON pd.PedidoId = pi.PedidoId
INNER JOIN catalogo.Productos pr ON pr.ProductoId = pi.ProductoId
INNER JOIN lkp.EstadosPedido e ON e.EstadoId = pd.EstadoId AND e.Codigo = N'COMPLETADO'
GROUP BY pr.ComercioId, pi.ProductoId, pi.NombreProductoSnapshot;
GO

CREATE OR ALTER VIEW app.PedidosDetalle AS
SELECT
    p.PedidoId,
    p.NumeroPedido,
    p.UsuarioId,
    p.ComercioId,
    es.Codigo AS EstadoCodigo,
    es.Nombre AS EstadoNombre,
    p.MetodoEntrega,
    p.Subtotal,
    p.CostoEnvio,
    p.Total,
    p.CreadoUtc,
    p.ActualizadoUtc
FROM ord.Pedidos p
INNER JOIN lkp.EstadosPedido es ON es.EstadoId = p.EstadoId;
GO
