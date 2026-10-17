# Imagen de producción del backend de ValleXpress
#   docker build -t vallexpress-backend ./backend
FROM node:22-alpine

ENV NODE_ENV=production
WORKDIR /app

# Dependencias primero (se reutiliza la capa mientras package*.json no cambie); sin las de desarrollo
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY src ./src
COPY scripts ./scripts
COPY legal ./legal

# Imágenes subidas: van a un volumen (no se pierden al actualizar la imagen). Corre como usuario sin privilegios.
RUN mkdir -p /app/uploads && chown -R node:node /app/uploads
USER node

EXPOSE 3000
# Docker reinicia el contenedor si deja de responder (además de "restart: always" en el compose)
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3000/api/health >/dev/null 2>&1 || exit 1

CMD ["node", "src/server.js"]
