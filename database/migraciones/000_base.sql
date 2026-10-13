-- =============================================================================
-- 000 · BASE: zona horaria y funciones comunes
-- =============================================================================
-- Sigue el patrón de PATRON_TABLAS_FITBANK.md:
--   * Tablas "ID": solo guardan el código (destino de las claves foráneas). Sin historial.
--   * Tablas históricas: PK = código + FHASTA, y llevan FDESDE, FHASTA, VERSIONCONTROL.
--     La fila vigente tiene FHASTA = 2999-12-31. Al modificarla, el trigger FNVERSION deja
--     una copia cerrada (FHASTA = ahora) y la fila vigente sigue con FDESDE = ahora.
--   * Tablas simples (sesiones, códigos, ubicaciones, logs): se insertan una vez, sin historial.
-- Nombres en MAYÚSCULAS, en español, sin guion bajo (salvo el rol de una FK: CUSUARIO_MODIFICACION).
-- PostgreSQL los guarda en minúsculas; NO se usan comillas dobles.
-- =============================================================================

-- Las fechas se guardan en UTC y se muestran en hora de Ecuador (así FHASTA se ve 2999-12-31 00:00:00).
DO $$ BEGIN
    EXECUTE format('ALTER DATABASE %I SET timezone TO %L', current_database(), 'America/Guayaquil');
END $$;
SET timezone TO 'America/Guayaquil';

-- -----------------------------------------------------------------------------
-- Quién hizo el cambio: el backend ejecuta  SET LOCAL app.usuario = 'jcayapa';  al inicio de su transacción
-- -----------------------------------------------------------------------------
CREATE FUNCTION USUARIOACTUAL() RETURNS VARCHAR(30) LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('app.usuario', true), '')::VARCHAR(30)
$$;

-- -----------------------------------------------------------------------------
-- Historial en la misma tabla (tablas históricas)
-- -----------------------------------------------------------------------------
-- UPDATE sobre la fila vigente: guarda una copia cerrada (FHASTA = ahora) y deja la vigente con
--   FDESDE = ahora, VERSIONCONTROL + 1 y CUSUARIO_MODIFICACION = quien hizo el cambio.
-- UPDATE o DELETE sobre una fila ya cerrada: se ignora (el historial no se toca).
-- Se usa clock_timestamp() (no now()) para que dos cambios en la misma transacción no choquen en la PK.
CREATE FUNCTION FNVERSION() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_ahora TIMESTAMPTZ := clock_timestamp();
BEGIN
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

-- Activa el historial en una tabla:  SELECT ACTIVARVERSION('TUSUARIOS');
CREATE FUNCTION ACTIVARVERSION(p_tabla TEXT) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION FNVERSION()',
                   'tr' || lower(p_tabla) || 'version', lower(p_tabla));
END $$;

-- -----------------------------------------------------------------------------
-- Utilidades de texto
-- -----------------------------------------------------------------------------
-- Texto en minúsculas, sin tildes ni símbolos
CREATE FUNCTION LIMPIARTEXTO(p TEXT) RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
  SELECT regexp_replace(
           lower(translate(coalesce(p, ''), 'áàäâéèëêíìïîóòöôúùüûñçÁÀÄÂÉÈËÊÍÌÏÎÓÒÖÔÚÙÜÛÑÇ', 'aaaaeeeeiiiioooouuuuncAAAAEEEEIIIIOOOOUUUUNC')),
           '[^a-z0-9 ]', '', 'g')
$$;
