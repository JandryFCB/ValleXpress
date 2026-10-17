-- =============================================================================
-- 014 · LIQUIDACIONES: cómo le cobra ValleXpress su comisión a cada negocio (opción A, 2026-10-16)
-- =============================================================================
--   TLIQUIDACIONES     pagos de la comisión semanal de cada negocio                        · simple
--   TCONFIGURACIONES   LIQUIDACIONDIASGRACIA (7), LIQUIDACIONCUENTA (datos para transferir)
-- Flujo (efectivo vía repartidor): el repartidor le paga al negocio sus productos al recoger, cobra el total al
-- cliente y se queda el envío. Cada semana (lunes a domingo, hora de Ecuador) el negocio le debe a ValleXpress la
-- comisión de sus pedidos entregados. La semana se calcula de los pedidos; esta tabla guarda SOLO los pagos
-- (con la foto de lo que se cobró en ese momento). Si una semana cerrada sigue sin pagar pasados los días de
-- gracia, el negocio deja de recibir pedidos hasta ponerse al día.
-- =============================================================================

CREATE TABLE TLIQUIDACIONES (
    CLIQUIDACION   BIGINT        GENERATED ALWAYS AS IDENTITY,
    CNEGOCIO       BIGINT        NOT NULL,
    SEMANA         DATE          NOT NULL,                 -- lunes de la semana liquidada
    PEDIDOS        INTEGER       NOT NULL,
    VENTAS         NUMERIC(12,2) NOT NULL,                 -- productos vendidos esa semana
    COMISION       NUMERIC(12,2) NOT NULL,                 -- lo que se cobró
    REFERENCIA     VARCHAR(100),                           -- número de transferencia o recibo
    FPAGO          TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    CUSUARIO       VARCHAR(30)   NOT NULL,                 -- administrador que registró el pago
    CONSTRAINT IPKLIQUIDACIONES PRIMARY KEY (CLIQUIDACION),
    CONSTRAINT FKLIQUIDACIONESNEG FOREIGN KEY (CNEGOCIO) REFERENCES TNEGOCIOSID (CNEGOCIO),
    CONSTRAINT IUKLIQUIDACIONES UNIQUE (CNEGOCIO, SEMANA),
    CONSTRAINT CKLIQUIDACIONESLUNES CHECK (EXTRACT(ISODOW FROM SEMANA) = 1)
);

INSERT INTO TCONFIGURACIONES (CCONFIGURACION, VALOR, DESCRIPCION) VALUES
    ('LIQUIDACIONDIASGRACIA', '7',  'Días después del cierre de la semana para pagar la comisión antes de que el negocio deje de recibir pedidos'),
    ('LIQUIDACIONCUENTA',     '""', 'Datos de la cuenta de ValleXpress donde los negocios transfieren la comisión (banco, número, titular)');

COMMENT ON TABLE TLIQUIDACIONES IS 'Pagos de la comisión semanal de cada negocio a ValleXpress (una fila por negocio y semana pagada)';
COMMENT ON COLUMN TLIQUIDACIONES.SEMANA IS 'Lunes de la semana liquidada (America/Guayaquil)';
