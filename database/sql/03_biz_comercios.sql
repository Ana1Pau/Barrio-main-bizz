/* ============================================================================
   03_biz_comercios.sql
   Perfil publico del comercio, categorias (giro), metodos de pago que
   acepta y horarios.
============================================================================ */

CREATE TABLE biz.Comercios (
    ComercioId          UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_biz_Comercios_Id DEFAULT NEWSEQUENTIALID(),
    UsuarioPropietarioId UNIQUEIDENTIFIER NOT NULL,
    NombreNegocio       NVARCHAR(150)    NOT NULL,
    Descripcion         NVARCHAR(500)    NULL,
    ColoniaId           INT              NULL,
    DireccionLinea      NVARCHAR(250)    NULL,
    Latitud             DECIMAL(9,6)     NULL,
    Longitud            DECIMAL(9,6)     NULL,
    FotoPerfilUrl       NVARCHAR(400)    NULL,
    FotoPortadaUrl      NVARCHAR(400)    NULL,
    CalificacionPromedio DECIMAL(3,2)    NOT NULL DEFAULT 0,
    TotalResenas        INT              NOT NULL DEFAULT 0,
    EstaActivo          BIT              NOT NULL DEFAULT 1,
    EstaVerificado       BIT              NOT NULL DEFAULT 0,
    FechaCreacionUtc    DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
    FechaActualizacionUtc DATETIME2(3)   NULL,
    CONSTRAINT PK_biz_Comercios PRIMARY KEY CLUSTERED (ComercioId),
    CONSTRAINT FK_biz_Comercios_Usuario FOREIGN KEY (UsuarioPropietarioId) REFERENCES ident.Usuarios(UsuarioId),
    CONSTRAINT FK_biz_Comercios_Colonia FOREIGN KEY (ColoniaId) REFERENCES lkp.Colonias(ColoniaId),
    CONSTRAINT CK_biz_Comercios_Calificacion CHECK (CalificacionPromedio BETWEEN 0 AND 5)
);
GO
CREATE INDEX IX_biz_Comercios_Propietario ON biz.Comercios(UsuarioPropietarioId);
CREATE INDEX IX_biz_Comercios_Colonia ON biz.Comercios(ColoniaId) INCLUDE (NombreNegocio, EstaActivo);
GO

CREATE TABLE biz.ComercioCategorias (
    ComercioId  UNIQUEIDENTIFIER NOT NULL,
    CategoriaId INT              NOT NULL,
    CONSTRAINT PK_biz_ComercioCategorias PRIMARY KEY CLUSTERED (ComercioId, CategoriaId),
    CONSTRAINT FK_biz_ComercioCategorias_Comercio FOREIGN KEY (ComercioId) REFERENCES biz.Comercios(ComercioId) ON DELETE CASCADE,
    CONSTRAINT FK_biz_ComercioCategorias_Categoria FOREIGN KEY (CategoriaId) REFERENCES lkp.Categorias(CategoriaId)
);
GO

CREATE TABLE biz.ComercioMetodosPago (
    ComercioId          UNIQUEIDENTIFIER NOT NULL,
    MetodoPagoId        TINYINT          NOT NULL,
    EstaHabilitado      BIT              NOT NULL DEFAULT 1,
    ConfiguracionJson   NVARCHAR(MAX)    NULL, -- configuracion NO sensible (nunca credenciales)
    CONSTRAINT PK_biz_ComercioMetodosPago PRIMARY KEY CLUSTERED (ComercioId, MetodoPagoId),
    CONSTRAINT FK_biz_ComercioMetodosPago_Comercio FOREIGN KEY (ComercioId) REFERENCES biz.Comercios(ComercioId) ON DELETE CASCADE,
    CONSTRAINT FK_biz_ComercioMetodosPago_Metodo FOREIGN KEY (MetodoPagoId) REFERENCES lkp.MetodosPago(MetodoPagoId)
);
GO

CREATE TABLE biz.ComercioHorarios (
    ComercioId  UNIQUEIDENTIFIER NOT NULL,
    DiaSemana   TINYINT          NOT NULL, -- 0=Domingo ... 6=Sabado
    HoraApertura TIME            NOT NULL,
    HoraCierre  TIME             NOT NULL,
    CONSTRAINT PK_biz_ComercioHorarios PRIMARY KEY CLUSTERED (ComercioId, DiaSemana),
    CONSTRAINT FK_biz_ComercioHorarios_Comercio FOREIGN KEY (ComercioId) REFERENCES biz.Comercios(ComercioId) ON DELETE CASCADE,
    CONSTRAINT CK_biz_ComercioHorarios_Dia CHECK (DiaSemana BETWEEN 0 AND 6)
);
GO
