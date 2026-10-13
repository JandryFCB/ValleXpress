-- =============================================================================
-- 001 · IDENTIDAD: roles, estatus, documentos, personas, usuarios y teléfonos
-- =============================================================================
-- Códigos: las entidades usan números (1, 2, 3...). El 1 es SIEMPRE el administrador: se inserta a mano
-- y las secuencias arrancan en 2. Los catálogos usan códigos de 3 caracteres ('001', '002'...).
-- Los permisos se deciden por ROL (TROLES), nunca por "CPERSONA = 1".
--
--   TPERSONASID / TPERSONAS          la persona (documento, nombres, correo)
--   TUSUARIOSID / TUSUARIOS          la cuenta de acceso (CUSUARIO = nombre para iniciar sesión: jcayapa)
--   TUSUARIOSACCESO                  estado de acceso que cambia en cada login (intentos, último ingreso).
--                                    Va aparte, SIN historial, para no llenar TUSUARIOS de versiones.
--   TPERSONATELEFONOS                teléfonos de la persona (varios, uno principal)
--   TROLES, TESTATUSUSUARIO, TTIPOSDOCUMENTO   catálogos (ID + histórica con idioma)
-- =============================================================================

CREATE SEQUENCE SECPERSONAS START WITH 2;      -- el 1 es el administrador

-- -----------------------------------------------------------------------------
-- CATÁLOGOS (variante "catálogo con idioma": ID (CCODIGO) + histórica (CIDIOMA, CCODIGO, FHASTA))
-- -----------------------------------------------------------------------------
CREATE TABLE TROLESID (
    CROL CHAR(3) NOT NULL,
    CONSTRAINT IPKROLESID PRIMARY KEY (CROL)
);
CREATE TABLE TROLES (
    CIDIOMA                 CHAR(2)       NOT NULL DEFAULT 'es',
    CROL                    CHAR(3)       NOT NULL,
    FHASTA                  TIMESTAMPTZ   NOT NULL DEFAULT '2999-12-31 00:00:00-05',
    FDESDE                  TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    VERSIONCONTROL          INTEGER       NOT NULL DEFAULT 0,
    CUSUARIO_MODIFICACION   VARCHAR(30)   DEFAULT USUARIOACTUAL(),
    DESCRIPCION             VARCHAR(60)   NOT NULL,
    CONSTRAINT IPKROLES PRIMARY KEY (CIDIOMA, CROL, FHASTA),
    CONSTRAINT FKROLESROLESID FOREIGN KEY (CROL) REFERENCES TROLESID (CROL)
);
SELECT ACTIVARVERSION('TROLES');

CREATE TABLE TESTATUSUSUARIOID (
    CESTATUSUSUARIO CHAR(3) NOT NULL,
    CONSTRAINT IPKESTATUSUSUARIOID PRIMARY KEY (CESTATUSUSUARIO)
);
CREATE TABLE TESTATUSUSUARIO (
    CIDIOMA                 CHAR(2)       NOT NULL DEFAULT 'es',
    CESTATUSUSUARIO         CHAR(3)       NOT NULL,
    FHASTA                  TIMESTAMPTZ   NOT NULL DEFAULT '2999-12-31 00:00:00-05',
    FDESDE                  TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    VERSIONCONTROL          INTEGER       NOT NULL DEFAULT 0,
    CUSUARIO_MODIFICACION   VARCHAR(30)   DEFAULT USUARIOACTUAL(),
    DESCRIPCION             VARCHAR(60)   NOT NULL,
    CONSTRAINT IPKESTATUSUSUARIO PRIMARY KEY (CIDIOMA, CESTATUSUSUARIO, FHASTA),
    CONSTRAINT FKESTUSUESTUSUID FOREIGN KEY (CESTATUSUSUARIO) REFERENCES TESTATUSUSUARIOID (CESTATUSUSUARIO)
);
SELECT ACTIVARVERSION('TESTATUSUSUARIO');

CREATE TABLE TTIPOSDOCUMENTOID (
    CTIPODOCUMENTO CHAR(3) NOT NULL,
    CONSTRAINT IPKTIPOSDOCUMENTOID PRIMARY KEY (CTIPODOCUMENTO)
);
CREATE TABLE TTIPOSDOCUMENTO (
    CIDIOMA                 CHAR(2)       NOT NULL DEFAULT 'es',
    CTIPODOCUMENTO          CHAR(3)       NOT NULL,
    FHASTA                  TIMESTAMPTZ   NOT NULL DEFAULT '2999-12-31 00:00:00-05',
    FDESDE                  TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    VERSIONCONTROL          INTEGER       NOT NULL DEFAULT 0,
    CUSUARIO_MODIFICACION   VARCHAR(30)   DEFAULT USUARIOACTUAL(),
    DESCRIPCION             VARCHAR(60)   NOT NULL,
    CONSTRAINT IPKTIPOSDOCUMENTO PRIMARY KEY (CIDIOMA, CTIPODOCUMENTO, FHASTA),
    CONSTRAINT FKTIPDOCTIPDOCID FOREIGN KEY (CTIPODOCUMENTO) REFERENCES TTIPOSDOCUMENTOID (CTIPODOCUMENTO)
);
SELECT ACTIVARVERSION('TTIPOSDOCUMENTO');

-- -----------------------------------------------------------------------------
-- PERSONAS
-- -----------------------------------------------------------------------------
CREATE TABLE TPERSONASID (
    CPERSONA BIGINT NOT NULL DEFAULT nextval('secpersonas'),
    CONSTRAINT IPKPERSONASID PRIMARY KEY (CPERSONA)
);
CREATE TABLE TPERSONAS (
    CPERSONA                BIGINT        NOT NULL,
    FHASTA                  TIMESTAMPTZ   NOT NULL DEFAULT '2999-12-31 00:00:00-05',
    FDESDE                  TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    VERSIONCONTROL          INTEGER       NOT NULL DEFAULT 0,
    CUSUARIO_MODIFICACION   VARCHAR(30)   DEFAULT USUARIOACTUAL(),
    CTIPODOCUMENTO          CHAR(3)       NOT NULL DEFAULT '001',
    NUMERODOCUMENTO         VARCHAR(20)   NOT NULL,
    NOMBRES                 VARCHAR(100)  NOT NULL,
    APELLIDOS               VARCHAR(100)  NOT NULL,
    CORREO                  VARCHAR(150)  NOT NULL,
    FCORREOVERIFICADO       TIMESTAMPTZ,
    FNACIMIENTO             DATE,
    CONSTRAINT IPKPERSONAS PRIMARY KEY (CPERSONA, FHASTA),
    CONSTRAINT FKPERSONASPERSID FOREIGN KEY (CPERSONA) REFERENCES TPERSONASID (CPERSONA),
    CONSTRAINT FKPERSONASTIPDOC FOREIGN KEY (CTIPODOCUMENTO) REFERENCES TTIPOSDOCUMENTOID (CTIPODOCUMENTO),
    CONSTRAINT CKPERSONASCORREO CHECK (CORREO = lower(btrim(CORREO)) AND CORREO LIKE '%_@_%')
);
-- Unicidad solo entre las filas VIGENTES (las cerradas del historial pueden repetir valores)
CREATE UNIQUE INDEX UQPERSONASCORREO ON TPERSONAS (CORREO) WHERE FHASTA = '2999-12-31 00:00:00-05';
CREATE UNIQUE INDEX UQPERSONASDOC    ON TPERSONAS (CTIPODOCUMENTO, NUMERODOCUMENTO) WHERE FHASTA = '2999-12-31 00:00:00-05';
SELECT ACTIVARVERSION('TPERSONAS');

-- Si el INSERT no trae CPERSONA se toma el siguiente de la secuencia; el ancla (TPERSONASID) se crea sola
CREATE FUNCTION FNASIGNARPERSONA() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.CPERSONA IS NULL THEN
        INSERT INTO TPERSONASID DEFAULT VALUES RETURNING CPERSONA INTO NEW.CPERSONA;
    ELSE
        INSERT INTO TPERSONASID (CPERSONA) VALUES (NEW.CPERSONA) ON CONFLICT DO NOTHING;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER TRPERSONASASIGNAR BEFORE INSERT ON TPERSONAS FOR EACH ROW EXECUTE FUNCTION FNASIGNARPERSONA();

-- -----------------------------------------------------------------------------
-- USUARIOS
-- -----------------------------------------------------------------------------
CREATE TABLE TUSUARIOSID (
    CUSUARIO VARCHAR(30) NOT NULL,
    CONSTRAINT IPKUSUARIOSID PRIMARY KEY (CUSUARIO),
    CONSTRAINT CKUSUARIOSID CHECK (CUSUARIO = lower(CUSUARIO) AND CUSUARIO ~ '^[a-z0-9]{3,30}$')
);
CREATE TABLE TUSUARIOS (
    CUSUARIO                VARCHAR(30)   NOT NULL,
    FHASTA                  TIMESTAMPTZ   NOT NULL DEFAULT '2999-12-31 00:00:00-05',
    FDESDE                  TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    VERSIONCONTROL          INTEGER       NOT NULL DEFAULT 0,
    CUSUARIO_MODIFICACION   VARCHAR(30)   DEFAULT USUARIOACTUAL(),
    CPERSONA                BIGINT        NOT NULL,
    CROL                    CHAR(3)       NOT NULL,
    CESTATUSUSUARIO         CHAR(3)       NOT NULL DEFAULT '001',
    CLAVEHASH               VARCHAR(255)  NOT NULL,
    FCLAVECAMBIO            TIMESTAMPTZ,
    FTERMINOS               TIMESTAMPTZ,
    VERSIONTERMINOS         VARCHAR(20),
    CONSTRAINT IPKUSUARIOS PRIMARY KEY (CUSUARIO, FHASTA),
    CONSTRAINT FKUSUARIOSUSUID  FOREIGN KEY (CUSUARIO)        REFERENCES TUSUARIOSID (CUSUARIO),
    CONSTRAINT FKUSUARIOSPERSID FOREIGN KEY (CPERSONA)        REFERENCES TPERSONASID (CPERSONA),
    CONSTRAINT FKUSUARIOSROLID  FOREIGN KEY (CROL)            REFERENCES TROLESID (CROL),
    CONSTRAINT FKUSUARIOSESTID  FOREIGN KEY (CESTATUSUSUARIO) REFERENCES TESTATUSUSUARIOID (CESTATUSUSUARIO)
);
CREATE UNIQUE INDEX UQUSUARIOSPERSONA ON TUSUARIOS (CPERSONA) WHERE FHASTA = '2999-12-31 00:00:00-05';
CREATE INDEX IXUSUARIOSROL ON TUSUARIOS (CROL) WHERE FHASTA = '2999-12-31 00:00:00-05';
SELECT ACTIVARVERSION('TUSUARIOS');

-- Estado de acceso: cambia en cada login, por eso NO lleva historial (una fila por usuario)
CREATE TABLE TUSUARIOSACCESO (
    CUSUARIO              VARCHAR(30) NOT NULL,
    NUMEROINTENTOS        SMALLINT    NOT NULL DEFAULT 0,        -- claves incorrectas seguidas
    FBLOQUEADOHASTA       TIMESTAMPTZ,                           -- bloqueo temporal por intentos fallidos
    FULTIMACONEXION       TIMESTAMPTZ,
    IPULTIMACONEXION      INET,
    CONSTRAINT IPKUSUARIOSACCESO PRIMARY KEY (CUSUARIO),
    CONSTRAINT FKUSUACCUSUID FOREIGN KEY (CUSUARIO) REFERENCES TUSUARIOSID (CUSUARIO)
);

-- Genera el CUSUARIO a partir del nombre: jcayapa, jecayapa, jcayapa2...
CREATE FUNCTION GENERARUSUARIO(p_nombres TEXT, p_apellidos TEXT) RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE
    particulas  TEXT[] := ARRAY['de','del','la','las','los','y','e'];
    reservados  TEXT[] := ARRAY['admin','administrador','root','soporte','sistema','vallexpress','api','null'];
    n  TEXT[] := ARRAY(SELECT w FROM unnest(regexp_split_to_array(btrim(LIMPIARTEXTO(p_nombres)),   '\s+')) w WHERE w <> '' AND w <> ALL(particulas));
    a  TEXT[] := ARRAY(SELECT w FROM unnest(regexp_split_to_array(btrim(LIMPIARTEXTO(p_apellidos)), '\s+')) w WHERE w <> '' AND w <> ALL(particulas));
    n1 TEXT := n[1];  n2 TEXT := n[2];  a1 TEXT := a[1];  a2 TEXT := a[2];
    candidatos TEXT[] := '{}';
    base TEXT;  c TEXT;  i INT := 1;
BEGIN
    IF a1 IS NULL THEN a1 := n1; n1 := n2; n2 := NULL; END IF;       -- sin apellido útil: se usa el nombre
    IF a1 IS NULL THEN a1 := 'usuario'; END IF;                      -- sin nada utilizable
    a1 := left(a1, 22);

    candidatos := candidatos || (COALESCE(left(n1, 1), '') || a1);
    IF n2 IS NOT NULL THEN candidatos := candidatos || (left(n1, 1) || left(n2, 1) || a1); END IF;
    IF a2 IS NOT NULL THEN candidatos := candidatos || (COALESCE(left(n1, 1), '') || a1 || left(a2, 1)); END IF;
    IF n2 IS NOT NULL AND a2 IS NOT NULL THEN candidatos := candidatos || (left(n1, 1) || left(n2, 1) || a1 || left(a2, 1)); END IF;

    base := candidatos[1];
    IF length(base) < 3 THEN base := COALESCE(n1, '') || a1; candidatos[1] := base; END IF;
    IF length(base) < 3 THEN base := base || 'usr'; candidatos[1] := base; END IF;

    FOREACH c IN ARRAY candidatos LOOP
        IF length(c) >= 3 AND c <> ALL(reservados)
           AND NOT EXISTS (SELECT 1 FROM TUSUARIOSID WHERE CUSUARIO = c) THEN
            RETURN c;
        END IF;
    END LOOP;

    LOOP                                                             -- jcayapa2, jcayapa3...
        i := i + 1;
        c := left(base, 30 - length(i::TEXT)) || i::TEXT;
        IF NOT EXISTS (SELECT 1 FROM TUSUARIOSID WHERE CUSUARIO = c) THEN RETURN c; END IF;
    END LOOP;
END $$;

-- Si el INSERT no trae CUSUARIO se genera del nombre de la persona; el ancla y la fila de acceso se crean solas
CREATE FUNCTION FNASIGNARUSUARIO() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.CUSUARIO IS NULL OR btrim(NEW.CUSUARIO) = '' THEN
        PERFORM pg_advisory_xact_lock(hashtext('tusuarios.cusuario'));   -- de a uno: evita nombres repetidos
        SELECT GENERARUSUARIO(NOMBRES, APELLIDOS) INTO NEW.CUSUARIO
          FROM TPERSONAS WHERE CPERSONA = NEW.CPERSONA AND FHASTA = '2999-12-31 00:00:00-05';
    ELSE
        NEW.CUSUARIO := lower(btrim(NEW.CUSUARIO));
    END IF;
    INSERT INTO TUSUARIOSID (CUSUARIO) VALUES (NEW.CUSUARIO) ON CONFLICT DO NOTHING;
    INSERT INTO TUSUARIOSACCESO (CUSUARIO) VALUES (NEW.CUSUARIO) ON CONFLICT DO NOTHING;
    RETURN NEW;
END $$;
CREATE TRIGGER TRUSUARIOSASIGNAR BEFORE INSERT ON TUSUARIOS FOR EACH ROW EXECUTE FUNCTION FNASIGNARUSUARIO();

-- -----------------------------------------------------------------------------
-- TELÉFONOS (hija de la persona: histórica sin tabla ID, nadie la referencia)
-- -----------------------------------------------------------------------------
CREATE TABLE TPERSONATELEFONOS (
    CPERSONA                BIGINT        NOT NULL,
    STELEFONO               SMALLINT      NOT NULL,                 -- 1, 2, 3... dentro de cada persona
    FHASTA                  TIMESTAMPTZ   NOT NULL DEFAULT '2999-12-31 00:00:00-05',
    FDESDE                  TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    VERSIONCONTROL          INTEGER       NOT NULL DEFAULT 0,
    CUSUARIO_MODIFICACION   VARCHAR(30)   DEFAULT USUARIOACTUAL(),
    NUMEROTELEFONO          VARCHAR(20)   NOT NULL,
    ESPRINCIPAL             BOOLEAN       NOT NULL DEFAULT FALSE,
    FVERIFICADO             TIMESTAMPTZ,
    CONSTRAINT IPKPERSONATELEFONOS PRIMARY KEY (CPERSONA, STELEFONO, FHASTA),
    CONSTRAINT FKPERTELPERSID FOREIGN KEY (CPERSONA) REFERENCES TPERSONASID (CPERSONA)
);
CREATE UNIQUE INDEX UQPERSONATELNUMERO    ON TPERSONATELEFONOS (NUMEROTELEFONO) WHERE FHASTA = '2999-12-31 00:00:00-05';
CREATE UNIQUE INDEX UQPERSONATELPRINCIPAL ON TPERSONATELEFONOS (CPERSONA) WHERE ESPRINCIPAL AND FHASTA = '2999-12-31 00:00:00-05';
SELECT ACTIVARVERSION('TPERSONATELEFONOS');

CREATE FUNCTION FNASIGNARTELEFONO() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.STELEFONO IS NULL THEN
        PERFORM pg_advisory_xact_lock(hashtext('tpersonatelefonos'), NEW.CPERSONA::INT);
        SELECT COALESCE(MAX(STELEFONO), 0) + 1 INTO NEW.STELEFONO FROM TPERSONATELEFONOS WHERE CPERSONA = NEW.CPERSONA;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER TRPERSONATELASIGNAR BEFORE INSERT ON TPERSONATELEFONOS FOR EACH ROW EXECUTE FUNCTION FNASIGNARTELEFONO();

-- -----------------------------------------------------------------------------
-- DATOS INICIALES
-- -----------------------------------------------------------------------------
INSERT INTO TROLESID (CROL) VALUES ('001'), ('002'), ('003'), ('004');
INSERT INTO TROLES (CROL, DESCRIPCION) VALUES ('001', 'Cliente'), ('002', 'Vendedor'), ('003', 'Repartidor'), ('004', 'Administrador');

INSERT INTO TESTATUSUSUARIOID (CESTATUSUSUARIO) VALUES ('001'), ('002'), ('003');
INSERT INTO TESTATUSUSUARIO (CESTATUSUSUARIO, DESCRIPCION) VALUES ('001', 'Activo'), ('002', 'Inactivo'), ('003', 'Bloqueado');

INSERT INTO TTIPOSDOCUMENTOID (CTIPODOCUMENTO) VALUES ('001'), ('002'), ('003');
INSERT INTO TTIPOSDOCUMENTO (CTIPODOCUMENTO, DESCRIPCION) VALUES ('001', 'Cédula'), ('002', 'RUC'), ('003', 'Pasaporte');

-- El administrador: CPERSONA = 1. Su clave es '!' (ningún hash la acepta): no puede iniciar sesión hasta
-- que se le asigne una clave real (pendiente: script de creación del administrador).
INSERT INTO TPERSONAS (CPERSONA, CTIPODOCUMENTO, NUMERODOCUMENTO, NOMBRES, APELLIDOS, CORREO)
VALUES (1, '001', '0000000000', 'Administrador', 'ValleXpress', 'admin@vallexpress.local');
INSERT INTO TUSUARIOS (CUSUARIO, CPERSONA, CROL, CLAVEHASH) VALUES ('admin', 1, '004', '!');

-- -----------------------------------------------------------------------------
-- COMENTARIOS
-- -----------------------------------------------------------------------------
COMMENT ON TABLE TROLESID IS 'Códigos de roles (destino de las FK)';
COMMENT ON TABLE TROLES IS 'Roles del sistema: 001 cliente, 002 vendedor, 003 repartidor, 004 administrador';
COMMENT ON TABLE TESTATUSUSUARIOID IS 'Códigos de estatus de usuario (destino de las FK)';
COMMENT ON TABLE TESTATUSUSUARIO IS 'Estatus de la cuenta: 001 activo, 002 inactivo, 003 bloqueado';
COMMENT ON TABLE TTIPOSDOCUMENTOID IS 'Códigos de tipo de documento (destino de las FK)';
COMMENT ON TABLE TTIPOSDOCUMENTO IS 'Tipos de documento de identidad: 001 cédula, 002 RUC, 003 pasaporte';
COMMENT ON TABLE TPERSONASID IS 'Código de cada persona (el 1 es el administrador; las demás desde el 2)';
COMMENT ON TABLE TPERSONAS IS 'Datos de la persona, con historial (FHASTA = 2999-12-31 es la versión vigente)';
COMMENT ON TABLE TUSUARIOSID IS 'Nombre de usuario (login) de cada cuenta; no cambia nunca';
COMMENT ON TABLE TUSUARIOS IS 'Cuenta de acceso de una persona: rol, estatus y clave. Con historial';
COMMENT ON TABLE TUSUARIOSACCESO IS 'Estado de acceso que cambia en cada login (sin historial a propósito)';
COMMENT ON TABLE TPERSONATELEFONOS IS 'Teléfonos de la persona; uno solo puede ser principal. Con historial';

COMMENT ON COLUMN TPERSONAS.CPERSONA IS 'Código de la persona (TPERSONASID)';
COMMENT ON COLUMN TPERSONAS.CTIPODOCUMENTO IS 'Tipo de documento (TTIPOSDOCUMENTOID)';
COMMENT ON COLUMN TPERSONAS.NUMERODOCUMENTO IS 'Número del documento de identidad';
COMMENT ON COLUMN TPERSONAS.CORREO IS 'Correo en minúsculas; único entre las personas vigentes';
COMMENT ON COLUMN TPERSONAS.FCORREOVERIFICADO IS 'Cuándo se verificó el correo (nulo = sin verificar)';
COMMENT ON COLUMN TPERSONAS.FNACIMIENTO IS 'Fecha de nacimiento';
COMMENT ON COLUMN TUSUARIOS.CUSUARIO IS 'Nombre de usuario para iniciar sesión (TUSUARIOSID)';
COMMENT ON COLUMN TUSUARIOS.CPERSONA IS 'Persona dueña de la cuenta (TPERSONASID); una persona, una cuenta';
COMMENT ON COLUMN TUSUARIOS.CROL IS 'Rol de la cuenta (TROLESID)';
COMMENT ON COLUMN TUSUARIOS.CESTATUSUSUARIO IS 'Estatus de la cuenta (TESTATUSUSUARIOID)';
COMMENT ON COLUMN TUSUARIOS.CLAVEHASH IS 'Clave con hash bcrypt; nunca en claro';
COMMENT ON COLUMN TUSUARIOS.FCLAVECAMBIO IS 'Último cambio de clave (invalida los enlaces de recuperación anteriores)';
COMMENT ON COLUMN TUSUARIOS.FTERMINOS IS 'Cuándo aceptó los términos y condiciones';
COMMENT ON COLUMN TUSUARIOS.VERSIONTERMINOS IS 'Versión de los términos que aceptó';
COMMENT ON COLUMN TUSUARIOSACCESO.NUMEROINTENTOS IS 'Claves incorrectas seguidas';
COMMENT ON COLUMN TUSUARIOSACCESO.FBLOQUEADOHASTA IS 'Hasta cuándo está bloqueada la cuenta por intentos fallidos';
COMMENT ON COLUMN TPERSONATELEFONOS.STELEFONO IS 'Secuencia del teléfono dentro de la persona (1, 2, 3...)';
COMMENT ON COLUMN TPERSONATELEFONOS.ESPRINCIPAL IS 'Teléfono principal (solo uno por persona)';
COMMENT ON COLUMN TPERSONATELEFONOS.FVERIFICADO IS 'Cuándo se verificó el teléfono (nulo = sin verificar)';
