-- =============================================================================
-- 012 · TARIFAS: envío por distancia y comisión de ValleXpress
-- =============================================================================
--   TCONFIGURACIONES   ENVIOBASE (1.00), ENVIOPORKM (0.30), ENVIOFACTORRUTA (1.3), COMISIONPORCENTAJE (10)
--   TPEDIDOS           DISTANCIAKM, COMISIONPORCENTAJE, COMISION    · histórica
-- Decisiones (2026-10-16):
--   * El envío lo calcula ValleXpress: base + valor por km de RUTA (la distancia en línea recta por un factor,
--     porque las calles no van en línea recta), redondeado hacia arriba a 5 centavos (fácil de dar vuelto).
--     El costo de envío fijo de cada negocio (TNEGOCIOS.COSTOENVIO) deja de usarse.
--   * El repartidor se lleva el 100 % del envío.
--   * ValleXpress cobra al NEGOCIO un % de lo vendido en productos; el cliente no paga de más.
--   * Precios con IVA incluido: la app no suma impuestos.
-- Cada pedido GUARDA su distancia, el % y la comisión del momento: cambiar las tarifas no altera los pedidos viejos.
-- =============================================================================

INSERT INTO TCONFIGURACIONES (CCONFIGURACION, VALOR, DESCRIPCION) VALUES
    ('ENVIOBASE',          '1.00', 'Envío: tarifa base de cada pedido (USD)'),
    ('ENVIOPORKM',         '0.30', 'Envío: valor por cada km de ruta desde el local hasta el cliente (USD)'),
    ('ENVIOFACTORRUTA',    '1.3',  'Envío: la distancia en línea recta se multiplica por este factor para aproximar la ruta por calles'),
    ('COMISIONPORCENTAJE', '10',   'Comisión de ValleXpress sobre lo vendido en productos (porcentaje, la paga el negocio)');

ALTER TABLE TPEDIDOS ADD COLUMN DISTANCIAKM        NUMERIC(6,2);
ALTER TABLE TPEDIDOS ADD COLUMN COMISIONPORCENTAJE NUMERIC(5,2) NOT NULL DEFAULT 0;
ALTER TABLE TPEDIDOS ADD COLUMN COMISION           NUMERIC(10,2) NOT NULL DEFAULT 0;

COMMENT ON COLUMN TPEDIDOS.DISTANCIAKM IS 'Distancia de ruta estimada del local a la entrega (km) con la que se calculó el envío';
COMMENT ON COLUMN TPEDIDOS.COMISIONPORCENTAJE IS 'Porcentaje de comisión de ValleXpress vigente al crear el pedido';
COMMENT ON COLUMN TPEDIDOS.COMISION IS 'Comisión de ValleXpress (USD) = subtotal de productos x porcentaje; el negocio recibe subtotal - comisión';
COMMENT ON COLUMN TNEGOCIOS.COSTOENVIO IS 'OBSOLETO desde la migración 012: el envío lo calcula ValleXpress por distancia (ENVIOBASE, ENVIOPORKM)';
