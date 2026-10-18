-- =============================================================================
-- 022 · Cupo de repartidores y WhatsApp de soporte
-- =============================================================================
--   TCONFIGURACIONES   CUPOREPARTIDORES   cuántos repartidores aprobados puede haber a la vez (0 = sin límite). Lleno
--                                         el cupo, nadie más se registra como repartidor y el admin no aprueba a más.
--                      SOPORTEWHATSAPP    número de WhatsApp de soporte (se muestra cuando no hay cupos)
-- =============================================================================
INSERT INTO TCONFIGURACIONES (CCONFIGURACION, VALOR, DESCRIPCION) VALUES
    ('CUPOREPARTIDORES', '0',  'Máximo de repartidores aprobados a la vez (0 = sin límite)'),
    ('SOPORTEWHATSAPP',  '""', 'WhatsApp de soporte de ValleXpress (09XXXXXXXX), se muestra a quien no encuentra cupo');
