// dotenv debe cargarse antes que cualquier otro módulo que lea process.env
require('dotenv').config();

const jwt = require('jsonwebtoken');

// En producción no se arranca con una clave de firma débil: cualquiera podría fabricar sesiones válidas
if (process.env.NODE_ENV === 'production' && String(process.env.JWT_SECRET || '').length < 32) {
  console.error('❌ JWT_SECRET debe tener al menos 32 caracteres en producción. Genera uno con:');
  console.error("   node -e \"console.log(require('crypto').randomBytes(64).toString('hex'))\"");
  process.exit(1);
}

// Inicializar Firebase Admin SDK
const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

try {
  let serviceAccountPath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
  
  if (serviceAccountPath) {
    // Normalizar path para Windows (reemplazar barras invertidas)
    serviceAccountPath = serviceAccountPath.replace(/\\/g, '/');
    // La ruta del servidor (/opt/...) no existe en la PC de desarrollo: se busca el mismo archivo en la carpeta del backend
    if (!fs.existsSync(serviceAccountPath)) {
      const local = path.join(__dirname, '..', path.basename(serviceAccountPath));
      if (fs.existsSync(local)) serviceAccountPath = local;
    }

    // Verificar si el archivo existe
    if (fs.existsSync(serviceAccountPath)) {
      // Leer y parsear el archivo JSON manualmente
      const serviceAccountContent = fs.readFileSync(serviceAccountPath, 'utf8');
      const serviceAccount = JSON.parse(serviceAccountContent);

      
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
      });
      console.log('✅ Firebase Admin SDK inicializado correctamente');
    } else {
      console.log('⚠️  Archivo de credenciales de Firebase no encontrado en:', serviceAccountPath);
    }
  } else {
    console.log('⚠️  FIREBASE_SERVICE_ACCOUNT_PATH no configurado. Las notificaciones push no funcionarán.');
  }
} catch (error) {
  console.error('❌ Error al inicializar Firebase Admin:', error.message);
}


const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const compression = require('compression');
const { createServer } = require('http');
const { Server } = require('socket.io');


// Importar rutas
// La base de datos se está reconstruyendo por bloques (database/migraciones). Solo se montan los módulos que ya
// usan las tablas nuevas; el resto vuelve a activarse al migrarlo.
const authRoutes = require('./modules/auth/auth.routes');
const usuarioRoutes = require('./modules/auth/usuario.routes');
const direccionesRoutes = require('./modules/direcciones/direcciones.routes');
const telefonosRoutes = require('./modules/telefonos/telefonos.routes');
const negociosRoutes = require('./modules/negocios/negocios.routes');
const miNegocioRoutes = require('./modules/negocios/mi-negocio.routes');
const pedidosRoutes = require('./modules/pedidos/pedido.routes');
const notificacionesRoutes = require('./modules/notificaciones/notificacion.routes');
const repartidorRoutes = require('./modules/repartidores/repartidor.routes');
const adminRoutes = require('./modules/admin/admin.routes');
const legalRoutes = require('./modules/legal/legal.routes');
const legalWeb = require('./modules/legal/legal.web');
const registrarUbicacionSocket = require('./modules/repartidores/ubicacion.socket');




// Importar base de datos y modelos
const { sequelize, Usuario } = require('./index');

// Piezas compartidas (ver src/shared)
const solicitudId = require('./shared/middlewares/solicitudId');
const limite = require('./shared/middlewares/limitadores');
const { notFoundHandler, errorHandler } = require('./shared/middlewares/errorHandler');




// Crear aplicación Express
const app = express();
const httpServer = createServer(app);

// Configurar Socket.IO para tiempo real
const io = new Server(httpServer, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST', 'PUT', 'DELETE']
  },
  // Evitar desconexiones por inactividad y permitir reanudación de sesión
  pingTimeout: 60000,            // 60s para considerar timeout del cliente
  pingInterval: 25000,           // 25s entre pings del servidor al cliente
  connectionStateRecovery: {
    maxDisconnectionDuration: 2 * 60 * 1000, // 2 minutos para reanudar
    skipMiddlewares: true
  }
});

// Middleware para exponer io en req.io (para notificaciones en controllers)
app.use((req, res, next) => {
  req.io = io;
  next();
});

// Detrás de un proxy (Caddy/Nginx con HTTPS) la IP real del usuario viene en X-Forwarded-For. Sin esto todas
// las peticiones parecerían de la IP del proxy y el limitador bloquearía a TODOS a la vez. TRUST_PROXY=1 = un proxy.
if (process.env.TRUST_PROXY) app.set('trust proxy', /^\d+$/.test(process.env.TRUST_PROXY) ? Number(process.env.TRUST_PROXY) : process.env.TRUST_PROXY);

// Middlewares globales
app.use(solicitudId);          // identificador por petición (une los logs de una misma petición)

app.use(helmet());
app.use(cors());
app.use(compression());
app.use(morgan(process.env.NODE_ENV === 'production' ? 'combined' : 'dev'));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Middleware para Socket.IO
// =======================
// Socket.IO Auth Middleware
// =======================
io.use(async (socket, next) => {
  try {
    // 1) token por handshake.auth.token (recomendado)
    // 2) o por header Authorization: Bearer xxx
    const token =
      socket.handshake?.auth?.token ||
      (socket.handshake?.headers?.authorization?.startsWith('Bearer ')
        ? socket.handshake.headers.authorization.split(' ')[1]
        : null);

    if (!token) return next(new Error('NO_TOKEN'));

    const decoded = jwt.verify(token, process.env.JWT_SECRET);

    // Igual que en HTTP: la cuenta debe existir y seguir activa (un usuario desactivado no conserva su conexión)
    const cuenta = await Usuario.findByPk(decoded.id);
    if (!cuenta || !cuenta.activo) return next(new Error('INVALID_TOKEN'));

      // Guarda el usuario en el socket (equivalente a req.usuario)
      socket.usuario = decoded;
      // Debug: mostrar tipoUsuario e id para ayudar a diagnosticar problemas de roles
      try {
        if (process.env.NODE_ENV === 'development') {
          console.log('🔐 Socket auth:', {
            id: socket.usuario?.id,
            tipoUsuario: socket.usuario?.tipoUsuario,
          });
        }
      } catch (_) {}
    // decoded debe traer al menos: { id, tipoUsuario } según tu auth

    return next();
  } catch (err) {
    return next(new Error('INVALID_TOKEN'));
  }
});

// Servir archivos estáticos
// Las imágenes se llaman como su hash (nunca cambian): el navegador/app puede guardarlas en caché una semana
app.use('/uploads', express.static(process.env.UPLOADS_DIR || path.join(__dirname, '../uploads'), { maxAge: '7d', immutable: true }));


// Límite general de peticiones por IP (cada ruta sensible tiene además el suyo, ver auth.routes.js)
app.use('/api', limite.general);

// Rutas de la API
app.use('/api/auth', authRoutes);
app.use('/api/usuarios', usuarioRoutes);
app.use('/api/direcciones', direccionesRoutes);
app.use('/api/telefonos', telefonosRoutes);
app.use('/api/negocios', negociosRoutes);
app.use('/api/mi-negocio', miNegocioRoutes);
app.use('/api/pedidos', pedidosRoutes);
app.use('/api/notificaciones', notificacionesRoutes);
app.use('/api/repartidor', repartidorRoutes);
app.use('/api/admin', adminRoutes);
app.use('/api/legal', legalRoutes);

// Páginas web públicas: términos, privacidad y cómo eliminar la cuenta (las URL que pide Google Play)
app.use('/legal', limite.general, legalWeb);



// Ruta de prueba
app.get('/api/health', (req, res) => {
  res.json({
    status: 'OK',
    message: 'ValleXpress Backend funcionando correctamente',
    timestamp: new Date().toISOString()
  });
});

// Rutas no encontradas y manejo global de errores (ver shared/middlewares/errorHandler.js).
// Los errores 5xx se guardan en la tabla LOGERRORES.
app.use(notFoundHandler);
app.use(errorHandler);

// Cambios de estado de un pedido: el servidor emite 'pedido:actualizado' y 'notificacion' a la sala "user:<usuario>"
// de cada participante. La ubicación del repartidor llega por 'repartidor:ubicacion' y se reenvía como
// 'pedido:ubicacion' solo al cliente y al negocio de su entrega en curso (modules/repartidores/ubicacion.socket.js).



io.on('connection', (socket) => {
  console.log(
    '✅ Cliente conectado:',
    socket.id,
    socket.usuario?.tipoUsuario,
    socket.usuario?.id
  );

  // Unir socket a sala por usuario para notificaciones directas
  try {
    const uid = socket.usuario?.id;
    if (uid) {
      socket.join(`user:${uid}`);
      // Además, unir por rol: los repartidores reciben los pedidos libres y el administrador ve todos los cambios
      if (['repartidor', 'administrador'].includes(socket.usuario?.tipoUsuario)) {
        socket.join(`role:${socket.usuario.tipoUsuario}`);
      }
    }
  } catch (_) {}

  registrarUbicacionSocket(io, socket);

  socket.on('disconnect', () => {
    console.log('❌ Cliente desconectado:', socket.id);
  });
});



// Iniciar servidor
const PORT = process.env.PORT || 3000;



async function startServer() {
  try {
    // Verificar conexión a la base de datos
    await sequelize.authenticate();
    console.log('Conexión a PostgreSQL establecida');

    // El esquema de la BD se gestiona SOLO con database/migraciones/*.sql. NO usar sequelize.sync().



    // Iniciar servidor
    // Vigilante de vencimientos: cancela los pedidos que quedan varados (sin repartidor o sin respuesta del negocio)
    require('./modules/pedidos/vencimiento.service').iniciar(io);

    httpServer.listen(PORT, () => {
      console.log('========================================');
      console.log('ValleXpress Backend');
      console.log('========================================');
      console.log(`Servidor: http://localhost:${PORT}`);
      console.log(`API: http://localhost:${PORT}/api`);
      console.log(`Base de datos: PostgreSQL`);
      console.log(`Entorno: ${process.env.NODE_ENV}`);
      console.log('========================================');
    });
  } catch (error) {
    console.error('❌ Error al iniciar servidor:', error);
    process.exit(1);
  }
}

startServer();

module.exports = { app, io };
