# Migraciones

La base se construye por bloques. Cada archivo es un paso; Docker los ejecuta en orden alfabético
**solo al crear la base por primera vez**.

| Archivo | Contenido |
|---|---|
| `000_base.sql` | Zona horaria, `USUARIOACTUAL()`, trigger de historial `FNVERSION` y `ACTIVARVERSION()` |
| `001_identidad.sql` | Roles, estatus, tipos de documento, personas, usuarios, acceso y teléfonos. Admin = persona 1 |
| `002_sesiones.sql` | Sesión persistente (refresh tokens con rotación), códigos de verificación y dispositivos push |
| `003_logs_configuracion.sql` | `TCONFIGURACIONES` (parámetros) y logs: `TLOGERRORES`, `TLOGMENSAJES`, `TAUDITORIA` |
| `004_vusuarios.sql` | Vista `VUSUARIOS` de lectura (usuario + persona + teléfono + acceso) |
| `005_direcciones.sql` | Direcciones de la persona (`TPERSONADIRECCIONES`), tipos de dirección y de teléfono; agrega el tipo a `TPERSONATELEFONOS` |
| `006_catalogo.sql` | Imágenes (`TARCHIVOS`), negocios con código propio, estado, horarios, productos e inventario; foto de perfil |

## Patrón (ver `PATRON_TABLAS_FITBANK.md`)

- Tabla **ID**: solo el código (destino de las FK). Sin historial.
- Tabla **histórica**: PK = código + `FHASTA`; lleva `FDESDE`, `FHASTA`, `VERSIONCONTROL` y `CUSUARIO_MODIFICACION`.
  La fila vigente tiene `FHASTA = 2999-12-31`. `UPDATE` y `DELETE` dejan una copia cerrada (trigger `FNVERSION`).
- Tabla **simple** (sesiones, códigos, ubicaciones, logs): sin historial.
- Entidades: números desde el **2** (el 1 es el administrador). Catálogos: `'001'`, `'002'`...
- Únicos solo entre filas vigentes: `CREATE UNIQUE INDEX ... WHERE FHASTA = '2999-12-31 00:00:00-05'`.
- El backend ejecuta `SET LOCAL app.usuario = 'jcayapa';` al inicio de cada transacción para registrar quién cambió.

## Uso

```bash
docker compose --env-file backend/.env up -d                       # levantar (pgAdmin: localhost:5433)
docker compose --env-file backend/.env down -v && \
docker compose --env-file backend/.env up -d                       # empezar de cero
```

## Reglas para agregar un bloque

1. Archivo nuevo con el siguiente número (`002_sesiones.sql`...), en una sola transacción lógica y sin tocar los anteriores
   mientras no haya datos reales. Con datos reales, los archivos ya aplicados no se editan: se agrega uno nuevo.
2. Cada tabla y columna lleva su `COMMENT ON`.
3. Probar con `down -v` y `up -d`, y revisar `docker logs vallexpress_db`.
