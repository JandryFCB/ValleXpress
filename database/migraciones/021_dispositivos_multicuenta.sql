-- =============================================================================
-- 021 · Un celular con varias cuentas de la misma persona
-- =============================================================================
--   TDISPOSITIVOS   el mismo token de Firebase puede quedar registrado para varias cuentas de la MISMA persona
--                   (su cuenta de negocio sigue recibiendo los pedidos mientras usa la app como cliente). Si el
--                   celular pasa a otra persona, el servidor borra los registros de la anterior.
-- =============================================================================
ALTER TABLE TDISPOSITIVOS DROP CONSTRAINT UQDISPOSITIVOSTOKEN;
ALTER TABLE TDISPOSITIVOS ADD CONSTRAINT UQDISPOSITIVOSTOKENUSU UNIQUE (TOKENFCM, CUSUARIO);
CREATE INDEX IXDISPOSITIVOSTOKEN ON TDISPOSITIVOS (TOKENFCM);
COMMENT ON COLUMN TDISPOSITIVOS.TOKENFCM IS 'Token de Firebase del celular; puede repetirse solo entre cuentas de la misma persona';
