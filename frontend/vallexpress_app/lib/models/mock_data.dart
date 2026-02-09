/// Mock Data para desarrollo y testing de ValleXpress
/// Contiene datos simulados para usuarios, productos, pedidos y repartidores
library;

class MockData {
  // ===================== USUARIOS MOCK =====================
  static const Map<String, dynamic> usuarioClienteMock = {
    'id': 1,
    'nombre': 'Juan',
    'apellido': 'García',
    'email': 'juan.garcia@ejemplo.com',
    'telefono': '0987654321',
    'cedula': '1234567890',
    'tipoUsuario': 'cliente',
    'activo': true,
    'verificado': true,
    'fotoPerfil': '',
    'direccion': 'Calle Principal 123, Valle del Cauca',
    'ciudad': 'Palmira',
    'departamento': 'Valle',
    'codigoPostal': '76001',
    'createdAt': '2025-01-15T10:30:00Z',
  };

  static const Map<String, dynamic> usuarioVendedorMock = {
    'id': 2,
    'nombre': 'Carlos',
    'apellido': 'López',
    'email': 'carlos.lopez@ejemplo.com',
    'telefono': '0991234567',
    'cedula': '1234567891',
    'tipoUsuario': 'vendedor',
    'activo': true,
    'verificado': true,
    'fotoPerfil': '',
    'createdAt': '2025-01-10T08:00:00Z',
  };

  static const Map<String, dynamic> usuarioRepartidorMock = {
    'id': 3,
    'nombre': 'Miguel',
    'apellido': 'Rodríguez',
    'email': 'miguel.rodriguez@ejemplo.com',
    'telefono': '0985432109',
    'cedula': '1234567892',
    'tipoUsuario': 'repartidor',
    'activo': true,
    'verificado': true,
    'fotoPerfil': '',
    'estado': 'disponible',
    'createdAt': '2025-01-12T14:20:00Z',
  };

  // ===================== VENDEDORES MOCK =====================
  static const Map<String, dynamic> vendedorMock = {
    'id': 1,
    'usuarioId': 2,
    'nombreNegocio': 'Comidas Rápidas Don Carlos',
    'categoria': 'Comida Rápida',
    'descripcion': 'Somos expertos en hamburguesas, alitas y más.',
    'direccion': 'Carrera 5 #234, Palmira',
    'ciudad': 'Palmira',
    'telefono': '0991234567',
    'email': 'doncarlos@ejemplo.com',
    'fotoPerfil': '',
    'logoNegocio': '',
    'calificacion': 4.8,
    'numeroCalificaciones': 156,
    'horarioApertura': '10:00',
    'horarioCierre': '22:00',
    'diaDescanso': 'Lunes',
    'tiempoPromedio': 25,
    'activo': true,
    'verificado': true,
    'createdAt': '2025-01-10T08:00:00Z',
  };

  static const Map<String, dynamic> vendedorMock2 = {
    'id': 2,
    'usuarioId': 4,
    'nombreNegocio': 'Pizzería Italia',
    'categoria': 'Italiana',
    'descripcion': 'Pizzas artesanales 100% italiana.',
    'direccion': 'Calle 8 #456, Cali',
    'ciudad': 'Cali',
    'telefono': '0992345678',
    'email': 'italia@ejemplo.com',
    'fotoPerfil': '',
    'logoNegocio': '',
    'calificacion': 4.9,
    'numeroCalificaciones': 234,
    'horarioApertura': '11:00',
    'horarioCierre': '23:00',
    'diaDescanso': 'Martes',
    'tiempoPromedio': 30,
    'activo': true,
    'verificado': true,
    'createdAt': '2025-01-08T09:30:00Z',
  };

  // ===================== PRODUCTOS MOCK =====================
  static const List<Map<String, dynamic>> productosMock = [
    {
      'id': 1,
      'vendedorId': 1,
      'nombre': 'Hamburguesa Clásica',
      'descripcion': 'Pan tostado, carne 200g, queso, lechuga, tomate',
      'precio': 12.99,
      'categoria': 'Comida',
      'disponible': true,
      'tiempoPreparacion': 15,
      'stock': 50,
      'imagen': '',
      'calificacion': 4.7,
      'numeroCalificaciones': 45,
      'createdAt': '2025-01-12T10:00:00Z',
    },
    {
      'id': 2,
      'vendedorId': 1,
      'nombre': 'Alitas BBQ (6 unidades)',
      'descripcion': 'Alitas marinadas en salsa BBQ casera, acompañadas de papas',
      'precio': 9.99,
      'categoria': 'Comida',
      'disponible': true,
      'tiempoPreparacion': 20,
      'stock': 30,
      'imagen': '',
      'calificacion': 4.8,
      'numeroCalificaciones': 67,
      'createdAt': '2025-01-12T10:15:00Z',
    },
    {
      'id': 3,
      'vendedorId': 1,
      'nombre': 'Papas Rellenas',
      'descripcion': 'Papas criollas rellenas de carne molida y queso gratinado',
      'precio': 6.99,
      'categoria': 'Entrada',
      'disponible': true,
      'tiempoPreparacion': 10,
      'stock': 40,
      'imagen': '',
      'calificacion': 4.5,
      'numeroCalificaciones': 32,
      'createdAt': '2025-01-12T10:30:00Z',
    },
    {
      'id': 4,
      'vendedorId': 1,
      'nombre': 'Refresco Natural (500ml)',
      'descripcion': 'Jugo natural de naranja, limón o piña',
      'precio': 2.99,
      'categoria': 'Bebida',
      'disponible': true,
      'tiempoPreparacion': 5,
      'stock': 100,
      'imagen': '',
      'calificacion': 4.6,
      'numeroCalificaciones': 89,
      'createdAt': '2025-01-12T10:45:00Z',
    },
    {
      'id': 5,
      'vendedorId': 2,
      'nombre': 'Pizza Margarita',
      'descripcion': 'Clásica pizza con tomate, mozzarella fresca y albahaca',
      'precio': 14.99,
      'categoria': 'Pizza',
      'disponible': true,
      'tiempoPreparacion': 25,
      'stock': 20,
      'imagen': '',
      'calificacion': 4.9,
      'numeroCalificaciones': 120,
      'createdAt': '2025-01-11T11:00:00Z',
    },
    {
      'id': 6,
      'vendedorId': 2,
      'nombre': 'Pizza Pepperoni',
      'descripcion': 'Pizza con pepperoni y queso mozzarella derretido',
      'precio': 16.99,
      'categoria': 'Pizza',
      'disponible': true,
      'tiempoPreparacion': 25,
      'stock': 25,
      'imagen': '',
      'calificacion': 4.8,
      'numeroCalificaciones': 98,
      'createdAt': '2025-01-11T11:15:00Z',
    },
  ];

  // ===================== REPARTIDORES MOCK =====================
  static const List<Map<String, dynamic>> repartidoresMock = [
    {
      'id': 1,
      'usuarioId': 3,
      'nombre': 'Miguel',
      'apellido': 'Rodríguez',
      'telefono': '0985432109',
      'email': 'miguel.rodriguez@ejemplo.com',
      'fotoPerfil': '',
      'estado': 'disponible',
      'calificacion': 4.9,
      'numeroCalificaciones': 245,
      'vehiculo': 'Moto',
      'placa': 'ABC123',
      'tiempoPromedio': 18,
      'ubicacionLatitud': 3.5375,
      'ubicacionLongitud': -76.5303,
      'activo': true,
      'createdAt': '2025-01-12T14:20:00Z',
    },
    {
      'id': 2,
      'usuarioId': 5,
      'nombre': 'David',
      'apellido': 'García',
      'telefono': '0984567890',
      'email': 'david.garcia@ejemplo.com',
      'fotoPerfil': '',
      'estado': 'disponible',
      'calificacion': 4.7,
      'numeroCalificaciones': 189,
      'vehiculo': 'Bicicleta',
      'placa': 'N/A',
      'tiempoPromedio': 22,
      'ubicacionLatitud': 3.5200,
      'ubicacionLongitud': -76.5100,
      'activo': true,
      'createdAt': '2025-01-10T08:30:00Z',
    },
  ];

  // ===================== PEDIDOS MOCK =====================
  static const List<Map<String, dynamic>> pedidosMock = [
    {
      'id': 1,
      'usuarioId': 1,
      'vendedorId': 1,
      'repartidorId': 1,
      'estado': 'entregado',
      'total': 32.97,
      'subtotal': 29.97,
      'impuesto': 3.00,
      'comisionPlataforma': 0,
      'direccionEntrega': 'Calle Principal 123, Valle del Cauca',
      'notasEspeciales': 'Sin cebolla por favor',
      'fechaPedido': '2025-01-20T14:30:00Z',
      'fechaEntrega': '2025-01-20T15:05:00Z',
      'tiempoEstimado': 25,
      'detalles': [
        {
          'id': 1,
          'pedidoId': 1,
          'productoId': 1,
          'nombre': 'Hamburguesa Clásica',
          'cantidad': 2,
          'precioUnitario': 12.99,
          'subtotal': 25.98,
        },
        {
          'id': 2,
          'pedidoId': 1,
          'productoId': 4,
          'nombre': 'Refresco Natural (500ml)',
          'cantidad': 1,
          'precioUnitario': 2.99,
          'subtotal': 2.99,
        },
      ],
      'valoracion': 5,
      'comentario': 'Excelente servicio, todo llegó caliente',
      'createdAt': '2025-01-20T14:30:00Z',
    },
    {
      'id': 2,
      'usuarioId': 1,
      'vendedorId': 2,
      'repartidorId': 2,
      'estado': 'entregado',
      'total': 33.97,
      'subtotal': 30.97,
      'impuesto': 3.00,
      'comisionPlataforma': 0,
      'direccionEntrega': 'Calle Principal 123, Valle del Cauca',
      'notasEspeciales': 'Extra queso',
      'fechaPedido': '2025-01-19T18:45:00Z',
      'fechaEntrega': '2025-01-19T19:25:00Z',
      'tiempoEstimado': 30,
      'detalles': [
        {
          'id': 3,
          'pedidoId': 2,
          'productoId': 5,
          'nombre': 'Pizza Margarita',
          'cantidad': 1,
          'precioUnitario': 14.99,
          'subtotal': 14.99,
        },
        {
          'id': 4,
          'pedidoId': 2,
          'productoId': 6,
          'nombre': 'Pizza Pepperoni',
          'cantidad': 1,
          'precioUnitario': 16.99,
          'subtotal': 16.99,
        },
      ],
      'valoracion': 4,
      'comentario': 'Buena calidad, llegó un poco tarde',
      'createdAt': '2025-01-19T18:45:00Z',
    },
    {
      'id': 3,
      'usuarioId': 1,
      'vendedorId': 1,
      'repartidorId': null,
      'estado': 'en_preparacion',
      'total': 26.97,
      'subtotal': 24.97,
      'impuesto': 2.00,
      'comisionPlataforma': 0,
      'direccionEntrega': 'Calle Principal 123, Valle del Cauca',
      'notasEspeciales': '',
      'fechaPedido': '2025-01-22T15:20:00Z',
      'fechaEntrega': null,
      'tiempoEstimado': 20,
      'detalles': [
        {
          'id': 5,
          'pedidoId': 3,
          'productoId': 2,
          'nombre': 'Alitas BBQ (6 unidades)',
          'cantidad': 2,
          'precioUnitario': 9.99,
          'subtotal': 19.98,
        },
        {
          'id': 6,
          'pedidoId': 3,
          'productoId': 4,
          'nombre': 'Refresco Natural (500ml)',
          'cantidad': 1,
          'precioUnitario': 2.99,
          'subtotal': 2.99,
        },
      ],
      'valoracion': null,
      'comentario': null,
      'createdAt': '2025-01-22T15:20:00Z',
    },
  ];

  // ===================== TOKEN MOCK =====================
  static const String tokenMock =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6MSwibmFtZSI6Ikpvw6xuIiwiZW1haWwiOiJqdWFuLmdhcmNpYUBlamVtcGxvLmNvbSIsInRpcG9Vc3VhcmlvIjoiY2xpZW50ZSIsImlhdCI6MTYzODM2MDAwMCwiZXhwIjoxNjM5NTcyODAwfQ.EXAMPLE_TOKEN_DO_NOT_USE';

  // ===================== MÉTODOS AUXILIARES =====================

  /// Obtener un usuario mock por tipo
  static Map<String, dynamic> obtenerUsuarioMock(String tipoUsuario) {
    switch (tipoUsuario) {
      case 'cliente':
        return usuarioClienteMock;
      case 'vendedor':
        return usuarioVendedorMock;
      case 'repartidor':
        return usuarioRepartidorMock;
      default:
        return usuarioClienteMock;
    }
  }

  /// Simular respuesta de login
  static Map<String, dynamic> simularRespuestaLogin(String tipoUsuario) {
    final usuario = obtenerUsuarioMock(tipoUsuario);
    return {
      'message': 'Login exitoso',
      'usuario': usuario,
      'token': tokenMock,
    };
  }

  /// Obtener productos de un vendedor
  static List<Map<String, dynamic>> obtenerProductosPorVendedor(int vendedorId) {
    return productosMock.where((p) => p['vendedorId'] == vendedorId).toList();
  }

  /// Obtener pedidos de un usuario
  static List<Map<String, dynamic>> obtenerPedidosPorUsuario(int usuarioId) {
    return pedidosMock.where((p) => p['usuarioId'] == usuarioId).toList();
  }

  /// Obtener un pedido específico
  static Map<String, dynamic>? obtenerPedidoPorId(int pedidoId) {
    try {
      return pedidosMock.firstWhere((p) => p['id'] == pedidoId);
    } catch (e) {
      return null;
    }
  }

  /// Obtener un producto específico
  static Map<String, dynamic>? obtenerProductoPorId(int productoId) {
    try {
      return productosMock.firstWhere((p) => p['id'] == productoId);
    } catch (e) {
      return null;
    }
  }
}
