-- =============================================================================
-- 005 · DIRECCIONES de la persona y TIPOS de dirección y de teléfono
-- =============================================================================
--   TTIPOSDIRECCION    catálogo: 001 casa, 002 trabajo, 003 familiar, 004 otro, 005 local del negocio
--   TTIPOSTELEFONO     catálogo: 001 móvil, 002 casa, 003 trabajo, 004 WhatsApp
--   TPERSONADIRECCIONESID / TPERSONADIRECCIONES   direcciones (casa, trabajo...) con su ubicación
--                      El ID existe porque otras tablas la van a referenciar: el local de un negocio y la
--                      dirección de entrega de un pedido.
--   TPERSONATELEFONOS  se le agrega el tipo de teléfono (migración de la tabla de 001)
-- Los códigos de las direcciones son números desde el 1 (solo personas y usuarios reservan el 1 para el admin).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Catálogos
-- -----------------------------------------------------------------------------
CREATE TABLE TTIPOSDIRECCIONID (
    CTIPODIRECCION CHAR(3) NOT NULL,
    CONSTRAINT IPKTIPOSDIRECCIONID PRIMARY KEY (CTIPODIRECCION)
);
CREATE TABLE TTIPOSDIRECCION (
    CIDIOMA                 CHAR(2)       NOT NULL DEFAULT 'es',
    CTIPODIRECCION          CHAR(3)       NOT NULL,
    FHASTA                  TIMESTAMPTZ   NOT NULL DEFAULT '2999-12-31 00:00:00-05',
    FDESDE                  TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    VERSIONCONTROL          INTEGER       NOT NULL DEFAULT 0,
    CUSUARIO_MODIFICACION   VARCHAR(30)   DEFAULT USUARIOACTUAL(),
    DESCRIPCION             VARCHAR(60)   NOT NULL,
    CONSTRAINT IPKTIPOSDIRECCION PRIMARY KEY (CIDIOMA, CTIPODIRECCION, FHASTA),
    CONSTRAINT FKTIPDIRTIPDIRID FOREIGN KEY (CTIPODIRECCION) REFERENCES TTIPOSDIRECCIONID (CTIPODIRECCION)
);
SELECT ACTIVARVERSION('TTIPOSDIRECCION');
INSERT INTO TTIPOSDIRECCIONID (CTIPODIRECCION) VALUES ('001'), ('002'), ('003'), ('004'), ('005');
INSERT INTO TTIPOSDIRECCION (CTIPODIRECCION, DESCRIPCION) VALUES
    ('001', 'Casa'), ('002', 'Trabajo'), ('003', 'Familiar'), ('004', 'Otro'), ('005', 'Local del negocio');

CREATE TABLE TTIPOSTELEFONOID (
    CTIPOTELEFONO CHAR(3) NOT NULL,
    CONSTRAINT IPKTIPOSTELEFONOID PRIMARY KEY (CTIPOTELEFONO)
);
CREATE TABLE TTIPOSTELEFONO (
    CIDIOMA                 CHAR(2)       NOT NULL DEFAULT 'es',
    CTIPOTELEFONO           CHAR(3)       NOT NULL,
    FHASTA                  TIMESTAMPTZ   NOT NULL DEFAULT '2999-12-31 00:00:00-05',
    FDESDE                  TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    VERSIONCONTROL          INTEGER       NOT NULL DEFAULT 0,
    CUSUARIO_MODIFICACION   VARCHAR(30)   DEFAULT USUARIOACTUAL(),
    DESCRIPCION             VARCHAR(60)   NOT NULL,
    CONSTRAINT IPKTIPOSTELEFONO PRIMARY KEY (CIDIOMA, CTIPOTELEFONO, FHASTA),
    CONSTRAINT FKTIPTELTIPTELID FOREIGN KEY (CTIPOTELEFONO) REFERENCES TTIPOSTELEFONOID (CTIPOTELEFONO)
);
SELECT ACTIVARVERSION('TTIPOSTELEFONO');
INSERT INTO TTIPOSTELEFONOID (CTIPOTELEFONO) VALUES ('001'), ('002'), ('003'), ('004');
INSERT INTO TTIPOSTELEFONO (CTIPOTELEFONO, DESCRIPCION) VALUES
    ('001', 'Móvil'), ('002', 'Casa'), ('003', 'Trabajo'), ('004', 'WhatsApp');

-- Los teléfonos que ya existían quedan como móvil (001)
ALTER TABLE TPERSONATELEFONOS
    ADD COLUMN CTIPOTELEFONO CHAR(3) NOT NULL DEFAULT '001',
    ADD CONSTRAINT FKPERTELTIPTELID FOREIGN KEY (CTIPOTELEFONO) REFERENCES TTIPOSTELEFONOID (CTIPOTELEFONO);
COMMENT ON COLUMN TPERSONATELEFONOS.CTIPOTELEFONO IS 'Tipo de teléfono (TTIPOSTELEFONOID): móvil, casa, trabajo, WhatsApp';

-- -----------------------------------------------------------------------------
-- Direcciones
-- -----------------------------------------------------------------------------
CREATE SEQUENCE SECDIRECCIONES;

CREATE TABLE TPERSONADIRECCIONESID (
    CDIRECCION BIGINT NOT NULL DEFAULT nextval('secdirecciones'),
    CONSTRAINT IPKPERSONADIRECCIONESID PRIMARY KEY (CDIRECCION)
);
CREATE TABLE TPERSONADIRECCIONES (
    CDIRECCION              BIGINT        NOT NULL,
    FHASTA                  TIMESTAMPTZ   NOT NULL DEFAULT '2999-12-31 00:00:00-05',
    FDESDE                  TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    VERSIONCONTROL          INTEGER       NOT NULL DEFAULT 0,
    CUSUARIO_MODIFICACION   VARCHAR(30)   DEFAULT USUARIOACTUAL(),
    CPERSONA                BIGINT        NOT NULL,
    CTIPODIRECCION          CHAR(3)       NOT NULL DEFAULT '001',
    NOMBRE                  VARCHAR(50),                              -- "Mi casa", "Oficina"
    DIRECCION               VARCHAR(500)  NOT NULL,
    REFERENCIA              VARCHAR(500),                             -- "Frente al parque, portón verde"
    INSTRUCCIONES           VARCHAR(500),                             -- indicaciones para el repartidor
    LATITUD                 NUMERIC(10,8) NOT NULL,
    LONGITUD                NUMERIC(11,8) NOT NULL,
    ESPREDETERMINADA        BOOLEAN       NOT NULL DEFAULT FALSE,
    CONSTRAINT IPKPERSONADIRECCIONES PRIMARY KEY (CDIRECCION, FHASTA),
    CONSTRAINT FKPERDIRDIRID   FOREIGN KEY (CDIRECCION)     REFERENCES TPERSONADIRECCIONESID (CDIRECCION),
    CONSTRAINT FKPERDIRPERSID  FOREIGN KEY (CPERSONA)       REFERENCES TPERSONASID (CPERSONA),
    CONSTRAINT FKPERDIRTIPDIR  FOREIGN KEY (CTIPODIRECCION) REFERENCES TTIPOSDIRECCIONID (CTIPODIRECCION),
    CONSTRAINT CKPERDIRLATITUD  CHECK (LATITUD  BETWEEN -90  AND 90),
    CONSTRAINT CKPERDIRLONGITUD CHECK (LONGITUD BETWEEN -180 AND 180)
);
CREATE INDEX IXPERSONADIRPERSONA ON TPERSONADIRECCIONES (CPERSONA) WHERE FHASTA = '2999-12-31 00:00:00-05';
-- Una sola predeterminada por persona (entre las vigentes)
CREATE UNIQUE INDEX UQPERSONADIRPRED ON TPERSONADIRECCIONES (CPERSONA)
    WHERE ESPREDETERMINADA AND CTIPODIRECCION <> '005' AND FHASTA = '2999-12-31 00:00:00-05';
SELECT ACTIVARVERSION('TPERSONADIRECCIONES');

-- Si el INSERT no trae CDIRECCION se toma el siguiente de la secuencia; el ancla se crea sola
CREATE FUNCTION FNASIGNARDIRECCION() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.CDIRECCION IS NULL THEN
        INSERT INTO TPERSONADIRECCIONESID DEFAULT VALUES RETURNING CDIRECCION INTO NEW.CDIRECCION;
    ELSE
        INSERT INTO TPERSONADIRECCIONESID (CDIRECCION) VALUES (NEW.CDIRECCION) ON CONFLICT DO NOTHING;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER TRPERSONADIRASIGNAR BEFORE INSERT ON TPERSONADIRECCIONES FOR EACH ROW EXECUTE FUNCTION FNASIGNARDIRECCION();

-- -----------------------------------------------------------------------------
-- Comentarios
-- -----------------------------------------------------------------------------
COMMENT ON TABLE TTIPOSDIRECCIONID IS 'Códigos de tipos de dirección (destino de las FK)';
COMMENT ON TABLE TTIPOSDIRECCION IS 'Tipos de dirección: 001 casa, 002 trabajo, 003 familiar, 004 otro, 005 local del negocio';
COMMENT ON TABLE TTIPOSTELEFONOID IS 'Códigos de tipos de teléfono (destino de las FK)';
COMMENT ON TABLE TTIPOSTELEFONO IS 'Tipos de teléfono: 001 móvil, 002 casa, 003 trabajo, 004 WhatsApp';
COMMENT ON TABLE TPERSONADIRECCIONESID IS 'Código de cada dirección (lo referencian el local de un negocio y los pedidos)';
COMMENT ON TABLE TPERSONADIRECCIONES IS 'Direcciones de la persona con su ubicación (latitud y longitud). Con historial';
COMMENT ON COLUMN TPERSONADIRECCIONES.CDIRECCION IS 'Código de la dirección (TPERSONADIRECCIONESID)';
COMMENT ON COLUMN TPERSONADIRECCIONES.CPERSONA IS 'Persona dueña de la dirección (TPERSONASID)';
COMMENT ON COLUMN TPERSONADIRECCIONES.CTIPODIRECCION IS 'Tipo de dirección (TTIPOSDIRECCIONID)';
COMMENT ON COLUMN TPERSONADIRECCIONES.NOMBRE IS 'Nombre corto que le pone el usuario: Mi casa, Oficina';
COMMENT ON COLUMN TPERSONADIRECCIONES.DIRECCION IS 'Dirección escrita (calle, barrio, número)';
COMMENT ON COLUMN TPERSONADIRECCIONES.REFERENCIA IS 'Referencia para ubicarla';
COMMENT ON COLUMN TPERSONADIRECCIONES.INSTRUCCIONES IS 'Indicaciones para el repartidor';
COMMENT ON COLUMN TPERSONADIRECCIONES.LATITUD IS 'Latitud de la ubicación en el mapa';
COMMENT ON COLUMN TPERSONADIRECCIONES.LONGITUD IS 'Longitud de la ubicación en el mapa';
COMMENT ON COLUMN TPERSONADIRECCIONES.ESPREDETERMINADA IS 'Dirección que se propone por defecto en un pedido (solo una por persona)';
