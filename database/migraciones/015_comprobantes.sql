-- =============================================================================
-- 015 · COMPROBANTES DE PAGO y cuenta de cobro con sus datos separados
-- =============================================================================
--   TCONFIGURACIONES            LIQUIDACIONCUENTA pasa de texto libre a {banco, tipo, numero, titular, identificacion}
--   TLIQUIDACIONCOMPROBANTES    el negocio sube la foto de su transferencia de una semana         · simple
-- Flujo: el negocio transfiere y sube el comprobante → el administrador lo revisa y lo APRUEBA (queda la semana
-- pagada en TLIQUIDACIONES) o lo RECHAZA con un motivo. Mientras el comprobante está en revisión, esa semana no
-- bloquea al negocio aunque se haya vencido (el negocio ya hizo su parte).
-- =============================================================================

UPDATE TCONFIGURACIONES
   SET VALOR = jsonb_build_object('banco', '', 'tipo', 'ahorros', 'numero', '', 'titular', '', 'identificacion', '',
                                  'notas', CASE WHEN jsonb_typeof(VALOR) = 'string' THEN VALOR #>> '{}' ELSE '' END),
       DESCRIPCION = 'Cuenta de ValleXpress donde los negocios transfieren la comisión: banco, tipo, número, titular y cédula/RUC'
 WHERE CCONFIGURACION = 'LIQUIDACIONCUENTA' AND FHASTA = '2999-12-31 00:00:00-05';

CREATE TABLE TLIQUIDACIONCOMPROBANTES (
    CCOMPROBANTE        BIGINT        GENERATED ALWAYS AS IDENTITY,
    CNEGOCIO            BIGINT        NOT NULL,
    SEMANA              DATE          NOT NULL,                -- lunes de la semana que paga
    CARCHIVO            BIGINT        NOT NULL,                -- la foto del comprobante
    MONTO               NUMERIC(12,2) NOT NULL,                -- lo que dice que transfirió
    REFERENCIA          VARCHAR(100),                          -- número de la transferencia
    ESTADO              VARCHAR(10)   NOT NULL DEFAULT 'ENVIADO',
    MOTIVORECHAZO       VARCHAR(300),
    FCREACION           TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    CUSUARIO            VARCHAR(30)   NOT NULL,                -- el dueño que lo subió
    FREVISION           TIMESTAMPTZ,
    CUSUARIO_REVISION   VARCHAR(30),                           -- el administrador que lo revisó
    CONSTRAINT IPKLIQCOMPROBANTES PRIMARY KEY (CCOMPROBANTE),
    CONSTRAINT FKLIQCOMPNEGOCIO FOREIGN KEY (CNEGOCIO) REFERENCES TNEGOCIOSID (CNEGOCIO),
    CONSTRAINT FKLIQCOMPARCHIVO FOREIGN KEY (CARCHIVO) REFERENCES TARCHIVOS (CARCHIVO),
    CONSTRAINT CKLIQCOMPESTADO CHECK (ESTADO IN ('ENVIADO', 'APROBADO', 'RECHAZADO')),
    CONSTRAINT CKLIQCOMPLUNES CHECK (EXTRACT(ISODOW FROM SEMANA) = 1)
);
-- Solo un comprobante en revisión por semana
CREATE UNIQUE INDEX IXLIQCOMPENVIADO ON TLIQUIDACIONCOMPROBANTES (CNEGOCIO, SEMANA) WHERE ESTADO = 'ENVIADO';

COMMENT ON TABLE TLIQUIDACIONCOMPROBANTES IS 'Comprobantes de transferencia que suben los negocios para pagar la comisión de una semana';
COMMENT ON COLUMN TLIQUIDACIONCOMPROBANTES.ESTADO IS 'ENVIADO (en revisión), APROBADO (la semana quedó pagada) o RECHAZADO (con motivo)';
