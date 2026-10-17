-- =============================================================================
-- 017 · FNCFHASTA(): la fecha "vigente" de las tablas con historial
-- =============================================================================
-- Para no escribir la fecha a mano en las consultas:
--   SELECT * FROM TNEGOCIOS WHERE FHASTA = FNCFHASTA();
-- Devuelve TIMESTAMPTZ con la zona de Ecuador (-05), igual que las columnas FHASTA: así compara bien sin importar
-- la zona horaria de la sesión (pgAdmin, el backend o el servidor).
-- =============================================================================

CREATE OR REPLACE FUNCTION FNCFHASTA() RETURNS TIMESTAMPTZ LANGUAGE sql IMMUTABLE AS $$
    SELECT '2999-12-31 00:00:00-05'::TIMESTAMPTZ;
$$;
COMMENT ON FUNCTION FNCFHASTA() IS 'Fecha de vigencia de las filas actuales (FHASTA): 2999-12-31 00:00:00-05';
