/* ============================================================================
   06_pay_pagos.sql
   Pagos, pagos en cripto (red Hedera/HBAR), antifraude y bitacora del
   "coordinador de pagos" descrito en el diagrama de arquitectura.

   Seguridad:
     - TokenPagoEncriptado se protege con ALWAYS ENCRYPTED (ver 11_security.sql).
       Nunca se guarda el numero de tarjeta completo (PAN): solo el token que
       entrega el procesador de pagos (Stripe/Conekta/etc.).
     - DireccionBilleteraUsuario tambien puede protegerse con Always Encrypted
       si se considera dato sensible segun el proveedor cripto.
============================================================================ */

CREATE TABLE pay.Pagos (
    PagoId              UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_pay_Pagos_Id DEFAULT NEWSEQUENTIALID(),
    PedidoId            UNIQUEIDENTIFIER NOT NULL,
    MetodoPagoId        TINYINT          NOT NULL,
    EstadoPagoId        TINYINT          NOT NULL,
    Monto               DECIMAL(10,2)    NOT NULL,
    Moneda              CHAR(3)          NOT NULL DEFAULT 'MXN',
    ProveedorReferencia NVARCHAR(100)    NULL,
    TokenPagoEncriptado VARBINARY(256)   NULL,
    CreadoUtc           DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
    ActualizadoUtc      DATETIME2(3)     NULL,
    SysStartTime        DATETIME2(3) GENERATED ALWAYS AS ROW START NOT NULL,
    SysEndTime          DATETIME2(3) GENERATED ALWAYS AS ROW END NOT NULL,
    PERIOD FOR SYSTEM_TIME (SysStartTime, SysEndTime),
    CONSTRAINT PK_pay_Pagos PRIMARY KEY CLUSTERED (PagoId),
    CONSTRAINT UQ_pay_Pagos_Pedido UNIQUE (PedidoId),
    CONSTRAINT FK_pay_Pagos_Pedido FOREIGN KEY (PedidoId) REFERENCES ord.Pedidos(PedidoId),
    CONSTRAINT FK_pay_Pagos_Metodo FOREIGN KEY (MetodoPagoId) REFERENCES lkp.MetodosPago(MetodoPagoId),
    CONSTRAINT FK_pay_Pagos_Estado FOREIGN KEY (EstadoPagoId) REFERENCES lkp.EstadosPago(EstadoPagoId),
    CONSTRAINT CK_pay_Pagos_Monto CHECK (Monto >= 0)
)
WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = pay.PagosHistorial));
GO
CREATE INDEX IX_pay_Pagos_Estado ON pay.Pagos(EstadoPagoId, CreadoUtc DESC);
GO

-- "Billetera propia del usuario" -> Red Hedera HBAR (el usuario autoriza y firma)
CREATE TABLE pay.PagosCripto (
    PagoId                      UNIQUEIDENTIFIER NOT NULL,
    RedBlockchain               NVARCHAR(20)     NOT NULL DEFAULT N'HEDERA_HBAR',
    DireccionBilleteraUsuario   NVARCHAR(100)    NOT NULL,
    HashTransaccion             NVARCHAR(150)    NULL,
    EstaAutorizadoPorUsuario    BIT              NOT NULL DEFAULT 0,
    VerificadoAntifraude        BIT              NOT NULL DEFAULT 0,
    CreadoUtc                   DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
    ConfirmadoUtc                DATETIME2(3)     NULL,
    CONSTRAINT PK_pay_PagosCripto PRIMARY KEY CLUSTERED (PagoId),
    CONSTRAINT FK_pay_PagosCripto_Pago FOREIGN KEY (PagoId) REFERENCES pay.Pagos(PagoId) ON DELETE CASCADE
);
GO

-- "Conector antifraude: solo para HBAR sospechoso" + verificacion adicional (reCeption)
CREATE TABLE pay.AlertasAntifraude (
    AlertaId                    BIGINT IDENTITY(1,1) NOT NULL,
    PagoId                      UNIQUEIDENTIFIER     NOT NULL,
    NivelRiesgo                 NVARCHAR(10)          NOT NULL,
    Motivo                      NVARCHAR(300)         NOT NULL,
    RequiereVerificacionAdicional BIT                 NOT NULL DEFAULT 0,
    EstadoResolucion            NVARCHAR(20)          NOT NULL DEFAULT N'PENDIENTE',
    CreadoUtc                   DATETIME2(3)          NOT NULL DEFAULT SYSUTCDATETIME(),
    ResueltoUtc                 DATETIME2(3)          NULL,
    CONSTRAINT PK_pay_AlertasAntifraude PRIMARY KEY CLUSTERED (AlertaId),
    CONSTRAINT FK_pay_AlertasAntifraude_Pago FOREIGN KEY (PagoId) REFERENCES pay.Pagos(PagoId) ON DELETE CASCADE,
    CONSTRAINT CK_pay_AlertasAntifraude_Nivel CHECK (NivelRiesgo IN (N'BAJO', N'MEDIO', N'ALTO')),
    CONSTRAINT CK_pay_AlertasAntifraude_Estado CHECK (EstadoResolucion IN (N'PENDIENTE', N'APROBADO', N'RECHAZADO'))
);
GO
CREATE INDEX IX_pay_AlertasAntifraude_Pago ON pay.AlertasAntifraude(PagoId);
GO

-- Bitacora de transiciones del "coordinador de pagos" (trazabilidad end-to-end)
CREATE TABLE pay.CoordinadorPagosEventos (
    EventoId    BIGINT IDENTITY(1,1) NOT NULL,
    PagoId      UNIQUEIDENTIFIER     NOT NULL,
    Etapa       NVARCHAR(50)         NOT NULL,
    DetalleJson NVARCHAR(MAX)        NULL,
    CreadoUtc   DATETIME2(3)         NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_pay_CoordinadorPagosEventos PRIMARY KEY CLUSTERED (EventoId),
    CONSTRAINT FK_pay_CoordinadorPagosEventos_Pago FOREIGN KEY (PagoId) REFERENCES pay.Pagos(PagoId) ON DELETE CASCADE
);
GO
CREATE INDEX IX_pay_CoordinadorPagosEventos_Pago ON pay.CoordinadorPagosEventos(PagoId, CreadoUtc);
GO
