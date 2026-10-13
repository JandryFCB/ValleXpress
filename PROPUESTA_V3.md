# Propuesta V3: lo que falta (tablas, logs y funciones de una app de delivery)

Fecha: 2026-10-06 · **Estado (2026-10-07):** la sección 2 (imágenes, teléfonos, tipos de dirección) ya está hecha con tu diseño (prefijo T, historial en la misma tabla): ver el Bloque 11 de `INFORME_AVANCES.md`. Quedan pendientes las secciones 3 y 4 (funciones de la app y orden).

---

## 1. Lo que revisé en la BD (hechos, no suposiciones)

### Historial (`HISTUSUARIOS`)
Probé con la BD real. **El historial sí se registra**, tanto cuando cambia la app como cuando se edita con SQL directo:

- Cambiar nombres, teléfono, etc. crea una fila en `HISTUSUARIOS` con la versión anterior (`VERSIONCONTROL`, `FDESDE`, `FHASTA`).
- Tu usuario tiene 3 filas de historial: un cambio de teléfono (…846 → …845 → …846) y un borrado.

Lo que **sí está flojo** (y creo que es lo que viste):
1. **`CAMBIADOPOR` queda vacío si editas desde Adminer o psql.** Solo se llena cuando el cambio lo hace el backend. Se puede mejorar poniendo un valor por defecto (`SESSION_USER`).
2. **Hay columnas que NO versionan a propósito:** `ULTIMACONEXION`, `ULTIMAIP`, `INTENTOSFALLIDOS`, `BLOQUEADOHASTA`. Cambian en cada login y llenarían el historial de basura. Si cambiaste solo eso, no verás versión nueva.
3. **No existe tabla de cliente** (`CLIENTES`): lo propio del cliente no tiene dónde guardarse ni versionarse (preferencias, alergias, favoritos…).
4. **No hay un "quién vio / qué cambió" legible:** el historial guarda la fila completa, pero no dice *qué campo* cambió. Se puede agregar una vista `VERCAMBIOS` que lo muestre.

Si tus cambios fueron otros, dime cuáles (campo y cómo los hiciste) y lo reproduzco.

### `LOGERRORES` vs `LOGMENSAJES`
| Tabla | Qué guarda hoy | Qué NO guarda |
|---|---|---|
| `LOGERRORES` | **Solo errores inesperados del servidor (HTTP 5xx):** fallos de código, BD caída, excepciones. Con módulo, ruta, stack y solicitud (sin contraseñas). | Errores del usuario (400/401/403/404/409): contraseña mala, token vencido, stock insuficiente |
| `LOGMENSAJES` | Eventos del sistema. **Hoy solo 2 casos:** "no se pudo enviar el correo". | Casi todo lo importante: logins fallidos, bloqueos, pedidos creados/cancelados, push que fallaron, imágenes rechazadas |

Por eso `LOGERRORES` está vacío (y es buena señal: no ha habido fallos graves) y `LOGMENSAJES` casi no dice nada. **Falta registrar eventos de negocio y de seguridad.** Propuesta de qué registrar:

- Seguridad: login fallido, cuenta bloqueada, token inválido repetido, acceso denegado (403), cambio de contraseña, rate limit superado.
- Negocio: pedido creado/cancelado/rechazado, repartidor que no acepta, pago fallido, stock agotado.
- Integraciones: push fallido, correo fallido, imagen rechazada.
- Errores del cliente (4xx) con nivel `INFO`/`ADVERTENCIA` y **solo los repetidos** (para no llenar la tabla).

---

## 2. Tablas nuevas que entendí de tu mensaje

Todas con el mismo patrón de siempre: MAYÚSCULAS, sin guion bajo, código legible, `FDESDE/FHASTA/VERSIONCONTROL`, `DATOSEXTRA`, tabla `HIST…`.

### a) Imágenes del usuario: `IMAGENUSUARIO`
Hoy `USUARIOS.FOTO` guarda un solo archivo y se pisa. Propuesta (igual que `IMAGENPRODUCTO`):

| Columna | Para qué |
|---|---|
| `IMAGEN` (PK, ej. `IMU-000001`) | código |
| `USUARIO` | dueño |
| `ARCHIVO` | enlace a `ARCHIVOS` (el WebP optimizado) |
| `TIPO` | `001` PERFIL · `002` PORTADA · `003` DOCUMENTO (cédula/licencia) |
| `VIGENTE` | solo una vigente por usuario y tipo |

Al subir una foto nueva, la anterior queda en el historial (no se pierde) y la nueva pasa a vigente. `USUARIOS.FOTO` se reemplaza por esta tabla.

### b) Teléfonos: `TELEFONOUSUARIO` + catálogo `TIPOTELEFONO`
Un usuario puede tener varios. Hoy `USUARIOS.TELEFONO` es uno solo y único.

- `TIPOTELEFONO`: `001` MÓVIL · `002` CASA · `003` TRABAJO · `004` WHATSAPP
- `TELEFONOUSUARIO`: `TELEFONO` (PK, `TEL-000001`), `USUARIO`, `TIPO`, `NUMERO`, `PRINCIPAL`, `VERIFICADO`, `VERIFICADOEN`.
- Regla: un solo teléfono principal por usuario; el número es único entre usuarios activos.

### c) Tipos de dirección: catálogo `TIPODIRECCION`
`DIRECCIONES` ya existe pero **no tiene tipo**. Agregar:

- `TIPODIRECCION`: `001` DOMICILIO · `002` TRABAJO · `003` PAREJA/FAMILIA · `004` OTRO
- Columna `TIPO` en `DIRECCIONES` (con `ALIAS` libre: "Casa de mamá").
- Para el vendedor: `TIPO` `005` LOCAL/NEGOCIO (donde se recoge el pedido).

### d) Otras que van de la mano
- `CLIENTES`, `VENDEDORES`, `REPARTIDORES` ya hay (los dos últimos); falta `CLIENTES` (perfil del cliente: favoritos, preferencias, total de pedidos, nivel de fidelidad).
- `CORREOUSUARIO` (opcional): varios correos, igual que teléfonos. Solo si lo necesitas.

**Si me das tu documento, lo tomo como verdad y ajusto esto a lo que tú definas.**

---

## 3. Cómo son las apps de delivery (Uber Eats, Rappi, PedidosYa, DiDi Food)

Lo que **todas** tienen y cada rol necesita. Marco ✅ lo que ValleXpress ya tiene, 🟡 lo que está a medias y ❌ lo que falta.

### Cliente
- ✅ Registro, login, direcciones, carrito, pedido, seguimiento en mapa, calificación
- 🟡 Buscar y filtrar (por categoría, precio, "abierto ahora", tiempo de entrega)
- ❌ **Pantalla de inicio rica:** categorías, promociones, "cerca de ti", favoritos, "pedir otra vez"
- ❌ **Costo y tiempo estimado antes de pagar** (envío por distancia, ETA)
- ❌ **Pagos reales:** tarjeta, transferencia con comprobante, efectivo con "pago exacto"; propina
- ❌ **Cupones y promociones**, programa de puntos
- ❌ **Chat con el repartidor** y botón de llamar (número enmascarado)
- ❌ **Soporte / reportar problema** con un pedido y reembolsos
- ❌ Pedidos programados, repetir pedido, ver recibo/factura

### Vendedor (tienda)
- ✅ Productos, pedidos entrantes, estados
- 🟡 Horarios (hay tabla, falta pantalla), disponibilidad de producto
- ❌ **Alerta sonora y "aceptar en X minutos"** (si no acepta, se rechaza solo)
- ❌ **Panel de ventas:** ventas por día, productos más vendidos, calificaciones, ganancias
- ❌ Opciones de producto (tamaño, extras, "sin cebolla"), categorías propias, combos
- ❌ Pausar la tienda, tiempo de preparación por pedido, liquidaciones

### Repartidor
- ✅ Ver pedidos, aceptar, ubicación en vivo
- ❌ **Navegación** al comercio y al cliente (abrir Google Maps/Waze)
- ❌ **Ganancias:** por entrega, propinas, resumen semanal, retiro
- ❌ Prueba de entrega (foto o código de 4 dígitos que da el cliente)
- ❌ Documentos y verificación (cédula, licencia, placa) con aprobación del admin
- ❌ Asignación automática por cercanía y reasignación si nadie acepta

### Administrador (hoy **no existe**; es lo más importante que falta)
- ❌ Panel web: aprobar vendedores y repartidores, ver pedidos en vivo, mapa de repartidores
- ❌ Gestión de usuarios, bloqueos, reembolsos, cupones, zonas de cobertura, tarifas
- ❌ Reportes y revisión de `LOGERRORES`/`LOGMENSAJES`

### Transversal (lo que hace que una app se sienta "profesional")
- **Notificaciones push por cada cambio de estado** (ya está el backend; falta probarlo en la app)
- Estados vacíos y de error amables, cargas con *skeleton*, reintentos cuando no hay internet
- Modo claro y oscuro, accesibilidad, varios idiomas
- Onboarding de 3 pantallas, términos, privacidad (obligatorio para Google Play)
- Seguridad: refresh de JWT, cierre de sesión en todos los dispositivos, verificación de teléfono por SMS
- Métricas y errores en producción (Firebase Crashlytics/Analytics), copias de seguridad de la BD

---

## 4. Orden que recomiendo

1. **BD V3 (esto): imágenes, teléfonos, tipos de dirección, `CLIENTES`, `CAMBIADOPOR` por defecto, más eventos en `LOGMENSAJES`.** (~1 bloque, con pruebas)
2. **Reglas de negocio:** costo de envío por distancia, ETA, propina, cupones, comisión.
3. **Rol administrador** (API primero, luego panel web).
4. **App Flutter:** inicio rico, carrito/checkout nuevo, seguimiento, ganancias del repartidor, panel del vendedor, con el tema nuevo.
5. Pagos reales, chat, soporte.

## 5. Preguntas rápidas para ti

1. ¿Tu documento incluye más tablas? Mándalo cuando esté y lo uso como base.
2. ¿Qué cambio exacto hiciste en el usuario cliente que no viste en el historial?
3. ¿Los pagos serán solo **efectivo** al inicio o también tarjeta/transferencia?
4. ¿Cuántos usuarios esperas al lanzar y en qué ciudad? (define tarifas y zonas)
