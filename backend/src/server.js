const Repartidor = require('./models/Repartidor');

const jwt = require('jsonwebtoken');
const Pedido = require('./models/Pedido'); // ajusta la ruta si es diferente

require('dotenv').config();

// Inicializar Firebase Admin SDK
const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

try {
  let serviceAccountPath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
  
  if (serviceAccountPath) {
    // Normalizar path para Windows (reemplazar barras invertidas)
    serviceAccountPath = serviceAccountPath.replace(/\\/g, '/');
    
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
const authRoutes = require('./routes/auth.routes');
const direccionesRoutes = require('./routes/direcciones.routes');
const vendedorRoutes = require('./routes/vendedor.routes');
const productoRoutes = require('./routes/producto.routes');
const pedidoRoutes = require('./routes/pedido.routes');
const repartidorRoutes = require('./routes/repartidor.routes');
const notificacionRoutes = require('./routes/notificacion.routes');
// const usuarioRoutes = require('./routes/usuarios.routes'); // Eliminado, unificado en auth.routes


// Importar base de datos
const { sequelize } = require('./config/database');
require('./models'); 

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

// Middlewares globales

app.use(helmet());
app.use(cors());
app.use(compression());
app.use(morgan('dev'));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Middleware para Socket.IO
// =======================
// Socket.IO Auth Middleware
// =======================
io.use((socket, next) => {
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
app.use('/uploads', express.static(path.join(__dirname, '../uploads')));


// Rutas de la API
app.use('/api/auth', authRoutes);
app.use('/api/direcciones', direccionesRoutes);
app.use('/api/vendedores', vendedorRoutes);
app.use('/api/productos', productoRoutes);
app.use('/api/pedidos', pedidoRoutes);
app.use('/api/repartidores', repartidorRoutes);
app.use('/api/notificaciones', notificacionRoutes);
// app.use('/api/usuarios', usuarioRoutes); // Eliminado, unificado en auth.routes


// Ruta de prueba
app.get('/api/health', (req, res) => {
  res.json({
    status: 'OK',
    message: 'ValleXpress Backend funcionando correctamente',
    timestamp: new Date().toISOString()
  });
});

// Manejo de rutas no encontradas
app.use('*', (req, res) => {
  res.status(404).json({
    error: 'Ruta no encontrada',
    path: req.originalUrl
  });
});

// Manejo global de errores
app.use((err, req, res, next) => {
  console.error('Error:', err);

  res.status(err.status || 500).json({
    error: err.message || 'Error interno del servidor',
    ...(process.env.NODE_ENV === 'development' && { stack: err.stack })
  });
});

// Nota: la lógica de autorización y el cache de ubicaciones
// se manejan dentro de `src/sockets/pedidos.socket.js`.
// Se eliminaron funciones/variables duplicadas para evitar confusión.

const registerPedidosSocket = require('./sockets/pedidos.socket');

io.on('connection', (socket) => {
  console.log(
    '✅ Cliente conectado:',
    socket.id,
    socket.usuario?.tipoUsuario,
    socket.usuario?.id
  );

  registerPedidosSocket(io, socket);

  // Unir socket a sala por usuario para notificaciones directas
  try {
    const uid = socket.usuario?.id;
    if (uid) {
      socket.join(`user:${uid}`);
      // Además, unir por rol para poder emitir a todos los repartidores
      if (socket.usuario?.tipoUsuario === 'repartidor') {
        socket.join('role:repartidor');
      }
    }
  } catch (_) {}

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
    console.log('✅ Conexión a PostgreSQL establecida');

    // Sincronizar modelos (solo en desarrollo)
    if (process.env.NODE_ENV === 'development') {
      await sequelize.sync({ alter: false });
      console.log('✅ Modelos sincronizados');
    }



    // Iniciar servidor
    httpServer.listen(PORT, () => {
      console.log('========================================');
      console.log('🚀 ValleXpress Backend');
      console.log('========================================');
      console.log(`📡 Servidor: http://localhost:${PORT}`);
      console.log(`🔗 API: http://localhost:${PORT}/api`);
      console.log(`💾 Base de datos: PostgreSQL`);
      console.log(`📊 Entorno: ${process.env.NODE_ENV}`);
      console.log('========================================');
    });
  } catch (error) {
    console.error('❌ Error al iniciar servidor:', error);
    process.exit(1);
  }
}

startServer();

module.exports = { app, io };
