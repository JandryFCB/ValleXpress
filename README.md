# ValleXpress

App de delivery (proyecto de tesis) que conecta **clientes**, **vendedores** y **repartidores**.
Backend en Node.js/Express + PostgreSQL y app móvil en Flutter.

> Estado: **backend completo y probado (411 pruebas)**. La app Flutter está en revisión para conectarla al backend nuevo.
> Avances: [INFORME_AVANCES.md](INFORME_AVANCES.md) · Plan: [ROADMAP_TOP.md](ROADMAP_TOP.md)

## Tecnologías

| Capa | Stack |
|---|---|
| Backend | Node 22, Express 4, Sequelize 6, Socket.IO, JWT + bcryptjs, express-validator, express-rate-limit |
| Base de datos | PostgreSQL 15 (Docker) |
| Imágenes | `sharp` (WebP en 3 tamaños, nombre por hash SHA-256) |
| Notificaciones | Firebase Cloud Messaging (firebase-admin) |
| Correo | Brevo (API) |
| App | Flutter (Provider, flutter_map, socket_io_client, firebase_messaging) |

## Inicio rápido

```bash
# 1. Variables de entorno (el docker-compose y el backend usan el mismo .env)
cd backend
cp .env.example .env        # completa DB_PASSWORD y JWT_SECRET
npm install

# 2. Base de datos (crea las tablas con database/schema.sql la primera vez)
cd ..
docker-compose up -d

# 3. Backend
cd backend
npm run dev                 # http://localhost:3000

# 4. App
cd ../frontend/vallexpress_app
flutter pub get
flutter run
```

## Pruebas del backend

```bash
cd backend
npm test                    # 5 suites, 411 pruebas
```

Cada suite crea su propia base y carpeta temporales y las borra al terminar:
`test:identidad` (70), `test:auth` (103), `test:tienda` (85), `test:pedidos` (106), `test:repartidores` (47).

## Estructura del backend

```
backend/src/
├── modules/                # Un módulo por área: routes → schema → controller → service
│   ├── auth/  vendedores/  productos/  archivos/  direcciones/
│   └── notificaciones/  pedidos/  repartidores/
├── shared/                 # Código común: errores (AppError), helpers, middlewares,
│                           # servicios (token, código, log, catálogo, archivo), constantes
├── services/fcm.service.js # Push (FCM)
└── server.js
database/schema.sql         # Esquema (tablas T, anclas, catálogos, triggers de versionado, comentarios)
```

## Base de datos

- Tablas en **MAYÚSCULAS, sin guion bajo**. Se consultan sin comillas: `SELECT * FROM VUSUARIOS`.
- **Identidad (prefijo `T`, columnas de código con prefijo `C`):** `TPERSONAS` (datos de la persona, atados por `CPERSONA` = 1, 2, 3…), `TUSUARIOS` (login: `CUSUARIO` como `jcayapa`, `CPERSONA`, `CROL`, `CESTATUSUARIO` = ACT/INA/BLQ), `TPERSONATELEFONOS`, `TPERSONADIRECCIONES`, `TPERSONAIMAGENES` y sus catálogos de tipos. Las tablas `TPERSONASID`, `TUSUARIOSID` y `TDIRECCIONESID` guardan el código estable al que apuntan las demás.
- **Historial en la misma tabla:** cada cambio cierra la fila vigente (`FHASTA` = ahora) y crea la nueva con `FHASTA = 2999-12-31`. Lo vigente es `WHERE FHASTA = '2999-12-31'`. `ACTUALIZADOPOR` guarda quién cambió.
- `VUSUARIOS`: vista con el usuario, la persona, el teléfono principal y la foto (solo lo vigente); se puede consultar e insertar.
- **El vendedor y el repartidor son un usuario con rol:** su perfil cuelga de `CUSUARIO` (`TNEGOCIOS` + `THORARIOSNEGOCIO`, `TREPARTIDORES`); su teléfono y correo salen de la persona y el local del negocio es una dirección tipo `LOC`.
- **Negocio:** `TPRODUCTOS`, `TPRODUCTOIMAGENES`, `TCUPONES`, `TPEDIDOS`, `TPEDIDODETALLE`, `TPAGOS`, `TCALIFICACIONES`, `TNOTIFICACIONES`, `TDISPOSITIVOS`, `TDOCUMENTOSUSUARIO`. Lo que otras tablas referencian (producto, cupón, pedido, dispositivo, persona, usuario, dirección) tiene su **ancla** `T…ID` con el código; las FK apuntan siempre al ancla.
- **Registros que solo se insertan:** `TSEGUIMIENTOPEDIDO` (cada cambio de estado, automático), `TUBICACIONREPARTIDOR`, `TAUDITORIA`, `TCODIGOSVERIFICACION`, `TSESIONES`.
- **Catálogos** (`ROLES`, `ESTADOPEDIDO`, `CATEGORIAS`, `TTIPOSTELEFONO`…) son los únicos con tabla gemela `HIST*`.
- Toda tabla y toda columna lleva `COMMENT ON` (descripción).
- **Ids legibles** generados por la BD: `PRO-000001`, `PED-20261006-000001`, `ARC-000001`; el usuario inicia sesión con su código (`jcayapa`) o su correo.
- **Catálogos** con códigos (`'001'`, `ACT`…) · `DATOSEXTRA` (VARCHAR, nula) en cada tabla.
- **Bitácoras:** `TLOGERRORES`, `TLOGMENSAJES` y `TAUDITORIA`, con datos sensibles ocultos.

## Flujo de un pedido

```
PENDIENTE → CONFIRMADO → PREPARANDO → LISTO → EN CAMINO → RECOGIDO → ENTREGADO → RECIBIDO
     └── CANCELADO / RECHAZADO (solo en los primeros estados)
```

Las transiciones las valida una máquina de estados en el backend, y el repartidor se asigna con bloqueo de fila (sin carreras entre repartidores).

## Endpoints principales (`/api`)

| Área | Rutas |
|---|---|
| Auth | `POST /auth/register`, `/auth/login`, verificación de correo y recuperación de contraseña |
| Usuario | `GET /usuarios/perfil`, `PUT /usuarios/actualizar`, `POST /usuarios/cambiar-contrasena`, `POST /usuarios/foto-perfil` |
| Vendedores / Productos | CRUD con imágenes en base64 |
| Pedidos | `POST /pedidos`, `GET /pedidos/mis-pedidos`, estado, calificación |
| Repartidores | `/repartidores/pedidos-disponibles`, `/aceptar`, `/ubicacion`, `/entregas-activas` |
| Notificaciones | `GET /notificaciones`, `POST /notificaciones/dispositivo` (token push) |

Errores con formato uniforme: `{ "error": "texto", "code": "CODIGO" }`.

## Variables de entorno

Ver [backend/.env.example](backend/.env.example). Nunca subas `.env` ni el JSON de Firebase al repositorio.

## Pendiente antes de producción

Claves fuertes (`JWT_SECRET`, BD), restringir la API key de Google, `BREVO_API_KEY` real, HTTPS y `trust proxy`, `PUBLIC_URL`, imágenes en S3/R2, JWT con refresh y programar `PURGARLOGS()`. Detalle en [INFORME_AVANCES.md](INFORME_AVANCES.md).
