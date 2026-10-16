# Informe de avances: ValleXpress

Documento breve de seguimiento. Se actualiza al cerrar cada bloque de trabajo.
Plan completo y checklist: [ROADMAP_TOP.md](ROADMAP_TOP.md).

---

## Estado actual

**Reconstrucción desde cero por flujos** · Los 5 flujos **hechos** (Cuenta, Catálogo, Pedidos del cliente, Vendedor y repartidor, Administrador) · Siguiente: probar el panel en el móvil, producción y reglas de negocio · Última actualización: 2026-10-15

> El 2026-10-12 se borró el esquema anterior (v2/V3) y la BD se rehízo con el patrón T de `PATRON_TABLAS_FITBANK.md`,
> por bloques (`database/migraciones`). Los bloques 1 a 13 de abajo describen el esquema ANTERIOR: quedan como historial.
> Cada flujo = migrar el backend a las tablas nuevas + rediseñar sus pantallas (tema claro/oscuro) + pruebas.

| Área | Estado |
|---|---|
| Ramas: `main` (estable), `desarrollo`, `feat/bd-desde-cero`, `feat/app-sesion`, `feat/flujo-cuenta`, `feat/flujo-catalogo`, `feat/flujo-pedidos` | Hecho, todo subido a GitHub |
| BD nueva: migraciones 000 a 008 (55 tablas + vista `VUSUARIOS`), PostgreSQL 17 en Docker | **Hecha y probada** |
| Sesión persistente (token 15 min + refresh token 90 días con rotación) | **Hecha y probada** (backend y app, también en el móvil) |
| Backend **auth** | **Hecho: 104 pruebas** |
| Backend **direcciones y teléfonos** | **Hecho: 71 pruebas** |
| App: sistema de diseño + tema claro/oscuro/sistema con la paleta del logo | **Hecho** |
| App rediseñada: login, registro (4 pasos), recuperar clave, perfil, direcciones con mapa, teléfonos, configuración | **Hecho: 24 pruebas**, verificado en el móvil |
| Backend **negocios, horarios, productos, inventario e imágenes** (+ foto de perfil real) | **Hecho: 72 pruebas** (total 247) |
| App: explorar negocios y su menú (cliente); mi negocio, horario y productos (vendedor) | **Hecho**, verificado en el móvil |
| Backend **pedidos, calificaciones y notificaciones** (+ avisos en vivo por socket) | **Hecho: 79 pruebas** (total 326) |
| App: inicio nuevo del cliente, carrito, pedido, seguimiento en vivo, recibir, calificar, avisos | **Hecho: 7 pruebas nuevas**, verificado en el móvil |
| Backend **repartidores** (perfil, en línea, aceptar, recoger, entregar) + ubicación en vivo por socket | **Hecho: 51 pruebas** (total 377) |
| App: inicio del vendedor (pedidos) y del repartidor (entregas), mapa en vivo para cliente, negocio y repartidor | **Hecho**, verificado en el móvil con el simulador |
| Tiempo real: geocerca "tu repartidor está cerca", GPS que ahorra batería, reconexión al volver a la app | **Hecho: 3 pruebas nuevas**, verificado en el móvil |
| App: diseño interactivo (animaciones, esqueletos de carga, confeti, transiciones) | **Hecho: 7 pruebas** |
| Backend **administrador** (resumen, aprobaciones, gestión de negocios y productos, pedidos, usuarios) | **Hecho: 81 pruebas** (total 461) |
| App: panel del administrador (5 pestañas) y foto de perfil para todos los roles | **Hecho**, compila (falta probar en el móvil) |
| Antes de producción (claves, HTTPS, almacenamiento de imágenes) y reglas de negocio (IVA, comisión, envío) | Pendiente |

### Bloque 19 (2026-10-15): bloqueo claro y correos reales
- Login: avisa los intentos que quedan (3.º y 4.º fallo) y al 5.º muestra "Cuenta bloqueada por seguridad" con cuenta regresiva en vivo, recuperar contraseña (desbloquea al instante) y contactar a soporte. Cuenta bloqueada o dada de baja por el admin: lo dice con el correo de soporte.
- Correos reales por Brevo (plan gratis, 300/día; la clave anterior estaba vencida y faltaba en `.env`; se desactivó en Brevo el bloqueo por IP). Plantilla con los colores de la marca. Nuevos: bienvenida con usuario y contraseña temporal (cuentas creadas por el admin), aviso de bloqueo por intentos y avisos de bloqueo, baja, reactivación y contraseña nueva.
- Probado en el móvil con un Gmail real: bloqueo, recuperación y entrada con la contraseña nueva. 465 pruebas del backend.
- **Pendiente detectado:** con la aprobación automática apagada, el vendedor y el repartidor solo ven una insignia pequeña de "en revisión"; falta una pantalla clara por estado (pendiente / rechazado / suspendido con su motivo), el aviso al terminar el registro y el correo al aprobar o rechazar.

### Bloque 18 (2026-10-15): flujo Administrador, tiempo real y diseño
- **Tiempo real** (consejos del usuario): geocerca en el servidor (a menos de 150 m de la entrega el cliente recibe "¡Tu repartidor está cerca!", una sola vez); el GPS del repartidor no envía nada detenido (latido cada 30 s) e ignora los saltos con mala señal; al volver la app del segundo plano se reconecta y las pantallas se recargan; la moto se desliza durante el intervalo real entre posiciones.
- **Diseño interactivo**: tarjetas y botones que se hunden y vibran, esqueletos de carga, listas escalonadas, la portada del negocio "vuela" a su pantalla, carrito que rebota y cuenta el total, confeti al pedir y al recibir, transiciones al estilo Android moderno.
- **Administrador** (`/api/admin`): resumen con ventas del día y de la semana; aprobar, rechazar, suspender y reactivar negocios y repartidores con motivo (avisa al interesado); gestionar cualquier negocio con las mismas rutas del vendedor (`/api/admin/negocios/:id/gestion`: datos, local, horario, abrir/cerrar, imágenes y productos); editar el vehículo de un repartidor; ver todos los pedidos y cancelar una disputa; crear cuentas de cualquier rol, editarlas, ponerles clave o foto, bloquearlas, darlas de baja (inactivas, sin borrar el historial) y reactivarlas. Todo queda en la auditoría.
- La clave inicial del administrador se pone con `CLAVE=... npm run admin:clave` (la migración lo crea sin clave válida).
- **Foto de perfil**: el perfil rediseñado (banner del color del rol) permite subirla en todos los roles; el endpoint ya existía y la app no lo usaba.

### Bloque 17 (2026-10-14): flujo Vendedor y repartidor
- Migración 008: tipos de vehículo (con si llevan placa), `TREPARTIDORES` histórica, `TREPARTIDORESESTADO` (en línea, última ubicación, calificación, entregas) y `TREPARTIDORUBICACIONES` (recorrido de cada entrega, un punto cada 15 s; se purga a los 60 días).
- El repartidor se registra con su vehículo y placa. En línea ve los pedidos listos (y los que se están preparando) sin datos del cliente, con la distancia y lo que gana. Una entrega a la vez; si dos aceptan el mismo pedido, gana uno (bloqueo de fila).
- Ubicación en vivo: el celular del repartidor la envía por socket y el servidor la reenvía solo al cliente y al negocio de su entrega en curso. Al entregar, deja de compartirse.
- App: inicio del vendedor (aceptar con tiempo estimado, rechazar con motivo, preparando, listo) y del repartidor (en línea, aceptar, mapa, cómo llegar, llamar, cobrar, recogí/entregué, historial). El cliente ve la moto moviéndose en el mapa, quién lo lleva y cuánto falta, y puede calificar al repartidor.
- Se borró todo lo viejo: inicio anterior, pantallas y servicios de pedidos, rastreo, avisos, vendedor y repartidor, y el módulo `vendedores` del backend. El analizador de Flutter queda sin avisos.
- Simulador para desarrollo (`npm run simular:entrega`): hace de negocio y de repartidor para ver una entrega completa con un solo celular.

### Bloque 16 (2026-10-14): flujo Pedidos del cliente
- Migración 007: estatus de pedido y métodos de pago (con cuáles están activos), `TPEDIDOS` histórica (cada cambio de estado deja su versión: de ahí sale la hora de cada paso del seguimiento), detalle con el precio de ese momento, calificaciones y notificaciones.
- Reglas del servidor: negocio abierto (interruptor + horario) y aceptando pedidos, dirección propia y dentro del radio de entrega, pedido mínimo, solo productos disponibles, stock descontado de forma atómica y devuelto al cancelar o rechazar, montos siempre de la BD.
- El negocio confirma (con tiempo estimado), prepara, deja listo o rechaza; el cliente cancela mientras está pendiente, confirma que lo recibió y califica. Cada paso avisa al otro por socket y queda en su lista de avisos.
- App: inicio nuevo del cliente con pestañas, carrito de un solo negocio, seguimiento en vivo, mis pedidos y avisos. Probado en el móvil de punta a punta.
- Corregido en la prueba: el cliente de Socket.IO de Flutter entrega los datos dentro de una lista y se descartaban sin error (los avisos no llegaban).

### Bloque 15 (2026-10-14): flujo Catálogo
- Migración 006: archivos (imágenes), categorías de negocio, negocios con código propio y dueño, estado abierto/acepta pedidos, horario semanal (cruza medianoche), productos con historial e inventario aparte.
- Backend: `/api/negocios` (público: lista con filtros y menú) y `/api/mi-negocio` (vendedor: datos, logo, portada, local, horario, productos, stock). El vendedor puede registrar su negocio en el mismo paso del registro.
- App: Explorar negocios y detalle con el menú por secciones (lo oculto no sale y lo agotado se ve atenuado); Mi negocio, Horario, Mis productos y formulario de producto. Home y Perfil enlazan a las pantallas nuevas.
- Probado en el móvil con un vendedor y un cliente reales. Se corrigieron dos detalles: "Disponible" se partía en dos líneas y las sugerencias de sección quedaban tapadas por el teclado (ahora son chips).

### Bloque 14 (2026-10-12/13): reconstrucción, sesión persistente y flujo Cuenta
- BD desde cero con tablas `T…ID` + históricas (`FDESDE/FHASTA/VERSIONCONTROL`); códigos numéricos desde el 2 (el 1 es el administrador).
- Login y registro entregan token de acceso (15 min) y refresh token (90 días sin usar, rota en cada uso, detecta robo). La app lo guarda cifrado y renueva sola; probado cerrando y reabriendo la app en el móvil.
- Direcciones (con historial, una predeterminada, el local del negocio separado) y teléfonos (hasta 5, uno principal).
- App: sistema de diseño reutilizable y 10 pantallas rediseñadas con tema claro/oscuro. Se corrigió que los servicios ocultaban el mensaje real del servidor.
- Entorno: se quitó el emulador (la ventana salía negra y saturaba la RAM); se prueba en Chrome y en el móvil por USB.

---|---|
| Revisión inicial del proyecto | Hecha |
| Higiene del repositorio | Hecha (commit pendiente, ver abajo) |
| Secretos y configuración | Pendiente de claves (se hace antes de producción) |
| Rediseño de la base de datos | Hecho y aplicado (Bloque 2) |
| Helpers compartidos (`src/shared`) | Hechos y en uso (Bloque 3) |
| Módulo **auth** migrado al esquema nuevo | **Hecho y probado: 103/103** (Bloques 3 a 5) |
| Usuario para iniciar sesión (`USUARIO`, ej. `jcayapa`) | Hecho; ahora es la clave primaria (Bloque 5). Falta la pantalla de login de la app |
| Nombres sin comillas y claves legibles, sin UUID | **Hecho y probado: 103/103** (Bloque 5) |
| Módulos **vendedores y productos** | **Hechos y probados: 85/85** (Bloque 6) |
| Módulos **direcciones, pedidos (con sockets) y notificaciones** | **Hechos y probados: 106/106** (Bloque 7) |
| Módulo **repartidores** | **Hecho y probado: 47/47** (Bloque 8). **Con este, el backend queda completo** |
| Servicio de imágenes (ARCHIVOS + optimización con `sharp`) | **Hecho** (Bloque 6) |

---

## Bloque 1: Revisión y fundamentos

### Hallazgos principales de la revisión
1. `node_modules` estaba en git (8119 archivos) y el `.gitignore` era de Django.
2. Contraseña de BD (la clave de desarrollo actual) escrita en `database.js` y `docker-compose.yml`.
3. `GET /api/pedidos/:id` sin control de propiedad: cualquier usuario autenticado veía pedidos ajenos.
4. API en HTTP sin cifrado (`http://5.161.208.204:3000`).
5. Códigos de verificación con `Math.random` y logueados en consola si falla el correo.
6. Sin rate limit en login/registro; JWT de 30 días sin refresh.
7. Mucho código duplicado en controllers (try/catch, validaciones, tokens, rollback).

### Cambios realizados
| Cambio | Archivo(s) |
|---|---|
| `.gitignore` reescrito; `node_modules` y `tmp/` fuera de git | `.gitignore` |
| Sin contraseña por defecto; falla con mensaje claro si falta una variable | `backend/src/config/database.js` |
| Credenciales desde `.env`; puertos solo en `127.0.0.1`; monta `schema.sql` | `docker-compose.yml` |
| Plantilla de variables de entorno | `backend/.env.example` |
| `dotenv` cargado antes que cualquier módulo | `backend/src/server.js` |
| Helpers: `AppError`, `asyncHandler`, `response`, `withTransaction`, `validar`, `errorHandler`, `validators`, `normalizers`, `codes` | `backend/src/shared/` |

### Verificado
- `.env` y el JSON de Firebase Admin **nunca** estuvieron en el historial de git.
- `google-services.json` sí estuvo en el commit `eb5f79f` (se borró en `3a38425`).
- `database.js` y los helpers cargan sin errores; validadores y generador de códigos probados.

---

## Pendientes inmediatos

| # | Tarea | Responsable | Cuándo |
|---|---|---|---|
| 1 | **Poner una clave difícil** en `JWT_SECRET` (hoy es un correo) y en la BD (hoy es la de desarrollo). Anotarlas en un gestor de contraseñas | Usuario | Antes de producción |
| 2 | **Restringir la API key** de Firebase/Google en la consola de Google Cloud (no se sube a ningún Drive; es un ajuste en la consola) | Usuario | Antes de producción |
| 3 | **Commit** a `main`: cuando todo el esquema esté registrado y probado en la BD. Separar los cambios de Flutter que no son de esta tarea | Usuario | Tras migrar los módulos |
| 4 | App Flutter: pantalla de login con "Correo o usuario", registrar el token push (`registerDeviceToken`) y revisar las pantallas contra los endpoints nuevos | Ambos | Siguiente |
| 5 | Actualizar el README (dice que usa Multer y que tiene pagos integrados; ninguna de las dos cosas es cierta) y decidir las reglas de negocio pendientes (IVA, propina, cupones, comisión, pagos, reasignación de pedidos) | Ambos | Después |

---

## Riesgos y notas
- El formato de error se mantiene compatible con la app (`error` como texto + `code` extra), así que no hace falta tocar Flutter por ahora.
- Si ya existe un volumen de Postgres, cambiar la contraseña en `.env` **no** la cambia dentro de la BD.
- Los valores del `.env` se mostraron una vez en la conversación: tratar esas claves como comprometidas.

---

## Prueba de humo (2026-10-05)

| Prueba | Resultado |
|---|---|
| Contenedor `vallexpress_db` (Postgres 15) | Activo; volumen `vallexpress202_postgres_data`; 12 tablas CON datos de prueba (7 usuarios, 14 pedidos, 126 notificaciones; ver corrección) |
| Backend arranca con el nuevo `database.js` | OK, conexión a PostgreSQL establecida |
| `GET /api/health` | 200 |
| `POST /api/auth/login` con credenciales falsas | 401 `Credenciales inválidas` |
| `GET /api/pedidos/abc` sin token | 401 `Token no proporcionado` |

**Notas**
- No se ejecutó `docker compose up`: ya existía un contenedor con ese nombre y volumen anterior. El `docker-compose.yml` nuevo se probará al recrear el entorno desde cero.
- Firebase no inicializa en local: `FIREBASE_SERVICE_ACCOUNT_PATH` apunta a una ruta de servidor (`/opt/vallexpress/...`). Las notificaciones push solo funcionan donde exista ese archivo.
- Hay dos volúmenes antiguos (`vallexpress202_...` y `vallexpress_...`). Conviene eliminar el que sobre cuando se confirme que está vacío.

**Corrección:** en la primera revisión se informó que las tablas estaban vacías. Era un error: se usaron estadísticas de Postgres desactualizadas (`n_live_tup`). Conteos reales con `count(*)`: usuarios 7, vendedores 2, repartidores 2, productos 3, pedidos 14, detalle_pedidos 14, direcciones 4, notificaciones 126, password_reset_codes 13, resto 0. Son datos de prueba; el usuario autorizó borrarlos.

---

## Bloque 2: Rediseño de la base de datos (hecho)

> **Nota:** los nombres entre comillas en MAYÚSCULAS y las claves UUID de este bloque fueron reemplazados en el **Bloque 5** (nombres sin comillas y claves legibles). El resto sigue vigente.

**Archivo:** [database/schema.sql](database/schema.sql) · aplicado a `vallexpress_db` el 2026-10-05 (BD sin datos de prueba).

### Problemas del esquema anterior (según el volcado `datos_base.txt`)
| Problema | Detalle |
|---|---|
| Fechas inconsistentes | Mezcla de `timestamp` y `timestamptz`; `created_at` junto a `fecha_*` |
| Códigos sin patrón | `PED-72574747-700` (al azar) |
| Estados como texto libre | `'en_camino'` repetido en cada fila |
| Imágenes en base64 dentro de la BD | Una foto de perfil pesaba 568 KB; la BD ocupaba 14 MB con 7 usuarios |
| Cédula repetida | En usuarios, vendedores y repartidores |
| Índices duplicados, nombres mezclados | `idx_usuarios_email` y `usuarios_email` a la vez |

### Reglas del diseño
1. **Nombres:** español, MAYÚSCULAS, **sin guiones bajos** y cortos: `USUARIOS`, `DETALLEPEDIDO`, `HORARIOVENDEDOR`. Siempre entre comillas dobles en SQL.
2. **Estados y tipos en catálogos con código numérico de 3 dígitos** (`'001'`, `'002'`...). Las tablas de negocio guardan solo el código:

   | Catálogo | Ejemplo de códigos | Lo usan |
   |---|---|---|
   | `ESTADOPEDIDO` | 001 Pendiente · 003 Preparando · 006 En camino · 008 Recibido · 010 Cancelado | `PEDIDOS.ESTADO` |
   | `ESTADOPRODUCTO` | 001 Disponible · 002 Agotado · 003 No disponible · 004 Descontinuado | `PRODUCTOS.ESTADO` |
   | `ESTADOPAGO` | 001 Pendiente · 002 Aprobado · 004 Reembolsado | `PAGOS.ESTADO` |
   | `ESTADOAPROBACION` | 001 Pendiente · 002 Aprobado · 003 Rechazado | vendedores, repartidores, documentos |
   | `ROLES`, `METODOPAGO`, `TIPOVEHICULO`, `CATEGORIAS` | 001, 002... | usuarios, pedidos, repartidores, vendedores |

   Columnas de cada catálogo: `CODIGO`, `DESCRIPCION`, `FDESDE`, `FHASTA`, `VERSIONCONTROL` (más `DETALLE`, `ORDEN` y reservas). Las claves foráneas validan que el código exista.
3. **Control de versiones por registro** en todas las tablas versionadas (26):
   - `FDESDE`: desde cuándo rige esta versión.
   - `FHASTA`: hasta cuándo; `2999-12-31 00:00:00` = vigente. Para dar de baja un código se pone la fecha de hoy.
   - `VERSIONCONTROL`: 0 al crear, +1 en cada modificación real.
   - La fila vigente queda en la tabla; la versión anterior pasa a `HIST<TABLA>` (ej. `HISTPEDIDOS`) con su `FDESDE`/`FHASTA` reales, quién la cambió y la operación. Lo hace un trigger; un `UPDATE` sin cambios no versiona.
4. **Códigos con patrón:** `USU-000001`, `VEN-`, `REP-`, `PRO-`, `DIR-`, `PAG-`, `CUP-`, `ARC-`, `CAL-` y `PED-20261005-000001`.
5. **Imágenes:** tabla `ARCHIVOS` (ruta, hash SHA-256, ancho/alto, variantes optimizada/mediana/miniatura, blurhash). Ya no se guarda base64.
6. **Columnas comunes** (reserva incluida): `ACTIVO`, `FDESDE`, `FHASTA`, `VERSIONCONTROL`, `DATOSEXTRA` (texto libre, ver abajo), `CREADOEN`, `CREADOPOR`, `ACTUALIZADOPOR`, `ELIMINADOEN` (borrado lógico).
7. **Seguimiento automático** de cada cambio de estado del pedido en `SEGUIMIENTOPEDIDO`.
8. **Reglas en la BD:** emails en minúsculas, placas en mayúsculas, montos válidos, claves foráneas a los catálogos, dirección y producto copiados dentro del pedido.
9. **Zona horaria** de la base: `America/Guayaquil` (se guarda en UTC, se muestra en hora local).

### Tablas (33 principales + 26 `HIST`)
- **Catálogos:** `ROLES`, `ESTADOPEDIDO`, `ESTADOPRODUCTO`, `ESTADOPAGO`, `ESTADOAPROBACION`, `METODOPAGO`, `TIPOVEHICULO`, `CATEGORIAS`, `ZONACOBERTURA`, `CONFIGURACIONES`
- **Núcleo:** `USUARIOS`, `VENDEDORES`, `REPARTIDORES`, `PRODUCTOS`, `PEDIDOS`, `DETALLEPEDIDO`, `DIRECCIONES`
- **Nuevas:** `PAGOS`, `CUPONES`, `CALIFICACIONES`, `NOTIFICACIONES`, `DISPOSITIVOS`, `ARCHIVOS`, `DOCUMENTOUSUARIO`, `HORARIOVENDEDOR`, `IMAGENPRODUCTO`
- **Registro (solo insertan):** `SEGUIMIENTOPEDIDO`, `CODIGOVERIFICACION`, `SESIONES`, `UBICACIONREPARTIDOR`, `AUDITORIA`, `LOGMENSAJES`, `LOGERRORES`

### Verificación
Probado en una BD temporal (ya eliminada): modificar la descripción de un estado genera v0 → v1 → v2 con sus vigencias; dar de baja un código fija `FHASTA`; el pedido guarda `'006'` y un `JOIN` lo muestra como "EN CAMINO"; se rechazan estados inexistentes, códigos mal formados y emails en mayúsculas. Cero guiones bajos en nombres.

### Respaldo
Respaldo de la BD anterior (7 usuarios, 14 pedidos) en `C:\Users\USUARIO\Backups\vallexpress\`, fuera del repo. `datos_base.txt` (volcado con correos y hashes) está en `.gitignore`.

### Bitácora técnica y cambios de estructura (añadido)
- **`LOGMENSAJES`** (eventos del sistema: niveles `DEBUG`/`INFO`/`ADVERTENCIA`) y **`LOGERRORES`** (errores con `STACK`, ruta, estado HTTP, `HUELLA` para agrupar repetidos y campos `RESUELTO`). Ambos llevan `SOLICITUDID` para unir todo lo ocurrido en una misma petición. No tienen claves foráneas a propósito (un log no debe fallar ni bloquear).
- `AUDITORIA` sigue siendo "qué hizo cada usuario"; `LOGMENSAJES` "qué hace el sistema"; `LOGERRORES` "qué falló".
- **`PURGARLOGS()`** borra mensajes de más de 30 días y errores resueltos de más de 180 (parámetros ajustables). Falta programarla a diario.
- **Cambiar columnas** (nombre, tipo, agregar): se puede, y `DATOSEXTRA` también (ver siguiente punto). Pero en tablas versionadas el cambio debe aplicarse a la tabla principal **y** a su `HIST`; si no, el siguiente `UPDATE` falla (comprobado). Usar siempre `AGREGARCOLUMNA`, `RENOMBRARCOLUMNA` y `CAMBIARTIPOCOLUMNA`, que hacen las dos a la vez.
- Regla de privacidad: nunca guardar contraseñas, tokens ni datos de tarjeta en `DETALLE`/`CUERPO`/`PARAMETROS`; el backend debe limpiarlos antes de insertar.

### `DATOSEXTRA`: texto libre de reserva (cambio)
Antes era `JSONB`; ahora es **`VARCHAR` nulo, sin valor por defecto**, para guardar un dato o un comentario según la tabla. El largo depende del tipo de tabla (ajustable con `CAMBIARTIPOCOLUMNA`):

| Largo | Tablas |
|---|---|
| 50 | catálogos: `ROLES`, `ESTADOPEDIDO`, `ESTADOPRODUCTO`, `ESTADOPAGO`, `ESTADOAPROBACION`, `METODOPAGO`, `TIPOVEHICULO`, `CATEGORIAS` |
| 100 | `ZONACOBERTURA`, `CONFIGURACIONES`, `HORARIOVENDEDOR`, `IMAGENPRODUCTO`, `DETALLEPEDIDO`, `DISPOSITIVOS` |
| 150 | `ARCHIVOS`, `DOCUMENTOUSUARIO`, `DIRECCIONES`, `CUPONES`, `PAGOS`, `CALIFICACIONES`, `NOTIFICACIONES` |
| 250 | `USUARIOS`, `VENDEDORES`, `REPARTIDORES`, `PRODUCTOS`, `PEDIDOS` |

Hoy todas están en `NULL`. Un texto más largo que el límite se rechaza. Los largos son una propuesta inicial: no hay consumidores todavía que los requieran.

### Consecuencias y pendientes
- **El backend actual no funciona con esta BD:** los modelos Sequelize apuntan a las tablas viejas. Hay que reescribirlos módulo por módulo (siguiente: auth).
- El backend y Flutter deben usar **constantes de códigos** (ej. `ESTADOPEDIDO.ENCAMINO = '006'`) en lugar de texto; una sola fuente de verdad.
- Se eliminó `ACTUALIZADOEN`: ahora es `FDESDE` de la versión vigente.
- Las tarifas y la comisión de `CONFIGURACIONES` son valores iniciales de ejemplo, a definir por el negocio.
- PostGIS no está en la imagen `postgres:15-alpine`; para asignación por cercanía eficiente, cambiar a `postgis/postgis`.
- Subida de imágenes: falta implementar el servicio con `sharp` (WebP, miniaturas, hash, blurhash).

---

## Bloque 3: Helpers compartidos y módulo auth (hecho y probado)

### Piezas compartidas nuevas (`backend/src/shared`)
| Pieza | Para qué |
|---|---|
| `constants/codigos.js` | Códigos de catálogos: `ESTADOPEDIDO.ENCAMINO = '006'`. Una sola fuente de verdad |
| `errors/AppError.js` | `throw AppError.conflict(...)`: los errores se lanzan, no se responden a mano |
| `helpers/asyncHandler.js`, `withTransaction.js` | Sin `try/catch` ni `rollback()` manual; la transacción registra quién cambió (`CAMBIADOPOR`) |
| `middlewares/errorHandler.js` | Un solo manejador de errores; los 5xx inesperados van a `LOGERRORES` |
| `middlewares/validar.js`, `limitadores.js`, `solicitudId.js` | Validación unificada, límites por ruta (contadores independientes), id por petición |
| `services/token.service.js`, `codigo.service.js`, `log.service.js`, `configuracion.service.js` | JWT, códigos de 6 dígitos, logs/auditoría, lectura de `CONFIGURACIONES` |
| `models/columnasComunes.js` | Columnas comunes (`ACTIVO`, `FDESDE`...) y borrado lógico para todos los modelos |

### Módulo auth reescrito en capas
`routes → schema (validaciones) → controller (delgado) → service (lógica) → modelos`. `auth.controller.js` pasó de 686 líneas con todo mezclado a unas 60. Modelos nuevos sobre `USUARIOS`, `VENDEDORES`, `REPARTIDORES` y `CODIGOVERIFICACION` (reemplaza a las dos tablas de códigos). Los atributos conservan sus nombres (`nombre`, `cedula`, `tipoUsuario`...) para que los módulos no migrados sigan compilando.

### Seguridad y correcciones (de la revisión inicial)
- Códigos con `crypto.randomInt`; ya no se imprimen en consola salvo en desarrollo.
- **Email verificado exigido en el servidor** antes de registrar (la app ya lo hacía, el servidor no).
- Emails normalizados a minúsculas en todos los endpoints.
- Bloqueo de cuenta: 5 claves incorrectas = 15 minutos. Respuesta idéntica exista o no el usuario (también en tiempo).
- Límites por ruta: login 20/15 min, registro 10/h, envío de código 5/min, consultas 40/min, general 300/min.
- Recuperar clave: no se envía correo a cuentas inexistentes; el token de reseteo es de un solo uso.
- No se envían códigos a emails ya registrados. Nadie puede registrarse como administrador.
- Contraseña máx. 72 caracteres (límite real de bcrypt).
- **Bug corregido:** registrar repartidores fallaba siempre (el servidor exigía `licencia` y la app no la envía); ahora es opcional.
- `sequelize.sync()` eliminado: habría recreado las tablas con los nombres viejos.

### Cambios al esquema descubiertos al hacer el login
- El trigger de versionado **ignora columnas volátiles** (`ULTIMACONEXION`, ubicación del repartidor...): sin esto cada login llenaba `HISTUSUARIOS` de versiones inútiles.
- `CODIGOVERIFICACION.VERIFICADOEN` distingue "verificado" de "invalidado".
- `CONFIGURACIONES.APROBACIONAUTOMATICA = true`: vendedores y repartidores quedan aprobados sin revisión hasta que exista el panel de administración.

### Verificación: `npm run test:auth` (82 pruebas en este bloque; hoy son 97, ver Bloque 4)
Crea su propia BD temporal, levanta el servidor y recorre el flujo como la app: registro de los 3 roles, verificación de email, login y bloqueo, cambio y recuperación de clave, perfil, límites, auditoría y logs. Comprueba también que un error 500 queda en `LOGERRORES` con la contraseña **oculta**, y que en producción el mensaje no filtra detalles. Se borra sola al terminar y no toca la BD de desarrollo.

### Pendiente y decisiones
- **Contrato con la app:** sin cambios (`error` en texto, 200 en login, 201 en registro). Campos nuevos opcionales: `code`, `codigo`, `retryAfter`.
- El perfil devuelve `fotoPerfil: null` y la subida de foto responde **501** hasta tener el servicio de imágenes.
- Los módulos aún no migrados atrapan sus propios errores y no llegan a `LOGERRORES`: se corrige al migrarlos.
- JWT sigue siendo de 30 días sin refresh (`SESIONES` queda para la fase de producción). Contraseña mínima 6 (igual que la app); subir a 8 requiere cambiar también la app.
- Con `NODE_ENV=development` y sin proveedor de correo, el código aparece en la consola del servidor. En producción, si el correo falla, responde 502.
- Para enviar correos reales hace falta `BREVO_API_KEY` en el `.env` (hoy el `.env` tiene `SENDGRID_API_KEY`, que el código no usa).

---

## Bloque 4: Usuario para iniciar sesión y FHASTA (hecho y probado)

### Qué se hizo
- **Columna `USUARIOS.USUARIO`** (ej. `jcayapa`), generada por la BD en cada INSERT (también desde Adminer) con un trigger. Reglas: inicial del nombre + primer apellido. Si está tomado, prueba en orden `jfcayapa` → `jcayapab` → `jfcayapab` → `jcayapa2`, `jcayapa3`... Ignora tildes, símbolos y partículas (de, del, la...). Evita palabras reservadas (`admin`, `soporte`...). Solo letras minúsculas y números, 3 a 30 caracteres, único.
- `CODIGO` (`USU-000001`) se mantiene como identificador interno que nunca cambia; `USUARIO` es el nombre visible para entrar.
- **Login con correo o usuario:** la app puede seguir enviando el valor en `email` (funciona sin cambios) o usar el campo nuevo `usuario`; no distingue mayúsculas. Errores idénticos exista o no el usuario; el bloqueo por intentos y los límites aplican igual.
- El registro y el perfil devuelven el campo `usuario`.
- **`FHASTA` vigente = `2999-12-31 00:00:00`** (hora de Ecuador), en las 26 tablas versionadas.

### Migración (primera de la carpeta `database/migraciones/`)
La BD ya tenía datos reales (tu registro), así que no se recreó: se aplicó `database/migraciones/001_usuario_y_fhasta.sql`. Se probó antes en una copia exacta de la BD. Conserva los datos, no genera versiones falsas en `HIST`, corre en una sola transacción y rechaza aplicarse dos veces. Respaldo previo en `C:\Users\USUARIO\Backups\vallexpress\`.
**Convención desde ahora:** `schema.sql` = instalación nueva (siempre actualizado); `migraciones/NNN_*.sql` = cambios para bases que ya tienen datos. Cada cambio de esquema se hace en los dos.

### Resultado en tu BD
`USU-000001 | usuario: jcayapa | FHASTA 2999-12-31 00:00:00-05 | VERSIONCONTROL 0`, sin filas nuevas en `HISTUSUARIOS`.

### Verificación: `npm run test:auth` (97 pruebas, 0 fallidas)
15 pruebas nuevas: generación y colisiones (`aperez`, `aperezs`, `aperez2`, `jcayapa`, `jfcayapa`, `mtorre`), login por usuario en ambos campos y en mayúsculas, formatos inválidos y `FHASTA`.

### Pendiente
- **App Flutter:** la pantalla de login valida formato de correo en el cliente, así que todavía no deja escribir un usuario. Falta cambiar la etiqueta a "Correo o usuario", quitar esa validación y mostrar el usuario asignado al terminar el registro.
- Poder **cambiar el usuario** más adelante (endpoint con las mismas reglas de unicidad).
- La tabla `HISTUSUARIOS` creada por la migración tiene `USUARIO` sin `NOT NULL` (en instalaciones nuevas sí): sin consecuencias.

---

## Bloque 5: Nombres sin comillas y claves legibles, sin UUID (hecho y probado)

### Por qué
`SELECT * FROM USUARIOS` fallaba con `relation "usuarios" does not exist`. En **PostgreSQL** lo que se escribe sin comillas se convierte a **minúsculas** (en Oracle, a mayúsculas), y las tablas se habían creado con comillas en mayúsculas (`"USUARIOS"`), que es otro nombre. Además, el usuario quería quitar los UUID (`51101a28-a258-...`) y usar códigos legibles.

### Decisiones tomadas
1. **Minúsculas reales:** el SQL se sigue escribiendo en MAYÚSCULAS y **sin comillas**, y PostgreSQL lo guarda en minúsculas. `SELECT * FROM USUARIOS`, `usuarios` o `Usuarios` funcionan igual. Adminer mostrará los nombres en minúsculas (no existe un ajuste de PostgreSQL para cambiar esa regla).
2. **Código legible como clave primaria en todas las tablas, sin ningún UUID.**

### Claves primarias nuevas
| Tabla | Clave | Ejemplo |
|---|---|---|
| `USUARIOS` | `USUARIO` | `jcayapa` (generado del nombre, **inmutable**) |
| `VENDEDORES`, `REPARTIDORES` | `VENDEDOR`, `REPARTIDOR` | `VEN-000001`, `REP-000001` |
| `PRODUCTOS`, `PEDIDOS`, `PAGOS`, `CUPONES` | `PRODUCTO`, `PEDIDO`, `PAGO`, `CUPON` | `PRO-000001`, `PED-20261006-000001`... |
| `DIRECCIONES`, `CALIFICACIONES`, `ARCHIVOS`, `ZONACOBERTURA` | `DIRECCION`, `CALIFICACION`, `ARCHIVO`, `ZONA` | `DIR-000001`... |
| Catálogos | `CODIGO` | `'001'`, `'006'` |
| Tablas internas (`DETALLEPEDIDO`, `NOTIFICACIONES`, `DISPOSITIVOS`, `HORARIOVENDEDOR`, `IMAGENPRODUCTO`, `DOCUMENTOUSUARIO`, logs, `SESIONES`...) | `ID` numérico | `1, 2, 3` |

Las demás tablas guardan **solo ese código** para relacionarse: `PEDIDOS.CLIENTE = 'jcayapa'`, `PEDIDOS.VENDEDOR = 'VEN-000001'`, `DETALLEPEDIDO.PEDIDO = 'PED-...'`. Las columnas de relación se llaman como la entidad (`CLIENTE`, `VENDEDOR`, `PRODUCTO`, `PEDIDO`...), no `...ID`.

### Otros cambios del esquema
- Se eliminó `USUARIOS.CODIGO` (`USU-000001`): el `USUARIO` ocupa su lugar. Las columnas `CREADOPOR`, `ACTUALIZADOPOR`, `APROBADOPOR`... ahora guardan el usuario (texto) en vez de un UUID.
- La columna de texto `DIRECCION` pasó a `DOMICILIO` (para no chocar con la clave de `DIRECCIONES`). Se quitó `DETALLEPEDIDO.CODIGOPRODUCTO` (ya es `PRODUCTO`).
- **Claves inmutables:** un trigger rechaza cambiar la clave de usuarios, pedidos, productos, etc. Por eso **ya no se podrá cambiar el nombre de usuario** (se descarta el endpoint "cambiar usuario").
- El usuario que hace un cambio se registra con `SET LOCAL app.usuario = 'jcayapa'` (antes `app.usuario_id`).
- Las funciones `AGREGARCOLUMNA`, `RENOMBRARCOLUMNA` y `CAMBIARTIPOCOLUMNA` aceptan los nombres en cualquier mayúscula.
- Se quitó la extensión `pgcrypto` (ya no hay UUID).

### Backend
- Cada modelo conserva el atributo `id` apuntando a su columna clave (`usuario`, `vendedor`...), así `findByPk`, `req.usuario.id` y el JWT siguen funcionando; el `id` ahora vale `jcayapa`. Helper nuevo `clavePrimaria()`: la genera la BD, el backend no la envía.
- Las respuestas incluyen `id` y `usuario` con el mismo valor. La app Flutter **no** valida UUID en ningún lado.
- Los tokens emitidos antes del cambio ya no sirven (llevan un UUID): hay que volver a iniciar sesión.

### Datos
Se recreó la base (respaldos previos en `C:\Users\USUARIO\Backups\vallexpress\`). El usuario de prueba se perdió: al registrarse de nuevo vuelve a ser `jcayapa`. `database/migraciones/` queda vacía: la migración 001 quedó absorbida por `schema.sql` (línea base v2).

### Verificación
Esquema probado primero en una base temporal (nombres, ausencia de UUID y mayúsculas, claves por código, versionado, claves inmutables, funciones de ayuda y purga). `npm run test:auth`: **103 pruebas, 0 fallidas** (21 nuevas desde el Bloque 4, entre ellas: JWT con `id=aperez`, la clave no se puede cambiar, `SELECT * FROM USUARIOS` sin comillas, cero columnas UUID).

### Pendiente
- `pedido.routes.js` aún valida `isUUID()` en `vendedorId` y `productoId`: se cambia al migrar el módulo de pedidos (ahora son `VEN-000001`, `PRO-000001`).
- Los módulos sin migrar siguen usando el esquema viejo y no funcionan; al migrarlos, sus ids pasan a ser códigos (la app los trata como texto).

---

## Bloque 6: Vendedores, productos e imágenes (hecho y probado)

### Qué se hizo
- **Vendedores** y **productos** reescritos en capas (`routes → schema → controller → service`), igual que `auth`: los controllers pasaron a ser de unas 40 líneas, sin `try/catch` ni validaciones dentro. Mismos endpoints y mismo formato de respuesta que ya consume la app.
- **Servicio de imágenes** (`shared/services/archivo.service.js`, con `sharp`): la app sigue enviando base64; el backend valida el contenido real (solo JPEG/PNG/WebP, rechaza SVG y texto), corrige la orientación, quita los metadatos (EXIF/GPS), convierte a **WebP** en 3 tamaños (principal, mediana 800 px, miniatura 200 px) y guarda el archivo en `backend/uploads` con el hash SHA-256 como nombre. La misma imagen subida dos veces se guarda una sola vez. La BD guarda solo el código (`ARC-000001`) y la API devuelve la **URL** (la app ya sabe mostrar URLs: `startsWith('http')`). Un PNG de 900x700 pesó menos de la mitad al optimizarlo.
- La **foto de perfil** de usuario, que respondía 501, ya funciona con el mismo servicio. Los archivos se sirven con caché de una semana.
- Catálogos: `catalogo.service.js` (lee las tablas de catálogo con caché) y `ConfiguracionService.aprobacionInicial()`. El registro de vendedores ahora reutiliza `VendedorService.crearPerfil` (antes el código estaba duplicado).

### Correcciones y decisiones
- **Privacidad:** las consultas públicas de vendedores ya **no exponen el email ni el teléfono** del dueño (antes cualquiera los veía); solo el propio vendedor los ve en `mi-negocio`.
- **Solo vendedores aprobados y activos** aparecen en las listas públicas; sus productos también. Un vendedor pendiente no puede crear productos (403).
- **Endpoint que faltaba:** la app llama a `PATCH /vendedores/perfil/banner` y nunca existió; agregado.
- **Seguridad de propiedad:** un vendedor no puede modificar, borrar ni cambiar la disponibilidad de productos de otro (404).
- **Validación nueva** de latitud/longitud, horas (HH:MM), precios, stock, tiempos y formato de los códigos (`VEN-000001`, `PRO-000001`).
- **Listado de productos paginado** (`?limite=&pagina=`, máx. 500) con `total`.
- **Estado del producto:** `disponible` (true/false) de la app se traduce al catálogo (001 disponible / 003 no disponible); con control de stock, 0 unidades pasa solo a AGOTADO (002) y al reponer vuelve a 001. Sin stock informado, el producto no controla stock.
- **Horarios:** la app maneja una hora de apertura y una de cierre; se guardan en `HORARIOVENDEDOR` (mismo horario los 7 días, una fila por día, sin duplicar).
- **Categoría** (texto libre en la app, catálogo en la BD): si coincide con una categoría (`Comida`, `Bebida` en singular también) se guarda su código; si no (`Pizza`), se guarda OTROS (099) y el texto original en `DATOSEXTRA` para devolverlo igual. Se simplifica cuando la app tenga un selector.
- Borrado lógico de negocios y productos (`ELIMINADOEN`); cada cambio queda versionado en `HISTVENDEDORES`/`HISTPRODUCTOS`.

### Verificación: `npm run test:tienda` (85 pruebas, 0 fallidas) y `npm run test:auth` (103, 0 fallidas)
Crea su propia BD y su propia carpeta temporal de imágenes (no toca las de desarrollo). Cubre listas públicas, privacidad, perfil, horarios, categorías, validaciones, aprobación, imágenes (formatos, SVG, 413, orientación, deduplicación, archivos en disco, caché), productos (stock, disponibilidad, propiedad, borrado lógico, versionado, columna volátil) y foto de perfil.

### Pendiente
- Las imágenes quedan en disco local; para producción conviene S3/R2 (la tabla ya tiene la columna `ALMACEN`). `BLURHASH` sin implementar. No se borran los archivos huérfanos (limpieza programada pendiente).
- `PUBLIC_URL` en el `.env` de producción (detrás de Nginx el host interno no sirve para armar las URLs).
- `diasAtencion` de la app no se guarda (devuelve null): la app casi no lo usa.
- El pedido (`pedidos.service`) deberá respetar `CONTROLASTOCK` y los estados 001-004 al migrarlo.

---

## Bloque 7: Direcciones, notificaciones y pedidos (hecho y probado)

### Qué se hizo
- **Direcciones**, **notificaciones** y **pedidos** reescritos en capas (`routes → schema → controller → service`). Mismos endpoints y formato de respuesta que consume la app. `pedido.controller.js` pasó de 1118 líneas a unas 50; el resto vive en servicios.
- **Máquina de estados** del pedido (`pedido_estado.service.js`): define qué transiciones existen y quién las hace. Ningún endpoint puede saltarse el flujo:
  `PENDIENTE → CONFIRMADO → PREPARANDO → LISTO → EN CAMINO → RECOGIDO → ENTREGADO → RECIBIDO`, con `RECHAZADO` (vendedor) y `CANCELADO` (cliente, solo si está pendiente).
- **Catálogo de estados corregido** para coincidir con la app: `005 EN CAMINO` (el repartidor aceptó y va al negocio) y `006 RECOGIDO` (lo recogió y lo lleva al cliente). Los códigos ahora van en orden cronológico. La app sigue hablando en texto (`en_camino`, `recogido`...); el backend traduce.
- **Seguimiento en tiempo real** (sockets): misma interfaz, ahora guarda la posición del repartidor en la BD (posición actual + historial en `UBICACIONREPARTIDOR`, como máximo cada 15 s) y la caché de ubicaciones caduca (antes crecía sin límite).
- **Notificaciones push:** nuevo `POST /api/notificaciones/dispositivo` para registrar el token de Firebase (la app tenía `registerDeviceToken` vacío, así que las push nunca funcionaron). El backend ya envía push a los dispositivos registrados y desactiva los tokens muertos. Cada notificación se guarda, se emite por socket y se envía como push; si falla no tumba la operación (queda en `LOGMENSAJES`).

### Correcciones de seguridad y de negocio
1. **Cualquier usuario podía ver cualquier pedido** (nombre, teléfono y dirección del cliente). Ahora solo lo ven su cliente, su vendedor y su repartidor (404 para los demás). Un repartidor aprobado ve los pedidos *listos sin asignar* (para decidir si los acepta), pero sin el teléfono del cliente.
2. **El cliente podía elegir el negocio** y mezclar productos de varios negocios. Ahora el negocio se deduce de los productos y deben ser todos del mismo.
3. **La dirección de entrega puede ser de otro usuario** (filtraba su dirección). Ahora debe ser del cliente y se guarda una copia en el pedido.
4. Se valida método de pago, cantidades (1 a 99), máximo 50 líneas, que el producto esté disponible y que el negocio esté aprobado y acepte pedidos.
5. **Stock sin sobreventa:** se bloquean las filas al pedir; se devuelve al cancelar o rechazar; el producto pasa solo a AGOTADO y vuelve a DISPONIBLE.
6. **Estados:** antes el vendedor podía saltar o retroceder estados libremente (de pendiente a listo, o de entregado a preparando).
7. **Carrera entre repartidores:** dos repartidores aceptando a la vez podían quedarse ambos con el pedido (el último pisaba al primero). Ahora gana uno y el otro recibe 409. El repartidor debe estar aprobado y el costo de envío se acota entre 0 y 100.
8. **Privacidad:** los pedidos ya no incluyen el correo de nadie.
9. `fechaRecogida` se llenaba al *asignar* el repartidor; ahora hay `fechaAsignacion` y `fechaRecogida` es la real.
10. Notificaciones: marcar la de otro usuario da 404 (antes 403, que confirmaba que existía); listado paginado con contador de no leídas.

### Funciones nuevas
- **Rechazar pedido** (vendedor, con motivo): el catálogo tenía el estado y nada lo usaba. Devuelve el stock y avisa al cliente.
- **Calificar** (`POST /pedidos/:id/calificar`): la app lo llamaba y nunca existió. Una calificación por pedido y por destinatario (negocio o repartidor); recalcula el promedio.
- **Contadores** al recibir: pedidos del negocio, entregas del repartidor y unidades vendidas por producto.
- **Direcciones:** límite de 20 por usuario, y la base garantiza una sola predeterminada.

### Verificación: `npm run test:pedidos` (106 pruebas, 0 fallidas) y `npm test` corre las tres suites
Cubre el flujo completo de un pedido, los permisos de cada rol, todas las validaciones y las correcciones de seguridad anteriores, una **carrera real entre dos repartidores**, la secuencia de `SEGUIMIENTOPEDIDO` y las versiones en `HISTPEDIDOS`, direcciones, notificaciones, tokens push y sockets (permisos, ubicación en vivo, límite de frecuencia, notificación en tiempo real). Total de las tres suites: **294 pruebas**. Las pruebas usan BD y carpeta temporales; comparten el arnés `test/arnes.js`.

### Pendiente
- **App Flutter:** llamar a `POST /api/notificaciones/dispositivo` en `registerDeviceToken` (unas 3 líneas) para recibir push; el canal Android de las push es el heredado (`verification_channel`).
- Totales: IVA, propina, cupones, comisión de la plataforma y pagos (`PAGOS`) siguen sin implementar (la app solo usa efectivo; el pedido guarda el total simple).
- Reglas de negocio por definir: que `abiertoAhora` limite los pedidos (hoy es `false` por defecto en cada negocio nuevo), tiempo máximo para que un repartidor acepte y reasignación si nadie acepta.
- Endpoint con la línea de tiempo del pedido (los datos ya se guardan en `SEGUIMIENTOPEDIDO`).
- La ruta heredada `PATCH /pedidos/:id/en-camino` quedó idempotente (aceptar ya deja el pedido en camino).
- Las suites `auth` y `tienda` aún tienen su propio código de arranque; falta pasarlas al arnés común.

---

## Bloque 8: Repartidores y revisión final del backend (hecho y probado)

### Repartidores en capas
Mismo patrón (`routes → schema → controller → service`). Las acciones sobre un pedido (aceptar, recoger, entregar) las hace `pedido.service`: aquí no se duplican. El registro de repartidores reutiliza `RepartidorService.crearPerfil`, igual que el de vendedores.

### Fallas del módulo viejo (corregidas)
1. **Cualquier usuario podía rastrear a cualquier repartidor** (`GET /repartidores/:id/ubicacion`). Ahora solo lo ve él mismo y el cliente o el vendedor de una entrega suya **en curso**; al terminar la entrega deja de verse.
2. **La ubicación se emitía a TODOS los clientes conectados** (`io.emit`). Ahora se avisa solo a la sala de cada entrega en curso.
3. `GET /repartidores/disponibles` era **público** y mostraba los teléfonos; ahora requiere ser vendedor y no muestra datos de contacto. `GET /repartidores` (lista completa) queda solo para administradores.
4. Un repartidor no aprobado no puede activar su disponibilidad ni ver pedidos.
5. Los pedidos listos que ve el repartidor no incluyen el teléfono del cliente hasta que acepta.
6. La ruta heredada `PUT /pedidos/:id/estado` marcaba "en_camino" y sumaba entregas sin validar el flujo; ahora usa la máquina de estados (`en_camino` = "ya lo recogí y voy hacia el cliente").
7. Perfil: validación de placa (formato y duplicados), vehículo traducido al catálogo (con texto original si no coincide) y foto optimizada con `sharp`.

### Endpoints que la app usaba y no existían (agregados)
`GET /repartidores/pedidos-disponibles`, `GET /repartidores/entregas-activas` y `PATCH /repartidores/estado`.

### Revisión final del backend
- **Vulnerabilidad cerrada:** la subida de foto de perfil todavía pasaba por `multer`, que guardaba el archivo en una carpeta pública con la extensión y el tipo que dijera el cliente (se podía alojar un `.html` en nuestro dominio). Se eliminó `multer` y `upload.middleware.js`: ahora toda imagen entra en base64 y se valida con `sharp`.
- **Dependencias:** de **33 a 10 vulnerabilidades conocidas, y ninguna alta ni crítica** (antes 12 altas y 3 críticas). Se quitaron `multer` y `nodemailer` (ya no se usaban) y `socket.io-client` pasó a dependencias de desarrollo. Las 10 restantes son moderadas: vienen de `firebase-admin` (arreglarlas exige saltar a una versión mayor, que conviene probar aparte) y de `sequelize`/`uuid` (`npm` sugiere un "arreglo" que sería bajar a una versión de 2015).
- Revisado: no quedan controllers con el estilo viejo (`try/catch` a mano), validaciones `isUUID`, nombres de columnas antiguos, archivos huérfanos ni `console.log` de depuración.

### Verificación: `npm run test:repartidores` (47 pruebas) y `npm test` corre las cuatro suites
| Suite | Pruebas |
|---|---|
| auth | 103 |
| tienda (vendedores, productos, imágenes) | 85 |
| pedidos (direcciones, notificaciones, sockets) | 106 |
| repartidores | 47 |
| **Total** | **341, 0 fallidas** (también después de actualizar las dependencias) |

### Estado del backend
Todos los módulos están migrados al esquema nuevo, en capas y con pruebas: auth/usuarios, vendedores, productos, direcciones, pedidos, notificaciones, repartidores, imágenes y sockets. La base de desarrollo está limpia (hay respaldos en `C:\Users\USUARIO\Backups\vallexpress\`).

### Pendiente (no es backend roto: es producción y la app)
- **App Flutter:** login con "Correo o usuario", registrar el token push y revisar pantallas contra los endpoints nuevos (por ejemplo, los ids ahora son códigos como `VEN-000001`).
- **Antes de producción:** clave fuerte en `JWT_SECRET` y en la BD; restringir la API key de Google; `BREVO_API_KEY`; HTTPS y `trust proxy`; `PUBLIC_URL`; imágenes en S3/R2; limpieza de archivos huérfanos y programar `PURGARLOGS()`; JWT con refresh; probar `firebase-admin` 14.
- **Negocio por definir:** IVA, propina, cupones, comisión, pagos (`PAGOS`), que `abiertoAhora` limite pedidos, tiempo máximo para aceptar y reasignación.
- **Docs:** README desactualizado.
- **Commit a `main`:** hecho para el backend (Bloque 9); lo de Flutter va aparte.

---

## Bloque 9: Cierre del backend y primer commit (2026-10-06)

- Revisión final: `npm test` → 4 suites, **341 pruebas, 0 fallidas**.
- **README reescrito** (ya no menciona Multer ni pagos integrados; describe el esquema v2, las pruebas y el flujo real).
- `.env.example` corregido (Brevo en vez de SendGrid, sin PayPal; se agregan `UPLOADS_DIR` y `JWT_EXPIRA`).
- **Borrados por obsoletos:** `MEJORAS_IMPLEMENTADAS_RESUMEN.md`, `OPTIMIZACION_PRODUCCION.md` y los 5 scripts de `backend/src/scripts/*.sql` (los reemplaza `database/schema.sql`).
- Se quitó de los documentos la clave antigua de la BD.
- **Commit del backend** a `main`: incluye `backend/`, `database/`, `docker-compose.yml`, `.gitignore` y los .md. **No incluye** los cambios de Flutter (van en un commit aparte). `node_modules` sale del repositorio.
- Pendiente de seguridad: la clave antigua de la BD y el `JWT_SECRET` anterior ya están en el historial de git, así que hay que **rotarlos** antes de producción.

---

## Bloque 10: App Flutter, primera pasada (2026-10-06)

- **Entornos sin tocar código** (`lib/config/constants.dart`): se elige al compilar con `--dart-define`.
  - `flutter run` → local (`localhost`, web/escritorio)
  - `flutter run --dart-define=ENTORNO=emulador` → emulador Android (`10.0.2.2`)
  - `flutter run --dart-define=ENTORNO=lan --dart-define=IP_LAN=192.168.1.50` → celular real en la misma red
  - `flutter build apk --dart-define=ENTORNO=prod --dart-define=API_PROD=https://api.tudominio.com` → producción
- **Tema nuevo "Medianoche eléctrica"** (`lib/config/theme.dart`): violeta eléctrico `#8B5CF6` sobre azul medianoche, turquesa neón de acento. Colores por rol distintos entre sí: cliente menta, vendedor ámbar, repartidor azul cielo. Las pantallas leen todo de `AppTheme`, así que **cambiar los valores de ese bloque recolorea toda la app**. Los dorados fijos que había en las pantallas ahora usan los colores del tema.
- **Login** con "Correo o usuario" (el backend ya aceptaba ambos).
- **Notificaciones push:** la app nunca registraba el token. Ahora lo envía a `POST /notificaciones/dispositivo` al abrir la app y al iniciar sesión (y si Firebase lo renueva), y lo quita al cerrar sesión.
- **Datos falsos eliminados:** si el servidor fallaba, el repartidor veía pedidos y perfil de mentira (`mock_data`); ahora ve vacío.
- **Código muerto borrado:** 3 pantallas duplicadas sin uso (`*_fixed`, `*_old`, `*_new`), `client_service.dart` (ids numéricos) y `mock_data.dart`. Ids de producto en `VendedorService` pasan a texto (`PRO-000001`).
- Revisado: **todas** las rutas que usa la app existen en el backend. `flutter analyze`: 0 errores.

### Pendiente en la app
Probar en emulador de punta a punta (registro, pedido, repartidor, seguimiento), revisar visualmente cada pantalla con el tema nuevo, rediseño de pantallas (home, tarjetas, animaciones), modo claro, ids `VEN-000001` mostrados al usuario, pantallas de mensajes de error de red.

---

## Bloque 11: Identidad V3, historial en la misma tabla (2026-10-07)

Primer bloque del rediseño que pediste: tablas con prefijo `T`, columnas de código con prefijo `C`, y **sin tablas `HIST`** para lo nuevo.

### Qué hay ahora
| Tabla | Para qué |
|---|---|
| `TPERSONASID` | Ancla: `CPERSONA` 1, 2, 3… (número entero que crece solo) |
| `TPERSONAS` | Datos de la persona (nombres, documento, correo) |
| `TUSUARIOSID` | Ancla: `CUSUARIO` (`jcayapa`) |
| `TUSUARIOS` | Login: `CUSUARIO` + `CPERSONA` + `CROL` + `CESTATUSUARIO` (`ACT`/`INA`/`BLQ`) |
| `TPERSONATELEFONOS` | Varios teléfonos por persona, con tipo, uno principal |
| `TDIRECCIONESID` | Ancla de las direcciones (`DIR-000001`) |
| `TPERSONADIRECCIONES` | Direcciones por persona, con tipo |
| `TPERSONAIMAGENES` | Imágenes por persona (foto de perfil vigente, portada, documento) |
| `TESTATUSUARIO`, `TTIPOSTELEFONO`, `TTIPOSDIRECCION`, `TTIPOSIMAGEN` | Catálogos con códigos de 3 letras |
| `TLOGMENSAJES`, `TLOGERRORES` | Las bitácoras, renombradas |
| `VUSUARIOS` | **Vista** con el usuario + persona + teléfono principal + foto, solo lo vigente. Se puede consultar **e insertar/actualizar**: reparte los datos en las tablas T |

Catálogos: `ACT` activo · `INA` inactivo · `BLQ` bloqueado. Teléfono: `MOV` móvil · `CAS` casa · `TRA` trabajo · `WAP` WhatsApp. Dirección: `DOM` domicilio · `TRA` trabajo · `FAM` familiar · `OTR` otro · `LOC` local del vendedor. Imagen: `PER` perfil · `POR` portada · `DOC` documento.

### Cómo funciona el historial en la misma tabla
- Cada cambio **cierra** la fila vigente (`FHASTA` = ahora) y deja la nueva con `FHASTA = 2999-12-31`. Lo vigente es siempre `WHERE FHASTA = '2999-12-31'`.
- Lo hace un trigger (`FNVERSION`): el código sigue haciendo `UPDATE` normal.
- Cada versión tiene su `ID` interno; el código (`CPERSONA`, `CUSUARIO`…) se repite en todas las versiones y **no se puede cambiar**.
- Las filas del historial no se pueden modificar (el `UPDATE` se ignora).
- Un `UPDATE` que no cambia nada no crea versión. Las columnas **volátiles** (`ULTIMACONEXION`, `ULTIMAIP`, `INTENTOSFALLIDOS`, `BLOQUEADOHASTA`) se guardan en la misma fila sin versionar.
- **`ACTUALIZADOPOR` ya no queda vacío:** guarda al usuario del backend o, si editas desde Adminer o psql, tu usuario de la base de datos.
- Un `DELETE` físico deja la copia cerrada en la misma tabla (con `ELIMINADOEN`).
- Para activarlo en una tabla nueva: `SELECT ACTIVARVERSION('NOMBRETABLA', 'columnaclave')`.

### Qué cambió en el código (la API y la app NO cambian)
- El modelo `Usuario` lee y escribe en `VUSUARIOS`, así que el registro, el login y el perfil siguen igual.
- **Direcciones** ahora son de la persona (`TPERSONADIRECCIONES`); la API sigue igual. Los pedidos apuntan al ancla `TDIRECCIONESID`.
- La foto de perfil vive en `TPERSONAIMAGENES`: al subir una nueva, la anterior queda en el historial de esa fila.
- Los modelos con historial en la misma tabla usan `opcionesVersionada()` (solo ven lo vigente).

### Lo que sigue igual por ahora
Vendedores, repartidores, productos, pedidos y demás tablas conservan el esquema anterior (con `HIST`): se migran cuando lleguemos a cada módulo. Ya apuntan a `TUSUARIOSID` y `TDIRECCIONESID`.

### Verificación: `npm run test:identidad` (70 pruebas nuevas) y `npm test` corre las cinco suites
| Suite | Pruebas |
|---|---|
| identidad (nueva) | 70 |
| auth | 103 |
| tienda | 85 |
| pedidos | 106 |
| repartidores | 47 |
| **Total** | **411, 0 fallidas** |

### Base de desarrollo
Se hizo un respaldo (`C:\Users\USUARIO\Backups\vallexpress\antes_v3_*.dump`), se recreó con el esquema nuevo y se restauró tu usuario `jcayapa` (ahora es la persona `1`).

### Cosas que debes saber
- **`CPERSONA` puede saltar números:** si un `INSERT` falla (por ejemplo, un correo repetido), el contador ya avanzó. Es el comportamiento normal de los números automáticos de PostgreSQL; sigue siendo único y creciente.
- Una persona puede tener **varios usuarios** (uno por rol).
- Para consultar el historial de una persona: `SELECT * FROM TPERSONAS WHERE CPERSONA = 1 ORDER BY FDESDE`.

### Pendiente de este rediseño
Teléfonos y direcciones aún no tienen pantallas ni endpoints propios (solo el teléfono principal, que sigue en el perfil). Migrar el resto de las tablas al mismo estilo, quitar el código duplicado y limpiar servicios (anotado).

---

## Bloque 12: el negocio del vendedor (2026-10-07)

Basado en `PATRON_TABLAS_FITBANK.md`. **Decisión:** el vendedor deja de ser una entidad aparte (`VEN-000001`): es un **usuario con rol vendedor** y su negocio cuelga de `CUSUARIO` (un negocio por vendedor). Más adelante, si hace falta (empleados, varios negocios), se agrega `TNEGOCIOUSUARIOS` al estilo `TCOMPANIAUSUARIOS`.

### Qué cambió en la BD (`schema.sql`)
| Antes | Ahora |
|---|---|
| `VENDEDORES` + `HISTVENDEDORES` | **`TNEGOCIOS`** (historial en la misma tabla, clave `CUSUARIO`) |
| `HORARIOVENDEDOR` + hist | **`THORARIOSNEGOCIO`** (clave `CHORARIO`, un día por fila) |
| teléfono, correo, domicilio, latitud y longitud propios del vendedor | se quitan: salen de la PERSONA; el local es una dirección tipo `LOC` y `TNEGOCIOS.CDIRECCION` apunta a ella |
| `PRODUCTOS`, `CUPONES`, `PEDIDOS`, `CALIFICACIONES`: `VENDEDOR` → `VENDEDORES` | `VENDEDOR` → `TUSUARIOSID.CUSUARIO` (ahora vale `lmora`, no `VEN-000001`) |

Se eliminaron `SECVENDEDORES` y los `HIST` de vendedores. Columnas volátiles (no crean versión): `TOTALPEDIDOS`, `CALIFICACION`, `TOTALCALIF`.

### Qué cambió en el código
Modelos `Vendedor` y `HorarioVendedor` sobre las tablas nuevas (el atributo `id` es el usuario); `actualizarUbicacion` crea o mueve la dirección `LOC`; las validaciones de id de vendedor aceptan un usuario; el promedio de calificaciones apunta a `TNEGOCIOS`. La forma de la API no cambia, **pero los ids de vendedor ahora son el usuario** (importante para la app).

### Verificación: `npm test`, 5 suites, **413 pruebas, 0 fallidas** (tienda 87: +2 del local `LOC`)

### Repartidores (mismo bloque)
`REPARTIDORES` + `HISTREPARTIDORES` → **`TREPARTIDORES`** (clave `CUSUARIO`, historial en la misma tabla, placa única solo entre vigentes). `PEDIDOS`, `CALIFICACIONES` y `UBICACIONREPARTIDOR` apuntan a `TUSUARIOSID`; el id de repartidor ahora es el usuario (`pruiz`, no `REP-000001`). Volátiles (no crean versión): ubicación, `ENSERVICIO`, calificación y contadores, saldo y ganancias. `SECREPARTIDORES` eliminada. **413 pruebas, 0 fallidas** (tienda 87, repartidores 47).

### Base de desarrollo recreada
Respaldo previo: `C:\Users\USUARIO\Backups\vallexpress\antes_v4_negocios_20261007_215209.dump`. Se recreó con el esquema nuevo (69 tablas) y se restauró tu usuario `jcayapa` (persona `1`). Estaba vacía de vendedores, repartidores, productos y pedidos.

### Pendiente
- `DOCUMENTOUSUARIO` (documentos de repartidor y vendedor) sigue en el estilo viejo con `HIST`; no tiene modelo en el código todavía, se pasa a estilo T cuando se use.
- Siguiente: productos (+ imágenes), cupones, pedidos (+ detalle, pagos, seguimiento), transversales (notificaciones, dispositivos, sesiones, auditoría); quitar los `HIST` restantes y agregar `comment on`.

---

## Bloque 13: cierre del backend (2026-10-07)

Se terminó la migración de **todas** las tablas al patrón (inspirado en `PATRON_TABLAS_FITBANK.md`). Ya no queda ninguna tabla de datos con `HIST`.

### Qué cambió en la BD
| Antes | Ahora |
|---|---|
| `PRODUCTOS`, `IMAGENPRODUCTO` | `TPRODUCTOSID` (ancla `PRO-000001`) + `TPRODUCTOS`, `TPRODUCTOIMAGENES` |
| `CUPONES` | `TCUPONESID` (ancla `CUP-000001`) + `TCUPONES` |
| `PEDIDOS`, `DETALLEPEDIDO` | `TPEDIDOSID` (ancla `PED-AAAAMMDD-000001`) + `TPEDIDOS`, `TPEDIDODETALLE` |
| `PAGOS`, `CALIFICACIONES` | `TPAGOS`, `TCALIFICACIONES` |
| `NOTIFICACIONES`, `DISPOSITIVOS` | `TNOTIFICACIONES` (leída/enviada no crean versión), `TDISPOSITIVOSID` + `TDISPOSITIVOS` |
| `DOCUMENTOUSUARIO` | `TDOCUMENTOSUSUARIO` |
| `SEGUIMIENTOPEDIDO`, `UBICACIONREPARTIDOR`, `AUDITORIA`, `CODIGOVERIFICACION`, `SESIONES` | `TSEGUIMIENTOPEDIDO`, `TUBICACIONREPARTIDOR`, `TAUDITORIA`, `TCODIGOSVERIFICACION`, `TSESIONES` (solo se insertan) |

- Las anclas se llenan solas con el trigger genérico `FNASIGNARANCLA`. Las FK de pedidos, detalle, pagos, calificaciones, notificaciones, seguimiento y ubicación apuntan a las anclas (`CPEDIDO`, `CPRODUCTO`, `CCUPON`, `CDISPOSITIVO`).
- El seguimiento de estados ignora las copias cerradas del historial (si no, cada cambio habría registrado un estado falso).
- **Catálogos** (`ROLES`, `ESTADOPEDIDO`, `CATEGORIAS`, `TTIPOS…`, 15 en total) siguen con su tabla gemela `HIST*`: su clave es el propio código y no necesitan ancla.
- **Todas las tablas (63) y todas las columnas llevan `COMMENT ON`** (813 descripciones).

### Endpoints nuevos
- `GET/POST/PUT/DELETE /api/telefonos` y `PATCH /api/telefonos/:id/principal`, `GET /api/telefonos/tipos`: varios teléfonos con tipo (MOV, CAS, TRA, WAP), máximo 5, uno principal, número único; al borrar el principal el siguiente pasa a serlo.
- Direcciones con **tipo** (`DOM`, `TRA`, `FAM`, `OTR`) y `GET /api/direcciones/tipos`. El tipo `LOC` (local del negocio) no se ofrece al cliente y no aparece en sus direcciones.

### Verificación: `npm test`, 5 suites, **435 pruebas, 0 fallidas**
| Suite | Pruebas |
|---|---|
| identidad (+ teléfonos, tipos, estructura) | 92 |
| auth | 103 |
| tienda | 87 |
| pedidos | 106 |
| repartidores | 47 |

### Base de desarrollo
Recreada con el esquema final (respaldo: `C:\Users\USUARIO\Backups\vallexpress\antes_v5_backend_completo_20261007_224117.dump`) y con tu usuario `jcayapa` restaurado. El backend arranca contra ella.

### Pendiente (no es de esquema)
- **Reglas de negocio por definir:** IVA, propina, cupones (no hay endpoints), comisión, pagos (no hay endpoints ni pasarela), reasignación de pedidos. Las tablas ya existen.
- **Antes de producción:** `PENDIENTES_USUARIO.md` (claves fuertes, API key de Google, `BREVO_API_KEY`, HTTPS, S3/R2, refresh de JWT, programar `PURGARLOGS`).
- **App Flutter:** ids de vendedor y repartidor ahora son el usuario; teléfonos y direcciones con tipos; "Correo o usuario" en el login.

