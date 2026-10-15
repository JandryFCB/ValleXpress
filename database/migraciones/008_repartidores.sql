-- =============================================================================
-- 008 · REPARTIDORES: perfil, estado en línea, ubicación y recorrido de cada entrega
-- =============================================================================
--   TTIPOSVEHICULO              catálogo: moto, auto, camioneta, bicicleta, a pie (con REQUIEREPLACA)
--   TREPARTIDORES               perfil del repartidor (vehículo, placa, aprobación)          · histórica
--   TREPARTIDORESESTADO         en línea, última ubicación, calificación y entregas         · simple
--   TREPARTIDORUBICACIONES      puntos del recorrido de cada entrega (cada ~15 s)           · simple
-- El repartidor es un usuario (CUSUARIO) con rol repartidor: no necesita código propio.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Catálogo de vehículos (con idioma)
-- -----------------------------------------------------------------------------
CREATE TABLE TTIPOSVEHICULOID (
    CTIPOVEHICULO CHAR(3) NOT NULL,
    CONSTRAINT IPKTIPOSVEHICULOID PRIMARY KEY (CTIPOVEHICULO)
);
CREATE TABLE TTIPOSVEHICULO (
    CIDIOMA                 CHAR(2)       NOT NULL DEFAULT 'es',
    CTIPOVEHICULO           CHAR(3)       NOT NULL,
    FHASTA                  TIMESTAMPTZ   NOT NULL DEFAULT '2999-12-31 00:00:00-05',
    FDESDE                  TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    VERSIONCONTROL          INTEGER       NOT NULL DEFAULT 0,
    CUSUARIO_MODIFICACION   VARCHAR(30)   DEFAULT USUARIOACTUAL(),
    DESCRIPCION             VARCHAR(60)   NOT NULL,
    REQUIEREPLACA           BOOLEAN       NOT NULL DEFAULT TRUE,
    CONSTRAINT IPKTIPOSVEHICULO PRIMARY KEY (CIDIOMA, CTIPOVEHICULO, FHASTA),
    CONSTRAINT FKTIPVEHTIPVEHID FOREIGN KEY (CTIPOVEHICULO) REFERENCES TTIPOSVEHICULOID (CTIPOVEHICULO)
);
SELECT ACTIVARVERSION('TTIPOSVEHICULO');
INSERT INTO TTIPOSVEHICULOID (CTIPOVEHICULO) VALUES ('001'), ('002'), ('003'), ('004'), ('005');
INSERT INTO TTIPOSVEHICULO (CTIPOVEHICULO, DESCRIPCION, REQUIEREPLACA) VALUES
    ('001', 'Moto', TRUE), ('002', 'Auto', TRUE), ('003', 'Camioneta', TRUE), ('004', 'Bicicleta', FALSE), ('005', 'A pie', FALSE);

-- -----------------------------------------------------------------------------
-- Perfil del repartidor (histórica: cada cambio de vehículo o placa queda registrado)
-- -----------------------------------------------------------------------------
CREATE TABLE TREPARTIDORES (
    CUSUARIO                VARCHAR(30)   NOT NULL,
    FHASTA                  TIMESTAMPTZ   NOT NULL DEFAULT '2999-12-31 00:00:00-05',
    FDESDE                  TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    VERSIONCONTROL          INTEGER       NOT NULL DEFAULT 0,
    CUSUARIO_MODIFICACION   VARCHAR(30)   DEFAULT USUARIOACTUAL(),
    CTIPOVEHICULO           CHAR(3)       NOT NULL DEFAULT '001',
    PLACA                   VARCHAR(10),                          -- ABC1234 / AB123C (sin guion); nula en bici o a pie
    COLORVEHICULO           VARCHAR(30),
    CESTATUSAPROBACION      CHAR(3)       NOT NULL DEFAULT '001',
    FAPROBACION             TIMESTAMPTZ,
    CONSTRAINT IPKREPARTIDORES PRIMARY KEY (CUSUARIO, FHASTA),
    CONSTRAINT FKREPARTUSUID   FOREIGN KEY (CUSUARIO)           REFERENCES TUSUARIOSID (CUSUARIO),
    CONSTRAINT FKREPARTVEHIC   FOREIGN KEY (CTIPOVEHICULO)      REFERENCES TTIPOSVEHICULOID (CTIPOVEHICULO),
    CONSTRAINT FKREPARTESTAPR  FOREIGN KEY (CESTATUSAPROBACION) REFERENCES TESTATUSAPROBACIONID (CESTATUSAPROBACION),
    CONSTRAINT CKREPARTPLACA   CHECK (PLACA IS NULL OR PLACA ~ '^[A-Z]{2,3}[0-9]{3,4}[A-Z]?$')
);
-- Una placa vigente pertenece a un solo repartidor
CREATE UNIQUE INDEX UXREPARTPLACA ON TREPARTIDORES (PLACA) WHERE FHASTA = '2999-12-31 00:00:00-05' AND PLACA IS NOT NULL;
SELECT ACTIVARVERSION('TREPARTIDORES');

-- Lo que cambia a cada rato: en línea, posición, calificación y contador. Sin historial a propósito.
CREATE TABLE TREPARTIDORESESTADO (
    CUSUARIO                VARCHAR(30)   NOT NULL,
    ESTADISPONIBLE          BOOLEAN       NOT NULL DEFAULT FALSE,  -- "en línea": recibe avisos de pedidos listos
    LATITUD                 NUMERIC(10,8),
    LONGITUD                NUMERIC(11,8),
    FUBICACION              TIMESTAMPTZ,
    CALIFICACION            NUMERIC(3,2)  NOT NULL DEFAULT 0,
    NUMEROCALIFICACIONES    INTEGER       NOT NULL DEFAULT 0,
    NUMEROENTREGAS          INTEGER       NOT NULL DEFAULT 0,
    FULTIMOCAMBIO           TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT IPKREPARTIDORESESTADO PRIMARY KEY (CUSUARIO),
    CONSTRAINT FKREPESTUSUID   FOREIGN KEY (CUSUARIO) REFERENCES TUSUARIOSID (CUSUARIO),
    CONSTRAINT CKREPESTCALIF   CHECK (CALIFICACION BETWEEN 0 AND 5),
    CONSTRAINT CKREPESTUBIC    CHECK ((LATITUD IS NULL AND LONGITUD IS NULL) OR (LATITUD BETWEEN -90 AND 90 AND LONGITUD BETWEEN -180 AND 180))
);
CREATE INDEX IXREPESTDISPONIBLE ON TREPARTIDORESESTADO (CUSUARIO) WHERE ESTADISPONIBLE;

CREATE FUNCTION FNASIGNARREPARTIDOR() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO TREPARTIDORESESTADO (CUSUARIO) VALUES (NEW.CUSUARIO) ON CONFLICT DO NOTHING;
    RETURN NEW;
END $$;
CREATE TRIGGER TRREPARTIDORESASIGNAR AFTER INSERT ON TREPARTIDORES FOR EACH ROW EXECUTE FUNCTION FNASIGNARREPARTIDOR();

-- -----------------------------------------------------------------------------
-- Recorrido de cada entrega: un punto cada ~15 segundos mientras el pedido va en camino
-- -----------------------------------------------------------------------------
CREATE TABLE TREPARTIDORUBICACIONES (
    SUBICACION              BIGINT        GENERATED ALWAYS AS IDENTITY,
    CUSUARIO                VARCHAR(30)   NOT NULL,
    CPEDIDO                 BIGINT        NOT NULL,
    LATITUD                 NUMERIC(10,8) NOT NULL,
    LONGITUD                NUMERIC(11,8) NOT NULL,
    PRECISIONM              NUMERIC(7,1),
    VELOCIDADKMH            NUMERIC(5,1),
    RUMBO                   NUMERIC(5,1),
    FREGISTRO               TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT IPKREPARTIDORUBICACIONES PRIMARY KEY (SUBICACION),
    CONSTRAINT FKREPUBIUSUID FOREIGN KEY (CUSUARIO) REFERENCES TUSUARIOSID (CUSUARIO),
    CONSTRAINT FKREPUBIPEDID FOREIGN KEY (CPEDIDO)  REFERENCES TPEDIDOSID (CPEDIDO),
    CONSTRAINT CKREPUBICOORD CHECK (LATITUD BETWEEN -90 AND 90 AND LONGITUD BETWEEN -180 AND 180)
);
CREATE INDEX IXREPUBIPEDIDO ON TREPARTIDORUBICACIONES (CPEDIDO, FREGISTRO);

-- Limpieza (programar a diario): recorridos de hace más de 60 días
CREATE FUNCTION PURGARUBICACIONES() RETURNS INTEGER LANGUAGE sql AS $$
  WITH r AS (DELETE FROM TREPARTIDORUBICACIONES WHERE FREGISTRO < now() - interval '60 days' RETURNING 1)
  SELECT count(*)::INTEGER FROM r
$$;

-- -----------------------------------------------------------------------------
-- Comentarios
-- -----------------------------------------------------------------------------
COMMENT ON TABLE TTIPOSVEHICULOID IS 'Códigos de tipo de vehículo (destino de las FK)';
COMMENT ON TABLE TTIPOSVEHICULO IS 'Tipos de vehículo del repartidor; REQUIEREPLACA dice si se pide la placa';
COMMENT ON TABLE TREPARTIDORES IS 'Perfil del repartidor: vehículo, placa y aprobación. Con historial';
COMMENT ON TABLE TREPARTIDORESESTADO IS 'En línea, última ubicación, calificación y entregas del repartidor. Sin historial a propósito';
COMMENT ON TABLE TREPARTIDORUBICACIONES IS 'Recorrido de cada entrega (un punto cada ~15 s). Sin historial; se purga a los 60 días';
COMMENT ON COLUMN TREPARTIDORES.PLACA IS 'Placa sin guion ni espacios (ABC1234). Nula si el vehículo no la requiere';
COMMENT ON COLUMN TREPARTIDORESESTADO.ESTADISPONIBLE IS 'En línea: recibe avisos de pedidos listos y puede aceptarlos';
COMMENT ON COLUMN TREPARTIDORESESTADO.FUBICACION IS 'Cuándo llegó la última ubicación';
COMMENT ON COLUMN TREPARTIDORUBICACIONES.VELOCIDADKMH IS 'Velocidad en km/h (el GPS la da en m/s)';
