-- =============================================================================
-- 007 · PEDIDOS: pedido, detalle, calificaciones y notificaciones
-- =============================================================================
--   TESTATUSPEDIDO                catálogo: pendiente, confirmado, preparando, listo, en camino... cancelado
--   TMETODOSPAGO                  catálogo: efectivo, transferencia, tarjeta, PayPal (con ESACTIVO)
--   TPEDIDOSID / TPEDIDOS         el pedido. Histórica: cada cambio de estado deja su versión, y esa es la
--                                 línea de tiempo del seguimiento (cuándo se confirmó, cuándo salió...)
--   TPEDIDODETALLES               productos del pedido con el precio de ese momento                   · simple
--   TCALIFICACIONES               calificación del cliente al negocio (y al repartidor, flujo 4)      · simple
--   TNOTIFICACIONES               avisos que ve cada usuario en la app                                · simple
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Catálogos (con idioma)
-- -----------------------------------------------------------------------------
CREATE TABLE TESTATUSPEDIDOID (
    CESTATUSPEDIDO CHAR(3) NOT NULL,
    CONSTRAINT IPKESTATUSPEDIDOID PRIMARY KEY (CESTATUSPEDIDO)
);
CREATE TABLE TESTATUSPEDIDO (
    CIDIOMA                 CHAR(2)       NOT NULL DEFAULT 'es',
    CESTATUSPEDIDO          CHAR(3)       NOT NULL,
    FHASTA                  TIMESTAMPTZ   NOT NULL DEFAULT '2999-12-31 00:00:00-05',
    FDESDE                  TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    VERSIONCONTROL          INTEGER       NOT NULL DEFAULT 0,
    CUSUARIO_MODIFICACION   VARCHAR(30)   DEFAULT USUARIOACTUAL(),
    DESCRIPCION             VARCHAR(60)   NOT NULL,
    ESFINAL                 BOOLEAN       NOT NULL DEFAULT FALSE,   -- ya no cambia (recibido, rechazado, cancelado)
    CONSTRAINT IPKESTATUSPEDIDO PRIMARY KEY (CIDIOMA, CESTATUSPEDIDO, FHASTA),
    CONSTRAINT FKESTPEDESTPEDID FOREIGN KEY (CESTATUSPEDIDO) REFERENCES TESTATUSPEDIDOID (CESTATUSPEDIDO)
);
SELECT ACTIVARVERSION('TESTATUSPEDIDO');
INSERT INTO TESTATUSPEDIDOID (CESTATUSPEDIDO) VALUES ('001'), ('002'), ('003'), ('004'), ('005'), ('006'), ('007'), ('008'), ('009'), ('010');
INSERT INTO TESTATUSPEDIDO (CESTATUSPEDIDO, DESCRIPCION, ESFINAL) VALUES
    ('001', 'Pendiente', FALSE), ('002', 'Confirmado', FALSE), ('003', 'Preparando', FALSE), ('004', 'Listo', FALSE),
    ('005', 'En camino', FALSE), ('006', 'Recogido', FALSE), ('007', 'Entregado', FALSE), ('008', 'Recibido', TRUE),
    ('009', 'Rechazado', TRUE), ('010', 'Cancelado', TRUE);

CREATE TABLE TMETODOSPAGOID (
    CMETODOPAGO CHAR(3) NOT NULL,
    CONSTRAINT IPKMETODOSPAGOID PRIMARY KEY (CMETODOPAGO)
);
CREATE TABLE TMETODOSPAGO (
    CIDIOMA                 CHAR(2)       NOT NULL DEFAULT 'es',
    CMETODOPAGO             CHAR(3)       NOT NULL,
    FHASTA                  TIMESTAMPTZ   NOT NULL DEFAULT '2999-12-31 00:00:00-05',
    FDESDE                  TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    VERSIONCONTROL          INTEGER       NOT NULL DEFAULT 0,
    CUSUARIO_MODIFICACION   VARCHAR(30)   DEFAULT USUARIOACTUAL(),
    DESCRIPCION             VARCHAR(60)   NOT NULL,
    ESACTIVO                BOOLEAN       NOT NULL DEFAULT TRUE,    -- si se puede elegir hoy en la app
    CONSTRAINT IPKMETODOSPAGO PRIMARY KEY (CIDIOMA, CMETODOPAGO, FHASTA),
    CONSTRAINT FKMETPAGMETPAGID FOREIGN KEY (CMETODOPAGO) REFERENCES TMETODOSPAGOID (CMETODOPAGO)
);
SELECT ACTIVARVERSION('TMETODOSPAGO');
INSERT INTO TMETODOSPAGOID (CMETODOPAGO) VALUES ('001'), ('002'), ('003'), ('004');
INSERT INTO TMETODOSPAGO (CMETODOPAGO, DESCRIPCION, ESACTIVO) VALUES
    ('001', 'Efectivo', TRUE), ('002', 'Transferencia', TRUE), ('003', 'Tarjeta', FALSE), ('004', 'PayPal', FALSE);

-- -----------------------------------------------------------------------------
-- Pedidos
-- -----------------------------------------------------------------------------
CREATE SEQUENCE SECPEDIDOS;

CREATE TABLE TPEDIDOSID (
    CPEDIDO BIGINT NOT NULL DEFAULT nextval('secpedidos'),
    CONSTRAINT IPKPEDIDOSID PRIMARY KEY (CPEDIDO)
);
CREATE TABLE TPEDIDOS (
    CPEDIDO                 BIGINT        NOT NULL,
    FHASTA                  TIMESTAMPTZ   NOT NULL DEFAULT '2999-12-31 00:00:00-05',
    FDESDE                  TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    VERSIONCONTROL          INTEGER       NOT NULL DEFAULT 0,
    CUSUARIO_MODIFICACION   VARCHAR(30)   DEFAULT USUARIOACTUAL(),
    CUSUARIO                VARCHAR(30)   NOT NULL,               -- cliente
    CNEGOCIO                BIGINT        NOT NULL,
    CUSUARIO_REPARTIDOR     VARCHAR(30),                          -- se asigna en el flujo del repartidor
    CESTATUSPEDIDO          CHAR(3)       NOT NULL DEFAULT '001',
    CMETODOPAGO             CHAR(3)       NOT NULL DEFAULT '001',
    -- Dirección de entrega: se COPIA al crear el pedido (si el cliente la edita después, el pedido no cambia)
    CDIRECCION              BIGINT,
    DIRECCIONENTREGA        VARCHAR(500)  NOT NULL,
    REFERENCIAENTREGA       VARCHAR(500),
    LATITUDENTREGA          NUMERIC(10,8) NOT NULL,
    LONGITUDENTREGA         NUMERIC(11,8) NOT NULL,
    -- Montos (salen de la BD, nunca de la app)
    SUBTOTAL                NUMERIC(10,2) NOT NULL,
    COSTOENVIO              NUMERIC(8,2)  NOT NULL DEFAULT 0,
    DESCUENTO               NUMERIC(8,2)  NOT NULL DEFAULT 0,
    PROPINA                 NUMERIC(8,2)  NOT NULL DEFAULT 0,
    TOTAL                   NUMERIC(10,2) NOT NULL,
    ESPAGADO                BOOLEAN       NOT NULL DEFAULT FALSE,
    NOTAS                   VARCHAR(300),                         -- indicaciones del cliente
    TIEMPOESTIMADO          SMALLINT,                             -- minutos (lo puede ajustar el negocio al confirmar)
    MOTIVOCANCELACION       VARCHAR(300),
    FPEDIDO                 TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),   -- cuándo se hizo (no cambia)
    CONSTRAINT IPKPEDIDOS PRIMARY KEY (CPEDIDO, FHASTA),
    CONSTRAINT FKPEDIDOSPEDID     FOREIGN KEY (CPEDIDO)             REFERENCES TPEDIDOSID (CPEDIDO),
    CONSTRAINT FKPEDIDOSUSUID     FOREIGN KEY (CUSUARIO)            REFERENCES TUSUARIOSID (CUSUARIO),
    CONSTRAINT FKPEDIDOSNEGID     FOREIGN KEY (CNEGOCIO)            REFERENCES TNEGOCIOSID (CNEGOCIO),
    CONSTRAINT FKPEDIDOSREPART    FOREIGN KEY (CUSUARIO_REPARTIDOR) REFERENCES TUSUARIOSID (CUSUARIO),
    CONSTRAINT FKPEDIDOSESTADO    FOREIGN KEY (CESTATUSPEDIDO)      REFERENCES TESTATUSPEDIDOID (CESTATUSPEDIDO),
    CONSTRAINT FKPEDIDOSMETPAGO   FOREIGN KEY (CMETODOPAGO)         REFERENCES TMETODOSPAGOID (CMETODOPAGO),
    CONSTRAINT FKPEDIDOSDIRID     FOREIGN KEY (CDIRECCION)          REFERENCES TPERSONADIRECCIONESID (CDIRECCION),
    CONSTRAINT CKPEDIDOSMONTOS    CHECK (SUBTOTAL > 0 AND COSTOENVIO >= 0 AND DESCUENTO >= 0 AND PROPINA >= 0 AND TOTAL >= 0),
    CONSTRAINT CKPEDIDOSTOTAL     CHECK (TOTAL = SUBTOTAL + COSTOENVIO - DESCUENTO + PROPINA),
    CONSTRAINT CKPEDIDOSUBICACION CHECK (LATITUDENTREGA BETWEEN -90 AND 90 AND LONGITUDENTREGA BETWEEN -180 AND 180)
);
CREATE INDEX IXPEDIDOSCLIENTE    ON TPEDIDOS (CUSUARIO, FPEDIDO DESC)            WHERE FHASTA = '2999-12-31 00:00:00-05';
CREATE INDEX IXPEDIDOSNEGOCIO    ON TPEDIDOS (CNEGOCIO, CESTATUSPEDIDO)          WHERE FHASTA = '2999-12-31 00:00:00-05';
CREATE INDEX IXPEDIDOSREPARTIDOR ON TPEDIDOS (CUSUARIO_REPARTIDOR)               WHERE FHASTA = '2999-12-31 00:00:00-05';
SELECT ACTIVARVERSION('TPEDIDOS');

CREATE FUNCTION FNASIGNARPEDIDO() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.CPEDIDO IS NULL THEN
        INSERT INTO TPEDIDOSID DEFAULT VALUES RETURNING CPEDIDO INTO NEW.CPEDIDO;
    ELSE
        INSERT INTO TPEDIDOSID (CPEDIDO) VALUES (NEW.CPEDIDO) ON CONFLICT DO NOTHING;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER TRPEDIDOSASIGNAR BEFORE INSERT ON TPEDIDOS FOR EACH ROW EXECUTE FUNCTION FNASIGNARPEDIDO();

-- Productos del pedido. No cambian una vez hecho el pedido: tabla simple.
-- Se copian el nombre y el precio de ese momento (si el negocio cambia el precio, el pedido no cambia).
CREATE TABLE TPEDIDODETALLES (
    CPEDIDO                 BIGINT        NOT NULL,
    NUMEROLINEA             SMALLINT      NOT NULL,
    CPRODUCTO               BIGINT        NOT NULL,
    NOMBREPRODUCTO          VARCHAR(120)  NOT NULL,
    PRECIOUNITARIO          NUMERIC(10,2) NOT NULL,
    CANTIDAD                SMALLINT      NOT NULL,
    SUBTOTAL                NUMERIC(10,2) NOT NULL,
    NOTAS                   VARCHAR(200),                         -- "sin cebolla"
    CONSTRAINT IPKPEDIDODETALLES PRIMARY KEY (CPEDIDO, NUMEROLINEA),
    CONSTRAINT FKPEDDETPEDID  FOREIGN KEY (CPEDIDO)   REFERENCES TPEDIDOSID (CPEDIDO),
    CONSTRAINT FKPEDDETPRODID FOREIGN KEY (CPRODUCTO) REFERENCES TPRODUCTOSID (CPRODUCTO),
    CONSTRAINT CKPEDDETMONTOS CHECK (CANTIDAD BETWEEN 1 AND 99 AND PRECIOUNITARIO > 0 AND SUBTOTAL = PRECIOUNITARIO * CANTIDAD)
);

-- -----------------------------------------------------------------------------
-- Calificaciones: una por pedido y por destinatario. No se editan: tabla simple.
-- -----------------------------------------------------------------------------
CREATE TABLE TCALIFICACIONES (
    CPEDIDO                 BIGINT        NOT NULL,
    DESTINO                 VARCHAR(10)   NOT NULL,               -- NEGOCIO | REPARTIDOR
    CUSUARIO                VARCHAR(30)   NOT NULL,               -- quien califica (el cliente)
    CNEGOCIO                BIGINT,
    CUSUARIO_REPARTIDOR     VARCHAR(30),
    PUNTUACION              SMALLINT      NOT NULL,
    COMENTARIO              VARCHAR(500),
    FCREACION               TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT IPKCALIFICACIONES PRIMARY KEY (CPEDIDO, DESTINO),
    CONSTRAINT FKCALIFPEDID   FOREIGN KEY (CPEDIDO)             REFERENCES TPEDIDOSID (CPEDIDO),
    CONSTRAINT FKCALIFUSUID   FOREIGN KEY (CUSUARIO)            REFERENCES TUSUARIOSID (CUSUARIO),
    CONSTRAINT FKCALIFNEGID   FOREIGN KEY (CNEGOCIO)            REFERENCES TNEGOCIOSID (CNEGOCIO),
    CONSTRAINT FKCALIFREPART  FOREIGN KEY (CUSUARIO_REPARTIDOR) REFERENCES TUSUARIOSID (CUSUARIO),
    CONSTRAINT CKCALIFDESTINO CHECK ((DESTINO = 'NEGOCIO' AND CNEGOCIO IS NOT NULL) OR (DESTINO = 'REPARTIDOR' AND CUSUARIO_REPARTIDOR IS NOT NULL)),
    CONSTRAINT CKCALIFPUNTOS  CHECK (PUNTUACION BETWEEN 1 AND 5)
);
CREATE INDEX IXCALIFNEGOCIO ON TCALIFICACIONES (CNEGOCIO) WHERE CNEGOCIO IS NOT NULL;

-- -----------------------------------------------------------------------------
-- Notificaciones que ve el usuario en la app (además se envían por socket y push)
-- -----------------------------------------------------------------------------
CREATE TABLE TNOTIFICACIONES (
    SNOTIFICACION           BIGINT        GENERATED ALWAYS AS IDENTITY,
    CUSUARIO                VARCHAR(30)   NOT NULL,
    TIPO                    VARCHAR(40)   NOT NULL,               -- pedido_nuevo, pedido_confirmado...
    TITULO                  VARCHAR(150)  NOT NULL,
    MENSAJE                 VARCHAR(500)  NOT NULL,
    CPEDIDO                 BIGINT,
    DATOS                   JSONB,
    ESLEIDA                 BOOLEAN       NOT NULL DEFAULT FALSE,
    FLEIDA                  TIMESTAMPTZ,
    FCREACION               TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT IPKNOTIFICACIONES PRIMARY KEY (SNOTIFICACION),
    CONSTRAINT FKNOTIFUSUID FOREIGN KEY (CUSUARIO) REFERENCES TUSUARIOSID (CUSUARIO),
    CONSTRAINT FKNOTIFPEDID FOREIGN KEY (CPEDIDO)  REFERENCES TPEDIDOSID (CPEDIDO)
);
CREATE INDEX IXNOTIFUSUARIO ON TNOTIFICACIONES (CUSUARIO, FCREACION DESC);
CREATE INDEX IXNOTIFNOLEIDAS ON TNOTIFICACIONES (CUSUARIO) WHERE NOT ESLEIDA;

-- Limpieza (programar a diario): notificaciones leídas de hace más de 90 días
CREATE FUNCTION PURGARNOTIFICACIONES() RETURNS INTEGER LANGUAGE sql AS $$
  WITH r AS (DELETE FROM TNOTIFICACIONES WHERE ESLEIDA AND FCREACION < now() - interval '90 days' RETURNING 1)
  SELECT count(*)::INTEGER FROM r
$$;

-- -----------------------------------------------------------------------------
-- Comentarios
-- -----------------------------------------------------------------------------
COMMENT ON TABLE TESTATUSPEDIDOID IS 'Códigos de estatus de pedido (destino de las FK)';
COMMENT ON TABLE TESTATUSPEDIDO IS 'Estatus del pedido: 001 pendiente ... 008 recibido, 009 rechazado, 010 cancelado';
COMMENT ON TABLE TMETODOSPAGOID IS 'Códigos de método de pago (destino de las FK)';
COMMENT ON TABLE TMETODOSPAGO IS 'Métodos de pago; ESACTIVO dice cuáles se pueden elegir hoy';
COMMENT ON TABLE TPEDIDOSID IS 'Código de cada pedido (lo referencian detalle, calificaciones y notificaciones)';
COMMENT ON TABLE TPEDIDOS IS 'El pedido. Con historial: cada cambio de estado deja su versión (línea de tiempo del seguimiento)';
COMMENT ON TABLE TPEDIDODETALLES IS 'Productos del pedido con el nombre y precio de ese momento. Sin historial: no cambian';
COMMENT ON TABLE TCALIFICACIONES IS 'Calificación del cliente al negocio o al repartidor, una por pedido y destino. Sin historial';
COMMENT ON TABLE TNOTIFICACIONES IS 'Avisos de la app por usuario (leída o no). Sin historial';
COMMENT ON COLUMN TPEDIDOS.CUSUARIO IS 'Cliente que hizo el pedido';
COMMENT ON COLUMN TPEDIDOS.CUSUARIO_REPARTIDOR IS 'Repartidor asignado (nulo hasta que uno lo acepta)';
COMMENT ON COLUMN TPEDIDOS.CDIRECCION IS 'Dirección de la que se copió la entrega (referencia; los datos copiados mandan)';
COMMENT ON COLUMN TPEDIDOS.COSTOENVIO IS 'Costo de envío del negocio al momento del pedido';
COMMENT ON COLUMN TPEDIDOS.TOTAL IS 'SUBTOTAL + COSTOENVIO - DESCUENTO + PROPINA';
COMMENT ON COLUMN TPEDIDOS.TIEMPOESTIMADO IS 'Minutos estimados de entrega';
COMMENT ON COLUMN TPEDIDOS.FPEDIDO IS 'Fecha y hora en que se hizo el pedido';
COMMENT ON COLUMN TPEDIDODETALLES.NOMBREPRODUCTO IS 'Nombre del producto al momento del pedido';
COMMENT ON COLUMN TPEDIDODETALLES.PRECIOUNITARIO IS 'Precio al momento del pedido';
COMMENT ON COLUMN TCALIFICACIONES.DESTINO IS 'A quién se califica: NEGOCIO o REPARTIDOR';
COMMENT ON COLUMN TNOTIFICACIONES.DATOS IS 'Datos extra para la app (estado del pedido, etc.)';
