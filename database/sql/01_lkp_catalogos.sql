/* ============================================================================
   01_lkp_catalogos.sql
   Catalogos de referencia compartidos por toda la aplicacion.
============================================================================ */

CREATE TABLE lkp.Colonias (
    ColoniaId       INT IDENTITY(1,1) NOT NULL,
    Nombre          NVARCHAR(100)     NOT NULL,
    Ciudad          NVARCHAR(100)     NOT NULL DEFAULT N'CDMX',
    Estado          NVARCHAR(100)     NOT NULL DEFAULT N'Ciudad de Mexico',
    CodigoPostal    NVARCHAR(10)      NULL,
    CONSTRAINT PK_lkp_Colonias PRIMARY KEY CLUSTERED (ColoniaId),
    CONSTRAINT UQ_lkp_Colonias_Nombre UNIQUE (Nombre, Ciudad)
);
GO

CREATE TABLE lkp.Categorias (
    CategoriaId     INT IDENTITY(1,1) NOT NULL,
    Nombre          NVARCHAR(50)      NOT NULL,
    Icono           NVARCHAR(50)      NULL,
    EstaActivo      BIT               NOT NULL DEFAULT 1,
    CONSTRAINT PK_lkp_Categorias PRIMARY KEY CLUSTERED (CategoriaId),
    CONSTRAINT UQ_lkp_Categorias_Nombre UNIQUE (Nombre)
);
GO

CREATE TABLE lkp.MetodosPago (
    MetodoPagoId    TINYINT         NOT NULL,
    Codigo          NVARCHAR(20)    NOT NULL,
    Nombre          NVARCHAR(50)    NOT NULL,
    RequiereAntifraude BIT          NOT NULL DEFAULT 0,
    CONSTRAINT PK_lkp_MetodosPago PRIMARY KEY CLUSTERED (MetodoPagoId),
    CONSTRAINT UQ_lkp_MetodosPago_Codigo UNIQUE (Codigo)
);
GO

CREATE TABLE lkp.EstadosPedido (
    EstadoId        TINYINT         NOT NULL,
    Codigo          NVARCHAR(20)    NOT NULL,
    Nombre          NVARCHAR(30)    NOT NULL,
    Orden           TINYINT         NOT NULL,
    CONSTRAINT PK_lkp_EstadosPedido PRIMARY KEY CLUSTERED (EstadoId),
    CONSTRAINT UQ_lkp_EstadosPedido_Codigo UNIQUE (Codigo)
);
GO

CREATE TABLE lkp.EstadosPago (
    EstadoPagoId    TINYINT         NOT NULL,
    Codigo          NVARCHAR(20)    NOT NULL,
    Nombre          NVARCHAR(30)    NOT NULL,
    CONSTRAINT PK_lkp_EstadosPago PRIMARY KEY CLUSTERED (EstadoPagoId),
    CONSTRAINT UQ_lkp_EstadosPago_Codigo UNIQUE (Codigo)
);
GO

CREATE TABLE lkp.Roles (
    RolId           TINYINT         NOT NULL,
    Nombre          NVARCHAR(30)    NOT NULL,
    CONSTRAINT PK_lkp_Roles PRIMARY KEY CLUSTERED (RolId),
    CONSTRAINT UQ_lkp_Roles_Nombre UNIQUE (Nombre)
);
GO
