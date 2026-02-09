# 📱 GuíA de Implementación - Frontend ValleXpress

## ✅ Estado Actual

Tu proyecto Frontend ya tiene:
- ✅ **3 Servicios nuevos** (VendedorService, RepartidorService, ClientService)
- ✅ **Mock Data Dart** (models/mock_data.dart)
- ✅ **Pantallas de Perfil** actualizadas (Cliente, Vendedor, Repartidor)
- ✅ **Servicios de API** listos para conectar con el backend

---

## 🎯 Pantallas y Sus Servicios

### 1️⃣ **CLIENTE** 
```
Pantalla: cliente_profile_screen.dart
Servicios usados:
  ✓ ProfileService.obtenerPerfil()
  ✓ ProfileService.actualizarPerfil()
  ✓ ProfileService.actualizarFotoPerfilBase64()
  
Funcionalidades:
  - Ver mi perfil (nombre, email, teléfono)
  - Editar datos personales
  - Cambiar foto de perfil
  - Ver mis pedidos (ClientService.obtenerMisPedidos())
  - Crear pedidos (ClientService.crearPedido())
  - Calificar pedidos (ClientService.calificarPedido())
```

### 2️⃣ **VENDEDOR**
```
Pantalla: vendedor_profile_screen.dart
Servicios usados:
  ✓ VendedorService.obtenerPerfilVendedor()
  ✓ VendedorService.actualizarPerfilVendedor()
  ✓ VendedorService.obtenerMisProductos()
  ✓ VendedorService.crearProducto()
  ✓ VendedorService.actualizarProducto()
  ✓ VendedorService.cambiarDisponibilidad()
  ✓ VendedorService.eliminarProducto()

Funcionalidades:
  - Ver datos del negocio (nombre, horarios, categoría)
  - Editar perfil del negocio
  - Gestionar productos (crear, editar, eliminar, cambiar disponibilidad)
  - Ver productos activos
```

### 3️⃣ **REPARTIDOR**
```
Pantalla: repartidor_profile_screen.dart
Servicios usados:
  ✓ RepartidorService.obtenerPerfilRepartidor()
  ✓ RepartidorService.actualizarPerfilRepartidor()
  ✓ RepartidorService.obtenerPedidosDisponibles()
  ✓ RepartidorPedidosService.aceptarPedido(pedidoId, costoDelivery)
  ✓ RepartidorService.actualizarEstadoEntrega()
  ✓ RepartidorService.obtenerEntregasActivas()
  ✓ RepartidorService.cambiarEstado()

Funcionalidades:
  - Ver mis datos (vehículo, placa, estado)
  - Editar perfil
  - Ver pedidos disponibles
  - Aceptar pedidos
  - Actualizar estado de entregas
  - Ver entregas activas
  - Cambiar disponibilidad
```

---

## 📁 Estructura de Archivos

```
lib/
├── services/
│   ├── auth_service.dart              (Login/Registro)
│   ├── auth_storage.dart              (Gestión de token)
│   ├── profile_service.dart           (Perfil cliente)
│   ├── vendedor_service.dart          (✨ NUEVO)
│   ├── repartidor_service.dart        (✨ NUEVO)
│   ├── client_service.dart            (✨ NUEVO)
│   ├── product_service.dart           (Productos)
│   ├── pedido_service.dart            (Pedidos)
│   └── password_reset_service.dart
│
├── models/
│   └── mock_data.dart                 (✨ NUEVO)
│
└── screens/
    └── profile/
        ├── cliente_profile_screen.dart
        ├── vendedor_profile_screen.dart
        ├── repartidor_profile_screen.dart
        ├── profile_router.dart
        └── settings_screen.dart
```

---

## 🔌 Cómo Conectar Pantallas con Servicios

### Ejemplo: Vendedor actualizando su perfil

```dart
// En vendedor_profile_screen.dart

Future<void> _cargarPerfil() async {
  try {
    // 1. Llamar al servicio
    final datos = await VendedorService.obtenerPerfilVendedor();
    
    // 2. Actualizar UI
    if (!mounted) return;
    setState(() {
      _vendedorData = datos;
      // Llenar controllers con los datos
      _nombreNegocioController.text = datos['nombreNegocio'] ?? '';
    });
  } catch (e) {
    _mostrarError('Error: $e');
  }
}

Future<void> _guardarCambios() async {
  try {
    _mostrarCargando('Guardando...');
    
    // 1. Llamar al servicio con datos
    await VendedorService.actualizarPerfilVendedor(
      nombreNegocio: _nombreNegocioController.text,
      categoria: _categoriaController.text,
      // ... otros campos
    );
    
    // 2. Actualizar estado local
    setState(() => _isEditing = false);
    _mostrarExito('¡Actualizado!');
  } catch (e) {
    _mostrarError('Error: $e');
  }
}
```

---

## 🧪 Cómo Usar Mock Data en Desarrollo

### Opción 1: Mostrar datos mock directamente

```dart
import 'package:vallexpress_app/models/mock_data.dart';

// En cualquier pantalla
class MyScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Usar datos mock
    final usuario = MockData.usuarioClienteMock;
    final productos = MockData.productosMock;
    
    return Scaffold(
      body: Column(
        children: [
          Text('Usuario: ${usuario['nombre']}'),
          ListView.builder(
            itemCount: productos.length,
            itemBuilder: (context, index) {
              return ListTile(
                title: Text(productos[index]['nombre']),
              );
            },
          ),
        ],
      ),
    );
  }
}
```

### Opción 2: Usar servicios que retornan mock data en caso de error

```dart
// Los servicios ya lo hacen automáticamente:
// Si hay error de conexión, retornan mock data

final productos = await VendedorService.obtenerMisProductos();
// Si falla, retorna MockData.productosMock
```

---

## 📡 Variables de Entorno

**Archivo:** `lib/config/constants.dart`

```dart
class AppConstants {
  // CAMBIAR SEGÚN TU ENTORNO
  static const String baseUrl = 'http://localhost:3000/api';
  // Para emulador Android: 'http://172.17.240.1:3000/api'
  // Para dispositivo físico: 'http://TU_IP:3000/api'
}
```

---

## 🚀 Pasos para Que Todo Funcione

### 1. Verificar que el Backend esté corriendo
```bash
cd backend
npm start
# El backend debe estar en http://localhost:3000
```

### 2. Verificar que Flutter pueda conectarse
```bash
flutter pub get
flutter run
```

### 3. Si hay errores de conexión:
- Cambiar `localhost` a tu IP en `AppConstants.baseUrl`
- Verificar que el backend tiene CORS habilitado
- Revisar los logs de la consola en Flutter

### 4. Usar Mock Data para testing
- Si el backend no está disponible, los servicios usan mock data automáticamente
- Perfecto para desarrollar pantallas sin conexión

---

## 🛠️ Errores Comunes y Soluciones

### Error: "Token no encontrado"
```dart
// El token no se guardó al hacer login
// Solución: Verificar auth_service.dart guarda el token
await AuthService.login(email, password);
// Debe guardar el token en SharedPreferences
```

### Error: "Connection refused"
```dart
// El backend no está corriendo o está en otro puerto
// Solución: 
// 1. Iniciar backend: npm start
// 2. Verificar puerto en backend/src/server.js
// 3. Actualizar AppConstants.baseUrl
```

### Error: "CORS error"
```dart
// El backend no acepta solicitudes desde el frontend
// Solución: En backend, verificar CORS en src/server.js
app.use(cors()); // Debe estar habilitado
```

---

## 📊 Flujo de Datos

```
PANTALLA (UI)
    ↓
SERVICIO (VendedorService, etc)
    ↓
API Backend ← Token
    ↓ (si falla)
MOCK DATA (si hay error)
    ↓
PANTALLA (actualiza UI)
```

---

## ✨ Siguientes Pasos

- [ ] Conectar pantalla de productos del vendedor
- [ ] Conectar vista de pedidos del cliente
- [ ] Implementar búsqueda de vendedores
- [ ] Agregar filtros de productos
- [ ] Implementar pago (si lo requieres)
- [ ] Integrar notificaciones en tiempo real (Socket.IO)

---

## 📞 Contacto / Preguntas

Si algo no funciona:
1. Revisar los logs en la consola
2. Verificar que el backend esté corriendo
3. Usar Mock Data para testing
4. Revisar la estructura del JSON que retorna el backend

¡Listo para desarrollar! 🎉
