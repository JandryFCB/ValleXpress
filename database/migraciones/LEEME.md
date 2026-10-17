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
| `007_pedidos.sql` | Estatus de pedido, métodos de pago, pedidos (histórica = línea de tiempo), detalles, calificaciones y notificaciones |
| `008_repartidores.sql` | Tipos de vehículo, perfil del repartidor (histórica), estado en línea y ubicaciones del recorrido |
| `009_motivo_aprobacion.sql` | Motivo del rechazo o la suspensión en negocios y repartidores |
| `010_perfiles.sql` | Perfiles y permisos: registro abierto por perfil y aprobación automática por separado para vendedor y repartidor (reemplaza a `APROBACIONAUTOMATICA`) |
| `011_vencimiento_pedidos.sql` | Minutos para avisar y cancelar solos los pedidos sin repartidor (desde que quedan listos) o sin respuesta del negocio |
| `012_tarifas.sql` | Envío por distancia (base + km de ruta) y comisión de ValleXpress; cada pedido guarda su distancia, % y comisión |
| `013_zona_servicio.sql` | Zona de servicio (Yantzaza, centro y radio): direcciones y locales fuera de ella se rechazan |
| `014_liquidaciones.sql` | Cobro semanal de la comisión a cada negocio: `TLIQUIDACIONES` (pagos), días de gracia y cuenta para transferir |

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
