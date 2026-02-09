# ValleXpress 2.0.2 🚀

Sistema completo de delivery con arquitectura cliente-servidor, desarrollado con Flutter (frontend) y Node.js/Express (backend).

## 📋 Descripción del Proyecto

ValleXpress es una plataforma de delivery que conecta a **clientes**, **vendedores** y **repartidores** en un ecosistema completo de pedidos y entregas. El sistema permite a los vendedores gestionar sus productos, a los clientes hacer pedidos desde múltiples tiendas, y a los repartidores gestionar las entregas con seguimiento en tiempo real.

### 🎯 Características Principales

- **👥 Multi-rol**: Sistema de autenticación con 3 tipos de usuarios (cliente, vendedor, repartidor)
- **📱 App Móvil**: Interfaz Flutter nativa para Android/iOS/Web
- **🛒 E-commerce**: Carrito de compras con productos de múltiples vendedores
- **📍 Geolocalización**: Mapas interactivos con OpenStreetMap
- **🔔 Notificaciones Push**: Firebase Cloud Messaging (FCM)
- **📡 Tiempo Real**: Socket.IO para actualizaciones en vivo
- **💳 Pagos**: Sistema de pagos integrado
- **📊 Dashboard**: Paneles diferenciados por rol con colores temáticos

## 🏗️ Arquitectura

### Backend (Node.js + Express)
- **Base de Datos**: PostgreSQL con Sequelize ORM
- **Autenticación**: JWT con bcryptjs
- **WebSockets**: Socket.IO para comunicación en tiempo real
- **Notificaciones**: Firebase Admin SDK
- **Archivos**: Multer para uploads de imágenes
- **Rate Limiting**: Protección contra abuso
- **CORS**: Configurado para desarrollo y producción

### Frontend (Flutter)
- **UI Framework**: Material Design 3
- **Estado**: Provider para gestión de estado
- **HTTP**: Cliente HTTP para APIs REST
- **WebSockets**: Socket.IO client para tiempo real
- **Mapas**: Flutter Map con OpenStreetMap
- **Notificaciones**: Firebase Messaging
- **Almacenamiento**: Shared Preferences para persistencia local

## 🚀 Inicio Rápido

### Prerrequisitos
- **Flutter**: SDK 3.8.1+
- **Node.js**: 16+
- **PostgreSQL**: 15+
- **Docker**: Para base de datos (opcional)

### 1. Clonar el Repositorio
```bash
git clone <url-del-repositorio>
cd ValleXpress2.0.2
```

### 2. Configurar Base de Datos
```bash
# Con Docker (recomendado)
docker-compose up -d

# O instalar PostgreSQL localmente
# Crear base de datos: vallexpress_db
# Usuario: vallexpress_user
# Contraseña: 2003
# Puerto: 5433
```

### 3. Configurar Backend
```bash
cd backend
npm install
cp .env.example .env  # Configurar variables de entorno
npm run dev
```

### 4. Configurar Frontend
```bash
cd frontend/vallexpress_app
flutter pub get
flutter run
```

## 📱 Funcionalidades por Rol

### 👤 Cliente
- ✅ Registro e inicio de sesión
- ✅ Explorar productos de todas las tiendas
- ✅ Carrito de compras inteligente
- ✅ Realizar pedidos múltiples
- ✅ Seguimiento de pedidos en tiempo real
- ✅ Historial de pedidos
- ✅ Gestión de direcciones de entrega
- ✅ Cancelación de pedidos pendientes

### 🏪 Vendedor
- ✅ Registro e inicio de sesión
- ✅ Gestión completa de productos (CRUD)
- ✅ Configuración de ubicación GPS
- ✅ Gestión de pedidos entrantes
- ✅ Actualización de estados de pedido
- ✅ Dashboard con estadísticas
- ✅ Indicador de estado online/offline

### 🚴 Repartidor
- ✅ Registro e inicio de sesión
- ✅ Visualización de pedidos asignados
- ✅ Seguimiento GPS en tiempo real
- ✅ Actualización de estados de entrega
- ✅ Contador de pedidos completados
- ✅ Rutas optimizadas en mapa

## 🎨 Diseño y UX

### Tema por Rol
- **Cliente**: Tema verde (#4CAF50) - Confianza y crecimiento
- **Vendedor**: Tema naranja (#FF9800) - Energía y vitalidad
- **Repartidor**: Tema azul (#2196F3) - Confianza y profesionalismo

### Características Visuales
- Gradientes dinámicos en headers
- Efectos de sombra y glow
- Iconos temáticos por funcionalidad
- Animaciones suaves de transición
- Badges de estado con colores vibrantes

## 📊 Estados de Pedido

```
Flujo Completo:
Pendiente → Confirmado → Preparando → Listo → En Camino → Entregado
     ↓
Cancelado (solo en estados iniciales)
```

## 🔧 Tecnologías Utilizadas

### Backend
- **Runtime**: Node.js
- **Framework**: Express.js
- **Base de Datos**: PostgreSQL
- **ORM**: Sequelize
- **Autenticación**: JWT + bcryptjs
- **WebSockets**: Socket.IO
- **Notificaciones**: Firebase Admin SDK
- **Uploads**: Multer
- **Validación**: express-validator
- **Rate Limiting**: express-rate-limit
- **CORS**: cors
- **Compresión**: compression
- **Logging**: morgan

### Frontend
- **Framework**: Flutter
- **Lenguaje**: Dart
- **UI**: Material Design 3
- **Estado**: Provider
- **HTTP**: http package
- **WebSockets**: socket_io_client
- **Mapas**: flutter_map + latlong2
- **Notificaciones**: firebase_messaging
- **Almacenamiento**: shared_preferences
- **Geolocalización**: geolocator
- **PDF Viewer**: syncfusion_flutter_pdfviewer
- **Fuentes**: google_fonts

## 📁 Estructura del Proyecto

```
ValleXpress2.0.2/
├── backend/                          # API REST + WebSockets
│   ├── src/
│   │   ├── config/                   # Configuración BD
│   │   ├── controllers/              # Lógica de negocio
│   │   ├── middlewares/              # Middlewares personalizados
│   │   ├── models/                   # Modelos Sequelize
│   │   ├── routes/                   # Definición de rutas
│   │   ├── services/                 # Servicios externos
│   │   ├── sockets/                  # WebSockets handlers
│   │   └── server.js                 # Punto de entrada
│   ├── uploads/                      # Archivos subidos
│   └── package.json
├── frontend/
│   └── vallexpress_app/              # App Flutter
│       ├── lib/
│       │   ├── config/               # Constantes y temas
│       │   ├── models/               # Modelos de datos
│       │   ├── providers/            # Gestión de estado
│       │   ├── screens/              # Pantallas por rol
│       │   ├── services/             # Servicios API
│       │   ├── widgets/              # Componentes reutilizables
│       │   └── main.dart             # Punto de entrada
│       ├── android/                  # Config Android
│       ├── ios/                      # Config iOS
│       └── pubspec.yaml
├── database/                         # Scripts SQL
├── docker-compose.yml                # Orquestación Docker
└── README.md
```

## 🔐 Variables de Entorno (Backend)

```env
# Base de Datos
DB_HOST=localhost
DB_PORT=5433
DB_NAME=vallexpress_db
DB_USER=vallexpress_user
DB_PASSWORD=2003

# JWT
JWT_SECRET=tu_jwt_secret_aqui

# Firebase (opcional)
FIREBASE_SERVICE_ACCOUNT_PATH=./vallexpress-delivery-firebase-adminsdk-fbsvc-625e5b0964.json

# Entorno
NODE_ENV=development

# Puerto
PORT=3000
```

## 📡 API Endpoints Principales

### Autenticación
- `POST /api/auth/register` - Registro de usuarios
- `POST /api/auth/login` - Inicio de sesión
- `POST /api/auth/forgot-password` - Recuperar contraseña

### Productos
- `GET /api/productos` - Listar productos
- `POST /api/productos` - Crear producto (vendedor)
- `PUT /api/productos/:id` - Actualizar producto
- `DELETE /api/productos/:id` - Eliminar producto

### Pedidos
- `POST /api/pedidos` - Crear pedido (cliente)
- `GET /api/pedidos/mis-pedidos` - Mis pedidos (cliente)
- `GET /api/pedidos/vendedor/pedidos` - Pedidos del vendedor
- `PUT /api/pedidos/:id/estado` - Cambiar estado

### Notificaciones
- `GET /api/notificaciones` - Obtener notificaciones
- `PUT /api/notificaciones/:id/leido` - Marcar como leída

## 🧪 Testing

### Backend
```bash
cd backend
npm test
```

### Frontend
```bash
cd frontend/vallexpress_app
flutter test
```

## 🚀 Despliegue

### Backend
```bash
cd backend
npm run build
npm start
```

### Frontend
```bash
cd frontend/vallexpress_app
flutter build apk  # Para Android
flutter build ios  # Para iOS
flutter build web  # Para Web
```

## 📈 Estado del Proyecto

### ✅ Completado
- [x] Sistema de autenticación multi-rol
- [x] Gestión completa de productos
- [x] Flujo end-to-end de pedidos
- [x] Seguimiento GPS en tiempo real
- [x] Notificaciones push con FCM
- [x] Interfaz diferenciada por rol
- [x] WebSockets para actualizaciones en vivo
- [x] Base de datos PostgreSQL completa
- [x] Docker para desarrollo

### 🔄 En Progreso
- [ ] Validación de email en registro
- [ ] Sistema de recuperación de contraseña
- [ ] Optimizaciones de rendimiento

### 📋 Pendiente
- [ ] Tests automatizados completos
- [ ] Documentación API completa
- [ ] CI/CD pipeline

## 🤝 Contribución

1. Fork el proyecto
2. Crea una rama para tu feature (`git checkout -b feature/AmazingFeature`)
3. Commit tus cambios (`git commit -m 'Add some AmazingFeature'`)
4. Push a la rama (`git push origin feature/AmazingFeature`)
5. Abre un Pull Request

## 📝 Licencia

Este proyecto está bajo la Licencia MIT - ver el archivo [LICENSE](LICENSE) para más detalles.

## 👥 Autor

**Tu Nombre** - *Desarrollo Inicial* - [Tu GitHub](https://github.com/tu-usuario)

## 🙏 Agradecimientos

- Flutter por el framework móvil
- Node.js por el runtime backend
- PostgreSQL por la base de datos
- Socket.IO por la comunicación en tiempo real
- Firebase por las notificaciones push

---

**Versión**: 2.0.2
**Última actualización**: Enero 2025
