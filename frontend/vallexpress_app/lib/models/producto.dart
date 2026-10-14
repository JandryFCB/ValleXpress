import 'package:flutter/material.dart';

/// Estatus de un producto. El servidor lo maneja como texto: 'disponible', 'agotado', 'oculto'.
enum EstadoProducto {
  disponible('disponible', 'Disponible', Icons.check_circle_rounded),
  agotado('agotado', 'Agotado', Icons.remove_shopping_cart_rounded),
  oculto('oculto', 'Oculto', Icons.visibility_off_rounded);

  const EstadoProducto(this.codigo, this.etiqueta, this.icono);

  final String codigo;
  final String etiqueta;
  final IconData icono;

  static EstadoProducto deCodigo(String? c) => EstadoProducto.values.firstWhere((e) => e.codigo == c, orElse: () => EstadoProducto.disponible);
}

/// Un producto del menú de un negocio. "stock" y "vendidos" solo llegan cuando lo pide el dueño.
class Producto {
  const Producto({
    required this.id,
    required this.negocioId,
    required this.nombre,
    required this.precio,
    this.descripcion,
    this.estado = EstadoProducto.disponible,
    this.disponible = true,
    this.seccion,
    this.imagen,
    this.miniatura,
    this.orden = 0,
    this.controlaStock = false,
    this.stock,
    this.vendidos,
  });

  final int id;
  final int negocioId;
  final String nombre;
  final String? descripcion;
  final double precio;
  final EstadoProducto estado;

  /// Se puede pedir ahora (disponible y, si controla stock, con unidades)
  final bool disponible;
  final String? seccion;
  final String? imagen;
  final String? miniatura;
  final int orden;
  final bool controlaStock;
  final int? stock;
  final int? vendidos;

  factory Producto.desdeJson(Map<String, dynamic> j) {
    String? texto(Object? v) => (v == null || '$v'.trim().isEmpty) ? null : '$v';
    return Producto(
      id: (j['id'] as num).toInt(),
      negocioId: (j['negocioId'] as num?)?.toInt() ?? 0,
      nombre: '${j['nombre'] ?? ''}',
      descripcion: texto(j['descripcion']),
      precio: (j['precio'] as num?)?.toDouble() ?? 0,
      estado: EstadoProducto.deCodigo(j['estado']?.toString()),
      disponible: j['disponible'] == true,
      seccion: texto(j['seccion']),
      imagen: texto(j['imagen']),
      miniatura: texto(j['miniatura']),
      orden: (j['orden'] as num?)?.toInt() ?? 0,
      controlaStock: j['controlaStock'] == true,
      stock: (j['stock'] as num?)?.toInt(),
      vendidos: (j['vendidos'] as num?)?.toInt(),
    );
  }
}

/// El menú: productos y secciones en orden ("Sin sección" = null, al final)
class Menu {
  const Menu(this.productos, this.secciones);

  final List<Producto> productos;
  final List<String?> secciones;

  factory Menu.desdeJson(Map<String, dynamic> j) => Menu(
        (j['productos'] as List? ?? []).map((p) => Producto.desdeJson(Map<String, dynamic>.from(p))).toList(),
        (j['secciones'] as List? ?? []).map((s) => s?.toString()).toList(),
      );

  /// Productos agrupados por sección, en el orden del menú
  Map<String?, List<Producto>> get porSeccion => {for (final s in secciones) s: productos.where((p) => p.seccion == s).toList()};
}
