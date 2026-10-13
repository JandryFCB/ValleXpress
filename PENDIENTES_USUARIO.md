# Pendientes tuyos (lo que debes hacer tú)

Última actualización: 2026-10-06

## 1. Subir el commit a GitHub

Estás en `main` y el commit `c9e5b7d` (backend) aún no está en `origin`.

```bash
cd C:\Users\USUARIO\Desktop\ValleXpress
git status -sb          # debe decir: main...origin/main [ahead 1]
git push origin main
```

Si te pide credenciales, usa tu usuario de GitHub y un **token personal** (Settings → Developer settings → Personal access tokens), no tu contraseña.

Después del push, entra a https://github.com/JandryFCB/ValleXpress y confirma que el repo sigue en **Private** (Settings → General → Danger Zone).

## 2. Qué NUNCA debes subir

| Archivo | Por qué | ¿Protegido? |
|---|---|---|
| `backend/.env` | Tiene la clave de la BD, `JWT_SECRET` y claves de servicios | Sí (`.gitignore`) |
| `*firebase-adminsdk*.json` | Llave privada de Firebase: da control del proyecto | Sí |
| `google-services.json` / `GoogleService-Info.plist` | Configuración de Firebase de la app | Sí |
| `*.pem`, `*.key` | Llaves y certificados | Sí |
| `backend/uploads/` | Imágenes de usuarios | Sí |
| `node_modules/` | Pesa mucho y se reinstala con `npm install` | Sí |
| `datos_base.txt` | Tus notas de trabajo | **No**: no lo agregues con `git add .` |

Reglas simples:

- Antes de cada commit mira `git status` y revisa los archivos que vas a subir.
- Evita `git add .` a ciegas. Es mejor `git add carpeta/` o `git add archivo`.
- Si un secreto llega a subirse, **no basta con borrarlo**: queda en el historial. Hay que cambiar esa clave por una nueva.

## 3. Cambiar claves (antes de producción)

Estas ya quedaron escritas en el historial de git, así que hay que reemplazarlas por nuevas:

- [ ] **Clave de la BD** (`DB_PASSWORD`): ponla larga y aleatoria. Cámbiala en `.env` y en la BD.
- [ ] **`JWT_SECRET`**: genera uno nuevo con
  `node -e "console.log(require('crypto').randomBytes(64).toString('hex'))"`
- [ ] **API key de Google** (Maps/Firebase): en Google Cloud Console, restríngela por app (SHA-1 del paquete Android) y por API.
- [ ] **`BREVO_API_KEY`**: crea una nueva en Brevo (la anterior ya venció) y ponla en `.env`.
- [ ] Guarda todas en un gestor de contraseñas.

## 4. Antes de publicar la app (producción)

- [ ] HTTPS en el servidor y `trust proxy`.
- [ ] `PUBLIC_URL` con tu dominio.
- [ ] Imágenes en S3/R2 en vez del disco del servidor.
- [ ] Programar `PURGARLOGS()` (limpieza de logs).
- [ ] Probar la actualización de `firebase-admin`.

## 5. Decisiones de negocio que debes tomar

IVA, propina, cupones, comisión de la plataforma, pagos en línea, si `abiertoAhora` bloquea pedidos y qué hacer cuando ningún repartidor acepta un pedido.

## 6. Siguiente paso del proyecto

App Flutter: login con "Correo o usuario", registrar el token push y revisar las pantallas contra el backend nuevo. Tus cambios actuales de Flutter (11 archivos) siguen sin commitear.
