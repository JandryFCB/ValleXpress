# ValleXpress: manual para llevarlo a nivel top

Documento de seguimiento. Marca con `[x]` lo que vayas completando.

---

## 0. Principio guía: no duplicar código

Regla: **un controller solo recibe la petición, llama a un servicio y responde.** La lógica vive en servicios, helpers y clases base. Si copias y pegas algo por segunda vez, va a un helper.

### Duplicación detectada hoy en el proyecto

| Qué se repite | Dónde | Se reemplaza por |
|---|---|---|
| `try { ... } catch { console.error; res.status(500) }` en cada método | todos los controllers | `asyncHandler` + middleware global de errores |
| `validationResult(req)` + `return res.status(400)` | auth, pedidos, productos | middleware `validar` reutilizable |
| `validarEmail`, `validarCedula`, `validarTelefono`, `validarPlaca` definidas dentro de `auth.controller.js` | auth | `utils/validators.js` (y usarlas también en `check-*`) |
| Normalizar placa (`trim().toUpperCase().replace(...)`) escrito 3 veces | register, checkPlaca | `normalizarPlaca()` |
| Generar código de 6 dígitos + hash + expiración | forgotPassword, sendEmailVerification | `CodigoService.generar(email, tipo)` |
| Verificar código (expira, intentos, bcrypt) | verifyResetCode, verifyEmailCode | `CodigoService.verificar(email, codigo, tipo)` |
| `jwt.sign({ id, email, tipoUsuario, cedula }, ...)` repetido | register, login | `TokenService.crear(usuario)` |
| Armar el objeto `usuario` de la respuesta a mano | register, login | `usuario.toPublicJSON()` o un serializer |
| `rollback()` repetido antes de cada `return` | register | `withTransaction(async t => {...})` |
| `include: [Usuario, Vendedor, Repartidor...]` enorme | pedido.controller | scopes de Sequelize o `PedidoRepository` |
| Comprobar rol con `verificarRol(...)` y luego si es dueño del recurso a mano | varios | middleware `verificarPropietario(Modelo)` |

### Estructura objetivo por módulo

```
modules/pedidos/
  pedido.routes.js        # solo rutas + middlewares + schema de validación
  pedido.controller.js    # delgado: req -> service -> res
  pedido.service.js       # reglas de negocio
  pedido.repository.js    # consultas a la BD (includes, scopes)
  pedido.schema.js        # validaciones (Zod / express-validator)
  pedido.model.js
shared/
  utils/        validators.js, normalizers.js, codes.js, dates.js
  errors/       AppError.js, NotFoundError, ForbiddenError, ...
  middlewares/  asyncHandler, validar, errorHandler, rateLimiters
  services/     token.service.js, codigo.service.js
  helpers/      response.js (ok, created, paginated), withTransaction.js
```

### Piezas base a crear (ejemplos)

```js
// shared/helpers/asyncHandler.js
module.exports = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

// shared/errors/AppError.js
class AppError extends Error {
  constructor(message, status = 500, code) { super(message); this.status = status; this.code = code; }
}
module.exports = { AppError };

// shared/helpers/withTransaction.js
const { sequelize } = require('../../config/database');
module.exports = (fn) => sequelize.transaction(fn); // commit/rollback automático

// shared/helpers/response.js
exports.ok = (res, data, status = 200) => res.status(status).json({ success: true, data });
```

Con eso, un controller queda así:

```js
register = asyncHandler(async (req, res) => {
  const { usuario, token } = await authService.registrar(req.body);
  return ok(res, { usuario: usuario.toPublicJSON(), token }, 201);
});
```

Y los errores se lanzan, no se responden a mano: `throw new AppError('El email ya está registrado', 409)`.

### Mejoras de endpoints

- [ ] Respuesta uniforme: `{ success, data, error: { code, message } }`.
- [ ] Versionado: `/api/v1/...`.
- [ ] Paginación, filtros y orden en todos los listados (`?page=&limit=&sort=`).
- [ ] Verbos y rutas REST consistentes (hoy hay mezcla de `PUT`/`PATCH` y rutas tipo `/:id/en-camino`).
- [~] Un solo punto de validación por endpoint (schema): hecho en auth, falta en el resto
- [ ] DTO/serializers: nunca devolver el modelo crudo de Sequelize.
- [ ] Documentar todo con OpenAPI/Swagger.
- [ ] Códigos de error estables (`EMAIL_YA_REGISTRADO`) para que la app los traduzca.
- [ ] Mismo patrón en Flutter: un `ApiClient` (dio) con interceptores para token, refresh y errores, en vez de lógica HTTP repartida en cada `*_service.dart`.
- [ ] Limpiar duplicados en Flutter (`*_old`, `*_new`, `*_fixed`, `mock_data`).

---

## 1. Funcionalidades por rol

### Cliente
- [ ] Registro con verificación real, login social (Google/Apple), biometría
- [ ] Catálogo con búsqueda, filtros, categorías, favoritos, reseñas
- [ ] Carrito multi-producto, notas, cupones, propina
- [ ] Pago dentro de la app, historial y facturas
- [ ] Seguimiento en vivo con ETA real, chat/llamada con el repartidor
- [ ] Calificación de vendedor y repartidor, repetir pedido, direcciones guardadas
- [ ] Push por cada cambio de estado

### Vendedor
- [ ] Panel de pedidos en tiempo real con alerta sonora, aceptar/rechazar
- [ ] Gestión de productos, stock, horarios, abierto/cerrado
- [ ] Reportes de ventas, más vendidos, liquidaciones
- [ ] Promociones y cupones propios

### Repartidor
- [ ] Disponibilidad on/off
- [ ] Ofertas de pedidos cercanos con tiempo límite
- [ ] Navegación a recogida y entrega
- [ ] Prueba de entrega (foto o PIN)
- [ ] Ganancias diarias/semanales
- [ ] Verificación de documentos (licencia, cédula, placa)

### Administrador (no existe aún)
- [ ] Panel web: aprobar vendedores/repartidores
- [ ] Pedidos, disputas, reembolsos
- [ ] Métricas, comisiones, zonas y tarifas
- [ ] Moderación de reseñas, bloqueo de usuarios

---

## 2. Lógica de negocio

- [ ] Asignación automática de repartidor por cercanía (PostGIS)
- [ ] Tarifa de envío dinámica (distancia, hora, demanda)
- [ ] Máquina de estados de pedido estricta + auditoría de cambios
- [ ] Cancelaciones y reembolsos con reglas claras
- [ ] Comisión de plataforma y liquidaciones
- [ ] Expiración y reasignación si nadie acepta el pedido

## 3. Pagos (Ecuador)

- [ ] PayPhone / Datafast / Kushki
- [ ] Efectivo contra entrega con control de caja del repartidor
- [ ] Webhooks con verificación de firma e idempotencia
- [ ] Tokenización, nunca guardar datos de tarjeta
- [ ] Facturación electrónica SRI (si se opera legalmente)

## 4. Stack recomendado

| Capa | Hoy | Meta |
|---|---|---|
| App | Flutter | Flutter + Riverpod/Bloc, go_router, dio, freezed |
| Backend | Express JS | TypeScript + NestJS o Express modular, Zod |
| BD | PostgreSQL | PostgreSQL + PostGIS, migraciones (Prisma/Knex) |
| Caché/colas | ninguno | Redis + BullMQ |
| Tiempo real | Socket.IO | Socket.IO + adaptador Redis |
| Mapas | Google Maps | + Directions / Distance Matrix |
| Archivos | disco local | S3 / Cloudflare R2 + CDN |
| Notificaciones | FCM + Brevo | + WhatsApp Business API |
| Auth | JWT 30 días | Access 15 min + refresh con rotación, OAuth, 2FA |

## 5. Seguridad: pendientes de la revisión

- [x] Sacar `node_modules` de git y arreglar `.gitignore` (falta hacer el commit)
- [x] Quitar contraseña la clave antigua de `database.js` y `docker-compose.yml`
- [ ] Rotar contraseña de BD si el repo es público
- [x] Verificar con `git log --all -- backend/.env` que nunca se subió (OK; solo google-services.json estuvo en el historial)
- [ ] Control de propiedad en `GET /api/pedidos/:id` (hoy cualquier usuario ve pedidos ajenos)
- [ ] HTTPS con dominio propio (hoy `http://5.161.208.204:3000`)
- [x] `crypto.randomInt` en lugar de `Math.random` para códigos
- [x] No loguear códigos en producción (solo en desarrollo)
- [x] Rate limit en `/login`, `/register` y `check-*`
- [x] Normalizar email (`toLowerCase`) en todos los endpoints
- [x] Exigir email verificado en el servidor al registrar y marcar `EMAILVERIF`
- [ ] Access token corto + refresh token
- [ ] CORS y Socket.IO con orígenes restringidos
- [ ] Extensión de archivos subidos según mimetype, no `originalname`
- [ ] Limitar tamaño/formato de `fotoPerfil`
- [ ] `flutter_secure_storage` para el token en el móvil
- [x] Arreglar `google-services.json` en `.gitignore`

## 6. No funcionales

- [ ] Paginación, índices y caché de catálogo
- [ ] Reconexión de sockets, reintentos, modo offline en consultas
- [ ] Logs estructurados, Sentry/Crashlytics, métricas y alertas
- [ ] Backend sin estado (varias instancias detrás de balanceador)
- [ ] Política de privacidad, términos y borrado de cuenta

## 7. Infraestructura

- [ ] Docker para backend + BD
- [ ] CI/CD con GitHub Actions (lint, tests, build, deploy)
- [ ] Entornos dev / staging / producción
- [ ] Nginx + TLS (Let's Encrypt) + dominio
- [ ] Backups automáticos de PostgreSQL y restauración probada
- [ ] Firebase App Distribution, luego Play Store / App Store

## 8. Calidad

- [~] Tests backend: hecho `npm run test:auth` (82 pruebas del módulo auth); falta el resto de módulos
- [ ] Tests de widgets e integración en Flutter
- [ ] OpenAPI/Swagger
- [ ] ESLint + `flutter analyze` en el CI
- [ ] Migraciones en lugar de `.sql` sueltos
- [ ] Limpiar `test-socket.js`, `tmp/`, `author: "Tu Nombre"`
- [x] Mover dotenv a la primera línea de `server.js`

## 9. Diferenciadores (al final)

- [ ] Recomendaciones personalizadas y búsqueda inteligente
- [ ] Puntos / suscripción de envío gratis
- [ ] Pedidos programados y grupales
- [ ] Modo oscuro, accesibilidad, i18n
- [ ] Chat de soporte / tickets
- [ ] Optimización de rutas con varios pedidos

---

## Fases sugeridas

1. **Fundamentos (1-2 sem):** `.gitignore`, secretos, HTTPS, seguridad crítica, helpers base (`asyncHandler`, `AppError`, `validar`, `withTransaction`), limpieza.
2. **Refactor y núcleo (3-4 sem):** servicios/repositorios por módulo, eliminar duplicados, TypeScript, Redis, almacenamiento en la nube, tests, CI/CD.
3. **Flujo real de delivery (3-4 sem):** pagos, asignación con PostGIS, tarifas dinámicas, prueba de entrega.
4. **Panel de administración (2-3 sem):** web con React/Next.js.
5. **Pulido y lanzamiento (2 sem):** observabilidad, pruebas con usuarios, tiendas.
6. **Diferenciadores:** iteraciones posteriores.

## Decisiones pendientes

- [ ] ¿Portafolio o producto real? (define prioridad de pagos, SRI, legal)
- [ ] ¿Migrar a TypeScript ya o mejorar el JavaScript actual?

---

## Registro de avance

### Fase 1 (en curso)
- [x] `.gitignore` reescrito, `node_modules` fuera del índice de git
- [x] Sin contraseña hardcodeada en `database.js`; `docker-compose.yml` lee del `.env`
- [x] `backend/.env.example` creado
- [x] Helpers base en `backend/src/shared/` (AppError, asyncHandler, response, withTransaction, validar, errorHandler, validators, normalizers, codes)
- [ ] **Rotar `JWT_SECRET`** (hoy es un correo, adivinable) y la contraseña de BD
- [ ] Hacer el commit de estos cambios
- [ ] Activar `errorHandler` global (cambia el formato de error: migrar la app Flutter a la vez)
- [ ] Refactorizar `auth.controller.js` usando los helpers (primer módulo piloto)
- [ ] Restringir la API key de `google-services.json` en Google Cloud (estuvo en el historial)

### Avance (2026-10-05)
- [x] Helpers base en uso: `AppError`, `asyncHandler`, `withTransaction`, `validar`, `errorHandler`, `limitadores`, servicios de token, códigos, logs y configuración
- [x] **Módulo auth** migrado al esquema nuevo, en capas, con 82 pruebas de extremo a extremo
- [x] `errorHandler` global activo (formato compatible con la app: `error` en texto + `code`)
- [ ] Migrar el resto de módulos: vendedores, productos, direcciones, pedidos, repartidores, notificaciones (incluye control de propiedad en `GET /pedidos/:id`)
- [ ] Servicio de imágenes con `sharp` (la foto de perfil responde 501 mientras tanto)
- [ ] **Antes de producción (anotado por el usuario):** clave fuerte en `JWT_SECRET` y en la BD; restringir la API key en Google Cloud; HTTPS; `BREVO_API_KEY`
- [ ] **Commit a `main`:** cuando todo el esquema esté registrado y probado en la BD

### Avance (2026-10-06)
- [x] `USUARIOS.USUARIO` generado por la BD (`jcayapa`, `jfcayapa`...) y login con correo **o** usuario (97 pruebas)
- [x] `FHASTA` vigente = `2999-12-31 00:00:00` en las 26 tablas
- [x] Carpeta `database/migraciones/` con la 001 (`schema.sql` = instalación nueva; migraciones = bases con datos)
- [ ] App Flutter: pantalla de login con "Correo o usuario" y mostrar el usuario asignado tras el registro
- [~] ~~Endpoint para cambiar el usuario~~ (descartado: ahora es la clave primaria y no se puede cambiar nunca)

### Avance (2026-10-06, 2.ª parte)
- [x] Nombres de tablas y columnas **sin comillas** (se escriben en mayúsculas, PostgreSQL los guarda en minúsculas): `SELECT * FROM USUARIOS` funciona
- [x] **Sin UUID:** clave primaria legible en todas las tablas (`jcayapa`, `VEN-000001`, `PED-20261006-000001`, catálogos `'001'`, tablas internas `1, 2, 3`) y claves inmutables
- [x] Esquema v2 aplicado; 103 pruebas del módulo auth
- [ ] Al migrar pedidos: cambiar las validaciones `isUUID()` por el formato de código

### Avance (2026-10-06, 3.ª parte)
- [x] **Vendedores y productos** migrados al esquema nuevo, en capas (85 pruebas en `npm run test:tienda`)
- [x] **Servicio de imágenes** con `sharp` (WebP en 3 tamaños, validación real, sin EXIF, deduplicación) y foto de perfil
- [x] Privacidad: las listas públicas de vendedores ya no exponen email ni teléfono; solo vendedores aprobados son visibles
- [x] Migrar direcciones, pedidos (sockets) y notificaciones (106 pruebas en `npm run test:pedidos`)
- [x] Migrar repartidores (último módulo del backend): 47 pruebas en `npm run test:repartidores`
- [ ] Imágenes en S3/R2 para producción; limpieza de archivos huérfanos; `PUBLIC_URL` en producción

### Avance (2026-10-06, 4.ª parte)
- [x] **Pedidos** en capas con máquina de estados, stock sin sobreventa, carrera entre repartidores resuelta y permisos por rol (corrige que cualquiera pudiera ver cualquier pedido)
- [x] **Direcciones** y **notificaciones** en capas; push por Firebase listo del lado del backend
- [x] Seguimiento en tiempo real: la ubicación del repartidor se guarda (posición actual + historial)
- [x] Funciones que la app usaba y no existían: calificar pedidos; nuevas: rechazar pedido, registrar token push
- [x] `npm test` corre las 3 suites (294 pruebas)
- [x] Migrar repartidores y revisar el backend completo
- [ ] App Flutter: registrar el token push; login con "Correo o usuario"
- [ ] IVA, propina, cupones, comisión y pagos; reglas de aceptación y reasignación de pedidos

### Avance (2026-10-06, 5.ª parte): BACKEND COMPLETO
- [x] **Repartidores** en capas; corregido el rastreo abierto a cualquier usuario y la difusión de ubicaciones a todos los clientes conectados
- [x] Endpoints que la app usaba y no existían: `pedidos-disponibles`, `entregas-activas`, `PATCH /repartidores/estado`, `calificar`
- [x] Vulnerabilidad de subida de archivos cerrada (se eliminó `multer`); dependencias: de 33 a 10 vulnerabilidades, ninguna alta ni crítica
- [x] **341 pruebas** en 4 suites (`npm test`), todas en verde
- [ ] App Flutter: login con "Correo o usuario", token push, revisar pantallas
- [ ] README actualizado
- [ ] Antes de producción: claves, HTTPS, S3/R2, JWT con refresh, probar firebase-admin 14

### Avance (2026-10-06, 6.ª parte): commit del backend
- [x] README actualizado; documentos y scripts obsoletos eliminados
- [x] Commit del backend a main (Flutter queda fuera, para el siguiente)

### Avance (2026-10-06, 7.ª parte): App Flutter, primera pasada
- [x] Entornos por --dart-define (local, emulador, lan, prod)
- [x] Tema nuevo "Medianoche eléctrica" centralizado en theme.dart
- [x] Login por correo o usuario; token push registrado en el backend
- [x] Quitados datos falsos (mock) y código muerto
- [ ] Probar en emulador de punta a punta y rediseñar pantallas

### Avance (2026-10-07, 8.ª parte): identidad V3
- [x] Tablas con prefijo T y columnas de código con prefijo C: personas, usuarios, teléfonos, direcciones, imágenes, catálogos y logs
- [x] Historial en la MISMA tabla (FDESDE/FHASTA) con trigger; ACTUALIZADOPOR siempre se llena
- [x] Vista VUSUARIOS (consultable e insertable); API y app sin cambios
- [x] 70 pruebas nuevas; total 411 en 5 suites
- [x] Vendedores → `TNEGOCIOS` + `THORARIOSNEGOCIO` (el vendedor es un usuario con rol; local = dirección `LOC`) · 413 pruebas
- [x] Repartidores → `TREPARTIDORES` (el repartidor es un usuario con rol) · BD de desarrollo recreada
- [x] Productos, cupones, pedidos, pagos, calificaciones, notificaciones, dispositivos, documentos y transversales al mismo estilo (anclas `T…ID`); `HIST*` solo en catálogos; `COMMENT ON` en todo
- [x] Endpoints de teléfonos y direcciones con tipos · 435 pruebas
- [ ] Reglas de negocio (IVA, propina, cupones, comisión, pagos con pasarela, reasignación) y pendientes de producción
- [ ] App Flutter (después del backend)
- [ ] Endpoints y pantallas de teléfonos y direcciones con tipos
- [ ] Limpiar y reutilizar código (servicios, helpers)
