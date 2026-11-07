/* ============================================================================
   07_soc_comunidad.sql
   Comunidad: publicaciones, mensajeria comercio-cliente, resenas, favoritos,
   notificaciones y el registro de sugerencias del "agente de compras"
   (propone opciones, nunca autoriza pagos).
============================================================================ */

CREATE TABLE soc.Publicaciones (
    PublicacionId   UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_soc_Publicaciones_Id DEFAULT NEWSEQUENTIALID(),
    AutorUsuarioId  UNIQUEIDENTIFIER NULL,
    AutorComercioId UNIQUEIDENTIFIER NULL,
    Contenido       NVARCHAR(500)    NOT NULL,
    ImagenUrl       NVARCHAR(400)    NULL,
    CreadoUtc       DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_soc_Publicaciones PRIMARY KEY CLUSTERED (PublicacionId),
    CONSTRAINT FK_soc_Publicaciones_Usuario FOREIGN KEY (AutorUsuarioId) REFERENCES ident.Usuarios(UsuarioId),
    CONSTRAINT FK_soc_Publicaciones_Comercio FOREIGN KEY (AutorComercioId) REFERENCES biz.Comercios(ComercioId),
    CONSTRAINT CK_soc_Publicaciones_Autor CHECK (AutorUsuarioId IS NOT NULL OR AutorComercioId IS NOT NULL)
);
GO
CREATE INDEX IX_soc_Publicaciones_Creado ON soc.Publicaciones(CreadoUtc DESC);
GO

CREATE TABLE soc.PublicacionLikes (
    PublicacionId UNIQUEIDENTIFIER NOT NULL,
    UsuarioId     UNIQUEIDENTIFIER NOT NULL,
    CreadoUtc     DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_soc_PublicacionLikes PRIMARY KEY CLUSTERED (PublicacionId, UsuarioId),
    CONSTRAINT FK_soc_PublicacionLikes_Publicacion FOREIGN KEY (PublicacionId) REFERENCES soc.Publicaciones(PublicacionId) ON DELETE CASCADE,
    CONSTRAINT FK_soc_PublicacionLikes_Usuario FOREIGN KEY (UsuarioId) REFERENCES ident.Usuarios(UsuarioId)
);
GO

CREATE TABLE soc.PublicacionComentarios (
    ComentarioId    BIGINT IDENTITY(1,1) NOT NULL,
    PublicacionId   UNIQUEIDENTIFIER     NOT NULL,
    UsuarioId       UNIQUEIDENTIFIER     NOT NULL,
    Contenido       NVARCHAR(300)        NOT NULL,
    CreadoUtc       DATETIME2(3)         NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_soc_PublicacionComentarios PRIMARY KEY CLUSTERED (ComentarioId),
    CONSTRAINT FK_soc_PublicacionComentarios_Publicacion FOREIGN KEY (PublicacionId) REFERENCES soc.Publicaciones(PublicacionId) ON DELETE CASCADE,
    CONSTRAINT FK_soc_PublicacionComentarios_Usuario FOREIGN KEY (UsuarioId) REFERENCES ident.Usuarios(UsuarioId)
);
GO

CREATE TABLE soc.Conversaciones (
    ConversacionId  UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_soc_Conversaciones_Id DEFAULT NEWSEQUENTIALID(),
    UsuarioId       UNIQUEIDENTIFIER NOT NULL,
    ComercioId      UNIQUEIDENTIFIER NOT NULL,
    UltimoMensajeUtc DATETIME2(3)    NULL,
    CONSTRAINT PK_soc_Conversaciones PRIMARY KEY CLUSTERED (ConversacionId),
    CONSTRAINT FK_soc_Conversaciones_Usuario FOREIGN KEY (UsuarioId) REFERENCES ident.Usuarios(UsuarioId),
    CONSTRAINT FK_soc_Conversaciones_Comercio FOREIGN KEY (ComercioId) REFERENCES biz.Comercios(ComercioId),
    CONSTRAINT UQ_soc_Conversaciones_UsuarioComercio UNIQUE (UsuarioId, ComercioId)
);
GO

CREATE TABLE soc.Mensajes (
    MensajeId       BIGINT IDENTITY(1,1) NOT NULL,
    ConversacionId  UNIQUEIDENTIFIER     NOT NULL,
    EmisorEsUsuario BIT                  NOT NULL,
    Contenido       NVARCHAR(1000)       NOT NULL,
    LeidoUtc        DATETIME2(3)         NULL,
    CreadoUtc       DATETIME2(3)         NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_soc_Mensajes PRIMARY KEY CLUSTERED (MensajeId),
    CONSTRAINT FK_soc_Mensajes_Conversacion FOREIGN KEY (ConversacionId) REFERENCES soc.Conversaciones(ConversacionId) ON DELETE CASCADE
);
GO
CREATE INDEX IX_soc_Mensajes_Conversacion ON soc.Mensajes(ConversacionId, CreadoUtc);
GO

CREATE TABLE soc.Resenas (
    ResenaId    BIGINT IDENTITY(1,1) NOT NULL,
    ComercioId  UNIQUEIDENTIFIER     NOT NULL,
    ProductoId  UNIQUEIDENTIFIER     NULL,
    UsuarioId   UNIQUEIDENTIFIER     NOT NULL,
    PedidoId    UNIQUEIDENTIFIER     NULL,
    Calificacion TINYINT             NOT NULL,
    Comentario  NVARCHAR(500)        NULL,
    CreadoUtc   DATETIME2(3)         NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_soc_Resenas PRIMARY KEY CLUSTERED (ResenaId),
    CONSTRAINT FK_soc_Resenas_Comercio FOREIGN KEY (ComercioId) REFERENCES biz.Comercios(ComercioId),
    CONSTRAINT FK_soc_Resenas_Producto FOREIGN KEY (ProductoId) REFERENCES catalogo.Productos(ProductoId),
    CONSTRAINT FK_soc_Resenas_Usuario FOREIGN KEY (UsuarioId) REFERENCES ident.Usuarios(UsuarioId),
    CONSTRAINT FK_soc_Resenas_Pedido FOREIGN KEY (PedidoId) REFERENCES ord.Pedidos(PedidoId),
    CONSTRAINT CK_soc_Resenas_Calificacion CHECK (Calificacion BETWEEN 1 AND 5)
);
GO
CREATE INDEX IX_soc_Resenas_Comercio ON soc.Resenas(ComercioId);
GO

CREATE TABLE soc.Favoritos (
    UsuarioId   UNIQUEIDENTIFIER NOT NULL,
    ComercioId  UNIQUEIDENTIFIER NOT NULL,
    CreadoUtc   DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_soc_Favoritos PRIMARY KEY CLUSTERED (UsuarioId, ComercioId),
    CONSTRAINT FK_soc_Favoritos_Usuario FOREIGN KEY (UsuarioId) REFERENCES ident.Usuarios(UsuarioId) ON DELETE CASCADE,
    CONSTRAINT FK_soc_Favoritos_Comercio FOREIGN KEY (ComercioId) REFERENCES biz.Comercios(ComercioId)
);
GO

CREATE TABLE soc.Notificaciones (
    NotificacionId BIGINT IDENTITY(1,1) NOT NULL,
    UsuarioId      UNIQUEIDENTIFIER     NOT NULL,
    Tipo           NVARCHAR(30)         NOT NULL,
    Titulo         NVARCHAR(150)        NOT NULL,
    Cuerpo         NVARCHAR(300)        NULL,
    DatosJson      NVARCHAR(MAX)        NULL,
    LeidoUtc       DATETIME2(3)         NULL,
    CreadoUtc      DATETIME2(3)         NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_soc_Notificaciones PRIMARY KEY CLUSTERED (NotificacionId),
    CONSTRAINT FK_soc_Notificaciones_Usuario FOREIGN KEY (UsuarioId) REFERENCES ident.Usuarios(UsuarioId) ON DELETE CASCADE
);
GO
CREATE INDEX IX_soc_Notificaciones_Usuario ON soc.Notificaciones(UsuarioId, LeidoUtc);
GO

-- "Agente de compras" solo registra sugerencias; jamas autoriza pagos
CREATE TABLE soc.AgenteComprasSugerencias (
    SugerenciaId    BIGINT IDENTITY(1,1) NOT NULL,
    UsuarioId       UNIQUEIDENTIFIER     NOT NULL,
    ConsultaTexto   NVARCHAR(300)        NOT NULL,
    ProductosSugeridosJson NVARCHAR(MAX) NULL,
    CreadoUtc       DATETIME2(3)         NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_soc_AgenteComprasSugerencias PRIMARY KEY CLUSTERED (SugerenciaId),
    CONSTRAINT FK_soc_AgenteComprasSugerencias_Usuario FOREIGN KEY (UsuarioId) REFERENCES ident.Usuarios(UsuarioId) ON DELETE CASCADE
);
GO
