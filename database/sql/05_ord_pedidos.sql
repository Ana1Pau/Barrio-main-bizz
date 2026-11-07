/* ============================================================================
   05_ord_pedidos.sql
   Carrito de compras y pedidos. Pedidos usa TABLA TEMPORAL (system-versioned)
   para conservar el historial completo de cambios (auditoria automatica),
   soportado tanto en SQL Server 2025 como en Azure SQL Database.
============================================================================ */

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE TABLE ord.Carritos (
    CarritoId   UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_ord_Carritos_Id DEFAULT NEWSEQUENTIALID(),
    UsuarioId   UNIQUEIDENTIFIER NOT NULL,
    ComercioId  UNIQUEIDENTIFIER NOT NULL,
    CreadoUtc   DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
    ActualizadoUtc DATETIME2(3)  NULL,
    CONSTRAINT PK_ord_Carritos PRIMARY KEY CLUSTERED (CarritoId),
    CONSTRAINT FK_ord_Carritos_Usuario FOREIGN KEY (UsuarioId) REFERENCES ident.Usuarios(UsuarioId) ON DELETE CASCADE,
    CONSTRAINT FK_ord_Carritos_Comercio FOREIGN KEY (ComercioId) REFERENCES biz.Comercios(ComercioId),
    CONSTRAINT UQ_ord_Carritos_UsuarioComercio UNIQUE (UsuarioId, ComercioId)
);
GO

CREATE TABLE ord.CarritoItems (
    CarritoItemId   BIGINT IDENTITY(1,1) NOT NULL,
    CarritoId       UNIQUEIDENTIFIER     NOT NULL,
    ProductoId      UNIQUEIDENTIFIER     NOT NULL,
    Cantidad        INT                  NOT NULL,
    PrecioUnitarioSnapshot DECIMAL(10,2) NOT NULL,
    CONSTRAINT PK_ord_CarritoItems PRIMARY KEY CLUSTERED (CarritoItemId),
    CONSTRAINT FK_ord_CarritoItems_Carrito FOREIGN KEY (CarritoId) REFERENCES ord.Carritos(CarritoId) ON DELETE CASCADE,
    CONSTRAINT FK_ord_CarritoItems_Producto FOREIGN KEY (ProductoId) REFERENCES catalogo.Productos(ProductoId),
    CONSTRAINT CK_ord_CarritoItems_Cantidad CHECK (Cantidad > 0),
    CONSTRAINT UQ_ord_CarritoItems_CarritoProducto UNIQUE (CarritoId, ProductoId)
);
GO

CREATE SEQUENCE ord.SecuenciaNumeroPedido AS INT START WITH 1000 INCREMENT BY 1;
GO

CREATE TABLE ord.Pedidos (
    PedidoId        UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_ord_Pedidos_Id DEFAULT NEWSEQUENTIALID(),
    NumeroPedido    AS ('BR-' + RIGHT('0000' + CAST(NumeroSecuencial AS VARCHAR(10)), 4)) PERSISTED,
    NumeroSecuencial INT             NOT NULL CONSTRAINT DF_ord_Pedidos_NumSec DEFAULT (NEXT VALUE FOR ord.SecuenciaNumeroPedido),
    UsuarioId       UNIQUEIDENTIFIER NOT NULL,
    ComercioId      UNIQUEIDENTIFIER NOT NULL,
    EstadoId        TINYINT          NOT NULL,
    MetodoEntrega   NVARCHAR(20)     NOT NULL,
    DireccionEntrega NVARCHAR(300)   NULL,
    Subtotal        DECIMAL(10,2)    NOT NULL,
    CostoEnvio      DECIMAL(10,2)    NOT NULL DEFAULT 0,
    Total           DECIMAL(10,2)    NOT NULL,
    NotaCliente     NVARCHAR(300)    NULL,
    CreadoUtc       DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
    ActualizadoUtc  DATETIME2(3)     NULL,
    SysStartTime    DATETIME2(3) GENERATED ALWAYS AS ROW START NOT NULL,
    SysEndTime      DATETIME2(3) GENERATED ALWAYS AS ROW END NOT NULL,
    PERIOD FOR SYSTEM_TIME (SysStartTime, SysEndTime),
    CONSTRAINT PK_ord_Pedidos PRIMARY KEY CLUSTERED (PedidoId),
    CONSTRAINT UQ_ord_Pedidos_NumeroSecuencial UNIQUE (NumeroSecuencial),
    CONSTRAINT FK_ord_Pedidos_Usuario FOREIGN KEY (UsuarioId) REFERENCES ident.Usuarios(UsuarioId),
    CONSTRAINT FK_ord_Pedidos_Comercio FOREIGN KEY (ComercioId) REFERENCES biz.Comercios(ComercioId),
    CONSTRAINT FK_ord_Pedidos_Estado FOREIGN KEY (EstadoId) REFERENCES lkp.EstadosPedido(EstadoId),
    CONSTRAINT CK_ord_Pedidos_MetodoEntrega CHECK (MetodoEntrega IN (N'RECOGER', N'ENTREGA_LOCAL'))
)
WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = ord.PedidosHistorial));
GO
CREATE INDEX IX_ord_Pedidos_Usuario ON ord.Pedidos(UsuarioId, CreadoUtc DESC);
CREATE INDEX IX_ord_Pedidos_Comercio ON ord.Pedidos(ComercioId, EstadoId, CreadoUtc DESC);
GO

CREATE TABLE ord.PedidoItems (
    PedidoItemId    BIGINT IDENTITY(1,1) NOT NULL,
    PedidoId        UNIQUEIDENTIFIER     NOT NULL,
    ProductoId      UNIQUEIDENTIFIER     NOT NULL,
    NombreProductoSnapshot NVARCHAR(150) NOT NULL,
    Cantidad        INT                  NOT NULL,
    PrecioUnitario  DECIMAL(10,2)        NOT NULL,
    Importe         AS (Cantidad * PrecioUnitario) PERSISTED,
    CONSTRAINT PK_ord_PedidoItems PRIMARY KEY CLUSTERED (PedidoItemId),
    CONSTRAINT FK_ord_PedidoItems_Pedido FOREIGN KEY (PedidoId) REFERENCES ord.Pedidos(PedidoId) ON DELETE CASCADE,
    CONSTRAINT FK_ord_PedidoItems_Producto FOREIGN KEY (ProductoId) REFERENCES catalogo.Productos(ProductoId),
    CONSTRAINT CK_ord_PedidoItems_Cantidad CHECK (Cantidad > 0)
);
GO
CREATE INDEX IX_ord_PedidoItems_Pedido ON ord.PedidoItems(PedidoId);
GO

CREATE TABLE ord.PedidoEstadoHistorial (
    HistorialId     BIGINT IDENTITY(1,1) NOT NULL,
    PedidoId        UNIQUEIDENTIFIER     NOT NULL,
    EstadoId        TINYINT              NOT NULL,
    CambiadoPorUsuarioId UNIQUEIDENTIFIER NULL,
    Comentario      NVARCHAR(200)        NULL,
    CambiadoUtc     DATETIME2(3)         NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_ord_PedidoEstadoHistorial PRIMARY KEY CLUSTERED (HistorialId),
    CONSTRAINT FK_ord_PedidoEstadoHistorial_Pedido FOREIGN KEY (PedidoId) REFERENCES ord.Pedidos(PedidoId) ON DELETE CASCADE,
    CONSTRAINT FK_ord_PedidoEstadoHistorial_Estado FOREIGN KEY (EstadoId) REFERENCES lkp.EstadosPedido(EstadoId)
);
GO
CREATE INDEX IX_ord_PedidoEstadoHistorial_Pedido ON ord.PedidoEstadoHistorial(PedidoId);
GO
