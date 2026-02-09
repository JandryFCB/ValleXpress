import '../../config/theme.dart';
import 'package:flutter/material.dart';
import 'package:vallexpress_app/services/product_service.dart';

class AgregarProductoScreen extends StatefulWidget {
  const AgregarProductoScreen({super.key});

  @override
  State<AgregarProductoScreen> createState() => _AgregarProductoScreenState();
}

class _AgregarProductoScreenState extends State<AgregarProductoScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nombreCtrl = TextEditingController();
  final _descripcionCtrl = TextEditingController();
  final _categoriaCtrl = TextEditingController();
  final _precioCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  final _tiempoPreparacionCtrl = TextEditingController();

  bool _guardando = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _descripcionCtrl.dispose();
    _categoriaCtrl.dispose();
    _precioCtrl.dispose();
    _stockCtrl.dispose();
    _tiempoPreparacionCtrl.dispose();
    super.dispose();
  }

  void _mostrarError(String msg) {
    if (!mounted) return;
    debugPrint('❌ ERROR AGREGAR PRODUCTO: $msg');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _guardar() async {
    if (_guardando) return;

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    final nombre = _nombreCtrl.text.trim();
    final descripcion = _descripcionCtrl.text.trim();
    final categoria = _categoriaCtrl.text.trim();

    final precioText = _precioCtrl.text.trim().replaceAll(',', '.');
    final stockText = _stockCtrl.text.trim();
    final tiempoPrepText = _tiempoPreparacionCtrl.text.trim();

    final precio = double.tryParse(precioText);
    final stock = int.tryParse(stockText);
    final tiempoPreparacion = int.tryParse(tiempoPrepText);

    if (precio == null) {
      _mostrarError('Precio inválido');
      return;
    }
    if (stock == null) {
      _mostrarError('Stock inválido');
      return;
    }
    if (tiempoPreparacion == null || tiempoPreparacion < 0) {
      _mostrarError('Tiempo de preparación inválido');
      return;
    }

    debugPrint('📝 Enviando producto:');
    debugPrint('  - Nombre: $nombre');
    debugPrint('  - Descripción: $descripcion');
    debugPrint('  - Categoría: $categoria');
    debugPrint('  - Precio: $precio');
    debugPrint('  - Stock: $stock');

    setState(() => _guardando = true);

    try {
      await ProductService.crearProducto(
        nombre: nombre,
        descripcion: descripcion,
        categoria: categoria,
        precio: precio,
        stock: stock,
        tiempoPreparacion: tiempoPreparacion,
      );

      if (!mounted) return;

      debugPrint('✅ Producto creado exitosamente');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Producto creado exitosamente'),
          backgroundColor: Colors.green,
        ),
      );

      // vuelve a MisProductosScreen y le dice "creado ok" para refrescar
      Navigator.pop(context, true);
    } catch (e) {
      final errorMsg = e.toString().replaceFirst('Exception: ', '');
      debugPrint('❌ Error completo: $e');
      _mostrarError(errorMsg);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Agregar Producto'),
        backgroundColor: AppTheme.primaryColor,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nombreCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  hintText: 'Ej: Hamburguesa Doble',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Requerido';
                  if (v.trim().length < 3) return 'Mínimo 3 caracteres';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tiempoPreparacionCtrl,
                textInputAction: TextInputAction.next,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tiempo de preparación (minutos)',
                  hintText: 'Ej: 10',
                ),
                validator: (v) {
                  final txt = (v ?? '').trim();
                  if (txt.isEmpty) return 'Requerido';
                  final value = int.tryParse(txt);
                  if (value == null || value < 0) return 'Inválido';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descripcionCtrl,
                textInputAction: TextInputAction.next,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  hintText: 'Ej: Carne doble con queso',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _categoriaCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Categoría',
                  hintText: 'Ej: Comida rápida',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _precioCtrl,
                textInputAction: TextInputAction.next,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Precio',
                  hintText: 'Ej: 4.50',
                ),
                validator: (v) {
                  final txt = (v ?? '').trim().replaceAll(',', '.');
                  if (txt.isEmpty) return 'Requerido';
                  final value = double.tryParse(txt);
                  if (value == null) return 'Número inválido';
                  if (value <= 0) return 'Debe ser mayor a 0';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _stockCtrl,
                textInputAction: TextInputAction.done,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Stock',
                  hintText: 'Ej: 20',
                ),
                validator: (v) {
                  final txt = (v ?? '').trim();
                  if (txt.isEmpty) return 'Requerido';
                  final value = int.tryParse(txt);
                  if (value == null) return 'Número inválido';
                  if (value < 0) return 'No puede ser negativo';
                  return null;
                },
                //onFieldSubmitted: (_) => _guardar(),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _guardando ? null : _guardar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: AppTheme.backgroundColor,
                    disabledBackgroundColor: AppTheme.primaryColor.withOpacity(
                      0.35,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _guardando
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppTheme.backgroundColor, // 👈 spinner oscuro pro
                            ),
                          ),
                        )
                      : const Text(
                          'Guardar Producto',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 22),
            ],
          ),
        ),
      ),
    );
  }
}
