-- =============================================================================
-- 013 · ZONA DE SERVICIO: dónde funciona ValleXpress (por ahora, Yantzaza)
-- =============================================================================
--   TCONFIGURACIONES   ZONANOMBRE ("Yantzaza"), ZONALATITUD, ZONALONGITUD (centro), ZONARADIOKM (15)
-- Las direcciones de los clientes y el local de cada negocio deben quedar dentro del círculo; fuera se responde
-- "ValleXpress todavía no llega a esa zona". ZONARADIOKM = 0 desactiva el límite (lo usan las pruebas).
-- A futuro (varias ciudades) esto pasa a una tabla de zonas, cada una con sus tarifas y sus negocios.
-- =============================================================================

INSERT INTO TCONFIGURACIONES (CCONFIGURACION, VALOR, DESCRIPCION) VALUES
    ('ZONANOMBRE',   '"Yantzaza"', 'Nombre de la zona donde funciona ValleXpress (se muestra al cliente)'),
    ('ZONALATITUD',  '-3.8277',    'Centro de la zona de servicio: latitud'),
    ('ZONALONGITUD', '-78.7593',   'Centro de la zona de servicio: longitud'),
    ('ZONARADIOKM',  '15',         'Radio de la zona de servicio en km desde el centro (0 = sin límite)');
