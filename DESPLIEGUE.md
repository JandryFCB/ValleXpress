# Despliegue de ValleXpress en producción

Todo corre con Docker en un servidor Linux: **base de datos + backend + HTTPS automático (Caddy) + respaldos diarios**.
Cada servicio se reinicia solo si falla o si el servidor se reinicia (reemplaza a PM2). Probado localmente el 2026-10-16.

```
deploy/
  docker-compose.prod.yml   los 4 servicios
  Caddyfile                 HTTPS automático y proxy al backend (incluye el tiempo real / WebSocket)
  .env.ejemplo              plantilla de variables (copiar como .env)
  secretos/firebase.json    credencial de Firebase (NO va a git; la subes tú)
  respaldos/                respaldos diarios de la base (NO va a git)
```

---

## 1. El servidor

- **Hetzner Cloud**: Ubuntu 24.04, 2 vCPU y 4 GB de RAM alcanzan de sobra para empezar (CX23 x86 o CAX11 ARM; las
  imágenes funcionan en las dos).
- Al crearlo, agrega tu **llave SSH** (más seguro que contraseña).
- Anota la **IP pública**.

## 2. El dominio (gratis)

La app necesita un nombre para tener HTTPS. Opción gratis y estable: **DuckDNS**
1. Entra a https://www.duckdns.org con tu cuenta de Google.
2. Crea un subdominio, por ejemplo `vallexpress` → queda `vallexpress.duckdns.org`.
3. Pon la IP del servidor y guarda.

(Si después compras un dominio, solo cambias `DOMINIO` y `PUBLIC_URL` en el `.env` y recompilas la app.)

## 3. Preparar el servidor (una sola vez)

```bash
ssh root@TU_IP
apt update && apt upgrade -y
curl -fsSL https://get.docker.com | sh          # instala Docker y Docker Compose
ufw allow OpenSSH && ufw allow 80 && ufw allow 443 && ufw --force enable
```

## 4. Subir el proyecto

```bash
# En el servidor (el repo es privado: usa un token de GitHub como contraseña)
git clone https://github.com/JandryFCB/ValleXpress.git
cd ValleXpress && git checkout feat/flujo-pedidos        # o main cuando lo fusiones
cd deploy && cp .env.ejemplo .env && nano .env            # llena TODOS los valores (claves NUEVAS)
mkdir -p secretos
```

Desde tu PC, sube la credencial de Firebase:
```bash
scp backend/vallexpress-delivery-firebase-adminsdk-*.json root@TU_IP:~/ValleXpress/deploy/secretos/firebase.json
```
Y en el servidor, que el backend (usuario 1000 dentro del contenedor) pueda leerla; si no, las push no salen
(en los logs: `EACCES: permission denied, open '/run/secrets/firebase.json'`):
```bash
chown 1000:1000 ~/ValleXpress/deploy/secretos/firebase.json && chmod 600 ~/ValleXpress/deploy/secretos/firebase.json
```

Valores del `.env` que importan:
| Variable | Qué poner |
|---|---|
| `DOMINIO` | `vallexpress.com` (desde 2026-10-23; antes `vallexpress.duckdns.org`) |
| `DOMINIO_ANTERIOR` | `vallexpress.duckdns.org` (las apps ya instaladas lo usan: Caddy sigue respondiendo en él) |
| `PUBLIC_URL` | `https://vallexpress.com` |
| `DB_PASSWORD` | una clave larga y aleatoria (nueva) |
| `JWT_SECRET` | `node -e "console.log(require('crypto').randomBytes(64).toString('hex'))"` (el servidor no arranca con menos de 32 caracteres) |
| `BREVO_API_KEY` | una clave **nueva** de Brevo (la de desarrollo quedó expuesta) |
| `SMTP_FROM` / `REPLY_TO_EMAIL` | el correo remitente verificado en Brevo y el de soporte |

## 5. Encender

```bash
cd ~/ValleXpress/deploy
docker compose --env-file .env -f docker-compose.prod.yml up -d --build
docker compose -f docker-compose.prod.yml ps                       # los 4 "Up", backend y db "healthy"
curl https://vallexpress.duckdns.org/api/health                     # {"status":"OK","message":"ValleXpress Backend funcionando correctamente",...}
```

La primera vez Caddy tarda ~30 s en sacar el certificado HTTPS. La base se crea sola con todas las migraciones.

**Clave del administrador:**
```bash
docker exec -e CLAVE="una-clave-larga-y-segura" vx_backend node scripts/clave-admin.js
```

**Luego, desde la app como admin** (Resumen → Configuración):
- *Perfiles y permisos*: aprobación **manual** para vendedores y repartidores.
- *Tarifas, comisión y zona*: revisa las tarifas y la zona de Yantzaza.
- *Cobros a negocios*: escribe la cuenta donde te transfieren y los días de gracia.

## 6. La app apuntando al servidor

```bash
cd frontend/vallexpress_app
flutter build apk --release --dart-define=ENTORNO=prod --dart-define=API_PROD=https://vallexpress.duckdns.org
# APK: build/app/outputs/flutter-apk/app-release.apk (~70 MB) → se instala en cualquier Android
# Más liviana (~25 MB, una por tipo de celular; casi todos usan la arm64-v8a): agrega --split-per-abi
```

### Para Google Play (cuando publiques)
1. **Identificador definitivo de la app**: hoy es `com.example.vallexpress_app` y Google Play NO acepta `com.example`.
   Hay que cambiarlo (por ejemplo `com.vallexpress.app`) **antes de la primera publicación** (después no se puede) y
   registrar ese nombre en Firebase para bajar un `google-services.json` nuevo.
2. **Llave de publicación** (una sola vez; guárdala para siempre, si la pierdes no puedes actualizar la app):
   ```bash
   keytool -genkey -v -keystore vallexpress-publicacion.jks -keyalg RSA -keysize 2048 -validity 10000 -alias vallexpress
   ```
   Crea `android/key.properties` (no va a git):
   ```
   storeFile=C:/ruta/vallexpress-publicacion.jks
   storePassword=...
   keyAlias=vallexpress
   keyPassword=...
   ```
3. Compila el paquete para Play: `flutter build appbundle --release --dart-define=ENTORNO=prod --dart-define=API_PROD=https://...`
4. En Play Console declara: ubicación (GPS del repartidor con servicio en primer plano de tipo *location*) y notificaciones.

## 7. Actualizar a una versión nueva

```bash
cd ~/ValleXpress && git pull
# Si la versión trae migraciones NUEVAS (database/migraciones/0XX_*.sql), aplícalas UNA vez, en orden:
docker exec -i vx_db psql -U "$(grep ^DB_USER deploy/.env | cut -d= -f2)" -d "$(grep ^DB_NAME deploy/.env | cut -d= -f2)" < database/migraciones/0XX_nombre.sql
cd deploy && docker compose --env-file .env -f docker-compose.prod.yml up -d --build backend
```

## 8. Respaldos

- Cada día se guarda `deploy/respaldos/vallexpress-AAAAMMDD-HHMM.sql.gz` (se conservan 14 días).
- **Cópialos fuera del servidor** (si el servidor muere, mueren con él). Desde tu PC:
  `scp root@TU_IP:~/ValleXpress/deploy/respaldos/*.sql.gz ./respaldos-vallexpress/`
  (o un Storage Box de Hetzner con una tarea programada).
- Restaurar un respaldo (¡borra los datos actuales!):
  ```bash
  gunzip -c respaldos/vallexpress-AAAAMMDD-HHMM.sql.gz | docker exec -i vx_db psql -U USUARIO -d BASE
  ```

## 9. Que no se caiga (y enterarte si pasa)

- **Reinicio automático**: `restart: always` + comprobación de salud del backend cada 30 s.
- **Vigilancia gratis**: crea un monitor en https://uptimerobot.com a `https://vallexpress.duckdns.org/api/health`
  (cada 5 min, aviso al correo/Telegram si se cae).
- **Ver qué pasa**: `docker logs -f vx_backend` (errores en vivo), `docker stats` (memoria y CPU).
- **La app aguanta caídas cortas**: muestra "No pudimos conectarnos con ValleXpress…" con *Reintentar* y no pierde la sesión.

## 10. Antes de abrir al público (checklist)

- [ ] Claves nuevas: `DB_PASSWORD`, `JWT_SECRET`, `BREVO_API_KEY` (las de desarrollo estuvieron expuestas).
- [ ] En Brevo, autorizar la IP del servidor (o dejar desactivado el bloqueo por IP).
- [ ] Aprobación manual activada; tarifas, zona y cuenta de cobro revisadas.
- [ ] UptimeRobot vigilando y primer respaldo copiado fuera del servidor.
- [ ] Probar en un celular con la APK de producción: registro (llega el correo), pedido completo, notificaciones.
