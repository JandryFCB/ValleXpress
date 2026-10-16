-- =============================================================================
-- 009 · MOTIVO DE LA APROBACIÓN: por qué el administrador rechazó o suspendió un negocio o un repartidor
-- =============================================================================
--   TNEGOCIOS.MOTIVOAPROBACION       · histórica (cada decisión queda en su versión)
--   TREPARTIDORES.MOTIVOAPROBACION   · histórica
-- Antes el motivo solo viajaba en la notificación; ahora la app lo muestra en la pantalla de "cuenta en revisión".
-- Al aprobar o devolver a revisión se limpia (NULL).
-- =============================================================================

ALTER TABLE TNEGOCIOS ADD COLUMN MOTIVOAPROBACION VARCHAR(300);
ALTER TABLE TREPARTIDORES ADD COLUMN MOTIVOAPROBACION VARCHAR(300);

COMMENT ON COLUMN TNEGOCIOS.MOTIVOAPROBACION IS 'Motivo del rechazo o la suspensión que escribió el administrador (NULL si está pendiente o aprobado)';
COMMENT ON COLUMN TREPARTIDORES.MOTIVOAPROBACION IS 'Motivo del rechazo o la suspensión que escribió el administrador (NULL si está pendiente o aprobado)';
