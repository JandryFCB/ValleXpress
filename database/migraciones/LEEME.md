# Migraciones

`database/schema.sql` es la **línea base** (versión 2) y sirve para crear la base desde cero.

Cuando la base ya tenga datos reales que no se quieran perder, cada cambio de esquema se agrega aquí como
`001_descripcion.sql`, `002_...` (en orden), y **también** se aplica a `schema.sql` para que una instalación
nueva quede igual. Reglas de cada migración:

1. Una sola transacción (`BEGIN; ... COMMIT;`) y una guarda que la rechace si ya se aplicó.
2. Antes de aplicarla a la base real: respaldo con `pg_dump` fuera del repo y prueba en una copia
   (`pg_dump | psql` hacia una base temporal).
3. Si toca columnas de una tabla versionada, usar `AGREGARCOLUMNA`, `RENOMBRARCOLUMNA` o `CAMBIARTIPOCOLUMNA`
   (cambian la tabla y su `HIST...` a la vez). Para actualizar filas sin generar versiones en `HIST`:
   `SET LOCAL session_replication_role = replica;`.

Hasta ahora no hay migraciones: la 001 (usuario de login y `FHASTA`) quedó incluida en la línea base.
