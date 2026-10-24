import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import '../../models/telefono.dart';
import '../../services/api_error.dart';
import '../../services/telefono_service.dart';
import '../../utils/formato.dart';
import '../../utils/validadores.dart';
import '../../widgets/ui/ui.dart';

/// Mis teléfonos: hasta 5, uno solo principal. Agregar, editar, cambiar el principal y borrar.
class TelefonosScreen extends StatefulWidget {
  const TelefonosScreen({super.key});

  @override
  State<TelefonosScreen> createState() => _TelefonosScreenState();
}

class _TelefonosScreenState extends State<TelefonosScreen> {
  static const int _maximo = 5;

  bool _cargando = true;
  String? _error;
  List<Telefono> _telefonos = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = _telefonos.isEmpty;
      _error = null;
    });
    try {
      final lista = await TelefonoService.listar();
      if (!mounted) return;
      setState(() {
        _telefonos = lista;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = textoDeError(e);
        _cargando = false;
      });
    }
  }

  Future<void> _abrirFormulario([Telefono? actual]) async {
    final guardado = await mostrarHoja<bool>(context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FormularioTelefono(actual: actual, haySiguientes: _telefonos.isNotEmpty),
    );
    if (guardado == true && mounted) {
      mostrarExito(context, actual == null ? 'Teléfono guardado' : 'Teléfono actualizado');
      await _cargar();
    }
  }

  Future<void> _hacerPrincipal(Telefono t) async {
    try {
      await TelefonoService.marcarPrincipal(t.id);
      if (!mounted) return;
      mostrarExito(context, '${Formato.telefono(t.numero)} es ahora tu teléfono principal');
      await _cargar();
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    }
  }

  Future<void> _eliminar(Telefono t) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar este teléfono?'),
        content: Text(
          t.principal && _telefonos.length > 1
              ? 'Es tu teléfono principal. El más antiguo que te quede pasará a ser el principal.'
              : 'Se eliminará ${Formato.telefono(t.numero)}.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;
    try {
      await TelefonoService.eliminar(t.id);
      if (!mounted) return;
      mostrarMensaje(context, 'Teléfono eliminado');
      await _cargar();
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lleno = _telefonos.length >= _maximo;
    return FondoValle(
      titulo: 'Mis teléfonos',
      botonFlotante: (_cargando || _error != null || _telefonos.isEmpty)
          ? null
          : FloatingActionButton.extended(
              onPressed: lleno
                  ? () => mostrarMensaje(context, 'Puedes guardar hasta $_maximo teléfonos. Elimina uno para agregar otro.')
                  : () => _abrirFormulario(),
              icon: const Icon(Icons.add_call),
              label: Text(lleno ? 'Límite alcanzado' : 'Agregar'),
            ),
      child: _contenido(),
    );
  }

  Widget _contenido() {
    if (_cargando) return const EsqueletoLista(cantidad: 3);
    if (_error != null) {
      return EstadoVacio(
        icono: Icons.cloud_off_rounded,
        color: AppTheme.errorColor,
        titulo: 'No pudimos cargar tus teléfonos',
        mensaje: _error,
        textoAccion: 'Reintentar',
        onAccion: _cargar,
      );
    }
    if (_telefonos.isEmpty) {
      return EstadoVacio(
        icono: Icons.phone_disabled_outlined,
        titulo: 'No tienes teléfonos guardados',
        mensaje: 'Agrega uno para que el repartidor y los negocios puedan contactarte.',
        textoAccion: 'Agregar teléfono',
        onAccion: () => _abrirFormulario(),
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        itemCount: _telefonos.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          if (i == _telefonos.length) {
            return Padding(
              padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
              child: Text(
                '${_telefonos.length} de $_maximo teléfonos. El principal es el que ven los repartidores y los negocios.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.colores.textoSuave),
              ),
            );
          }
          final t = _telefonos[i];
          return _TarjetaTelefono(
            telefono: t,
            onEditar: () => _abrirFormulario(t),
            onPrincipal: () => _hacerPrincipal(t),
            onEliminar: () => _eliminar(t),
          );
        },
      ),
    );
  }
}

class _TarjetaTelefono extends StatelessWidget {
  const _TarjetaTelefono({required this.telefono, required this.onEditar, required this.onPrincipal, required this.onEliminar});

  final Telefono telefono;
  final VoidCallback onEditar;
  final VoidCallback onPrincipal;
  final VoidCallback onEliminar;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final t = telefono;

    return TarjetaValle(
      onTap: onEditar,
      colorBorde: t.principal ? c.primario : null,
      padding: const EdgeInsets.fromLTRB(16, 14, 4, 14),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: c.primario.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
            child: Icon(t.tipo.icono, color: c.primario),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(Formato.telefono(t.numero), style: tema.titleMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.4)),
                const SizedBox(height: 2),
                Text(t.tipo.etiqueta, style: tema.bodySmall?.copyWith(color: c.textoSuave)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (t.principal) InsigniaValle('Principal', color: c.primario, icono: Icons.star_rounded),
                    if (t.verificado)
                      const InsigniaValle('Verificado', color: AppTheme.successColor, icono: Icons.verified_rounded)
                    else
                      InsigniaValle('Sin verificar', color: c.textoSuave),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Opciones',
            icon: Icon(Icons.more_vert_rounded, color: c.textoSuave),
            onSelected: (v) {
              switch (v) {
                case 'editar':
                  onEditar();
                case 'principal':
                  onPrincipal();
                case 'eliminar':
                  onEliminar();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'editar',
                child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Editar'), contentPadding: EdgeInsets.zero),
              ),
              if (!t.principal)
                const PopupMenuItem(
                  value: 'principal',
                  child: ListTile(
                    leading: Icon(Icons.star_outline_rounded),
                    title: Text('Hacer principal'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              PopupMenuItem(
                value: 'eliminar',
                child: ListTile(
                  leading: const Icon(Icons.delete_outline, color: AppTheme.errorColor),
                  title: Text('Eliminar', style: TextStyle(color: AppTheme.errorColor)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Hoja inferior para agregar o editar un teléfono
class _FormularioTelefono extends StatefulWidget {
  const _FormularioTelefono({required this.actual, required this.haySiguientes});

  final Telefono? actual;
  final bool haySiguientes; // si ya hay otros, se puede elegir que este sea el principal

  @override
  State<_FormularioTelefono> createState() => _FormularioTelefonoState();
}

class _FormularioTelefonoState extends State<_FormularioTelefono> {
  late final TextEditingController _numero;
  late TipoTelefono _tipo;
  bool _principal = false;
  bool _guardando = false;
  String? _error;

  bool get _editando => widget.actual != null;

  @override
  void initState() {
    super.initState();
    _numero = TextEditingController(text: widget.actual?.numero ?? '');
    _tipo = widget.actual?.tipo ?? TipoTelefono.movil;
  }

  @override
  void dispose() {
    _numero.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();
    final numero = _numero.text.replaceAll(RegExp(r'[\s\-]'), '');
    if (!Validadores.telefono(numero)) {
      setState(() => _error = 'Debe tener 10 dígitos y empezar con 09 (ej: 0991234567)');
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      if (_editando) {
        await TelefonoService.actualizar(widget.actual!.id, numero: numero, tipo: _tipo);
      } else {
        await TelefonoService.crear(numero: numero, tipo: _tipo, principal: _principal);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = textoDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_editando ? 'Editar teléfono' : 'Nuevo teléfono', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            CampoValle(
              controller: _numero,
              etiqueta: 'Número',
              icono: Icons.phone_iphone_outlined,
              tipoTeclado: TextInputType.phone,
              formateadores: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 \-]'))],
              maxLongitud: 12,
              estado: _error == null ? EstadoCampo.neutro : EstadoCampo.error,
              ayuda:
                  _error ??
                  (_editando && widget.actual!.verificado ? 'Si cambias el número, tendrás que verificarlo de nuevo' : 'Ej: 0991234567'),
              accion: TextInputAction.done,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _guardando ? null : _guardar(),
            ),
            const SizedBox(height: 16),
            // Los tipos van en una sola fila que se desliza (antes "WhatsApp" quedaba solo en una segunda fila)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                spacing: 8,
                children: [
                  for (final t in TipoTelefono.values)
                    ChoiceChip(
                      avatar: Icon(t.icono, size: 18, color: _tipo == t ? Colors.white : c.textoSuave),
                      label: Text(t.etiqueta),
                      selected: _tipo == t,
                      showCheckmark: false,
                      labelStyle: TextStyle(color: _tipo == t ? Colors.white : c.texto, fontWeight: FontWeight.w600),
                      onSelected: (_) => setState(() => _tipo = t),
                    ),
                ],
              ),
            ),
            if (!_editando && widget.haySiguientes)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Usar como principal'),
                value: _principal,
                onChanged: (v) => setState(() => _principal = v),
              ),
            const SizedBox(height: 20),
            BotonValle(
              texto: _editando ? 'Guardar cambios' : 'Guardar teléfono',
              icono: Icons.check_rounded,
              cargando: _guardando,
              onPressed: _guardar,
            ),
          ],
        ),
      ),
    );
  }
}
