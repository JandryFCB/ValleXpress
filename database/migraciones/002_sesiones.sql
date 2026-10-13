-- =============================================================================
-- 002 · SESIONES: sesión persistente, códigos de verificación y dispositivos
-- =============================================================================
-- Sesión persistente (como Uber o Rappi): el login entrega un token de acceso corto (15 min) y un
-- REFRESH TOKEN largo (90 días sin usar la app). Aquí solo se guarda el HASH del refresh token.
--   * Cada vez que se usa, se rota: el viejo queda marcado (FUSADO) y se crea uno nuevo de la misma familia.
--   * Si llega un token ya usado, es señal de robo: se revoca toda la familia (todas las sesiones del equipo).
--   * "Cerrar sesión" / "cerrar en todos los dispositivos" = marcar FREVOCADO.
-- Las tres tablas son SIMPLES (sin historial): son movimientos que se insertan y se consumen.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Propósito de un código de verificación (catálogo)
-- -----------------------------------------------------------------------------
CREATE TABLE TPROPOSITOSCODIGOID (
    CPROPOSITOCODIGO CHAR(3) NOT NULL,
    CONSTRAINT IPKPROPOSITOSCODIGOID PRIMARY KEY (CPROPOSITOCODIGO)
);
CREATE TABLE TPROPOSITOSCODIGO (
    CIDIOMA                 CHAR(2)       NOT NULL DEFAULT 'es',
    CPROPOSITOCODIGO        CHAR(3)       NOT NULL,
    FHASTA                  TIMESTAMPTZ   NOT NULL DEFAULT '2999-12-31 00:00:00-05',
    FDESDE                  TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    VERSIONCONTROL          INTEGER       NOT NULL DEFAULT 0,
    CUSUARIO_MODIFICACION   VARCHAR(30)   DEFAULT USUARIOACTUAL(),
    DESCRIPCION             VARCHAR(60)   NOT NULL,
    CONSTRAINT IPKPROPOSITOSCODIGO PRIMARY KEY (CIDIOMA, CPROPOSITOCODIGO, FHASTA),
    CONSTRAINT FKPROPCODPROPCODID FOREIGN KEY (CPROPOSITOCODIGO) REFERENCES TPROPOSITOSCODIGOID (CPROPOSITOCODIGO)
);
SELECT ACTIVARVERSION('TPROPOSITOSCODIGO');

INSERT INTO TPROPOSITOSCODIGOID (CPROPOSITOCODIGO) VALUES ('001'), ('002');
INSERT INTO TPROPOSITOSCODIGO (CPROPOSITOCODIGO, DESCRIPCION) VALUES ('001', 'Verificar correo'), ('002', 'Restablecer clave');

-- -----------------------------------------------------------------------------
-- Códigos de 6 dígitos (verificar correo antes de registrarse, recuperar clave)
-- -----------------------------------------------------------------------------
CREATE TABLE TCODIGOSVERIFICACION (
    SCODIGO             BIGINT        GENERATED ALWAYS AS IDENTITY,
    CPROPOSITOCODIGO    CHAR(3)       NOT NULL,
    CORREO              VARCHAR(150)  NOT NULL,
    CUSUARIO            VARCHAR(30),                              -- nulo si la cuenta aún no existe
    CODIGOHASH          VARCHAR(255)  NOT NULL,                   -- el código va con hash, nunca en claro
    NUMEROINTENTOS      SMALLINT      NOT NULL DEFAULT 0,
    MAXINTENTOS         SMALLINT      NOT NULL DEFAULT 5,
    IPSOLICITUD         INET,
    TOKENFCM            VARCHAR(255),                             -- para enviar el código también por push
    FCREACION           TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    FEXPIRA             TIMESTAMPTZ   NOT NULL,
    FVERIFICADO         TIMESTAMPTZ,                              -- cuándo se escribió bien
    FUSADO              TIMESTAMPTZ,                              -- cuándo se consumió (ya no sirve)
    CONSTRAINT IPKCODIGOSVERIFICACION PRIMARY KEY (SCODIGO),
    CONSTRAINT FKCODVERPROPCODID FOREIGN KEY (CPROPOSITOCODIGO) REFERENCES TPROPOSITOSCODIGOID (CPROPOSITOCODIGO),
    CONSTRAINT FKCODVERUSUID     FOREIGN KEY (CUSUARIO)         REFERENCES TUSUARIOSID (CUSUARIO),
    CONSTRAINT CKCODVERCORREO    CHECK (CORREO = lower(btrim(CORREO)))
);
CREATE INDEX IXCODVERBUSCAR ON TCODIGOSVERIFICACION (CPROPOSITOCODIGO, CORREO, FCREACION DESC);

-- -----------------------------------------------------------------------------
-- Sesiones persistentes (refresh tokens)
-- -----------------------------------------------------------------------------
CREATE TABLE TSESIONES (
    SSESION             BIGINT        GENERATED ALWAYS AS IDENTITY,
    CUSUARIO            VARCHAR(30)   NOT NULL,
    CFAMILIA            UUID          NOT NULL,                   -- agrupa los tokens rotados de un mismo equipo
    TOKENHASH           CHAR(64)      NOT NULL,                   -- SHA-256 del refresh token (nunca el token)
    DISPOSITIVO         VARCHAR(100),                             -- "Samsung A14", "Chrome"...
    PLATAFORMA          VARCHAR(10),
    IPCREACION          INET,
    FCREACION           TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    FEXPIRA             TIMESTAMPTZ   NOT NULL,                   -- 90 días desde su creación (se renueva al rotar)
    FUSADO              TIMESTAMPTZ,                              -- cuándo se cambió por uno nuevo
    FREVOCADO           TIMESTAMPTZ,                              -- cierre de sesión o sospecha de robo
    MOTIVOREVOCACION    VARCHAR(30),                              -- CIERRE, CIERRETODAS, REUSO, CLAVE, DESACTIVADA
    CONSTRAINT IPKSESIONES PRIMARY KEY (SSESION),
    CONSTRAINT FKSESIONESUSUID FOREIGN KEY (CUSUARIO) REFERENCES TUSUARIOSID (CUSUARIO),
    CONSTRAINT UQSESIONESTOKEN UNIQUE (TOKENHASH),
    CONSTRAINT CKSESIONESPLAT CHECK (PLATAFORMA IS NULL OR PLATAFORMA IN ('ANDROID', 'IOS', 'WEB'))
);
CREATE INDEX IXSESIONESUSUARIO ON TSESIONES (CUSUARIO) WHERE FREVOCADO IS NULL;
CREATE INDEX IXSESIONESFAMILIA ON TSESIONES (CFAMILIA);

-- Revoca todas las sesiones de una familia (token robado) o de un usuario (cambio de clave, cuenta desactivada)
CREATE FUNCTION REVOCARSESIONES(p_cusuario VARCHAR, p_motivo VARCHAR, p_cfamilia UUID DEFAULT NULL)
RETURNS INTEGER LANGUAGE sql AS $$
  WITH r AS (
    UPDATE TSESIONES SET FREVOCADO = clock_timestamp(), MOTIVOREVOCACION = p_motivo
     WHERE CUSUARIO = p_cusuario AND FREVOCADO IS NULL AND (p_cfamilia IS NULL OR CFAMILIA = p_cfamilia)
    RETURNING 1)
  SELECT count(*)::INTEGER FROM r
$$;

-- -----------------------------------------------------------------------------
-- Dispositivos (token de Firebase para notificaciones push)
-- -----------------------------------------------------------------------------
CREATE TABLE TDISPOSITIVOS (
    SDISPOSITIVO        BIGINT        GENERATED ALWAYS AS IDENTITY,
    CUSUARIO            VARCHAR(30)   NOT NULL,
    TOKENFCM            VARCHAR(255)  NOT NULL,
    PLATAFORMA          VARCHAR(10)   NOT NULL DEFAULT 'ANDROID',
    MODELO              VARCHAR(100),
    VERSIONAPP          VARCHAR(20),
    ESACTIVO            BOOLEAN       NOT NULL DEFAULT TRUE,      -- se apaga si Firebase dice que el token ya no existe
    FCREACION           TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    FULTIMOUSO          TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT IPKDISPOSITIVOS PRIMARY KEY (SDISPOSITIVO),
    CONSTRAINT FKDISPOSITIVOSUSUID FOREIGN KEY (CUSUARIO) REFERENCES TUSUARIOSID (CUSUARIO),
    CONSTRAINT UQDISPOSITIVOSTOKEN UNIQUE (TOKENFCM),          -- un token pertenece a un solo usuario a la vez
    CONSTRAINT CKDISPOSITIVOSPLAT CHECK (PLATAFORMA IN ('ANDROID', 'IOS', 'WEB'))
);
CREATE INDEX IXDISPOSITIVOSUSUARIO ON TDISPOSITIVOS (CUSUARIO) WHERE ESACTIVO;

-- -----------------------------------------------------------------------------
-- Limpieza (programar a diario): códigos vencidos hace más de 2 días, sesiones vencidas o cerradas hace más de 30
-- -----------------------------------------------------------------------------
CREATE FUNCTION PURGARSESIONES() RETURNS TABLE (codigos INTEGER, sesiones INTEGER) LANGUAGE plpgsql AS $$
DECLARE c INTEGER; s INTEGER;
BEGIN
    DELETE FROM TCODIGOSVERIFICACION WHERE FEXPIRA < now() - interval '2 days';
    GET DIAGNOSTICS c = ROW_COUNT;
    DELETE FROM TSESIONES WHERE COALESCE(FREVOCADO, FEXPIRA) < now() - interval '30 days';
    GET DIAGNOSTICS s = ROW_COUNT;
    RETURN QUERY SELECT c, s;
END $$;

-- -----------------------------------------------------------------------------
-- COMENTARIOS
-- -----------------------------------------------------------------------------
COMMENT ON TABLE TPROPOSITOSCODIGOID IS 'Códigos de propósito de verificación (destino de las FK)';
COMMENT ON TABLE TPROPOSITOSCODIGO IS 'Para qué se envía un código: 001 verificar correo, 002 restablecer clave';
COMMENT ON TABLE TCODIGOSVERIFICACION IS 'Códigos de 6 dígitos enviados por correo/push. Con hash, caducan y limitan intentos. Sin historial';
COMMENT ON TABLE TSESIONES IS 'Sesiones persistentes: un refresh token (solo su hash) por equipo, con rotación y revocación. Sin historial';
COMMENT ON TABLE TDISPOSITIVOS IS 'Celulares con token de Firebase para notificaciones push. Sin historial';

COMMENT ON COLUMN TCODIGOSVERIFICACION.SCODIGO IS 'Secuencia del código';
COMMENT ON COLUMN TCODIGOSVERIFICACION.CUSUARIO IS 'Cuenta a la que pertenece (nulo si aún no se registra)';
COMMENT ON COLUMN TCODIGOSVERIFICACION.CODIGOHASH IS 'Hash bcrypt del código de 6 dígitos';
COMMENT ON COLUMN TCODIGOSVERIFICACION.NUMEROINTENTOS IS 'Intentos fallidos al escribir el código';
COMMENT ON COLUMN TCODIGOSVERIFICACION.MAXINTENTOS IS 'Intentos permitidos antes de pedir un código nuevo';
COMMENT ON COLUMN TCODIGOSVERIFICACION.FVERIFICADO IS 'Cuándo el usuario escribió bien el código';
COMMENT ON COLUMN TCODIGOSVERIFICACION.FUSADO IS 'Cuándo se consumió; después ya no sirve';
COMMENT ON COLUMN TSESIONES.SSESION IS 'Secuencia de la sesión';
COMMENT ON COLUMN TSESIONES.CFAMILIA IS 'Agrupa los refresh tokens rotados de un mismo equipo; si se reusa uno viejo se revoca toda la familia';
COMMENT ON COLUMN TSESIONES.TOKENHASH IS 'SHA-256 del refresh token; el token en claro solo lo tiene la app';
COMMENT ON COLUMN TSESIONES.FEXPIRA IS 'Vence a los 90 días de su creación; cada rotación entrega uno nuevo';
COMMENT ON COLUMN TSESIONES.FUSADO IS 'Cuándo se cambió por un token nuevo (rotación)';
COMMENT ON COLUMN TSESIONES.FREVOCADO IS 'Cierre de sesión o sospecha de robo; la sesión deja de servir';
COMMENT ON COLUMN TSESIONES.MOTIVOREVOCACION IS 'CIERRE, CIERRETODAS, REUSO, CLAVE o DESACTIVADA';
COMMENT ON COLUMN TDISPOSITIVOS.TOKENFCM IS 'Token de Firebase del celular; único en toda la tabla';
COMMENT ON COLUMN TDISPOSITIVOS.ESACTIVO IS 'Falso cuando Firebase informa que el token ya no es válido';
