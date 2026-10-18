-- =============================================================================
-- 020 · Varios perfiles por persona, suscripción mensual, calificaciones del negocio y advertencias
-- =============================================================================
--   RENOMBRARUSUARIO(viejo, nuevo)   cambia el nombre de usuario (login) en TODAS las tablas que lo usan, también
--                                    en el historial, y borra el viejo de TUSUARIOSID. Cambiarlo a mano en
--                                    TUSUARIOS deja las otras tablas apuntando al viejo: ahora la BD lo impide.
--   TUSUARIOS                        una persona (cédula y correo) puede tener una cuenta por perfil: cliente,
--                                    vendedor y repartidor, pero nunca dos del mismo perfil.
--   ELIMINARDATOSPERSONALES          si la persona tiene otras cuentas, solo desvincula la que se elimina (las demás
--                                    siguen con sus datos).
--   TCALIFICACIONES.ORIGEN           quién califica: el CLIENTE (al negocio o al repartidor) o el NEGOCIO (al repartidor)
--   TREPARTIDORADVERTENCIAS          avisos del administrador al repartidor por su comportamiento        · simple
--   TSUSCRIPCIONPAGOS                pagos de la suscripción mensual de vendedores y repartidores        · simple
--   TCONFIGURACIONES                 SUSCRIPCIONVENDEDOR, SUSCRIPCIONREPARTIDOR (USD al mes), SUSCRIPCIONDIASGRACIA,
--                                    SUSCRIPCIONINICIO; COMISIONPORCENTAJE pasa a 0 (ya no se cobra comisión)
-- Suscripción: cada mes (calendario, hora de Ecuador) el vendedor y el repartidor APROBADOS pagan una cuota fija. El
-- mes en que lo aprueban es gratis; paga desde el siguiente (nunca antes de SUSCRIPCIONINICIO). Tiene hasta el día
-- SUSCRIPCIONDIASGRACIA del mes para pagar; después, el negocio deja de recibir pedidos y el repartidor no puede
-- conectarse hasta ponerse al día. Un comprobante en revisión no bloquea (ya hizo su parte).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Renombrar un usuario
-- -----------------------------------------------------------------------------
CREATE FUNCTION RENOMBRARUSUARIO(p_viejo VARCHAR, p_nuevo VARCHAR) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    v_viejo  VARCHAR := lower(btrim(p_viejo));
    v_nuevo  VARCHAR := lower(btrim(p_nuevo));
    v_persona BIGINT;
    r RECORD;
BEGIN
    IF v_nuevo !~ '^[a-z0-9]{3,30}$' THEN
        RAISE EXCEPTION 'El usuario nuevo "%" solo puede tener letras minúsculas y números (3 a 30)', v_nuevo;
    END IF;
    IF v_viejo = v_nuevo THEN RETURN; END IF;
    IF NOT EXISTS (SELECT 1 FROM TUSUARIOSID WHERE CUSUARIO = v_viejo) THEN
        RAISE EXCEPTION 'No existe el usuario "%"', v_viejo;
    END IF;
    SELECT CPERSONA INTO v_persona FROM TUSUARIOS WHERE CUSUARIO = v_viejo ORDER BY FHASTA DESC LIMIT 1;
    -- El nombre nuevo no puede ser de otra persona. Sí puede existir ya si el cambio se hizo a medias a mano
    -- (UPDATE en TUSUARIOS): entonces se termina de mover lo que quedó con el nombre viejo.
    IF EXISTS (SELECT 1 FROM TUSUARIOS WHERE CUSUARIO = v_nuevo AND CPERSONA IS DISTINCT FROM v_persona) THEN
        RAISE EXCEPTION 'El usuario "%" ya es de otra persona', v_nuevo;
    END IF;
    IF EXISTS (SELECT 1 FROM TUSUARIOS WHERE CUSUARIO = v_viejo AND FHASTA = '2999-12-31 00:00:00-05')
       AND EXISTS (SELECT 1 FROM TUSUARIOS WHERE CUSUARIO = v_nuevo AND FHASTA = '2999-12-31 00:00:00-05') THEN
        RAISE EXCEPTION 'Los dos usuarios ("%" y "%") están vigentes: son dos cuentas distintas', v_viejo, v_nuevo;
    END IF;

    INSERT INTO TUSUARIOSID (CUSUARIO) VALUES (v_nuevo) ON CONFLICT DO NOTHING;
    PERFORM set_config('vallexpress.borrado', 'si', true);      -- se mueve también el historial, sin versionar

    -- Las sesiones abiertas llevan el nombre viejo: se cierran (vuelve a iniciar sesión con el nuevo)
    DELETE FROM TSESIONES WHERE CUSUARIO = v_viejo;
    -- Estado de acceso: una fila por usuario
    IF EXISTS (SELECT 1 FROM TUSUARIOSACCESO WHERE CUSUARIO = v_nuevo) THEN
        DELETE FROM TUSUARIOSACCESO WHERE CUSUARIO = v_viejo;
    END IF;

    -- Todas las columnas que apuntan a TUSUARIOSID (se buscan en el catálogo: sirve para tablas futuras)
    FOR r IN
        SELECT c.conrelid::regclass::text AS tabla, a.attname AS columna
          FROM pg_constraint c
          JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
         WHERE c.confrelid = 'tusuariosid'::regclass AND c.contype = 'f'
    LOOP
        EXECUTE format('UPDATE %s SET %I = $1 WHERE %I = $2', r.tabla, r.columna, r.columna) USING v_nuevo, v_viejo;
    END LOOP;

    PERFORM set_config('vallexpress.borrado', '', true);
    DELETE FROM TUSUARIOSID WHERE CUSUARIO = v_viejo;
END $$;
COMMENT ON FUNCTION RENOMBRARUSUARIO(VARCHAR, VARCHAR) IS 'Cambia el nombre de usuario en todas las tablas (también el historial) y borra el viejo. Uso: SELECT RENOMBRARUSUARIO(''viejo'', ''nuevo'')';

-- El nombre de usuario ya no se cambia con un UPDATE suelto (dejaría las otras tablas con el viejo)
CREATE FUNCTION FNUSUARIOSRENOMBRE() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.CUSUARIO IS DISTINCT FROM OLD.CUSUARIO AND coalesce(current_setting('vallexpress.borrado', true), '') <> 'si' THEN
        RAISE EXCEPTION 'Para cambiar el usuario usa: SELECT RENOMBRARUSUARIO(''%'', ''%'')', OLD.CUSUARIO, NEW.CUSUARIO;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER TRUSUARIOSRENOMBRE BEFORE UPDATE OF CUSUARIO ON TUSUARIOS FOR EACH ROW EXECUTE FUNCTION FNUSUARIOSRENOMBRE();

-- -----------------------------------------------------------------------------
-- Una cuenta por perfil y persona
-- -----------------------------------------------------------------------------
DROP INDEX UQUSUARIOSPERSONA;
CREATE UNIQUE INDEX UQUSUARIOSPERSONAROL ON TUSUARIOS (CPERSONA, CROL) WHERE FHASTA = '2999-12-31 00:00:00-05';
CREATE INDEX IXUSUARIOSPERSONA ON TUSUARIOS (CPERSONA) WHERE FHASTA = '2999-12-31 00:00:00-05';
COMMENT ON COLUMN TUSUARIOS.CPERSONA IS 'Persona dueña de la cuenta (TPERSONASID); una persona tiene a lo sumo una cuenta por rol';

-- -----------------------------------------------------------------------------
-- Eliminar una cuenta cuando la persona tiene otras
-- -----------------------------------------------------------------------------
-- Si la persona tiene otras cuentas, la que se elimina pasa a una persona nueva anónima ("Cuenta eliminada") y la
-- persona real sigue con sus datos para las otras. Si era la única, se borran los datos de la persona como antes.
CREATE OR REPLACE FUNCTION ELIMINARDATOSPERSONALES(p_persona BIGINT, p_usuario VARCHAR) RETURNS SETOF BIGINT LANGUAGE plpgsql AS $$
DECLARE
    v_fotos BIGINT[];
    v_anonima BIGINT;
    v_otras BOOLEAN := EXISTS (SELECT 1 FROM TUSUARIOS WHERE CPERSONA = p_persona AND CUSUARIO <> p_usuario AND FHASTA = '2999-12-31 00:00:00-05');
BEGIN
    PERFORM set_config('vallexpress.borrado', 'si', true);

    IF v_otras THEN
        v_anonima := nextval('secpersonas');
        INSERT INTO TPERSONAS (CPERSONA, CTIPODOCUMENTO, NUMERODOCUMENTO, NOMBRES, APELLIDOS, CORREO)
        VALUES (v_anonima, '001', 'ELIM' || v_anonima, 'Cuenta', 'eliminada', 'eliminada-' || v_anonima || '@vallexpress.invalid');
        UPDATE TUSUARIOS SET CPERSONA = v_anonima WHERE CUSUARIO = p_usuario;
    ELSE
        SELECT array_agg(DISTINCT CARCHIVO_FOTO) INTO v_fotos FROM TPERSONAS WHERE CPERSONA = p_persona AND CARCHIVO_FOTO IS NOT NULL;

        -- Persona (vigente e historial): sin nombre, cédula, correo, nacimiento ni foto
        UPDATE TPERSONAS
           SET NOMBRES = 'Cuenta', APELLIDOS = 'eliminada', NUMERODOCUMENTO = 'ELIM' || p_persona,
               CORREO = 'eliminada-' || p_persona || '@vallexpress.invalid', FCORREOVERIFICADO = NULL,
               FNACIMIENTO = NULL, CARCHIVO_FOTO = NULL
         WHERE CPERSONA = p_persona;

        -- Teléfonos y direcciones guardadas
        UPDATE TPERSONATELEFONOS SET NUMEROTELEFONO = 'ELIM' || p_persona || '-' || STELEFONO, FVERIFICADO = NULL WHERE CPERSONA = p_persona;
        UPDATE TPERSONADIRECCIONES
           SET NOMBRE = NULL, DIRECCION = 'Dirección eliminada', REFERENCIA = NULL, INSTRUCCIONES = NULL, LATITUD = 0, LONGITUD = 0
         WHERE CPERSONA = p_persona;
    END IF;

    -- Repartidor: vehículo y recorridos
    UPDATE TREPARTIDORES SET PLACA = NULL, COLORVEHICULO = NULL WHERE CUSUARIO = p_usuario;
    DELETE FROM TREPARTIDORUBICACIONES WHERE CUSUARIO = p_usuario;
    UPDATE TREPARTIDORESESTADO SET ESTADISPONIBLE = FALSE WHERE CUSUARIO = p_usuario;

    PERFORM set_config('vallexpress.borrado', '', true);

    -- Equipos con notificaciones: ya no se le envía nada
    DELETE FROM TDISPOSITIVOS WHERE CUSUARIO = p_usuario;

    -- Fotos de perfil que ninguna otra persona usa
    RETURN QUERY
        SELECT a.CARCHIVO FROM TARCHIVOS a
         WHERE a.CARCHIVO = ANY (coalesce(v_fotos, '{}'))
           AND NOT EXISTS (SELECT 1 FROM TPERSONAS p WHERE p.CARCHIVO_FOTO = a.CARCHIVO);
END $$;

-- -----------------------------------------------------------------------------
-- Calificaciones: el negocio también califica al repartidor
-- -----------------------------------------------------------------------------
ALTER TABLE TCALIFICACIONES ADD COLUMN ORIGEN VARCHAR(10) NOT NULL DEFAULT 'CLIENTE';
ALTER TABLE TCALIFICACIONES ADD CONSTRAINT CKCALIFORIGEN CHECK (ORIGEN IN ('CLIENTE', 'NEGOCIO') AND (ORIGEN = 'CLIENTE' OR DESTINO = 'REPARTIDOR'));
ALTER TABLE TCALIFICACIONES DROP CONSTRAINT IPKCALIFICACIONES;
ALTER TABLE TCALIFICACIONES ADD CONSTRAINT IPKCALIFICACIONES PRIMARY KEY (CPEDIDO, DESTINO, ORIGEN);
CREATE INDEX IXCALIFREPARTIDOR ON TCALIFICACIONES (CUSUARIO_REPARTIDOR) WHERE CUSUARIO_REPARTIDOR IS NOT NULL;
COMMENT ON COLUMN TCALIFICACIONES.ORIGEN IS 'Quién califica: CLIENTE (al negocio o al repartidor) o NEGOCIO (solo al repartidor)';

-- -----------------------------------------------------------------------------
-- Advertencias al repartidor
-- -----------------------------------------------------------------------------
CREATE TABLE TREPARTIDORADVERTENCIAS (
    CADVERTENCIA    BIGINT        GENERATED ALWAYS AS IDENTITY,
    CUSUARIO        VARCHAR(30)   NOT NULL,                  -- el repartidor
    MOTIVO          VARCHAR(500)  NOT NULL,
    FCREACION       TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    CUSUARIO_ADMIN  VARCHAR(30)   NOT NULL,                  -- el administrador que la envió
    CONSTRAINT IPKREPARTIDORADVERTENCIAS PRIMARY KEY (CADVERTENCIA),
    CONSTRAINT FKREPADVUSUID FOREIGN KEY (CUSUARIO) REFERENCES TUSUARIOSID (CUSUARIO)
);
CREATE INDEX IXREPADVUSUARIO ON TREPARTIDORADVERTENCIAS (CUSUARIO);
COMMENT ON TABLE TREPARTIDORADVERTENCIAS IS 'Advertencias del administrador al repartidor por su calidad de servicio (antes de darlo de baja)';

-- -----------------------------------------------------------------------------
-- Suscripción mensual
-- -----------------------------------------------------------------------------
CREATE TABLE TSUSCRIPCIONPAGOS (
    CPAGO               BIGINT        GENERATED ALWAYS AS IDENTITY,
    CUSUARIO            VARCHAR(30)   NOT NULL,                -- el vendedor o repartidor que paga
    MES                 DATE          NOT NULL,                -- primer día del mes que paga
    MONTO               NUMERIC(8,2)  NOT NULL,
    REFERENCIA          VARCHAR(100),                          -- número de la transferencia o recibo
    CARCHIVO            BIGINT,                                -- foto del comprobante (nula si el admin lo registró a mano)
    ESTADO              VARCHAR(10)   NOT NULL DEFAULT 'ENVIADO',
    MOTIVORECHAZO       VARCHAR(300),
    FCREACION           TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    CUSUARIO_REGISTRO   VARCHAR(30)   NOT NULL,                -- quien lo subió (el mismo usuario o el administrador)
    FREVISION           TIMESTAMPTZ,
    CUSUARIO_REVISION   VARCHAR(30),                           -- el administrador que lo revisó
    CONSTRAINT IPKSUSCRIPCIONPAGOS PRIMARY KEY (CPAGO),
    CONSTRAINT FKSUSPAGUSUID   FOREIGN KEY (CUSUARIO) REFERENCES TUSUARIOSID (CUSUARIO),
    CONSTRAINT FKSUSPAGARCHIVO FOREIGN KEY (CARCHIVO) REFERENCES TARCHIVOS (CARCHIVO),
    CONSTRAINT CKSUSPAGESTADO  CHECK (ESTADO IN ('ENVIADO', 'APROBADO', 'RECHAZADO')),
    CONSTRAINT CKSUSPAGMES     CHECK (EXTRACT(DAY FROM MES) = 1),
    CONSTRAINT CKSUSPAGMONTO   CHECK (MONTO >= 0)
);
-- Cada mes se paga una vez: a lo sumo un pago aprobado o en revisión por usuario y mes
CREATE UNIQUE INDEX UQSUSPAGMES ON TSUSCRIPCIONPAGOS (CUSUARIO, MES) WHERE ESTADO IN ('ENVIADO', 'APROBADO');
CREATE INDEX IXSUSPAGESTADO ON TSUSCRIPCIONPAGOS (ESTADO, FCREACION);
COMMENT ON TABLE TSUSCRIPCIONPAGOS IS 'Pagos de la suscripción mensual de vendedores y repartidores (comprobante que revisa el administrador o pago registrado a mano)';
COMMENT ON COLUMN TSUSCRIPCIONPAGOS.ESTADO IS 'ENVIADO (en revisión), APROBADO (el mes quedó pagado) o RECHAZADO (con motivo)';

INSERT INTO TCONFIGURACIONES (CCONFIGURACION, VALOR, DESCRIPCION) VALUES
    ('SUSCRIPCIONVENDEDOR',   '10',           'Cuota mensual (USD) de cada vendedor aprobado'),
    ('SUSCRIPCIONREPARTIDOR', '10',           'Cuota mensual (USD) de cada repartidor aprobado'),
    ('SUSCRIPCIONDIASGRACIA', '5',            'Hasta qué día del mes se puede pagar la cuota antes de bloquear al vendedor o repartidor'),
    ('SUSCRIPCIONINICIO',     '"2026-11-01"', 'Primer mes que se cobra la suscripción (nadie paga meses anteriores)');

UPDATE TCONFIGURACIONES SET VALOR = '0'
 WHERE CCONFIGURACION = 'COMISIONPORCENTAJE' AND FHASTA = '2999-12-31 00:00:00-05';
UPDATE TCONFIGURACIONES SET DESCRIPCION = 'Cuenta de ValleXpress donde vendedores y repartidores transfieren su suscripción: banco, tipo, número, titular y cédula/RUC'
 WHERE CCONFIGURACION = 'LIQUIDACIONCUENTA' AND FHASTA = '2999-12-31 00:00:00-05';
