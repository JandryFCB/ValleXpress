#!/usr/bin/env bash
# Compila la app para la web y la sube al servidor (la sirve Caddy en https://app.<DOMINIO>).
# Se ejecuta desde TU PC (Git Bash), en la raíz del repo:
#   bash deploy/publicar-web.sh root@IP_DEL_SERVIDOR [~/.ssh/llave]
#
# --pwa-strategy=none: sin caché del service worker. Con la de por defecto (offline-first) el navegador seguía
# mostrando la versión vieja después de publicar una nueva.
set -euo pipefail

SERVIDOR="${1:?Uso: bash deploy/publicar-web.sh root@IP_DEL_SERVIDOR [llave_ssh]}"
LLAVE="${2:-$HOME/.ssh/vallexpress}"
API="${API_PROD:-https://vallexpress.com}"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"

echo "== Compilando la app web (API: $API)"
cd "$RAIZ/frontend/vallexpress_app"
flutter build web --release --pwa-strategy=none --dart-define=ENTORNO=prod --dart-define=API_PROD="$API"

echo "== Subiendo a $SERVIDOR"
# Se copia DENTRO de la carpeta existente (no se reemplaza la carpeta): Caddy la tiene montada y no vería una nueva
tar -C build/web -czf - . | ssh -i "$LLAVE" "$SERVIDOR" '
  set -e
  cd ~/ValleXpress/deploy
  rm -rf web.nueva && mkdir -p web web.nueva
  tar -xzf - -C web.nueva
  find web -mindepth 1 -delete
  cp -a web.nueva/. web/
  rm -rf web.nueva
  echo "Publicada: $(ls web | wc -l) archivos"
'
echo "== Listo: abre https://app.${API#https://}"
