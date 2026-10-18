-- =============================================================================
-- 019 · Documentos del repartidor (verificación de identidad y del vehículo)
-- =============================================================================
--   TREPARTIDORDOCUMENTOS (simple) la foto vigente de cada documento del repartidor. Al subir otra del mismo tipo se
--                         reemplaza. El administrador las revisa antes de aprobarlo.
--     CEDULAFRENTE / CEDULAREVERSO   cédula de identidad
--     SELFIE                         foto del repartidor sosteniendo su cédula (que la cara coincida)
--     LICENCIA                       licencia de conducir (solo vehículos con placa)
--     MATRICULA                      matrícula del vehículo (solo vehículos con placa)
-- Al eliminar la cuenta se borran las filas y los archivos.
-- =============================================================================

CREATE TABLE TREPARTIDORDOCUMENTOS (
    CUSUARIO        VARCHAR(30)   NOT NULL,
    TIPO            VARCHAR(15)   NOT NULL,
    CARCHIVO        BIGINT        NOT NULL,
    FSUBIDO         TIMESTAMPTZ   NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT IPKREPARTIDORDOCUMENTOS PRIMARY KEY (CUSUARIO, TIPO),
    CONSTRAINT FKREPDOCUSUID  FOREIGN KEY (CUSUARIO) REFERENCES TUSUARIOSID (CUSUARIO),
    CONSTRAINT FKREPDOCARCH   FOREIGN KEY (CARCHIVO) REFERENCES TARCHIVOS (CARCHIVO),
    CONSTRAINT CKREPDOCTIPO   CHECK (TIPO IN ('CEDULAFRENTE', 'CEDULAREVERSO', 'SELFIE', 'LICENCIA', 'MATRICULA'))
);
COMMENT ON TABLE TREPARTIDORDOCUMENTOS IS 'Fotos de los documentos del repartidor (una vigente por tipo) para verificar su identidad y su vehículo';
COMMENT ON COLUMN TREPARTIDORDOCUMENTOS.TIPO IS 'CEDULAFRENTE, CEDULAREVERSO, SELFIE (con la cédula), LICENCIA o MATRICULA';
