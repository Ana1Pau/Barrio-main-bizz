/* ============================================================================
   02_ident_identidad.sql
   Cuentas de usuario, perfiles, sesiones y verificacion de identidad.
   Notas de seguridad:
     - Nunca se guarda la contrasena en texto plano: se guarda hash + sal
       (el hash se calcula en la capa de aplicacion con Argon2id/bcrypt).
     - Correo/Telefono llevan Dynamic Data Masking (ver 11_security.sql).
============================================================================ */

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE TABLE ident.Usuarios (
    UsuarioId           UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_ident_Usuarios_Id DEFAULT NEWSEQUENTIALID(),
    Correo              NVARCHAR(256)    MASKED WITH (FUNCTION = 'email()') NULL,
    Telefono            NVARCHAR(20)     MASKED WITH (FUNCTION = 'partial(2,"XXXXXXX",2)') NULL,
    HashContrasena      VARBINARY(256)   NOT NULL,
    SalContrasena       VARBINARY(64)    NOT NULL,
    TipoUso             TINYINT          NOT NULL, -- 1=Comprar, 2=Negocio, 3=Ambas
    CorreoVerificado    BIT              NOT NULL DEFAULT 0,
    TelefonoVerificado  BIT              NOT NULL DEFAULT 0,
    EstaActivo          BIT              NOT NULL DEFAULT 1,
    UltimoAccesoUtc     DATETIME2(3)     NULL,
    FechaCreacionUtc    DATETIME2(3)     NOT NULL CONSTRAINT DF_ident_Usuarios_Creado DEFAULT SYSUTCDATETIME(),
    FechaActualizacionUtc DATETIME2(3)   NULL,
    CONSTRAINT PK_ident_Usuarios PRIMARY KEY CLUSTERED (UsuarioId),
    CONSTRAINT CK_ident_Usuarios_TipoUso CHECK (TipoUso IN (1,2,3)),
    CONSTRAINT CK_ident_Usuarios_ContactoMinimo CHECK (Correo IS NOT NULL OR Telefono IS NOT NULL)
);
GO

-- Indices unicos FILTRADOS: una constraint UNIQUE normal en SQL Server solo
-- admite un unico valor NULL por columna, lo que bloquearia a mas de un
-- usuario que se registre sin correo (o sin telefono). Al filtrar los NULL
-- se garantiza unicidad solo cuando el dato si fue proporcionado.
CREATE UNIQUE INDEX UQ_ident_Usuarios_Correo ON ident.Usuarios(Correo) WHERE Correo IS NOT NULL;
CREATE UNIQUE INDEX UQ_ident_Usuarios_Telefono ON ident.Usuarios(Telefono) WHERE Telefono IS NOT NULL;
GO

CREATE TABLE ident.UsuarioRoles (
    UsuarioId   UNIQUEIDENTIFIER NOT NULL,
    RolId       TINYINT          NOT NULL,
    AsignadoUtc DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_ident_UsuarioRoles PRIMARY KEY CLUSTERED (UsuarioId, RolId),
    CONSTRAINT FK_ident_UsuarioRoles_Usuario FOREIGN KEY (UsuarioId) REFERENCES ident.Usuarios(UsuarioId) ON DELETE CASCADE,
    CONSTRAINT FK_ident_UsuarioRoles_Rol FOREIGN KEY (RolId) REFERENCES lkp.Roles(RolId)
);
GO

CREATE TABLE ident.Perfiles (
    UsuarioId       UNIQUEIDENTIFIER NOT NULL,
    NombreMostrar   NVARCHAR(100)    NOT NULL,
    FotoUrl         NVARCHAR(400)    NULL,
    Biografia       NVARCHAR(300)    NULL,
    ColoniaId       INT              NULL,
    FechaActualizacionUtc DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_ident_Perfiles PRIMARY KEY CLUSTERED (UsuarioId),
    CONSTRAINT FK_ident_Perfiles_Usuario FOREIGN KEY (UsuarioId) REFERENCES ident.Usuarios(UsuarioId) ON DELETE CASCADE,
    CONSTRAINT FK_ident_Perfiles_Colonia FOREIGN KEY (ColoniaId) REFERENCES lkp.Colonias(ColoniaId)
);
GO

CREATE TABLE ident.UsuarioIntereses (
    UsuarioId   UNIQUEIDENTIFIER NOT NULL,
    CategoriaId INT              NOT NULL,
    CONSTRAINT PK_ident_UsuarioIntereses PRIMARY KEY CLUSTERED (UsuarioId, CategoriaId),
    CONSTRAINT FK_ident_UsuarioIntereses_Usuario FOREIGN KEY (UsuarioId) REFERENCES ident.Usuarios(UsuarioId) ON DELETE CASCADE,
    CONSTRAINT FK_ident_UsuarioIntereses_Categoria FOREIGN KEY (CategoriaId) REFERENCES lkp.Categorias(CategoriaId)
);
GO

-- Refresh tokens de sesion (nunca se guarda el token en claro, solo su hash)
CREATE TABLE ident.SesionesRefreshToken (
    TokenId         UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_ident_Sesiones_Id DEFAULT NEWID(),
    UsuarioId       UNIQUEIDENTIFIER NOT NULL,
    TokenHash       VARBINARY(256)   NOT NULL,
    DispositivoInfo NVARCHAR(200)    NULL,
    DireccionIp     VARBINARY(16)    NULL,
    ExpiraUtc       DATETIME2(3)     NOT NULL,
    RevocadoUtc     DATETIME2(3)     NULL,
    CreadoUtc       DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_ident_SesionesRefreshToken PRIMARY KEY CLUSTERED (TokenId),
    CONSTRAINT FK_ident_Sesiones_Usuario FOREIGN KEY (UsuarioId) REFERENCES ident.Usuarios(UsuarioId) ON DELETE CASCADE,
    CONSTRAINT UQ_ident_Sesiones_TokenHash UNIQUE (TokenHash)
);
GO
CREATE INDEX IX_ident_Sesiones_Usuario ON ident.SesionesRefreshToken(UsuarioId, ExpiraUtc);
GO

-- Verificaciones de identidad: validacion de correo/telefono y la
-- "verificacion adicional ante sospecha" (reCeption) del flujo antifraude
CREATE TABLE ident.VerificacionesIdentidad (
    VerificacionId  BIGINT IDENTITY(1,1) NOT NULL,
    UsuarioId       UNIQUEIDENTIFIER     NOT NULL,
    Tipo            NVARCHAR(30)         NOT NULL, -- TELEFONO, CORREO, ANTIFRAUDE_ADICIONAL
    Estado          NVARCHAR(20)         NOT NULL DEFAULT N'PENDIENTE',
    Proveedor       NVARCHAR(50)         NULL,     -- p.ej. 'reCeption'
    ReferenciaExterna NVARCHAR(100)      NULL,
    CreadoUtc       DATETIME2(3)         NOT NULL DEFAULT SYSUTCDATETIME(),
    ResueltoUtc     DATETIME2(3)         NULL,
    CONSTRAINT PK_ident_Verificaciones PRIMARY KEY CLUSTERED (VerificacionId),
    CONSTRAINT FK_ident_Verificaciones_Usuario FOREIGN KEY (UsuarioId) REFERENCES ident.Usuarios(UsuarioId) ON DELETE CASCADE,
    CONSTRAINT CK_ident_Verificaciones_Estado CHECK (Estado IN (N'PENDIENTE', N'APROBADA', N'RECHAZADA'))
);
GO
CREATE INDEX IX_ident_Verificaciones_Usuario ON ident.VerificacionesIdentidad(UsuarioId, Tipo);
GO
