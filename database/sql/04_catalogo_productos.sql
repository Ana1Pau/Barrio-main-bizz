/* ============================================================================
   04_catalogo_productos.sql
   Catalogo de productos publicados por cada comercio.
============================================================================ */

CREATE TABLE catalogo.Productos (
    ProductoId          UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_catalogo_Productos_Id DEFAULT NEWSEQUENTIALID(),
    ComercioId          UNIQUEIDENTIFIER NOT NULL,
    CategoriaId         INT              NULL,
    Nombre              NVARCHAR(150)    NOT NULL,
    DescripcionCorta    NVARCHAR(160)    NULL,
    Precio              DECIMAL(10,2)    NOT NULL,
    Existencias         INT              NOT NULL DEFAULT 0,
    EstaActivo          BIT              NOT NULL DEFAULT 1,
    FotoUrl             NVARCHAR(400)    NULL,
    CreadoUtc           DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
    ActualizadoUtc      DATETIME2(3)     NULL,
    CONSTRAINT PK_catalogo_Productos PRIMARY KEY CLUSTERED (ProductoId),
    CONSTRAINT FK_catalogo_Productos_Comercio FOREIGN KEY (ComercioId) REFERENCES biz.Comercios(ComercioId) ON DELETE CASCADE,
    CONSTRAINT FK_catalogo_Productos_Categoria FOREIGN KEY (CategoriaId) REFERENCES lkp.Categorias(CategoriaId),
    CONSTRAINT CK_catalogo_Productos_Precio CHECK (Precio >= 0),
    CONSTRAINT CK_catalogo_Productos_Existencias CHECK (Existencias >= 0)
);
GO
CREATE INDEX IX_catalogo_Productos_Comercio ON catalogo.Productos(ComercioId, EstaActivo);
CREATE INDEX IX_catalogo_Productos_Categoria ON catalogo.Productos(CategoriaId);
GO

CREATE TABLE catalogo.ProductoImagenes (
    ImagenId    INT IDENTITY(1,1) NOT NULL,
    ProductoId  UNIQUEIDENTIFIER  NOT NULL,
    Url         NVARCHAR(400)     NOT NULL,
    Orden       TINYINT           NOT NULL DEFAULT 0,
    CONSTRAINT PK_catalogo_ProductoImagenes PRIMARY KEY CLUSTERED (ImagenId),
    CONSTRAINT FK_catalogo_ProductoImagenes_Producto FOREIGN KEY (ProductoId) REFERENCES catalogo.Productos(ProductoId) ON DELETE CASCADE
);
GO
CREATE INDEX IX_catalogo_ProductoImagenes_Producto ON catalogo.ProductoImagenes(ProductoId);
GO
