-- =============================================================================
-- 004 · VUSUARIOS: vista de LECTURA con todo lo vigente de un usuario
-- =============================================================================
-- Une usuario + persona + teléfono principal + estado de acceso, solo con filas vigentes.
-- El backend la usa para leer (middleware de autenticación, perfil, login). Para ESCRIBIR se usan
-- las tablas reales (TPERSONAS, TUSUARIOS, TPERSONATELEFONOS, TUSUARIOSACCESO).
-- =============================================================================
CREATE VIEW VUSUARIOS AS
SELECT u.CUSUARIO                              AS USUARIO,
       u.CPERSONA,
       u.CROL                                  AS ROL,
       u.CESTATUSUSUARIO                       AS ESTATUS,
       (u.CESTATUSUSUARIO = '001')             AS ACTIVO,
       p.NOMBRES,
       p.APELLIDOS,
       p.CORREO                                AS EMAIL,
       (p.FCORREOVERIFICADO IS NOT NULL)       AS EMAILVERIF,
       p.FCORREOVERIFICADO                     AS EMAILVERIFEN,
       p.CTIPODOCUMENTO                        AS TIPODOC,
       p.NUMERODOCUMENTO                       AS NUMDOC,
       t.NUMEROTELEFONO                        AS TELEFONO,
       u.CLAVEHASH,
       u.FCLAVECAMBIO                          AS CLAVECAMBIADAEN,
       u.FTERMINOS                             AS TERMINOSEN,
       u.VERSIONTERMINOS                       AS TERMINOSVER,
       COALESCE(a.NUMEROINTENTOS, 0)           AS INTENTOSFALLIDOS,
       a.FBLOQUEADOHASTA                       AS BLOQUEADOHASTA,
       a.FULTIMACONEXION                       AS ULTIMACONEXION,
       u.FDESDE                                AS CREADOEN
  FROM TUSUARIOS u
  JOIN TPERSONAS p ON p.CPERSONA = u.CPERSONA AND p.FHASTA = '2999-12-31 00:00:00-05'
  LEFT JOIN LATERAL (
        SELECT NUMEROTELEFONO FROM TPERSONATELEFONOS
         WHERE CPERSONA = u.CPERSONA AND FHASTA = '2999-12-31 00:00:00-05'
         ORDER BY ESPRINCIPAL DESC, STELEFONO LIMIT 1) t ON TRUE
  LEFT JOIN TUSUARIOSACCESO a ON a.CUSUARIO = u.CUSUARIO
 WHERE u.FHASTA = '2999-12-31 00:00:00-05';

COMMENT ON VIEW VUSUARIOS IS 'Lectura: usuario + persona + teléfono principal + acceso, solo lo vigente';
