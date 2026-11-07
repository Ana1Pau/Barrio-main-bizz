/*
  13_api_runtime.sql
  Runtime surface for apps/api: Pey merchant accounts, idempotent checkouts,
  webhook inbox and the narrow views/procedures exposed to the API principal.
  Run after 12_seed_data.sql in fresh installations and once on existing DBs.
*/
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS (SELECT 1 FROM lkp.MetodosPago WHERE Codigo = N'PEY_CODI')
  INSERT INTO lkp.MetodosPago (MetodoPagoId, Codigo, Nombre, RequiereAntifraude)
  VALUES ((SELECT ISNULL(MAX(MetodoPagoId), 0) + 1 FROM lkp.MetodosPago), N'PEY_CODI', N'CoDi (pey)', 0);
GO

CREATE SEQUENCE pay.SecuenciaReferenciaPey AS INT START WITH 1000000 INCREMENT BY 1;
GO

CREATE TABLE pay.CuentasPeyComercio (
  CuentaPeyId UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_pay_CuentasPey_Id DEFAULT NEWSEQUENTIALID(),
  ComercioId UNIQUEIDENTIFIER NOT NULL,
  PeyBankAccountId NVARCHAR(40) NOT NULL,
  ClabeUltimos4 CHAR(4) NOT NULL,
  CodiStatus NVARCHAR(20) NOT NULL,
  CreadoUtc DATETIME2(3) NOT NULL CONSTRAINT DF_pay_CuentasPey_Creado DEFAULT SYSUTCDATETIME(),
  ActualizadoUtc DATETIME2(3) NULL,
  CONSTRAINT PK_pay_CuentasPeyComercio PRIMARY KEY (CuentaPeyId),
  CONSTRAINT UQ_pay_CuentasPey_Comercio UNIQUE (ComercioId),
  CONSTRAINT UQ_pay_CuentasPey_Proveedor UNIQUE (PeyBankAccountId),
  CONSTRAINT FK_pay_CuentasPey_Comercio FOREIGN KEY (ComercioId) REFERENCES biz.Comercios(ComercioId),
  CONSTRAINT CK_pay_CuentasPey_Status CHECK (CodiStatus IN (N'PENDING', N'PROCESSING', N'ACTIVE', N'ERROR'))
);
GO

CREATE TABLE pay.PeyAltaCuentaIntentos (
  IntentoId UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_pay_PeyAlta_Id DEFAULT NEWSEQUENTIALID(),
  ComercioId UNIQUEIDENTIFIER NOT NULL,
  IdempotencyKey NVARCHAR(100) NOT NULL,
  ClabeUltimos4 CHAR(4) NOT NULL,
  Estado NVARCHAR(20) NOT NULL,
  CreadoUtc DATETIME2(3) NOT NULL CONSTRAINT DF_pay_PeyAlta_Creado DEFAULT SYSUTCDATETIME(),
  CONSTRAINT PK_pay_PeyAltaCuentaIntentos PRIMARY KEY (IntentoId),
  CONSTRAINT UQ_pay_PeyAlta_ComercioKey UNIQUE (ComercioId, IdempotencyKey),
  CONSTRAINT FK_pay_PeyAlta_Comercio FOREIGN KEY (ComercioId) REFERENCES biz.Comercios(ComercioId),
  CONSTRAINT CK_pay_PeyAlta_Estado CHECK (Estado IN (N'SOLICITANDO', N'REGISTRADA', N'INCIERTA'))
);
GO
CREATE UNIQUE INDEX UQ_pay_PeyAlta_Solicitando ON pay.PeyAltaCuentaIntentos(ComercioId)
WHERE Estado=N'SOLICITANDO';
CREATE UNIQUE INDEX UQ_pay_PeyAlta_Incierta ON pay.PeyAltaCuentaIntentos(ComercioId)
WHERE Estado=N'INCIERTA';
GO

ALTER TABLE pay.Pagos ADD
  CheckoutIdempotencyKey NVARCHAR(100) NULL,
  PeyBankAccountId NVARCHAR(40) NULL,
  PeyQrId NVARCHAR(100) NULL,
  PeyQrString NVARCHAR(MAX) NULL,
  PeyNumRef CHAR(7) NULL,
  PeyQrState NVARCHAR(20) NOT NULL CONSTRAINT DF_pay_Pagos_PeyQrState DEFAULT N'NO_APLICA',
  PeyTransactionId NVARCHAR(40) NULL,
  PeyDatePaidUtc DATETIME2(3) NULL,
  PeyReservaExpiraUtc DATETIME2(3) NULL;
GO
CREATE UNIQUE INDEX UQ_pay_Pagos_CheckoutKey ON pay.Pagos(CheckoutIdempotencyKey) WHERE CheckoutIdempotencyKey IS NOT NULL;
CREATE UNIQUE INDEX UQ_pay_Pagos_PeyTransaction ON pay.Pagos(PeyTransactionId) WHERE PeyTransactionId IS NOT NULL;
CREATE UNIQUE INDEX UQ_pay_Pagos_PeyQr ON pay.Pagos(PeyQrId) WHERE PeyQrId IS NOT NULL;
GO

CREATE TABLE pay.PeyWebhookInbox (
  WebhookId NVARCHAR(200) NOT NULL,
  EventType NVARCHAR(100) NOT NULL,
  PayloadHash VARBINARY(32) NOT NULL,
  Estado NVARCHAR(24) NOT NULL,
  RecibidoUtc DATETIME2(3) NOT NULL CONSTRAINT DF_pay_PeyInbox_Recibido DEFAULT SYSUTCDATETIME(),
  ProcesadoUtc DATETIME2(3) NULL,
  CONSTRAINT PK_pay_PeyWebhookInbox PRIMARY KEY (WebhookId),
  CONSTRAINT CK_pay_PeyWebhookInbox_Estado CHECK (Estado IN (N'RECIBIDO', N'PROCESADO', N'REQUIERE_REVISION', N'IGNORADO'))
);
GO

CREATE OR ALTER VIEW app.ProductosPublicos AS
SELECT p.ProductoId, p.ComercioId, p.Nombre, p.DescripcionCorta, p.Precio,
       p.Existencias, p.FotoUrl
FROM catalogo.Productos p
INNER JOIN biz.Comercios c ON c.ComercioId = p.ComercioId AND c.EstaActivo = 1
WHERE p.EstaActivo = 1;
GO

CREATE OR ALTER PROCEDURE app.sp_ObtenerCredencialLogin
  @Correo NVARCHAR(256)
AS
BEGIN
  SET NOCOUNT ON;
  SELECT u.UsuarioId, u.HashContrasena, u.SalContrasena,
         STRING_AGG(r.Nombre, N',') AS RolesCsv
  FROM ident.Usuarios u
  LEFT JOIN ident.UsuarioRoles ur ON ur.UsuarioId = u.UsuarioId
  LEFT JOIN lkp.Roles r ON r.RolId = ur.RolId
  WHERE u.Correo = @Correo AND u.EstaActivo = 1
  GROUP BY u.UsuarioId, u.HashContrasena, u.SalContrasena;
END;
GO

CREATE OR ALTER PROCEDURE app.sp_CrearComercioPropio
  @UsuarioId UNIQUEIDENTIFIER,
  @NombreNegocio NVARCHAR(150),
  @Descripcion NVARCHAR(500) = NULL,
  @ColoniaId INT = NULL,
  @ComercioId UNIQUEIDENTIFIER OUTPUT
AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  IF NOT EXISTS (SELECT 1 FROM ident.UsuarioRoles ur JOIN lkp.Roles r ON r.RolId=ur.RolId WHERE ur.UsuarioId=@UsuarioId AND r.Nombre=N'Comercio')
    THROW 50101, 'El usuario no tiene rol de comercio.', 1;
  IF EXISTS (SELECT 1 FROM biz.Comercios WHERE UsuarioPropietarioId=@UsuarioId)
    THROW 50102, 'El usuario ya tiene un comercio.', 1;
  SET @ComercioId=NEWID();
  INSERT biz.Comercios (ComercioId, UsuarioPropietarioId, NombreNegocio, Descripcion, ColoniaId)
  VALUES (@ComercioId, @UsuarioId, @NombreNegocio, @Descripcion, @ColoniaId);
END;
GO

CREATE OR ALTER PROCEDURE app.sp_GuardarProductoPropio
  @UsuarioId UNIQUEIDENTIFIER,
  @ComercioId UNIQUEIDENTIFIER,
  @Nombre NVARCHAR(150),
  @DescripcionCorta NVARCHAR(160)=NULL,
  @Precio DECIMAL(10,2),
  @Existencias INT,
  @ProductoId UNIQUEIDENTIFIER OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  IF NOT EXISTS(SELECT 1 FROM biz.Comercios WHERE ComercioId=@ComercioId AND UsuarioPropietarioId=@UsuarioId AND EstaActivo=1)
    THROW 50106, 'El comercio no pertenece al usuario.', 1;
  IF @Precio<=0 OR @Existencias<0 OR NULLIF(LTRIM(RTRIM(@Nombre)),N'') IS NULL
    THROW 50107, 'Los datos del producto son invalidos.', 1;
  SET @ProductoId=NEWID();
  INSERT catalogo.Productos(ProductoId,ComercioId,Nombre,DescripcionCorta,Precio,Existencias)
  VALUES(@ProductoId,@ComercioId,@Nombre,@DescripcionCorta,@Precio,@Existencias);
END;
GO

CREATE OR ALTER PROCEDURE app.sp_ObtenerComercioPropio
  @UsuarioId UNIQUEIDENTIFIER
AS
BEGIN
  SET NOCOUNT ON;
  SELECT TOP (1) ComercioId,NombreNegocio,Descripcion,EstaActivo
  FROM biz.Comercios WHERE UsuarioPropietarioId=@UsuarioId;
END;
GO

CREATE OR ALTER PROCEDURE app.sp_ObtenerCuentaPeyPropia
  @UsuarioId UNIQUEIDENTIFIER
AS
BEGIN
  SET NOCOUNT ON;
  SELECT c.PeyBankAccountId,c.ClabeUltimos4,c.CodiStatus,c.CreadoUtc,c.ActualizadoUtc
  FROM pay.CuentasPeyComercio c JOIN biz.Comercios b ON b.ComercioId=c.ComercioId
  WHERE b.UsuarioPropietarioId=@UsuarioId;
END;
GO

CREATE OR ALTER PROCEDURE app.sp_IniciarAltaCuentaPey
  @UsuarioId UNIQUEIDENTIFIER,
  @IdempotencyKey NVARCHAR(100),
  @ClabeUltimos4 CHAR(4)
AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  DECLARE @ComercioId UNIQUEIDENTIFIER;
  SELECT @ComercioId=ComercioId FROM biz.Comercios WHERE UsuarioPropietarioId=@UsuarioId AND EstaActivo=1;
  IF @ComercioId IS NULL THROW 50103, 'No existe un comercio activo para este usuario.', 1;
  BEGIN TRANSACTION;
    DECLARE @Estado NVARCHAR(20);
    SELECT @Estado=Estado FROM pay.PeyAltaCuentaIntentos WITH (UPDLOCK,HOLDLOCK)
    WHERE ComercioId=@ComercioId AND IdempotencyKey=@IdempotencyKey;
    IF @Estado IS NOT NULL AND EXISTS(SELECT 1 FROM pay.PeyAltaCuentaIntentos WHERE ComercioId=@ComercioId AND IdempotencyKey=@IdempotencyKey AND ClabeUltimos4<>@ClabeUltimos4)
      THROW 50108, 'La clave de idempotencia ya se uso con otra cuenta.', 1;
    IF @Estado IS NULL
    BEGIN
      IF EXISTS (SELECT 1 FROM pay.CuentasPeyComercio WHERE ComercioId=@ComercioId)
        THROW 50104, 'El comercio ya tiene una cuenta Pey asociada.', 1;
      INSERT pay.PeyAltaCuentaIntentos (ComercioId,IdempotencyKey,ClabeUltimos4,Estado)
      VALUES (@ComercioId,@IdempotencyKey,@ClabeUltimos4,N'SOLICITANDO');
      SELECT CAST(1 AS BIT) AS DebeRegistrar, @ComercioId AS ComercioId, N'SOLICITANDO' AS Estado;
    END
    ELSE
      SELECT CAST(0 AS BIT) AS DebeRegistrar,@ComercioId AS ComercioId,@Estado AS Estado,
             c.PeyBankAccountId,c.CodiStatus,c.ClabeUltimos4
      FROM pay.PeyAltaCuentaIntentos i
      LEFT JOIN pay.CuentasPeyComercio c ON c.ComercioId=i.ComercioId
      WHERE i.ComercioId=@ComercioId AND i.IdempotencyKey=@IdempotencyKey;
  COMMIT;
END;
GO

CREATE OR ALTER PROCEDURE app.sp_GuardarCuentaPeyComercio
  @UsuarioId UNIQUEIDENTIFIER,
  @ComercioId UNIQUEIDENTIFIER,
  @IdempotencyKey NVARCHAR(100),
  @PeyBankAccountId NVARCHAR(40),
  @ClabeUltimos4 CHAR(4),
  @CodiStatus NVARCHAR(20)
AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  IF NOT EXISTS (SELECT 1 FROM biz.Comercios WHERE ComercioId=@ComercioId AND UsuarioPropietarioId=@UsuarioId AND EstaActivo=1)
    THROW 50105, 'El comercio no pertenece al usuario.', 1;
  BEGIN TRANSACTION;
    IF EXISTS (SELECT 1 FROM pay.CuentasPeyComercio WHERE ComercioId=@ComercioId AND PeyBankAccountId<>@PeyBankAccountId)
      THROW 50109, 'El comercio ya tiene otra cuenta Pey asociada.', 1;
    IF EXISTS (SELECT 1 FROM pay.CuentasPeyComercio WHERE ComercioId=@ComercioId)
      UPDATE pay.CuentasPeyComercio SET CodiStatus=@CodiStatus,ActualizadoUtc=SYSUTCDATETIME()
      WHERE ComercioId=@ComercioId AND PeyBankAccountId=@PeyBankAccountId;
    ELSE
      INSERT pay.CuentasPeyComercio (ComercioId,PeyBankAccountId,ClabeUltimos4,CodiStatus)
      VALUES (@ComercioId,@PeyBankAccountId,@ClabeUltimos4,@CodiStatus);
    UPDATE pay.PeyAltaCuentaIntentos SET Estado=N'REGISTRADA'
    WHERE ComercioId=@ComercioId AND IdempotencyKey=@IdempotencyKey;
  COMMIT;
  SELECT @PeyBankAccountId AS PeyBankAccountId,@CodiStatus AS CodiStatus;
END;
GO

CREATE OR ALTER PROCEDURE app.sp_MarcarAltaCuentaPeyIncierta
  @ComercioId UNIQUEIDENTIFIER,
  @IdempotencyKey NVARCHAR(100)
AS
BEGIN
  SET NOCOUNT ON;
  UPDATE pay.PeyAltaCuentaIntentos SET Estado=N'INCIERTA'
  WHERE ComercioId=@ComercioId AND IdempotencyKey=@IdempotencyKey AND Estado=N'SOLICITANDO';
END;
GO

CREATE OR ALTER PROCEDURE app.sp_ActualizarEstadoCuentaPey
  @UsuarioId UNIQUEIDENTIFIER,
  @PeyBankAccountId NVARCHAR(40),
  @CodiStatus NVARCHAR(20)
AS
BEGIN
  SET NOCOUNT ON;
  IF @CodiStatus NOT IN (N'PENDING',N'PROCESSING',N'ACTIVE',N'ERROR') THROW 50120, 'Estado de cuenta Pey invalido.', 1;
  UPDATE c SET CodiStatus=@CodiStatus,ActualizadoUtc=SYSUTCDATETIME()
  FROM pay.CuentasPeyComercio c JOIN biz.Comercios b ON b.ComercioId=c.ComercioId
  WHERE b.UsuarioPropietarioId=@UsuarioId AND c.PeyBankAccountId=@PeyBankAccountId
    AND @CodiStatus IN (N'PENDING',N'PROCESSING',N'ACTIVE',N'ERROR');
  IF @@ROWCOUNT<>1 THROW 50121, 'Cuenta Pey no encontrada para este usuario.', 1;
  SELECT CodiStatus FROM pay.CuentasPeyComercio WHERE PeyBankAccountId=@PeyBankAccountId;
END;
GO

CREATE OR ALTER PROCEDURE app.sp_CrearPedidoPey
  @UsuarioId UNIQUEIDENTIFIER,
  @ComercioId UNIQUEIDENTIFIER,
  @ItemsJson NVARCHAR(MAX),
  @MetodoEntrega NVARCHAR(20),
  @DireccionEntrega NVARCHAR(300)=NULL,
  @IdempotencyKey NVARCHAR(100),
  @ModoSimulado BIT=0
AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  IF ISJSON(@ItemsJson)<>1 OR @MetodoEntrega NOT IN (N'RECOGER',N'ENTREGA_LOCAL')
    THROW 50110, 'Checkout invalido.', 1;
  IF @MetodoEntrega=N'ENTREGA_LOCAL' AND NULLIF(LTRIM(RTRIM(@DireccionEntrega)),N'') IS NULL
    THROW 50122, 'La direccion es requerida para entrega local.', 1;
  DECLARE @PagoId UNIQUEIDENTIFIER,@PedidoId UNIQUEIDENTIFIER,@Total DECIMAL(10,2),@PeyBankAccountId NVARCHAR(40),@CodiStatus NVARCHAR(20),@NumRef CHAR(7);
  EXEC sys.sp_set_session_context @key=N'UsuarioId',@value=@UsuarioId;
  BEGIN TRY
  BEGIN TRANSACTION;
  SELECT @PagoId=p.PagoId,@PedidoId=p.PedidoId,@Total=p.Monto,@PeyBankAccountId=p.PeyBankAccountId,
         @NumRef=p.PeyNumRef,@CodiStatus=c.CodiStatus
  FROM pay.Pagos p WITH (UPDLOCK,HOLDLOCK)
  JOIN ord.Pedidos o ON o.PedidoId=p.PedidoId
  LEFT JOIN pay.CuentasPeyComercio c ON c.PeyBankAccountId=p.PeyBankAccountId
  WHERE p.CheckoutIdempotencyKey=@IdempotencyKey AND o.UsuarioId=@UsuarioId AND o.ComercioId=@ComercioId;
  IF @PagoId IS NOT NULL
  BEGIN
    SELECT p.PedidoId,p.PagoId,p.Monto AS Total,o.NumeroPedido,p.PeyBankAccountId,c.CodiStatus,p.PeyNumRef AS PagoReferencia,p.PeyQrString AS QrString,p.PeyQrState
    FROM pay.Pagos p JOIN ord.Pedidos o ON o.PedidoId=p.PedidoId LEFT JOIN pay.CuentasPeyComercio c ON c.PeyBankAccountId=p.PeyBankAccountId WHERE p.PagoId=@PagoId;
    COMMIT;
    EXEC sys.sp_set_session_context @key=N'UsuarioId',@value=NULL;
    RETURN;
  END;
  IF EXISTS (SELECT 1 FROM pay.Pagos p JOIN ord.Pedidos o ON o.PedidoId=p.PedidoId WHERE o.UsuarioId=@UsuarioId AND o.ComercioId=@ComercioId AND p.CheckoutIdempotencyKey=@IdempotencyKey)
    THROW 50111, 'Idempotency key conflict.', 1;
  SELECT @PeyBankAccountId=c.PeyBankAccountId,@CodiStatus=c.CodiStatus
  FROM biz.Comercios b JOIN pay.CuentasPeyComercio c ON c.ComercioId=b.ComercioId
  WHERE b.ComercioId=@ComercioId AND b.EstaActivo=1;
  IF @ModoSimulado=0 AND (@PeyBankAccountId IS NULL OR @CodiStatus<>N'ACTIVE')
    THROW 50119, 'La cuenta bancaria del comercio no esta activa para CoDi.', 1;
  DECLARE @Items TABLE (ProductoId UNIQUEIDENTIFIER PRIMARY KEY,Cantidad INT NOT NULL);
  INSERT @Items (ProductoId,Cantidad)
  SELECT TRY_CONVERT(UNIQUEIDENTIFIER,JSON_VALUE(value,'$.productId')),
         SUM(TRY_CONVERT(INT,JSON_VALUE(value,'$.quantity')))
  FROM OPENJSON(@ItemsJson) GROUP BY TRY_CONVERT(UNIQUEIDENTIFIER,JSON_VALUE(value,'$.productId'));
  IF NOT EXISTS (SELECT 1 FROM @Items) OR EXISTS(SELECT 1 FROM @Items WHERE ProductoId IS NULL OR Cantidad NOT BETWEEN 1 AND 100)
    THROW 50113, 'Los articulos del checkout son invalidos.', 1;
  IF EXISTS (
    SELECT 1 FROM @Items i LEFT JOIN catalogo.Productos p WITH (UPDLOCK,HOLDLOCK)
      ON p.ProductoId=i.ProductoId AND p.ComercioId=@ComercioId AND p.EstaActivo=1
    WHERE p.ProductoId IS NULL OR p.Existencias<i.Cantidad OR p.Precio<=0
  ) THROW 50114, 'Producto no disponible o sin existencias.', 1;
  SELECT @Total=SUM(CONVERT(DECIMAL(10,2),p.Precio*i.Cantidad))
  FROM @Items i JOIN catalogo.Productos p ON p.ProductoId=i.ProductoId AND p.ComercioId=@ComercioId;
  IF @Total IS NULL OR @Total<=0 THROW 50115, 'El monto del pedido es invalido.', 1;
  DECLARE @EstadoPedido TINYINT=(SELECT EstadoId FROM lkp.EstadosPedido WHERE Codigo=N'NUEVO');
  DECLARE @MetodoPago TINYINT=(SELECT MetodoPagoId FROM lkp.MetodosPago WHERE Codigo=N'PEY_CODI');
  DECLARE @EstadoPago TINYINT=(SELECT EstadoPagoId FROM lkp.EstadosPago WHERE Codigo=N'PENDIENTE');
  SET @PedidoId=NEWID(); SET @PagoId=NEWID(); SET @NumRef=RIGHT('0000000'+CONVERT(VARCHAR(7),NEXT VALUE FOR pay.SecuenciaReferenciaPey),7);
  INSERT ord.Pedidos (PedidoId,UsuarioId,ComercioId,EstadoId,MetodoEntrega,DireccionEntrega,Subtotal,CostoEnvio,Total)
  VALUES (@PedidoId,@UsuarioId,@ComercioId,@EstadoPedido,@MetodoEntrega,@DireccionEntrega,@Total,0,@Total);
  INSERT ord.PedidoItems (PedidoId,ProductoId,NombreProductoSnapshot,Cantidad,PrecioUnitario)
  SELECT @PedidoId,p.ProductoId,p.Nombre,i.Cantidad,p.Precio FROM @Items i JOIN catalogo.Productos p ON p.ProductoId=i.ProductoId;
  UPDATE p SET Existencias=p.Existencias-i.Cantidad,ActualizadoUtc=SYSUTCDATETIME()
  FROM catalogo.Productos p JOIN @Items i ON i.ProductoId=p.ProductoId;
  INSERT ord.PedidoEstadoHistorial (PedidoId,EstadoId,CambiadoPorUsuarioId,Comentario)
  VALUES (@PedidoId,@EstadoPedido,@UsuarioId,N'Pedido creado para pago CoDi');
  INSERT pay.Pagos (PagoId,PedidoId,MetodoPagoId,EstadoPagoId,Monto,Moneda,CheckoutIdempotencyKey,PeyBankAccountId,PeyNumRef,PeyQrState,PeyReservaExpiraUtc)
  VALUES (@PagoId,@PedidoId,@MetodoPago,@EstadoPago,@Total,'MXN',@IdempotencyKey,@PeyBankAccountId,@NumRef,CASE WHEN @ModoSimulado=1 THEN N'SIMULADO' ELSE N'NUEVO' END,DATEADD(MINUTE,20,SYSUTCDATETIME()));
  COMMIT;
  SELECT @PedidoId AS PedidoId,@PagoId AS PagoId,@Total AS Total,@NumRef AS PagoReferencia,@PeyBankAccountId AS PeyBankAccountId,@CodiStatus AS CodiStatus,
         (SELECT NumeroPedido FROM ord.Pedidos WHERE PedidoId=@PedidoId) AS NumeroPedido,CAST(NULL AS NVARCHAR(MAX)) AS QrString,N'NUEVO' AS PeyQrState;
  EXEC sys.sp_set_session_context @key=N'UsuarioId',@value=NULL;
  END TRY
  BEGIN CATCH
    IF @@TRANCOUNT>0 ROLLBACK;
    EXEC sys.sp_set_session_context @key=N'UsuarioId',@value=NULL;
    THROW;
  END CATCH
END;
GO

CREATE OR ALTER PROCEDURE app.sp_AdjuntarQrPey
  @PagoId UNIQUEIDENTIFIER,
  @UsuarioId UNIQUEIDENTIFIER,
  @PeyBankAccountId NVARCHAR(40),
  @DebeCrearQr BIT OUTPUT
AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  BEGIN TRANSACTION;
  DECLARE @State NVARCHAR(20),@Qr NVARCHAR(MAX);
  SELECT @State=p.PeyQrState,@Qr=p.PeyQrString
  FROM pay.Pagos p JOIN ord.Pedidos o ON o.PedidoId=p.PedidoId
  WHERE p.PagoId=@PagoId AND p.PeyBankAccountId=@PeyBankAccountId AND o.UsuarioId=@UsuarioId;
  IF @State IS NULL THROW 50116, 'Pago no encontrado.', 1;
  SET @DebeCrearQr=0;
  IF @State=N'NUEVO'
  BEGIN
    UPDATE pay.Pagos SET PeyQrState=N'SOLICITANDO' WHERE PagoId=@PagoId;
    SET @DebeCrearQr=1;
  END;
  SELECT @DebeCrearQr AS DebeCrearQr,@Qr AS QrString,@State AS PeyQrState;
  COMMIT;
END;
GO

CREATE OR ALTER PROCEDURE app.sp_GuardarQrPey
  @PagoId UNIQUEIDENTIFIER,
  @PeyQrId NVARCHAR(100),
  @QrString NVARCHAR(MAX)
AS
BEGIN
  SET NOCOUNT ON;
  UPDATE pay.Pagos SET PeyQrId=@PeyQrId,PeyQrString=@QrString,PeyQrState=N'LISTO',ProveedorReferencia=@PeyQrId,ActualizadoUtc=SYSUTCDATETIME()
  WHERE PagoId=@PagoId AND PeyQrState=N'SOLICITANDO';
  IF @@ROWCOUNT<>1 THROW 50117, 'No se pudo asociar el QR.', 1;
END;
GO

CREATE OR ALTER PROCEDURE app.sp_MarcarCreacionQrIncierta @PagoId UNIQUEIDENTIFIER
AS
BEGIN
  SET NOCOUNT ON;
  UPDATE pay.Pagos SET PeyQrState=N'INCIERTO',ActualizadoUtc=SYSUTCDATETIME()
  WHERE PagoId=@PagoId AND PeyQrState=N'SOLICITANDO';
END;
GO

CREATE OR ALTER PROCEDURE app.sp_ProcesarWebhookPey
  @WebhookId NVARCHAR(200),
  @EventType NVARCHAR(100),
  @PayloadJson NVARCHAR(MAX)
AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  IF ISJSON(@PayloadJson)<>1 THROW 50118, 'Webhook JSON invalido.', 1;
  DECLARE @Hash VARBINARY(32)=HASHBYTES('SHA2_256',CONVERT(VARBINARY(MAX),@PayloadJson));
  BEGIN TRANSACTION;
  IF EXISTS(SELECT 1 FROM pay.PeyWebhookInbox WITH (UPDLOCK,HOLDLOCK) WHERE WebhookId=@WebhookId)
  BEGIN
    IF EXISTS(SELECT 1 FROM pay.PeyWebhookInbox WHERE WebhookId=@WebhookId AND PayloadHash<>@Hash)
      UPDATE pay.PeyWebhookInbox SET Estado=N'REQUIERE_REVISION',ProcesadoUtc=SYSUTCDATETIME() WHERE WebhookId=@WebhookId;
    COMMIT; RETURN;
  END;
  INSERT pay.PeyWebhookInbox (WebhookId,EventType,PayloadHash,Estado) VALUES (@WebhookId,@EventType,@Hash,N'RECIBIDO');
  IF @EventType=N'bank.account.updated'
  BEGIN
    UPDATE pay.CuentasPeyComercio SET CodiStatus=UPPER(JSON_VALUE(@PayloadJson,'$.codiStatus')),ActualizadoUtc=SYSUTCDATETIME()
    WHERE PeyBankAccountId=JSON_VALUE(@PayloadJson,'$.bankAccountId');
    UPDATE pay.PeyWebhookInbox SET Estado=CASE WHEN @@ROWCOUNT=1 THEN N'PROCESADO' ELSE N'REQUIERE_REVISION' END,ProcesadoUtc=SYSUTCDATETIME() WHERE WebhookId=@WebhookId;
  END
  ELSE IF @EventType IN (N'codi.qr.payment_received',N'codi.pn.payment_received')
  BEGIN
    DECLARE @QrId NVARCHAR(100)=JSON_VALUE(@PayloadJson,'$.codiQrId');
    DECLARE @TxId NVARCHAR(40)=JSON_VALUE(@PayloadJson,'$.transactionId');
    DECLARE @Amount DECIMAL(10,2)=TRY_CONVERT(DECIMAL(10,2),JSON_VALUE(@PayloadJson,'$.amount'));
    DECLARE @BankId NVARCHAR(40)=JSON_VALUE(@PayloadJson,'$.bankAccountId');
    DECLARE @PagoId UNIQUEIDENTIFIER,@Expected DECIMAL(10,2),@ExpectedBank NVARCHAR(40);
    SELECT @PagoId=PagoId,@Expected=Monto,@ExpectedBank=PeyBankAccountId FROM pay.Pagos WITH (UPDLOCK,HOLDLOCK) WHERE PeyQrId=@QrId;
    DECLARE @PagoConTransaccion UNIQUEIDENTIFIER;
    SELECT @PagoConTransaccion=PagoId FROM pay.Pagos WHERE PeyTransactionId=@TxId;
    IF @PagoId IS NOT NULL AND @PagoConTransaccion=@PagoId
      UPDATE pay.PeyWebhookInbox SET Estado=N'PROCESADO',ProcesadoUtc=SYSUTCDATETIME() WHERE WebhookId=@WebhookId;
    ELSE IF @PagoId IS NOT NULL AND @Amount=@Expected AND @ExpectedBank=@BankId AND @TxId IS NOT NULL
    BEGIN
      UPDATE pay.Pagos SET EstadoPagoId=(SELECT EstadoPagoId FROM lkp.EstadosPago WHERE Codigo=N'CONFIRMADO'),PeyTransactionId=@TxId,PeyDatePaidUtc=DATEADD(SECOND,TRY_CONVERT(BIGINT,JSON_VALUE(@PayloadJson,'$.datePaid')),'1970-01-01'),ActualizadoUtc=SYSUTCDATETIME()
      WHERE PagoId=@PagoId AND PeyTransactionId IS NULL AND EstadoPagoId=(SELECT EstadoPagoId FROM lkp.EstadosPago WHERE Codigo=N'PENDIENTE');
      UPDATE pay.PeyWebhookInbox SET Estado=CASE WHEN @@ROWCOUNT=1 THEN N'PROCESADO' ELSE N'REQUIERE_REVISION' END,ProcesadoUtc=SYSUTCDATETIME() WHERE WebhookId=@WebhookId;
    END
    ELSE UPDATE pay.PeyWebhookInbox SET Estado=N'REQUIERE_REVISION',ProcesadoUtc=SYSUTCDATETIME() WHERE WebhookId=@WebhookId;
  END
  ELSE UPDATE pay.PeyWebhookInbox SET Estado=N'IGNORADO',ProcesadoUtc=SYSUTCDATETIME() WHERE WebhookId=@WebhookId;
  COMMIT;
END;
GO

CREATE OR ALTER PROCEDURE app.sp_LiberarReservasPeyVencidas
AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  DECLARE @Vencidos TABLE (PagoId UNIQUEIDENTIFIER,PedidoId UNIQUEIDENTIFIER);
  BEGIN TRANSACTION;
  UPDATE pay.Pagos
    SET EstadoPagoId=(SELECT EstadoPagoId FROM lkp.EstadosPago WHERE Codigo=N'RECHAZADO'),
        PeyReservaExpiraUtc=NULL,ActualizadoUtc=SYSUTCDATETIME()
    OUTPUT inserted.PagoId,inserted.PedidoId INTO @Vencidos
  WHERE PeyReservaExpiraUtc<=SYSUTCDATETIME()
    AND EstadoPagoId=(SELECT EstadoPagoId FROM lkp.EstadosPago WHERE Codigo=N'PENDIENTE')
    AND PeyTransactionId IS NULL;
  UPDATE pr SET Existencias=pr.Existencias+items.Cantidad,ActualizadoUtc=SYSUTCDATETIME()
  FROM catalogo.Productos pr
  JOIN (SELECT pi.ProductoId,SUM(pi.Cantidad) AS Cantidad FROM ord.PedidoItems pi JOIN @Vencidos v ON v.PedidoId=pi.PedidoId GROUP BY pi.ProductoId) items
    ON items.ProductoId=pr.ProductoId;
  UPDATE o SET EstadoId=(SELECT EstadoId FROM lkp.EstadosPedido WHERE Codigo=N'CANCELADO'),ActualizadoUtc=SYSUTCDATETIME()
  FROM ord.Pedidos o JOIN @Vencidos v ON v.PedidoId=o.PedidoId;
  INSERT ord.PedidoEstadoHistorial(PedidoId,EstadoId,Comentario)
  SELECT v.PedidoId,(SELECT EstadoId FROM lkp.EstadosPedido WHERE Codigo=N'CANCELADO'),N'Reserva de pago vencida; inventario liberado' FROM @Vencidos v;
  COMMIT;
  SELECT COUNT(*) AS ReservasLiberadas FROM @Vencidos;
END;
GO

CREATE OR ALTER PROCEDURE app.sp_ObtenerPedidoPropio
  @UsuarioId UNIQUEIDENTIFIER,
  @PedidoId UNIQUEIDENTIFIER
AS
BEGIN
  SET NOCOUNT ON;
  EXEC sys.sp_set_session_context @key=N'UsuarioId',@value=@UsuarioId;
  BEGIN TRY
  SELECT o.PedidoId,o.NumeroPedido,e.Codigo AS EstadoPedido,p.Monto,p.EstadoPagoId,ep.Codigo AS EstadoPago,p.PeyQrString,p.PeyQrState,o.CreadoUtc
  FROM ord.Pedidos o JOIN lkp.EstadosPedido e ON e.EstadoId=o.EstadoId
  LEFT JOIN pay.Pagos p ON p.PedidoId=o.PedidoId LEFT JOIN lkp.EstadosPago ep ON ep.EstadoPagoId=p.EstadoPagoId
  WHERE o.PedidoId=@PedidoId AND (o.UsuarioId=@UsuarioId OR EXISTS(SELECT 1 FROM biz.Comercios c WHERE c.ComercioId=o.ComercioId AND c.UsuarioPropietarioId=@UsuarioId));
  EXEC sys.sp_set_session_context @key=N'UsuarioId',@value=NULL;
  END TRY
  BEGIN CATCH
    EXEC sys.sp_set_session_context @key=N'UsuarioId',@value=NULL;
    THROW;
  END CATCH
END;
GO

CREATE OR ALTER PROCEDURE app.sp_ListarPedidosPropios
  @UsuarioId UNIQUEIDENTIFIER
AS
BEGIN
  SET NOCOUNT ON;
  EXEC sys.sp_set_session_context @key=N'UsuarioId',@value=@UsuarioId;
  BEGIN TRY
    SELECT TOP (100) o.PedidoId,o.NumeroPedido,e.Codigo AS EstadoPedido,p.Monto,ep.Codigo AS EstadoPago,o.CreadoUtc,
           c.NombreNegocio AS Comercio
    FROM ord.Pedidos o
    JOIN lkp.EstadosPedido e ON e.EstadoId=o.EstadoId
    JOIN biz.Comercios c ON c.ComercioId=o.ComercioId
    LEFT JOIN pay.Pagos p ON p.PedidoId=o.PedidoId
    LEFT JOIN lkp.EstadosPago ep ON ep.EstadoPagoId=p.EstadoPagoId
    WHERE o.UsuarioId=@UsuarioId OR c.UsuarioPropietarioId=@UsuarioId
    ORDER BY o.CreadoUtc DESC;
    EXEC sys.sp_set_session_context @key=N'UsuarioId',@value=NULL;
  END TRY
  BEGIN CATCH
    EXEC sys.sp_set_session_context @key=N'UsuarioId',@value=NULL;
    THROW;
  END CATCH
END;
GO

GRANT SELECT ON app.ProductosPublicos TO role_app_api;
GRANT EXECUTE ON OBJECT::app.sp_ObtenerCredencialLogin TO role_app_api;
GRANT EXECUTE ON OBJECT::app.sp_CrearComercioPropio TO role_app_api;
GRANT EXECUTE ON OBJECT::app.sp_GuardarProductoPropio TO role_app_api;
GRANT EXECUTE ON OBJECT::app.sp_ObtenerComercioPropio TO role_app_api;
GRANT EXECUTE ON OBJECT::app.sp_ObtenerCuentaPeyPropia TO role_app_api;
GRANT EXECUTE ON OBJECT::app.sp_IniciarAltaCuentaPey TO role_app_api;
GRANT EXECUTE ON OBJECT::app.sp_GuardarCuentaPeyComercio TO role_app_api;
GRANT EXECUTE ON OBJECT::app.sp_MarcarAltaCuentaPeyIncierta TO role_app_api;
GRANT EXECUTE ON OBJECT::app.sp_ActualizarEstadoCuentaPey TO role_app_api;
GRANT EXECUTE ON OBJECT::app.sp_CrearPedidoPey TO role_app_api;
GRANT EXECUTE ON OBJECT::app.sp_AdjuntarQrPey TO role_app_api;
GRANT EXECUTE ON OBJECT::app.sp_GuardarQrPey TO role_app_api;
GRANT EXECUTE ON OBJECT::app.sp_MarcarCreacionQrIncierta TO role_app_api;
GRANT EXECUTE ON OBJECT::app.sp_ProcesarWebhookPey TO role_app_api;
GRANT EXECUTE ON OBJECT::app.sp_ObtenerPedidoPropio TO role_app_api;
GRANT EXECUTE ON OBJECT::app.sp_ListarPedidosPropios TO role_app_api;
GRANT EXECUTE ON OBJECT::app.sp_LiberarReservasPeyVencidas TO role_app_api;
GO
