// Pruebas del carrito y del modelo de pedido (lógica pura, sin servidor).
//   flutter test test/carrito_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vallexpress_app/models/negocio.dart';
import 'package:vallexpress_app/models/pedido.dart';
import 'package:vallexpress_app/models/producto.dart';
import 'package:vallexpress_app/providers/carrito_provider.dart';

const _pizzeria = Negocio(id: 1, nombre: 'Pizzería', categoria: Categoria('001', 'Comida'), costoEnvio: 1.5, pedidoMinimo: 10);
const _panaderia = Negocio(id: 2, nombre: 'Panadería', categoria: Categoria('004', 'Panadería'));
const _pizza = Producto(id: 10, negocioId: 1, nombre: 'Pizza', precio: 8.5);
const _cola = Producto(id: 11, negocioId: 1, nombre: 'Cola', precio: 1.25);
const _pan = Producto(id: 20, negocioId: 2, nombre: 'Pan', precio: 0.25);

void main() {
  group('Carrito', () {
    test('suma unidades del mismo producto y calcula subtotal, envío y total', () {
      final c = CarritoProvider()
        ..agregar(_pizzeria, _pizza)
        ..agregar(_pizzeria, _pizza, cantidad: 2, notas: '  sin aceitunas ')
        ..agregar(_pizzeria, _cola, cantidad: 2);
      expect(c.items.length, 2);
      expect(c.cantidadDe(_pizza.id), 3);
      expect(c.cantidadTotal, 5);
      expect(c.subtotal, closeTo(28, 0.001));
      expect(c.total, closeTo(29.5, 0.001));
      expect(c.items.first.notas, 'sin aceitunas');
    });

    test('avisa cuánto falta para el pedido mínimo', () {
      final c = CarritoProvider()..agregar(_pizzeria, _cola, cantidad: 2);
      expect(c.faltaParaMinimo, closeTo(7.5, 0.001));
      c.agregar(_pizzeria, _pizza);
      expect(c.faltaParaMinimo, 0);
    });

    test('un producto de otro negocio vacía el carrito (la pantalla lo confirma antes)', () {
      final c = CarritoProvider()..agregar(_pizzeria, _pizza);
      expect(c.esDeOtroNegocio(_panaderia), isTrue);
      c.agregar(_panaderia, _pan);
      expect(c.negocio!.id, 2);
      expect(c.items.single.producto.id, _pan.id);
    });

    test('cantidad 0 quita el producto; sin productos queda vacío', () {
      final c = CarritoProvider()..agregar(_pizzeria, _pizza);
      c.fijarCantidad(_pizza.id, 0);
      expect(c.vacio, isTrue);
      expect(c.faltaParaMinimo, 0);
    });

    test('no pasa de 99 unidades y envía solo código, cantidad y nota', () {
      final c = CarritoProvider()..agregar(_pizzeria, _pizza, cantidad: 150);
      expect(c.cantidadDe(_pizza.id), 99);
      expect(c.paraEnviar(), [
        {'productoId': 10, 'cantidad': 99},
      ]);
    });
  });

  group('Pedido', () {
    final json = {
      'id': 7,
      'estado': 'preparando',
      'fecha': '2026-10-14T19:00:00.000Z',
      'negocio': {'id': 1, 'nombre': 'Pizzería', 'logo': null},
      'entrega': {'direccion': 'Calle 1', 'referencia': 'Portón verde'},
      'metodoPago': 'efectivo',
      'subtotal': 19.5,
      'costoEnvio': 1.5,
      'total': 21,
      'tiempoEstimado': 35,
      'productos': [
        {'productoId': 10, 'nombre': 'Pizza', 'precioUnitario': 8.5, 'cantidad': 2, 'subtotal': 17, 'notas': 'Sin aceitunas'},
        {'productoId': 11, 'nombre': 'Cola', 'precioUnitario': 1.25, 'cantidad': 2, 'subtotal': 2.5},
      ],
      'lineaTiempo': [
        {'estado': 'pendiente', 'fecha': '2026-10-14T19:00:00.000Z'},
        {'estado': 'confirmado', 'fecha': '2026-10-14T19:02:00.000Z'},
      ],
      'calificacion': null,
    };

    test('se lee completo desde el servidor', () {
      final p = Pedido.desdeJson(json);
      expect(p.estado, EstadoPedido.preparando);
      expect(p.negocioNombre, 'Pizzería');
      expect(p.total, 21);
      expect(p.productos.first.notas, 'Sin aceitunas');
      expect(p.resumenProductos, '2× Pizza, 2× Cola');
      expect(p.lineaTiempo.keys, ['pendiente', 'confirmado']);
      expect(p.llegadaEstimada, p.fecha!.add(const Duration(minutes: 35)));
    });

    test('repartidor con vehículo y ubicación; el mapa solo mientras lo lleva', () {
      final p = Pedido.desdeJson({
        ...json,
        'estado': 'recogido',
        'negocio': {'id': 1, 'nombre': 'Pizzería', 'local': {'direccion': 'Av. 1', 'latitud': -3.82, 'longitud': -78.75}, 'telefono': '0991112222'},
        'entrega': {'direccion': 'Calle 1', 'latitud': -3.83, 'longitud': -78.76},
        'distanciaKm': 1.45,
        'repartidor': {'nombre': 'Pedro', 'apellido': 'Vera', 'telefono': '0987', 'vehiculo': 'moto', 'placa': 'AB123C', 'color': 'Roja', 'calificacion': 4.5, 'ubicacion': {'latitud': -3.825, 'longitud': -78.755}},
      });
      expect(p.enReparto, isTrue);
      expect(p.repartidor!.vehiculo, Vehiculo.moto);
      expect(p.repartidor!.descripcionVehiculo, 'Moto roja · AB123C');
      expect(p.repartidor!.ubicacion!.latitud, -3.825);
      expect(p.negocioLocal!.longitud, -78.75);
      expect(p.negocioTelefono, '0991112222');
      expect(p.entregaPunto!.latitud, -3.83);
      expect(p.distanciaKm, 1.45);
      expect(Pedido.desdeJson({...json, 'estado': 'entregado'}).enReparto, isFalse);
      expect(Pedido.desdeJson({...json, 'estado': 'recibido', 'repartidor': {'nombre': 'Pedro'}}).puedeCalificarRepartidor, isTrue);
      expect(Pedido.desdeJson({...json, 'estado': 'recibido', 'repartidor': {'nombre': 'Pedro'}, 'calificacionRepartidor': {'puntuacion': 5}}).puedeCalificarRepartidor, isFalse);
      expect(Vehiculo.deCodigo('bicicleta').llevaPlaca, isFalse);
    });

    test('acciones permitidas según el estado', () {
      Pedido con(String estado, [Map? calif]) => Pedido.desdeJson({...json, 'estado': estado, 'calificacion': calif});
      expect(con('pendiente').puedeCancelar, isTrue);
      expect(con('confirmado').puedeCancelar, isFalse);
      expect(con('entregado').puedeConfirmarRecibido, isTrue);
      expect(con('recibido').puedeCalificar, isTrue);
      expect(con('recibido', {'puntuacion': 4}).puedeCalificar, isFalse);
      expect(con('cancelado').estado.activo, isFalse);
      expect(EstadoPedido.deCodigo('en_camino'), EstadoPedido.enCamino);
    });
  });
}
