# 🚀 ValleXpress - Flujo Completo de Pedidos (IMPLEMENTADO)

## 📋 Resumen de lo implementado

Se ha completado el flujo end-to-end para que:
1. **Vendedores** registren productos
2. **Clientes** vean productos de todas las tiendas y hagan pedidos
3. **Vendedores** vean sus pedidos y cambien el estado (pendiente → confirmado → preparando → listo)
4. **Repartidores** vean pedidos listos para entregar y cambien el estado (en_camino → entregado)

---

## 🏗️ Arquitectura del Flujo

### Roles y sus funciones:

```
┌─────────────────────────────────────────────────────────────┐
│                    CLIENTE                                   │
├─────────────────────────────────────────────────────────────┤
│ ✅ Ver productos de todas las tiendas                        │
│ ✅ Agregar productos al carrito (por tienda)                 │
│ ✅ Crear pedidos                                              │
│ ✅ Ver mis pedidos con estados                               │
│ ✅ Cancelar pedidos (si están pendientes)                    │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    VENDEDOR                                  │
├─────────────────────────────────────────────────────────────┤
│ ✅ Crear/Editar/Eliminar productos                          │
│ ✅ Ver mis productos                                         │
│ ✅ Ver mis pedidos (de mis productos)                       │
│ ✅ Cambiar estado: pendiente → confirmado → preparando → listo
│ ✅ Marcar pedido como "listo" para que repartidor lo busque │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    REPARTIDOR                                │
├─────────────────────────────────────────────────────────────┤
│ ✅ Ver pedidos asignados (con estado "listo")               │
│ ✅ Cambiar estado: en_camino → entregado                   │
│ ✅ Incrementar contador de pedidos completados              │
└─────────────────────────────────────────────────────────────┘
```

---

## 🎯 Estados de Pedido

```
Flujo de estados:
┌──────────┐  ┌───────────┐  ┌──────────┐  ┌──────┐  ┌──────────┐  ┌──────────┐
│Pendiente │→ │Confirmado │→ │Preparando│→ │Listo │→ │En camino │→ │Entregado │
└──────────┘  └───────────┘  └──────────┘  └──────┘  └──────────┘  └──────────┘
  (Cliente       (Vendedor     (Vendedor    (Vendedor (Repartidor  (Repartidor
   crea)          confirma)      inicia)     termina)   sale)       termina)

Cancelable:
  - Pendiente ✅
  - Confirmado ✅ (si se permite)
  - Después NO ❌
```

---

## 📱 Pantallas Implementadas

### Cliente
- **ClienteProductosScreen** (cliente_productos_screen.dart)
  - Lista productos agrupados por tienda
  - Carrito con cantidad de productos
  - Botón para hacer pedido
  
- **ClienteMisPedidosScreen** (cliente_mis_pedidos_screen.dart)
  - Lista todos los pedidos del cliente
  - Muestra estado con color
  - Detalle de productos en cada pedido
  - Opción de cancelar si está pendiente

### Vendedor
- **AgregarProductoScreen** (ya existía) - crear productos
- **MisProductosScreen** (ya existía) - listar y editar productos
- **VendedorMisPedidosScreen** (vendedor_mis_pedidos_screen.dart)
  - Lista pedidos de este vendedor
  - Botones dinámicos según estado
  - Cambiar: pendiente → confirmado → preparando → listo

### Repartidor
- **RepartidorPedidosScreen** (mejorada)
  - Lista pedidos con estado "listo"
  - Muestra información del pedido con costos
  - Botones: "En camino" → "Entregado"
  - Incrementa contador de pedidos completados

---

## 🔧 Servicios Implementados

### Frontend Services

#### `pedido_service.dart` (actualizado)
```dart
- crearPedido()           // Cliente: crear pedido
- misPedidos()            // Cliente: obtener mis pedidos
- obtenerPorId()          // Obtener detalles de pedido
- actualizarEstado()      // Vendedor/Repartidor: cambiar estado
- cancelarPedido()        // Cliente: cancelar pedido
```

#### `vendedor_pedidos_service.dart` (NUEVO)
```dart
- misPedidos()            // Vendedor: obtener mis pedidos
- actualizarEstado()      // Vendedor: cambiar estado del pedido
```

#### `repartidor_pedidos_service.dart` (actualizado)
```dart
- obtenerPedidos()        // Repartidor: obtener mis pedidos
- cambiarEstado()         // Repartidor: cambiar estado del pedido
```

### Backend Controllers

#### `pedido.controller.js`
- `crear()` - Crear pedido (con validación de productos y disponibilidad)
- `misPedidos()` - Obtener pedidos del cliente
- `pedidosVendedor()` - Obtener pedidos del vendedor
- `obtenerPorId()` - Obtener detalles de un pedido
- `actualizarEstado()` - Cambiar estado (vendedor o repartidor)
- `cancelar()` - Cancelar pedido (cliente)

#### `repartidor.controller.js`
- `misPedidos()` - Obtener pedidos asignados al repartidor
- `actualizarEstadoPedido()` - Cambiar estado (en_camino, entregado)

---

## 🛣️ Rutas Backend

### Pedidos
```
POST   /api/pedidos                      - Crear pedido (cliente)
GET    /api/pedidos/mis-pedidos          - Mis pedidos (cliente)
GET    /api/pedidos/vendedor/pedidos     - Pedidos del vendedor
GET    /api/pedidos/:id                  - Obtener pedido por ID
PUT    /api/pedidos/:id/estado           - Actualizar estado
PUT    /api/pedidos/:id/cancelar         - Cancelar pedido
```

### Repartidor
```
GET    /api/repartidores/mis-pedidos     - Mis pedidos asignados
PUT    /api/repartidores/pedidos/:id/estado - Cambiar estado del pedido
```

---

## 💡 Cómo Funciona el Flujo

### 1️⃣ CLIENTE - Hacer un pedido

```
1. Cliente va a "Nuevo Pedido"
   ↓
2. Ve productos de todas las tiendas
   ↓
3. Agrega productos al carrito (separados por tienda)
   ↓
4. Clica "Pedir ahora"
   ↓
5. Sistema crea UN PEDIDO POR TIENDA (si hay productos de varias tiendas)
   ↓
6. Estado inicial: "pendiente"
   ↓
7. Cliente ve sus pedidos en "Mis Pedidos"
```

### 2️⃣ VENDEDOR - Procesar pedido

```
1. Vendedor ve sus pedidos en "Mis Pedidos"
   ↓
2. Cuando llega un pedido: estado = "pendiente"
   ↓
3. Vendedor clica "Confirmar" → estado = "confirmado"
   ↓
4. Vendedor clica "Preparando" → estado = "preparando"
   ↓
5. Cuando está listo, clica "Listo" → estado = "listo"
   ↓
6. AHORA el repartidor puede verlo
```

### 3️⃣ REPARTIDOR - Entregar pedido

```
1. Repartidor ve "Pedidos asignados" (estado = "listo")
   ↓
2. Clica "En camino" → estado = "en_camino"
   ↓
3. Cuando entrega, clica "Entregado" → estado = "entregado"
   ↓
4. Se incrementa: pedidosCompletados += 1
```

---

## 🔄 Estados y Transiciones

```json
{
  "pendiente": {
    "quienPuede": "vendedor",
    "siguientes": ["confirmado", "cancelado"]
  },
  "confirmado": {
    "quienPuede": "vendedor",
    "siguientes": ["preparando"]
  },
  "preparando": {
    "quienPuede": "vendedor",
    "siguientes": ["listo"]
  },
  "listo": {
    "quienPuede": "repartidor",
    "siguientes": ["en_camino"]
  },
  "en_camino": {
    "quienPuede": "repartidor",
    "siguientes": ["entregado"]
  },
  "entregado": {
    "quienPuede": "sistema",
    "siguientes": []
  },
  "cancelado": {
    "quienPuede": "cliente",
    "siguientes": []
  }
}
```

---

## 📊 Base de Datos

### Tabla: pedidos
```sql
- id (UUID)
- numero_pedido (STRING, único)
- cliente_id (UUID, FK usuario)
- vendedor_id (UUID, FK vendedor)
- repartidor_id (UUID, FK repartidor, nullable)
- estado (ENUM: pendiente, confirmado, preparando, listo, en_camino, entregado, cancelado)
- subtotal (DECIMAL)
- costo_delivery (DECIMAL)
- total (DECIMAL)
- metodo_pago (STRING)
- pagado (BOOLEAN)
- notas_cliente (TEXT)
- fecha_pedido (DATE)
- fecha_confirmacion (DATE)
- fecha_preparacion (DATE)
- fecha_listo (DATE)
- fecha_recogida (DATE)
- fecha_entrega (DATE)
- created_at / updated_at
```

### Tabla: detalle_pedidos
```sql
- id (UUID)
- pedido_id (UUID, FK pedidos)
- producto_id (UUID, FK productos)
- cantidad (INTEGER)
- precio_unitario (DECIMAL)
- subtotal (DECIMAL)
- notas (TEXT)
```

---

## 🎨 Interfaz de Usuario

### Colores de estado
```
pendiente      🟠 Orange
confirmado     🔵 Blue
preparando     🟡 Amber
listo          🟢 Green
en_camino      🟣 Purple
entregado      🟦 Teal
cancelado      🔴 Red
```

---

## ⚠️ Validaciones Implementadas

### Cliente
- ✅ No puede crear pedido con carrito vacío
- ✅ No puede comprar productos no disponibles
- ✅ No puede cancelar pedido en estado avanzado (solo pendiente/confirmado)

### Vendedor
- ✅ Solo vendedores pueden ver/crear productos
- ✅ Solo vendedores pueden cambiar estado de sus pedidos
- ✅ No puede cambiar estado a estados no permitidos

### Repartidor
- ✅ Solo repartidores pueden cambiar estado en_camino/entregado
- ✅ No puede modificar pedidos de otros repartidores
- ✅ Solo ve pedidos asignados a él

---

## 🚀 Cómo Probar

### 1. Crear Producto (Vendedor)
```
1. Login como vendedor
2. Home → "Agregar Producto"
3. Llenar datos (nombre, precio, categoría, stock)
4. Guardar
```

### 2. Hacer Pedido (Cliente)
```
1. Login como cliente
2. Home → "Nuevo Pedido"
3. Ver productos agrupados por tienda
4. Agregar productos al carrito
5. Clica "Pedir ahora"
6. Confirmación: "¡Pedidos creados exitosamente!"
```

### 3. Procesar Pedido (Vendedor)
```
1. Home → "Mis Pedidos"
2. Expande pedido en estado "pendiente"
3. Clica "Confirmar"
4. Clica "Preparando"
5. Clica "Listo" (ahora repartidor puede verlo)
```

### 4. Entregar Pedido (Repartidor)
```
1. Home → "Pedidos asignados"
2. Ve pedidos con estado "listo"
3. Clica "En camino"
4. Clica "Entregado"
5. Se incrementa contador de pedidos completados
```

---

## 📝 Notas Importantes

1. **Carrito por tienda**: El cliente puede agregar productos de diferentes tiendas, y se crean pedidos separados (1 por tienda)

2. **Validación de stock**: El backend valida que los productos sigan siendo disponibles al momento de crear el pedido

3. **Transacciones DB**: Se usa transacción al crear pedido para garantizar integridad de datos

4. **Socket.IO**: Se emiten eventos en tiempo real cuando hay cambios de estado (implementado en backend)

5. **Estados automáticos**: Las fechas se registran automáticamente:
   - fecha_pedido: cuando se crea
   - fecha_confirmacion: cuando vendedor confirma
   - fecha_preparacion: cuando vendedor comienza preparación
   - fecha_listo: cuando vendedor marca como listo
   - fecha_recogida: cuando repartidor va en camino
   - fecha_entrega: cuando repartidor entrega

---

## ✅ Checklist de Funcionalidades

- [x] Cliente puede ver productos de todas las tiendas
- [x] Cliente puede hacer pedidos (agregar al carrito)
- [x] Cliente puede ver sus pedidos
- [x] Cliente puede cancelar pedidos pendientes
- [x] Vendedor puede crear productos
- [x] Vendedor puede editar productos
- [x] Vendedor puede ver sus productos
- [x] Vendedor puede ver sus pedidos
- [x] Vendedor puede cambiar estado de pedidos
- [x] Repartidor puede ver pedidos asignados
- [x] Repartidor puede cambiar estado de pedidos
- [x] Backend valida roles y permisos
- [x] Base de datos guarda todos los datos correctamente
- [x] Frontend no tiene errores de compilación

---

**Fecha de implementación:** 22/01/2026  
**Estado:** ✅ COMPLETADO
