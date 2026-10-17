-- =============================================================================
-- 016 · Documentos legales y eliminación de cuenta
-- =============================================================================
--   TACEPTACIONESLEGALES   (simple) qué versión de cada documento aceptó cada usuario, cuándo y desde dónde.
--                          Los textos viven en backend/legal/*.md (versionados en git); aquí solo la prueba
--                          de la aceptación. Si un documento cambia de versión, el usuario debe aceptarlo otra vez.
--   FNVERSION              ahora respeta la marca de sesión "vallexpress.borrado" = 'si': mientras está puesta
--                          los cambios NO crean historial y también se pueden cambiar las filas de historial.
--                          Solo la usa ELIMINARDATOSPERSONALES.
--   ELIMINARDATOSPERSONALES(persona, usuario)  borra los datos personales de una cuenta que se elimina, también
--                          de su historial (Ley Orgánica de Protección de Datos Personales: derecho de eliminación).
--                          Los pedidos se conservan (obligaciones contables), pero ya no apuntan a una persona.
-- =============================================================================

CREATE TABLE TACEPTACIONESLEGALES (
    SACEPTACION     BIGINT        GENERATED ALWAYS AS IDENTITY,
    CUSUARIO        VARCHAR(30)   NOT NULL,
    DOCUMENTO       VARCHAR(30)   NOT NULL,
    VERSION         VARCHAR(20)   NOT NULL,
    FACEPTACION     TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    IP              VARCHAR(45),
    PLATAFORMA      VARCHAR(20),
    CONSTRAINT IPKACEPTACIONESLEGALES PRIMARY KEY (SACEPTACION),
    CONSTRAINT FKACEPLEGUSUID FOREIGN KEY (CUSUARIO) REFERENCES TUSUARIOSID (CUSUARIO),
    CONSTRAINT UQACEPLEGVERSION UNIQUE (CUSUARIO, DOCUMENTO, VERSION),
    CONSTRAINT CKACEPLEGDOC CHECK (DOCUMENTO IN ('terminos-cliente', 'terminos-vendedor', 'terminos-repartidor', 'privacidad'))
);
COMMENT ON TABLE TACEPTACIONESLEGALES IS 'Prueba de aceptación de los términos y la política de privacidad (una fila por documento y versión)';
COMMENT ON COLUMN TACEPTACIONESLEGALES.DOCUMENTO IS 'terminos-cliente, terminos-vendedor, terminos-repartidor o privacidad (backend/legal/<documento>.md)';
COMMENT ON COLUMN TACEPTACIONESLEGALES.VERSION IS 'Versión del documento que aceptó (cabecera "version" del .md)';

-- -----------------------------------------------------------------------------
-- Historial: modo borrado
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION FNVERSION() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_ahora TIMESTAMPTZ := clock_timestamp();
BEGIN
    -- Borrado de datos personales: se cambia la fila tal cual (vigente o de historial), sin copiar la anterior
    IF current_setting('vallexpress.borrado', true) = 'si' THEN
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        RETURN NEW;
    END IF;

    IF OLD.FHASTA <> '2999-12-31 00:00:00-05' THEN
        RETURN NULL;                                           -- fila de historial: intocable
    END IF;

    EXECUTE format(
        'INSERT INTO %I.%I SELECT * FROM jsonb_populate_record(NULL::%I.%I, $1)',
        TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_TABLE_SCHEMA, TG_TABLE_NAME)
    USING to_jsonb(OLD) || jsonb_build_object('fhasta', v_ahora);   -- copia cerrada de la versión anterior

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;                                            -- se borra la vigente; queda la copia cerrada
    END IF;

    NEW.FHASTA := OLD.FHASTA;
    NEW.FDESDE := v_ahora;
    NEW.VERSIONCONTROL := OLD.VERSIONCONTROL + 1;
    NEW.CUSUARIO_MODIFICACION := USUARIOACTUAL();
    RETURN NEW;
END $$;

-- -----------------------------------------------------------------------------
-- Eliminación de los datos personales de una cuenta
-- -----------------------------------------------------------------------------
-- Se llama dentro de la transacción que da de baja la cuenta. Devuelve los códigos de las fotos de perfil que
-- quedaron sin usar, para que el servidor borre los archivos del disco.
CREATE FUNCTION ELIMINARDATOSPERSONALES(p_persona BIGINT, p_usuario VARCHAR) RETURNS SETOF BIGINT LANGUAGE plpgsql AS $$
DECLARE
    v_fotos BIGINT[];
BEGIN
    SELECT array_agg(DISTINCT CARCHIVO_FOTO) INTO v_fotos FROM TPERSONAS WHERE CPERSONA = p_persona AND CARCHIVO_FOTO IS NOT NULL;

    PERFORM set_config('vallexpress.borrado', 'si', true);

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
COMMENT ON FUNCTION ELIMINARDATOSPERSONALES(BIGINT, VARCHAR) IS 'Borra los datos personales de una cuenta eliminada, también del historial; devuelve las fotos que quedaron sin usar';
