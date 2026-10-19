-- =============================================================================
-- 025 · Plazo para que el repartidor suba sus documentos
-- =============================================================================
--   TCONFIGURACIONES   DOCUMENTOSPLAZODIAS (7): días que tiene un repartidor pendiente para subir todos sus documentos.
--                      Al día 1 y al día 3 se le recuerda; al vencer, la solicitud se cierra (queda "rechazada" con el
--                      motivo) y puede pedir revisión cuando los suba. Su cuenta no se bloquea ni se elimina.
-- =============================================================================
INSERT INTO TCONFIGURACIONES (CCONFIGURACION, VALOR, DESCRIPCION) VALUES
    ('DOCUMENTOSPLAZODIAS', '7', 'Días que tiene un repartidor nuevo para subir sus documentos antes de que se cierre su solicitud');
