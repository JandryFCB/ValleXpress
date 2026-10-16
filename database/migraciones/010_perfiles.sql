-- =============================================================================
-- 010 · PERFILES Y PERMISOS: qué perfiles pueden registrarse y cuáles necesitan aprobación
-- =============================================================================
--   TCONFIGURACIONES   REGISTROCLIENTE, REGISTROVENDEDOR, REGISTROREPARTIDOR       (¿registro abierto?)
--                      APROBACIONAUTOVENDEDOR, APROBACIONAUTOREPARTIDOR           (¿nacen aprobados?)
-- Reemplaza a APROBACIONAUTOMATICA (una sola para los dos): ahora cada perfil se maneja por separado desde el
-- panel del administrador. El cliente no pasa por aprobación: solo se puede abrir o cerrar su registro.
-- Las cuentas que crea el administrador no dependen de estos permisos.
-- =============================================================================

INSERT INTO TCONFIGURACIONES (CCONFIGURACION, VALOR, DESCRIPCION)
SELECT v.clave, v.valor, v.descripcion
FROM (VALUES
    ('REGISTROCLIENTE',    'true'::jsonb, 'Los clientes pueden crear su cuenta desde la app'),
    ('REGISTROVENDEDOR',   'true'::jsonb, 'Los vendedores pueden crear su cuenta desde la app'),
    ('REGISTROREPARTIDOR', 'true'::jsonb, 'Los repartidores pueden crear su cuenta desde la app')
) AS v(clave, valor, descripcion);

-- La aprobación automática de cada perfil arranca con el valor que tenía la configuración anterior
INSERT INTO TCONFIGURACIONES (CCONFIGURACION, VALOR, DESCRIPCION)
SELECT v.clave, COALESCE(a.valor, 'true'::jsonb), v.descripcion
FROM (VALUES
    ('APROBACIONAUTOVENDEDOR',   'Los negocios nuevos nacen aprobados (si no, esperan la revisión del administrador)'),
    ('APROBACIONAUTOREPARTIDOR', 'Los repartidores nuevos nacen aprobados (si no, esperan la revisión del administrador)')
) AS v(clave, descripcion)
LEFT JOIN TCONFIGURACIONES a ON a.CCONFIGURACION = 'APROBACIONAUTOMATICA' AND a.FHASTA = '2999-12-31 00:00:00-05';

-- La anterior queda cerrada en el historial (el trigger guarda la copia)
DELETE FROM TCONFIGURACIONES WHERE CCONFIGURACION = 'APROBACIONAUTOMATICA' AND FHASTA = '2999-12-31 00:00:00-05';
