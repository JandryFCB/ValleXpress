-- =============================================================================
-- 023 · Sugerencias: "Ayúdanos a mejorar ValleXpress"
-- =============================================================================
--   TSUGERENCIAS   lo que clientes, vendedores y repartidores proponen o reportan desde la app       · simple
--     TIPO           SUGERENCIA (una idea), PROBLEMA (algo que falla), FELICITACION (algo que les gusta)
--     SATISFACCION   1 a 5: qué tan contentos están con la app (opcional)
--     ESTADO         NUEVA → LEIDA → ATENDIDA. El administrador puede responder y a la persona le llega el aviso.
-- =============================================================================
CREATE TABLE TSUGERENCIAS (
    CSUGERENCIA         BIGINT        GENERATED ALWAYS AS IDENTITY,
    CUSUARIO            VARCHAR(30)   NOT NULL,
    CROL                CHAR(3)       NOT NULL,                 -- con qué perfil la envió
    TIPO                VARCHAR(12)   NOT NULL DEFAULT 'SUGERENCIA',
    MENSAJE             VARCHAR(1000) NOT NULL,
    SATISFACCION        SMALLINT,
    VERSIONAPP          VARCHAR(20),
    ESTADO              VARCHAR(10)   NOT NULL DEFAULT 'NUEVA',
    RESPUESTA           VARCHAR(1000),
    FCREACION           TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    FREVISION           TIMESTAMPTZ,
    CUSUARIO_REVISION   VARCHAR(30),                            -- el administrador que la atendió
    CONSTRAINT IPKSUGERENCIAS PRIMARY KEY (CSUGERENCIA),
    CONSTRAINT FKSUGERENCIASUSU  FOREIGN KEY (CUSUARIO) REFERENCES TUSUARIOSID (CUSUARIO),
    CONSTRAINT FKSUGERENCIASROL  FOREIGN KEY (CROL) REFERENCES TROLESID (CROL),
    CONSTRAINT CKSUGERENCIASTIPO CHECK (TIPO IN ('SUGERENCIA', 'PROBLEMA', 'FELICITACION')),
    CONSTRAINT CKSUGERENCIASEST  CHECK (ESTADO IN ('NUEVA', 'LEIDA', 'ATENDIDA')),
    CONSTRAINT CKSUGERENCIASSAT  CHECK (SATISFACCION IS NULL OR SATISFACCION BETWEEN 1 AND 5)
);
CREATE INDEX IXSUGERENCIASESTADO ON TSUGERENCIAS (ESTADO, FCREACION DESC);
CREATE INDEX IXSUGERENCIASUSUARIO ON TSUGERENCIAS (CUSUARIO);
COMMENT ON TABLE TSUGERENCIAS IS 'Sugerencias, problemas y felicitaciones que envían clientes, vendedores y repartidores desde la app';
