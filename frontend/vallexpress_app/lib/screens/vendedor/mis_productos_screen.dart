import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/product_service.dart';

class MisProductosScreen extends StatefulWidget {
  const MisProductosScreen({super.key});

  @override
  State<MisProductosScreen> createState() => _MisProductosScreenState();
}

class _MisProductosScreenState extends State<MisProductosScreen> {
  bool _loading = true;
  String? _error;
  List<dynamic> _productos = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _mostrarEditarProducto(dynamic p, int index) async {
    final nombreCtrl = TextEditingController(
      text: (p['nombre'] ?? '').toString(),
    );
    final descCtrl = TextEditingController(
      text: (p['descripcion'] ?? '').toString(),
    );
    final precioCtrl = TextEditingController(
      text: (p['precio'] ?? '').toString(),
    );
    final stockCtrl = TextEditingController(
      text: (p['stock'] ?? '0').toString(),
    );
    final tiempoPrepCtrl = TextEditingController(
      text: (p['tiempoPreparacion'] ?? '0').toString(),
    );

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppTheme.borderColor.withOpacity(0.35)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ====== TÍTULO ======
                const Text(
                  'Editar producto',
                  style: TextStyle(
                    color: AppTheme.textPrimaryColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),

                // ====== CAMPOS ======
                _campoForm(
                  label: 'Nombre',
                  controller: nombreCtrl,
                  icon: Icons.fastfood,
                ),
                const SizedBox(height: 12),

                _campoForm(
                  label: 'Descripción',
                  controller: descCtrl,
                  icon: Icons.notes,
                  maxLines: 2,
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: _campoForm(
                        label: 'Precio',
                        controller: precioCtrl,
                        icon: Icons.attach_money,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _campoForm(
                        label: 'Stock',
                        controller: stockCtrl,
                        icon: Icons.inventory_2_outlined,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                _campoForm(
                  label: 'Tiempo de preparación (min)',
                  controller: tiempoPrepCtrl,
                  icon: Icons.timer_outlined,
                  keyboardType: TextInputType.number,
                ),

                const SizedBox(height: 18),
                Divider(color: Colors.white.withOpacity(0.08)),
                const SizedBox(height: 12),

                // ====== BOTONES ======
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: Colors.white.withOpacity(0.12),
                            ),
                          ),
                        ),
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: AppTheme.backgroundColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Guardar',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (ok != true) return;

    final precio = double.tryParse(precioCtrl.text.trim());
    final stock = int.tryParse(stockCtrl.text.trim());
    if (precio == null || stock == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Precio o stock inválidos')));
      return;
    }
    final tiempoPreparacion = int.tryParse(tiempoPrepCtrl.text.trim());
    if (tiempoPreparacion == null || tiempoPreparacion < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tiempo de preparación inválido')),
      );
      return;
    }

    try {
      await ProductService.actualizarProducto(
        id: p['id'],
        nombre: nombreCtrl.text.trim(),
        descripcion: descCtrl.text.trim(),
        precio: precio,
        stock: stock,
        tiempoPreparacion: tiempoPreparacion,
      );

      // Actualiza UI sin recargar
      setState(() {
        _productos[index]['nombre'] = nombreCtrl.text.trim();
        _productos[index]['descripcion'] = descCtrl.text.trim();
        _productos[index]['precio'] = precio;
        _productos[index]['stock'] = stock;
        _productos[index]['tiempoPreparacion'] = tiempoPreparacion;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Producto actualizado')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await ProductService.listarMisProductos();
      if (!mounted) return;
      setState(() => _productos = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Widget _campoForm({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(
        color: AppTheme.textPrimaryColor,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppTheme.primaryColor),
        filled: true,
        fillColor: AppTheme.backgroundColor.withOpacity(0.25),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: AppTheme.borderColor.withOpacity(0.35),
            width: 1.4,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.borderColor, width: 2),
        ),
        labelStyle: const TextStyle(color: AppTheme.textSecondaryColor),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Mis Productos'),
        backgroundColor: AppTheme.primaryColor,
        elevation: 0,
        actions: [
          IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : _productos.isEmpty
          ? const Center(
              child: Text(
                'Aún no tienes productos',
                style: TextStyle(color: AppTheme.textSecondaryColor),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _productos.length,
              itemBuilder: (_, i) {
                final p = _productos[i];
                final nombre = (p['nombre'] ?? '').toString();
                final desc = (p['descripcion'] ?? '').toString();
                final precio = (p['precio'] ?? '0').toString();
                final disponible = (p['disponible'] == true);
                final tiempoPrep = (p['tiempoPreparacion'] ?? 0).toString();

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.borderColor.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          disponible ? Icons.check_circle : Icons.cancel,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nombre,
                              style: const TextStyle(
                                color: AppTheme.textPrimaryColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            if (desc.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                desc,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.textSecondaryColor,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Text(
                              '\$$precio',
                              style: const TextStyle(
                                color: AppTheme.primaryColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '⏱ $tiempoPrep min preparación',
                              style: const TextStyle(
                                color: AppTheme.textSecondaryColor,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // ✅ Switch ON/OFF
                      Switch(
                        value: disponible,
                        onChanged: (value) async {
                          try {
                            await ProductService.cambiarDisponible(
                              id: p['id'],
                              disponible: value,
                            );
                            setState(() {
                              _productos[i]['disponible'] = value;
                            });
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  e.toString().replaceFirst('Exception: ', ''),
                                ),
                              ),
                            );
                          }
                        },
                      ),

                      IconButton(
                        onPressed: () => _mostrarEditarProducto(p, i),
                        icon: const Icon(
                          Icons.edit,
                          color: AppTheme.textSecondaryColor,
                        ),
                      ),

                      IconButton(
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            barrierDismissible: true,
                            builder: (_) => Dialog(
                              backgroundColor: AppTheme.cardColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22),
                                side: BorderSide(
                                  color: AppTheme.borderColor.withOpacity(0.35),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Título
                                    const Text(
                                      'Eliminar producto',
                                      style: TextStyle(
                                        color: AppTheme.textPrimaryColor,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 10),

                                    // Mensaje
                                    Text(
                                      '¿Eliminar "${p['nombre']}"?',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: AppTheme.textSecondaryColor
                                            .withOpacity(0.95),
                                        fontSize: 14,
                                        height: 1.35,
                                      ),
                                    ),

                                    const SizedBox(height: 16),
                                    Divider(
                                      color: Colors.white.withOpacity(0.08),
                                    ),
                                    const SizedBox(height: 14),

                                    // Botones
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            style: TextButton.styleFrom(
                                              foregroundColor: Colors.white70,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 14,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                side: BorderSide(
                                                  color: Colors.white
                                                      .withOpacity(0.12),
                                                ),
                                              ),
                                            ),
                                            child: const Text(
                                              'Cancelar',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: ElevatedButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  AppTheme.primaryColor,
                                              foregroundColor:
                                                  AppTheme.backgroundColor,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 14,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                            ),
                                            child: const Text(
                                              'Eliminar',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );

                          if (ok != true) return;

                          try {
                            await ProductService.eliminarProducto(p['id']);
                            setState(() {
                              _productos.removeAt(i);
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Producto eliminado'),
                              ),
                            );
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  e.toString().replaceFirst('Exception: ', ''),
                                ),
                              ),
                            );
                          }
                        },
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
