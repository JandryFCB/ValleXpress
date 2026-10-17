import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import '../../services/permisos_celular.dart';
import '../../widgets/aviso_ubicacion.dart';
import '../../widgets/ui/ui.dart';

/// "Prepara tu celular": los permisos que necesita cada rol, por qué, cómo están y un botón para resolverlos.
/// Al volver de los ajustes del celular se revisa todo otra vez. Devuelve true si quedó todo lo obligatorio.
class PermisosScreen extends StatefulWidget {
  const PermisosScreen({super.key, required this.rol});

  final String? rol;

  @override
  State<PermisosScreen> createState() => _PermisosScreenState();
}

class _PermisosScreenState extends State<PermisosScreen> with WidgetsBindingObserver {
  EstadoPermiso? _ubicacion;
  EstadoPermiso? _notificaciones;
  EstadoPermiso? _bateria;
  bool _revisando = false;

  bool get _esRepartidor => widget.rol == 'repartidor';

  bool get _obligatoriosListos =>
      _notificaciones == EstadoPermiso.listo && (!PermisosCelular.necesitaUbicacion(widget.rol) || _ubicacion == EstadoPermiso.listo);

  bool get _todoListo => _obligatoriosListos && (!PermisosCelular.necesitaBateria(widget.rol) || _bateria == EstadoPermiso.listo);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _revisar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Al volver de los ajustes del celular, puede que ya haya cambiado algo
  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed) _revisar();
  }

  Future<void> _revisar() async {
    if (_revisando) return;
    _revisando = true;
    final yaRevisado = _notificaciones != null;
    final antes = _todoListo;
    final n = await PermisosCelular.notificaciones();
    final u = PermisosCelular.necesitaUbicacion(widget.rol) ? await PermisosCelular.ubicacion() : null;
    final b = PermisosCelular.necesitaBateria(widget.rol) ? await PermisosCelular.bateria() : null;
    _revisando = false;
    if (!mounted) return;
    setState(() => (_notificaciones = n, _ubicacion = u, _bateria = b));
    if (yaRevisado && !antes && _todoListo) HapticFeedback.mediumImpact(); // vibra al completar lo que faltaba
  }

  Future<void> _resolver(Future<void> Function() accion) async {
    await accion();
    await _revisar();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final cargando = _notificaciones == null;

    return FondoValle(
      appBar: AppBar(title: const Text('Prepara tu celular')),
      child: cargando
          ? const EsqueletoLista(cantidad: 3, conImagen: false)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text(
                  _esRepartidor
                      ? 'Para recibir pedidos y que tus clientes vean dónde va su entrega, tu celular necesita estos permisos.'
                      : 'Para que no se te pase ningún aviso, activa estos permisos.',
                  style: tema.bodyMedium?.copyWith(color: c.textoSuave),
                ),
                const SizedBox(height: 16),
                if (_ubicacion != null)
                  Aparecer(
                    child: _TarjetaPermiso(
                      icono: Icons.my_location_rounded,
                      titulo: 'Ubicación precisa',
                      porque: 'El cliente ve en el mapa dónde va su pedido y te asignamos los pedidos cercanos.',
                      estado: _ubicacion!,
                      textoEstado: switch (_ubicacion!) {
                        EstadoPermiso.gpsApagado => 'El GPS de tu celular está apagado',
                        EstadoPermiso.aproximada => 'Solo diste ubicación aproximada: elige "Precisa"',
                        EstadoPermiso.ajustes => 'La negaste: actívala en Ajustes → Permisos → Ubicación',
                        _ => 'Elige "Mientras se usa la app" y ubicación precisa',
                      },
                      textoBoton: switch (_ubicacion!) {
                        EstadoPermiso.gpsApagado => 'Encender GPS',
                        EstadoPermiso.ajustes => 'Abrir ajustes',
                        _ => 'Permitir ubicación',
                      },
                      onResolver: () async {
                        if (_esRepartidor && !await confirmarAvisoUbicacion(context)) return;
                        await _resolver(() => PermisosCelular.resolverUbicacion(_ubicacion!));
                      },
                    ),
                  ),
                Aparecer(
                  indice: 1,
                  child: _TarjetaPermiso(
                    icono: Icons.notifications_active_rounded,
                    titulo: 'Notificaciones',
                    porque: switch (widget.rol) {
                      'repartidor' => 'Te avisamos con sonido cuando hay un pedido listo para recoger.',
                      'vendedor' => 'Suena cada vez que un cliente te hace un pedido, aunque la app esté cerrada.',
                      _ => 'Te avisamos cuando tu pedido se confirma, sale y está por llegar.',
                    },
                    estado: _notificaciones!,
                    textoEstado: _notificaciones == EstadoPermiso.ajustes ? 'Las negaste: actívalas en Ajustes → Notificaciones' : 'Toca "Permitir" en el aviso del celular',
                    textoBoton: _notificaciones == EstadoPermiso.ajustes ? 'Abrir ajustes' : 'Permitir notificaciones',
                    onResolver: () => _resolver(() => PermisosCelular.resolverNotificaciones(_notificaciones!)),
                  ),
                ),
                if (_bateria != null)
                  Aparecer(
                    indice: 2,
                    child: _TarjetaPermiso(
                      icono: Icons.battery_charging_full_rounded,
                      titulo: 'Batería sin restricciones',
                      porque: 'Algunos celulares (Xiaomi, Samsung, Huawei...) cierran las apps para ahorrar batería y tu ubicación dejaría de llegar en plena entrega.',
                      estado: _bateria!,
                      textoEstado: 'En Ajustes entra a "Batería" (en Xiaomi se llama "Encendido") y elige "Sin restricciones"',
                      textoBoton: 'Abrir ajustes',
                      recomendado: true,
                      onResolver: () => _resolver(PermisosCelular.abrirAjustesBateria),
                    ),
                  ),
                const SizedBox(height: 20),
                BotonValle(
                  texto: _todoListo ? '¡Todo listo!' : (_obligatoriosListos ? 'Continuar' : 'Lo haré después'),
                  icono: _todoListo ? Icons.check_rounded : null,
                  tipo: _obligatoriosListos ? TipoBoton.principal : TipoBoton.texto,
                  onPressed: () => Navigator.pop(context, _obligatoriosListos),
                ),
              ],
            ),
    );
  }
}

class _TarjetaPermiso extends StatelessWidget {
  const _TarjetaPermiso({
    required this.icono,
    required this.titulo,
    required this.porque,
    required this.estado,
    required this.textoEstado,
    required this.textoBoton,
    required this.onResolver,
    this.recomendado = false,
  });

  final IconData icono;
  final String titulo;
  final String porque;
  final EstadoPermiso estado;
  final String textoEstado;
  final String textoBoton;
  final VoidCallback onResolver;
  final bool recomendado;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final listo = estado == EstadoPermiso.listo;
    final color = listo ? AppTheme.successColor : (recomendado ? AppTheme.warningColor : AppTheme.errorColor);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TarjetaValle(
        colorBorde: listo ? AppTheme.successColor.withValues(alpha: 0.5) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icono, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(titulo, style: tema.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                InsigniaValle(
                  listo ? 'Listo' : (recomendado ? 'Recomendado' : 'Falta'),
                  color: color,
                  icono: listo ? Icons.check_rounded : Icons.priority_high_rounded,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(porque, style: tema.bodyMedium?.copyWith(color: c.textoSuave)),
            if (!listo) ...[
              const SizedBox(height: 8),
              Text(textoEstado, style: tema.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              BotonValle(texto: textoBoton, tipo: TipoBoton.secundario, onPressed: onResolver),
            ],
          ],
        ),
      ),
    );
  }
}
