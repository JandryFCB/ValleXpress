-- =============================================================================
-- 011 · VENCIMIENTO DE PEDIDOS: que ningún pedido quede varado horas o días
-- =============================================================================
--   TCONFIGURACIONES   PEDIDOAVISOSINREPARTIDORMIN   (30)  aviso: nadie lo ha recogido todavía
--                      PEDIDOVENCESINREPARTIDORMIN   (60)  se cancela solo: nadie lo recogió a tiempo
--                      PEDIDOVENCEPENDIENTEMIN       (30)  se cancela solo: el negocio no respondió
-- Los minutos del "sin repartidor" se cuentan desde que el negocio lo dejó LISTO (aunque un repartidor lo haya
-- aceptado, si no lo recoge también vence). Los de "pendiente", desde que el cliente hizo el pedido.
-- Un vigilante del backend revisa cada minuto; el stock vuelve y todos reciben el aviso.
-- =============================================================================

INSERT INTO TCONFIGURACIONES (CCONFIGURACION, VALOR, DESCRIPCION) VALUES
    ('PEDIDOAVISOSINREPARTIDORMIN', '30', 'Minutos listo sin que un repartidor lo recoja para avisar al negocio, al admin y otra vez a los repartidores'),
    ('PEDIDOVENCESINREPARTIDORMIN', '60', 'Minutos listo sin que un repartidor lo recoja para cancelarlo automáticamente'),
    ('PEDIDOVENCEPENDIENTEMIN',     '30', 'Minutos sin que el negocio responda (pendiente) para cancelarlo automáticamente');
