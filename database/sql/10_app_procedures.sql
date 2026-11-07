/* ============================================================================
   10_app_procedures.sql
   Procedimientos almacenados: unico punto de escritura permitido para la
   API de la aplicacion. Todos usan parametros tipados (previene inyeccion
   SQL) y transacciones explicitas.
============================================================================ */

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE app.sp_RegistrarUsuario
    @Correo         NVARCHAR(256) = NULL,
    @Telefono       NVARCHAR(20)  = NULL,
    @HashContrasena VARBINARY(256),
    @SalContrasena  VARBINARY(64),
    @TipoUso        TINYINT,
    @NombreMostrar  NVARCHAR(100),
    @ColoniaId      INT = NULL,
    @UsuarioId      UNIQUEIDENTIFIER OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;
    BEGIN TRY
        DECLARE @NuevosUsuarios TABLE (UsuarioId UNIQUEIDENTIFIER);

        INSERT INTO ident.Usuarios (Correo, Telefono, HashContrasena, SalContrasena, TipoUso)
        OUTPUT inserted.UsuarioId INTO @NuevosUsuarios
        VALUES (@Correo, @Telefono, @HashContrasena, @SalContrasena, @TipoUso);

        SELECT @UsuarioId = UsuarioId FROM @NuevosUsuarios;

        INSERT INTO ident.Perfiles (UsuarioId, NombreMostrar, ColoniaId)
        VALUES (@UsuarioId, @NombreMostrar, @ColoniaId);

        INSERT INTO ident.UsuarioRoles (UsuarioId, RolId)
        SELECT @UsuarioId, RolId FROM lkp.Roles
        WHERE (@TipoUso = 1 AND Nombre = N'Comprador')
           OR (@TipoUso = 2 AND Nombre = N'Comercio')
           OR (@TipoUso = 3 AND Nombre IN (N'Comprador', N'Comercio'));

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE app.sp_CrearPedidoDesdeCarrito
    @UsuarioId      UNIQUEIDENTIFIER,
    @CarritoId      UNIQUEIDENTIFIER,
    @MetodoEntrega  NVARCHAR(20),
    @DireccionEntrega NVARCHAR(300) = NULL,
    @CostoEnvio     DECIMAL(10,2) = 0,
    @NotaCliente    NVARCHAR(300) = NULL,
    @PedidoId       UNIQUEIDENTIFIER OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM ord.Carritos WHERE CarritoId = @CarritoId AND UsuarioId = @UsuarioId)
    BEGIN
        THROW 50001, 'El carrito no pertenece al usuario indicado.', 1;
    END;

    DECLARE @ComercioId UNIQUEIDENTIFIER;
    DECLARE @Subtotal DECIMAL(10,2);
    DECLARE @EstadoNuevo TINYINT = (SELECT EstadoId FROM lkp.EstadosPedido WHERE Codigo = N'NUEVO');

    BEGIN TRANSACTION;
    BEGIN TRY
        SELECT @ComercioId = ComercioId FROM ord.Carritos WHERE CarritoId = @CarritoId;

        SELECT @Subtotal = SUM(Cantidad * PrecioUnitarioSnapshot)
        FROM ord.CarritoItems WHERE CarritoId = @CarritoId;

        IF @Subtotal IS NULL OR @Subtotal <= 0
            THROW 50002, 'El carrito esta vacio.', 1;

        SET @PedidoId = NEWID();

        INSERT INTO ord.Pedidos (PedidoId, UsuarioId, ComercioId, EstadoId, MetodoEntrega, DireccionEntrega, Subtotal, CostoEnvio, Total, NotaCliente)
        VALUES (@PedidoId, @UsuarioId, @ComercioId, @EstadoNuevo, @MetodoEntrega, @DireccionEntrega, @Subtotal, @CostoEnvio, @Subtotal + @CostoEnvio, @NotaCliente);

        INSERT INTO ord.PedidoItems (PedidoId, ProductoId, NombreProductoSnapshot, Cantidad, PrecioUnitario)
        SELECT @PedidoId, ci.ProductoId, p.Nombre, ci.Cantidad, ci.PrecioUnitarioSnapshot
        FROM ord.CarritoItems ci
        INNER JOIN catalogo.Productos p ON p.ProductoId = ci.ProductoId
        WHERE ci.CarritoId = @CarritoId;

        UPDATE pr
        SET Existencias = pr.Existencias - ci.Cantidad
        FROM catalogo.Productos pr
        INNER JOIN ord.CarritoItems ci ON ci.ProductoId = pr.ProductoId
        WHERE ci.CarritoId = @CarritoId;

        INSERT INTO ord.PedidoEstadoHistorial (PedidoId, EstadoId, CambiadoPorUsuarioId, Comentario)
        VALUES (@PedidoId, @EstadoNuevo, @UsuarioId, N'Pedido creado');

        DELETE FROM ord.CarritoItems WHERE CarritoId = @CarritoId;
        DELETE FROM ord.Carritos WHERE CarritoId = @CarritoId;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE app.sp_ActualizarEstadoPedido
    @PedidoId   UNIQUEIDENTIFIER,
    @NuevoEstadoCodigo NVARCHAR(20),
    @CambiadoPorUsuarioId UNIQUEIDENTIFIER = NULL,
    @Comentario NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @EstadoId TINYINT = (SELECT EstadoId FROM lkp.EstadosPedido WHERE Codigo = @NuevoEstadoCodigo);
    IF @EstadoId IS NULL THROW 50003, 'Estado de pedido invalido.', 1;

    BEGIN TRANSACTION;
    BEGIN TRY
        UPDATE ord.Pedidos
        SET EstadoId = @EstadoId, ActualizadoUtc = SYSUTCDATETIME()
        WHERE PedidoId = @PedidoId;

        INSERT INTO ord.PedidoEstadoHistorial (PedidoId, EstadoId, CambiadoPorUsuarioId, Comentario)
        VALUES (@PedidoId, @EstadoId, @CambiadoPorUsuarioId, @Comentario);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE app.sp_RegistrarPago
    @PedidoId           UNIQUEIDENTIFIER,
    @MetodoPagoCodigo   NVARCHAR(20),
    @Monto              DECIMAL(10,2),
    @ProveedorReferencia NVARCHAR(100) = NULL,
    @TokenPagoEncriptado VARBINARY(256) = NULL,
    @PagoId             UNIQUEIDENTIFIER OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @MetodoPagoId TINYINT = (SELECT MetodoPagoId FROM lkp.MetodosPago WHERE Codigo = @MetodoPagoCodigo);
    DECLARE @EstadoPendiente TINYINT = (SELECT EstadoPagoId FROM lkp.EstadosPago WHERE Codigo = N'PENDIENTE');
    SET @PagoId = NEWID();

    BEGIN TRANSACTION;
    BEGIN TRY
        INSERT INTO pay.Pagos (PagoId, PedidoId, MetodoPagoId, EstadoPagoId, Monto, ProveedorReferencia, TokenPagoEncriptado)
        VALUES (@PagoId, @PedidoId, @MetodoPagoId, @EstadoPendiente, @Monto, @ProveedorReferencia, @TokenPagoEncriptado);

        INSERT INTO pay.CoordinadorPagosEventos (PagoId, Etapa, DetalleJson)
        VALUES (@PagoId, N'SOLICITADO', JSON_QUERY((SELECT @MetodoPagoCodigo AS metodo, @Monto AS monto FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)));

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE app.sp_RegistrarAlertaAntifraude
    @PagoId         UNIQUEIDENTIFIER,
    @NivelRiesgo    NVARCHAR(10),
    @Motivo         NVARCHAR(300),
    @RequiereVerificacionAdicional BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;
    BEGIN TRY
        INSERT INTO pay.AlertasAntifraude (PagoId, NivelRiesgo, Motivo, RequiereVerificacionAdicional)
        VALUES (@PagoId, @NivelRiesgo, @Motivo, @RequiereVerificacionAdicional);

        INSERT INTO pay.CoordinadorPagosEventos (PagoId, Etapa, DetalleJson)
        VALUES (@PagoId, N'VERIFICACION_RIESGO',
            JSON_QUERY((SELECT @NivelRiesgo AS nivel, @Motivo AS motivo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)));

        IF @NivelRiesgo = N'ALTO'
        BEGIN
            UPDATE pay.Pagos
            SET EstadoPagoId = (SELECT EstadoPagoId FROM lkp.EstadosPago WHERE Codigo = N'EN_REVISION')
            WHERE PagoId = @PagoId;
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
