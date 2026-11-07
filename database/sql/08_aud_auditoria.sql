/* ============================================================================
   08_aud_auditoria.sql
   Auditoria generica (complementa el historial automatico de las tablas
   temporales ord.Pedidos y pay.Pagos) para capturar quien ejecuto cada
   cambio desde la capa de aplicacion.
============================================================================ */

CREATE TABLE aud.RegistroAuditoria (
    AuditoriaId         BIGINT IDENTITY(1,1) NOT NULL,
    TablaAfectada       NVARCHAR(128)        NOT NULL,
    Operacion           NVARCHAR(10)         NOT NULL, -- INSERT/UPDATE/DELETE
    RegistroId          NVARCHAR(100)        NOT NULL,
    UsuarioEjecutorId   UNIQUEIDENTIFIER     NULL,
    DatosAnteriores     NVARCHAR(MAX)        NULL,
    DatosNuevos         NVARCHAR(MAX)        NULL,
    CreadoUtc           DATETIME2(3)         NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_aud_RegistroAuditoria PRIMARY KEY CLUSTERED (AuditoriaId),
    CONSTRAINT CK_aud_RegistroAuditoria_Operacion CHECK (Operacion IN (N'INSERT', N'UPDATE', N'DELETE'))
);
GO
CREATE INDEX IX_aud_RegistroAuditoria_Tabla ON aud.RegistroAuditoria(TablaAfectada, CreadoUtc DESC);
GO

/* Ejemplo de trigger de auditoria sobre pay.Pagos (cambios de estado de pago).
   Se replica el mismo patron para otras tablas criticas si se requiere. */
CREATE OR ALTER TRIGGER pay.trg_Pagos_Auditoria
ON pay.Pagos
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO aud.RegistroAuditoria (TablaAfectada, Operacion, RegistroId, DatosAnteriores, DatosNuevos)
    SELECT
        N'pay.Pagos',
        N'UPDATE',
        CAST(i.PagoId AS NVARCHAR(100)),
        (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM inserted i
    INNER JOIN deleted d ON d.PagoId = i.PagoId;
END;
GO
