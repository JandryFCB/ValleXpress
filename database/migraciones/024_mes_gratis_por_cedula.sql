-- =============================================================================
-- 024 · Mes gratis de la suscripción: uno solo por cédula y perfil, para siempre
-- =============================================================================
--   TBENEFICIOS   cuándo se aprobó por PRIMERA vez a una persona como vendedor o repartidor               · simple
--     HUELLA        SHA-256 del tipo y número de documento (no se guarda la cédula: si la persona elimina su cuenta
--                   sus datos se borran, pero la huella queda para que no vuelva a tener el mes gratis)
-- Sin esto bastaba con eliminar la cuenta de repartidor y crear otra con los mismos datos para recibir otro mes gratis.
-- =============================================================================
CREATE TABLE TBENEFICIOS (
    HUELLA      CHAR(64)      NOT NULL,
    CROL        CHAR(3)       NOT NULL,
    FPRIMERA    TIMESTAMPTZ   NOT NULL,
    CONSTRAINT IPKBENEFICIOS PRIMARY KEY (HUELLA, CROL),
    CONSTRAINT FKBENEFICIOSROL FOREIGN KEY (CROL) REFERENCES TROLESID (CROL)
);
COMMENT ON TABLE TBENEFICIOS IS 'Primera aprobación de cada persona (huella de su documento) como vendedor o repartidor: el mes gratis es uno solo';
