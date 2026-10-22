-- =============================================================================
-- 026 · Pago por TRANSFERENCIA del cliente al negocio
-- =============================================================================
--   TNEGOCIOCUENTAS          cuentas donde el negocio recibe transferencias (una o varias)          · simple
--   TPEDIDOCOMPROBANTES      foto de la transferencia que sube el cliente; el negocio la confirma    · simple
--   TCONFIGURACIONES         PEDIDOVENCETRANSFERENCIAMIN (30)
-- Flujo: el cliente elige "Transferencia" (solo si el negocio tiene cuentas) -> el negocio confirma el pedido ->
-- el cliente ve las cuentas, transfiere y sube el comprobante -> el negocio toca "Pago recibido" (el pedido queda
-- pagado y ya puede prepararlo) o "No me llegó" con un motivo (el cliente sube otro). ValleXpress no toca el dinero.
-- Si el negocio confirma y el cliente no sube el comprobante en PEDIDOVENCETRANSFERENCIAMIN, el pedido se cancela solo.
-- =============================================================================

CREATE TABLE TNEGOCIOCUENTAS (
    CNEGOCIO            BIGINT        NOT NULL,
    NUMEROLINEA         SMALLINT      NOT NULL,                -- orden en que las muestra la app
    BANCO               VARCHAR(80)   NOT NULL,
    TIPO                VARCHAR(10)   NOT NULL DEFAULT 'ahorros',
    NUMERO              VARCHAR(30)   NOT NULL,
    TITULAR             VARCHAR(120)  NOT NULL,
    IDENTIFICACION      VARCHAR(13),                           -- cédula o RUC del titular
    FCREACION           TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    CUSUARIO_REGISTRO   VARCHAR(30)   NOT NULL DEFAULT USUARIOACTUAL(),
    CONSTRAINT IPKNEGOCIOCUENTAS PRIMARY KEY (CNEGOCIO, NUMEROLINEA),
    CONSTRAINT FKNEGCUENEGID     FOREIGN KEY (CNEGOCIO) REFERENCES TNEGOCIOSID (CNEGOCIO),
    CONSTRAINT CKNEGCUETIPO      CHECK (TIPO IN ('ahorros', 'corriente'))
);
COMMENT ON TABLE TNEGOCIOCUENTAS IS 'Cuentas donde el negocio recibe las transferencias de sus clientes';

CREATE TABLE TPEDIDOCOMPROBANTES (
    CCOMPROBANTE        BIGINT        GENERATED ALWAYS AS IDENTITY,
    CPEDIDO             BIGINT        NOT NULL,
    CARCHIVO            BIGINT        NOT NULL,                -- la foto de la transferencia
    REFERENCIA          VARCHAR(100),                          -- número de la transferencia
    ESTADO              VARCHAR(10)   NOT NULL DEFAULT 'ENVIADO',
    MOTIVORECHAZO       VARCHAR(300),
    FCREACION           TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    CUSUARIO_REGISTRO   VARCHAR(30)   NOT NULL,                -- el cliente
    FREVISION           TIMESTAMPTZ,
    CUSUARIO_REVISION   VARCHAR(30),                           -- el dueño del negocio que lo revisó
    CONSTRAINT IPKPEDIDOCOMPROBANTES PRIMARY KEY (CCOMPROBANTE),
    CONSTRAINT FKPEDCOMPEDID     FOREIGN KEY (CPEDIDO) REFERENCES TPEDIDOSID (CPEDIDO),
    CONSTRAINT FKPEDCOMARCHIVO   FOREIGN KEY (CARCHIVO) REFERENCES TARCHIVOS (CARCHIVO),
    CONSTRAINT CKPEDCOMESTADO    CHECK (ESTADO IN ('ENVIADO', 'APROBADO', 'RECHAZADO'))
);
-- A lo sumo un comprobante en revisión o aprobado por pedido
CREATE UNIQUE INDEX UQPEDCOMVIGENTE ON TPEDIDOCOMPROBANTES (CPEDIDO) WHERE ESTADO IN ('ENVIADO', 'APROBADO');
COMMENT ON TABLE TPEDIDOCOMPROBANTES IS 'Comprobantes de transferencia que sube el cliente para pagar un pedido; los confirma el negocio';
COMMENT ON COLUMN TPEDIDOCOMPROBANTES.ESTADO IS 'ENVIADO (el negocio lo revisa), APROBADO (pago recibido) o RECHAZADO (no le llegó, con motivo)';

INSERT INTO TCONFIGURACIONES (CCONFIGURACION, VALOR, DESCRIPCION) VALUES
    ('PEDIDOVENCETRANSFERENCIAMIN', '30', 'Minutos que tiene el cliente para subir el comprobante de la transferencia desde que el negocio confirma (si no, se cancela)');
