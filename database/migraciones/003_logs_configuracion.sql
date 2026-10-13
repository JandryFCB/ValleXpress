-- =============================================================================
-- 003 · CONFIGURACIÓN Y REGISTROS (logs, auditoría)
-- =============================================================================
--   TCONFIGURACIONES   parámetros del sistema (histórica sin tabla ID: nadie la referencia)
--   TLOGERRORES        errores técnicos del backend (los 5xx)                   · simple
--   TLOGMENSAJES       eventos del sistema (envíos de correo fallidos, etc.)      · simple
--   TAUDITORIA         acciones de los usuarios (login, cambio de clave...)       · simple
-- Los logs NO llevan FK a usuarios ni pedidos: un log nunca debe fallar por una referencia.
-- =============================================================================

CREATE TABLE TCONFIGURACIONES (
    CCONFIGURACION          VARCHAR(50)   NOT NULL,
    FHASTA                  TIMESTAMPTZ   NOT NULL DEFAULT '2999-12-31 00:00:00-05',
    FDESDE                  TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    VERSIONCONTROL          INTEGER       NOT NULL DEFAULT 0,
    CUSUARIO_MODIFICACION   VARCHAR(30)   DEFAULT USUARIOACTUAL(),
    VALOR                   JSONB         NOT NULL,
    DESCRIPCION             VARCHAR(200),
    CONSTRAINT IPKCONFIGURACIONES PRIMARY KEY (CCONFIGURACION, FHASTA),
    CONSTRAINT CKCONFIGURACIONESC CHECK (CCONFIGURACION = upper(CCONFIGURACION))
);
SELECT ACTIVARVERSION('TCONFIGURACIONES');

INSERT INTO TCONFIGURACIONES (CCONFIGURACION, VALOR, DESCRIPCION) VALUES
    ('VERSIONTERMINOS',      '"1.0"',  'Versión vigente de los términos y condiciones'),
    ('APROBACIONAUTOMATICA', 'true',   'Vendedores y repartidores nacen aprobados (mientras no exista el panel de administración)');

CREATE TABLE TLOGERRORES (
    SLOGERROR     BIGINT        GENERATED ALWAYS AS IDENTITY,
    FCREACION     TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    NIVEL         VARCHAR(10)   NOT NULL DEFAULT 'ERROR',
    MODULO        VARCHAR(40)   NOT NULL,
    ORIGEN        VARCHAR(20)   NOT NULL DEFAULT 'BACKEND',
    CODIGO        VARCHAR(50),
    MENSAJE       TEXT          NOT NULL,
    STACK         TEXT,
    HUELLA        CHAR(64),                                -- agrupa errores iguales
    METODO        VARCHAR(10),
    RUTA          VARCHAR(500),
    ESTADOHTTP    SMALLINT,
    PARAMETROS    JSONB,
    CUERPO        JSONB,
    CUSUARIO      VARCHAR(30),
    CPEDIDO       VARCHAR(30),
    SOLICITUDID   VARCHAR(64),
    IP            INET,
    USERAGENT     VARCHAR(300),
    ENTORNO       VARCHAR(20),
    CONSTRAINT IPKLOGERRORES PRIMARY KEY (SLOGERROR)
);
CREATE INDEX IXLOGERRORESFECHA ON TLOGERRORES (FCREACION DESC);
CREATE INDEX IXLOGERRORESHUELLA ON TLOGERRORES (HUELLA);

CREATE TABLE TLOGMENSAJES (
    SLOGMENSAJE   BIGINT        GENERATED ALWAYS AS IDENTITY,
    FCREACION     TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    NIVEL         VARCHAR(12)   NOT NULL DEFAULT 'INFO',
    MODULO        VARCHAR(40)   NOT NULL,
    ACCION        VARCHAR(50),
    MENSAJE       TEXT          NOT NULL,
    DETALLE       JSONB         NOT NULL DEFAULT '{}',
    CUSUARIO      VARCHAR(30),
    CPEDIDO       VARCHAR(30),
    SOLICITUDID   VARCHAR(64),
    IP            INET,
    ENTORNO       VARCHAR(20),
    CONSTRAINT IPKLOGMENSAJES PRIMARY KEY (SLOGMENSAJE)
);
CREATE INDEX IXLOGMENSAJESFECHA ON TLOGMENSAJES (FCREACION DESC);

CREATE TABLE TAUDITORIA (
    SAUDITORIA    BIGINT        GENERATED ALWAYS AS IDENTITY,
    FCREACION     TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    CUSUARIO      VARCHAR(30),
    ACCION        VARCHAR(50)   NOT NULL,                  -- LOGIN, LOGINFALLIDO, REGISTRO, CAMBIOCLAVE...
    ENTIDAD       VARCHAR(40),
    ENTIDADID     VARCHAR(40),
    DETALLE       JSONB         NOT NULL DEFAULT '{}',
    IP            INET,
    USERAGENT     VARCHAR(300),
    CONSTRAINT IPKAUDITORIA PRIMARY KEY (SAUDITORIA)
);
CREATE INDEX IXAUDITORIAUSUARIO ON TAUDITORIA (CUSUARIO, FCREACION DESC);

-- Limpieza (programar a diario): mensajes de más de 30 días y errores de más de 180
CREATE FUNCTION PURGARLOGS(p_diasmensajes INT DEFAULT 30, p_diaserrores INT DEFAULT 180)
RETURNS TABLE (mensajes INTEGER, errores INTEGER) LANGUAGE plpgsql AS $$
DECLARE m INTEGER; e INTEGER;
BEGIN
    DELETE FROM TLOGMENSAJES WHERE FCREACION < now() - make_interval(days => p_diasmensajes);
    GET DIAGNOSTICS m = ROW_COUNT;
    DELETE FROM TLOGERRORES WHERE FCREACION < now() - make_interval(days => p_diaserrores);
    GET DIAGNOSTICS e = ROW_COUNT;
    RETURN QUERY SELECT m, e;
END $$;

COMMENT ON TABLE TCONFIGURACIONES IS 'Parámetros del sistema (clave en mayúsculas, valor JSON). Con historial';
COMMENT ON TABLE TLOGERRORES IS 'Errores técnicos del backend (5xx). Sin historial, sin FK a propósito';
COMMENT ON TABLE TLOGMENSAJES IS 'Eventos del sistema (avisos, envíos fallidos). Sin historial, sin FK a propósito';
COMMENT ON TABLE TAUDITORIA IS 'Acciones de los usuarios (login, registro, cambio de clave). Sin historial, sin FK a propósito';
COMMENT ON COLUMN TLOGERRORES.HUELLA IS 'SHA-256 de módulo+código+mensaje: agrupa errores repetidos';
