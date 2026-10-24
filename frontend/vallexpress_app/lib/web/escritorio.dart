import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/tema_provider.dart';
import 'aviso_notificaciones.dart';
import '../widgets/ui/animaciones.dart';

/// En la web con pantalla ancha (computador o tablet de lado) la app usa el diseño de escritorio: menú lateral o
/// barra superior en vez de la barra de abajo, y el contenido centrado con un ancho cómodo de leer.
/// En el celular (app o navegador del celular) todo sigue igual.
const double anchoEscritorio = 900;

/// Aire a los lados en el computador: la web usa todo el ancho de la pantalla
const double margenWeb = 48;

bool esEscritorio(BuildContext context) => kIsWeb && MediaQuery.sizeOf(context).width >= anchoEscritorio;

/// Una pestaña de la navegación principal
class Destino {
  const Destino({required this.icono, required this.iconoActivo, required this.texto, this.insignia = 0, this.colorInsignia});

  final IconData icono;
  final IconData iconoActivo;
  final String texto;

  /// Número en el globito (0 = sin globito)
  final int insignia;
  final Color? colorInsignia;
}

/// Logo de ValleXpress con el nombre ("Valle" + "Xpress" en verde)
class LogoValle extends StatelessWidget {
  const LogoValle({super.key, this.tamano = 40, this.conNombre = true});

  final double tamano;
  final bool conNombre;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(tamano * 0.28),
          child: Image.asset('assets/images/logo.png', width: tamano, height: tamano, fit: BoxFit.cover),
        ),
        if (conNombre) ...[
          SizedBox(width: tamano * 0.25),
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Valle'),
              TextSpan(text: 'Xpress', style: TextStyle(color: c.primario)),
            ]),
            style: TextStyle(fontSize: tamano * 0.55, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: c.texto),
          ),
        ],
      ],
    );
  }
}

/// Navegación principal de un rol. En el celular: barra de abajo. En el computador:
///   * [lateral] (negocio, administrador): menú a la izquierda con logo, [cabeceraLateral] y las pestañas
///   * superior (cliente): barra arriba con logo, pestañas y [accionesSuperiores] (avisos, carrito)
class PestanasAdaptables extends StatelessWidget {
  const PestanasAdaptables({
    super.key,
    required this.indice,
    required this.onCambiar,
    required this.destinos,
    required this.paginas,
    this.lateral = true,
    this.cabeceraLateral,
    this.accionesSuperiores = const [],
    this.sobreLaBarra,
    this.rutas,
  });

  /// Dirección de cada pestaña en la web (/inicio, /pedidos, /perfil...): la barra del navegador la muestra y al
  /// recargar o abrir un enlace se vuelve a esa pestaña
  final List<String>? rutas;

  static String? _rutaAlAbrir = kIsWeb ? Uri.base.path : null;
  static String? _ultimaRuta;

  /// Pestaña con la que arranca un inicio: la de la dirección con que se abrió la web (una sola vez)
  static int indiceInicial(List<String> rutas) {
    final ruta = _rutaAlAbrir;
    _rutaAlAbrir = null;
    final i = ruta == null ? -1 : rutas.indexOf(ruta);
    return i < 0 ? 0 : i;
  }

  void _anunciarRuta() {
    if (!kIsWeb || rutas == null || indice >= rutas!.length) return;
    final ruta = rutas![indice];
    if (ruta == _ultimaRuta) return;
    _ultimaRuta = ruta;
    WidgetsBinding.instance.addPostFrameCallback((_) => SystemNavigator.routeInformationUpdated(uri: Uri(path: ruta), replace: true));
  }

  final int indice;
  final ValueChanged<int> onCambiar;
  final List<Destino> destinos;
  final List<Widget> paginas;
  final bool lateral;
  final Widget? cabeceraLateral;
  final List<Widget> accionesSuperiores;

  /// Solo en el celular: algo encima de la barra de abajo (la barra del carrito del cliente)
  final Widget? sobreLaBarra;

  Widget _icono(Destino d, bool activo) {
    final icono = Icon(activo ? d.iconoActivo : d.icono);
    if (d.insignia <= 0) return icono;
    return Badge(backgroundColor: d.colorInsignia, label: Text(d.insignia > 99 ? '99+' : '${d.insignia}'), child: icono);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    _anunciarRuta();
    final contenido = PestanasAnimadas(indice: indice, children: paginas);

    if (!esEscritorio(context)) {
      return Scaffold(
        body: Column(children: [const AvisoNotificaciones(), Expanded(child: contenido)]),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ?sobreLaBarra,
            NavigationBar(
              selectedIndex: indice,
              backgroundColor: c.tarjeta,
              indicatorColor: c.primario.withValues(alpha: 0.18),
              onDestinationSelected: onCambiar,
              destinations: [
                for (final d in destinos) NavigationDestination(icon: _icono(d, false), selectedIcon: _icono(d, true), label: d.texto),
              ],
            ),
          ],
        ),
      );
    }

    // Lo que se abre desde una pestaña (detalle, carrito, configuración...) aparece en el área de contenido: la
    // barra de arriba o el menú lateral siguen a la vista, como en una página web
    final interno = _NavegadorInterno(indice: indice, alCambiarPestana: onCambiar, child: contenido);

    if (!lateral) {
      return Scaffold(
        backgroundColor: c.fondo,
        body: Column(
          children: [
            _BarraSuperior(indice: indice, onCambiar: onCambiar, destinos: destinos, acciones: accionesSuperiores, icono: _icono),
            const AvisoNotificaciones(),
            Expanded(child: interno),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.fondo,
      body: Row(
        children: [
          _MenuLateral(indice: indice, onCambiar: onCambiar, destinos: destinos, cabecera: cabeceraLateral),
          Expanded(child: Column(children: [const AvisoNotificaciones(), Expanded(child: interno)])),
        ],
      ),
    );
  }
}

/// Navegador del área de contenido (computador). Al tocar una pestaña se cierra lo que estaba abierto encima.
class _NavegadorInterno extends StatefulWidget {
  const _NavegadorInterno({required this.indice, required this.alCambiarPestana, required this.child});

  final int indice;
  final ValueChanged<int> alCambiarPestana;
  final Widget child;

  @override
  State<_NavegadorInterno> createState() => _NavegadorInternoState();
}

class _NavegadorInternoState extends State<_NavegadorInterno> {
  final _llave = GlobalKey<NavigatorState>();
  static GlobalKey<NavigatorState>? _actual;

  @override
  void initState() {
    super.initState();
    _actual = _llave;
  }

  @override
  void dispose() {
    if (_actual == _llave) _actual = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _NavegadorInterno vieja) {
    super.didUpdateWidget(vieja);
    if (vieja.indice != widget.indice) _llave.currentState?.popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return NavigatorPopHandler(
      // El botón "atrás" (del navegador o del teclado) cierra primero lo abierto dentro de la página
      onPopWithResult: (_) => _llave.currentState?.maybePop(),
      child: Navigator(
        key: _llave,
        pages: [MaterialPage(key: const ValueKey('pestanas'), child: widget.child)],
        onDidRemovePage: (_) {},
      ),
    );
  }
}

class _MenuLateral extends StatelessWidget {
  const _MenuLateral({required this.indice, required this.onCambiar, required this.destinos, this.cabecera});

  final int indice;
  final ValueChanged<int> onCambiar;
  final List<Destino> destinos;
  final Widget? cabecera;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    return Container(
      width: 264,
      decoration: BoxDecoration(color: c.tarjeta, border: Border(right: BorderSide(color: c.borde))),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
          children: [
            const Padding(padding: EdgeInsets.only(left: 8, bottom: 24), child: LogoValle()),
            if (cabecera != null) ...[cabecera!, const SizedBox(height: 16)],
            const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.only(left: 4, bottom: 12), child: BotonTema(conTexto: true))),
            for (var i = 0; i < destinos.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Material(
                  color: i == indice ? c.primario.withValues(alpha: 0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onCambiar(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Icon(i == indice ? destinos[i].iconoActivo : destinos[i].icono, size: 22, color: i == indice ? c.primario : c.textoSuave),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              destinos[i].texto,
                              style: tema.titleSmall?.copyWith(
                                fontWeight: i == indice ? FontWeight.w800 : FontWeight.w600,
                                color: i == indice ? c.primario : c.texto,
                              ),
                            ),
                          ),
                          if (destinos[i].insignia > 0)
                            Container(
                              constraints: const BoxConstraints(minWidth: 24),
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(color: destinos[i].colorInsignia ?? AppTheme.accentColor, borderRadius: BorderRadius.circular(12)),
                              child: Text(
                                destinos[i].insignia > 99 ? '99+' : '${destinos[i].insignia}',
                                textAlign: TextAlign.center,
                                style: tema.labelSmall?.copyWith(fontWeight: FontWeight.w800, color: const Color(0xFF15201A)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BarraSuperior extends StatelessWidget {
  const _BarraSuperior({required this.indice, required this.onCambiar, required this.destinos, required this.acciones, required this.icono});

  final int indice;
  final ValueChanged<int> onCambiar;
  final List<Destino> destinos;
  final List<Widget> acciones;
  final Widget Function(Destino, bool) icono;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(color: c.tarjeta, border: Border(bottom: BorderSide(color: c.borde))),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: double.infinity),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: margenWeb, vertical: 12),
            child: Row(
              children: [
                InkWell(borderRadius: BorderRadius.circular(12), onTap: () => onCambiar(0), child: const LogoValle()),
                const SizedBox(width: 32),
                for (var i = 0; i < destinos.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: TextButton.icon(
                      onPressed: () => onCambiar(i),
                      style: TextButton.styleFrom(
                        foregroundColor: i == indice ? c.primario : c.texto,
                        backgroundColor: i == indice ? c.primario.withValues(alpha: 0.10) : null,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: icono(destinos[i], i == indice),
                      label: Text(destinos[i].texto, style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: i == indice ? c.primario : c.texto)),
                    ),
                  ),
                const Spacer(),
                const BotonTema(),
                const SizedBox(width: 4),
                ...acciones,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Centra el contenido con un ancho máximo en el computador (en el celular no hace nada)
class AnchoMaximo extends StatelessWidget {
  const AnchoMaximo({super.key, required this.child, this.ancho = 840});

  final Widget child;
  final double ancho;

  @override
  Widget build(BuildContext context) {
    if (!esEscritorio(context)) return child;
    return Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: BoxConstraints(maxWidth: ancho), child: child));
  }
}

/// Hoja de opciones: en el celular sube desde abajo; en el computador es una ventana centrada
Future<T?> mostrarHoja<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool showDragHandle = false,
  bool useSafeArea = false,
  bool isDismissible = true,
  Color? backgroundColor,
}) {
  if (!esEscritorio(context)) {
    return showModalBottomSheet<T>(
      context: context,
      builder: builder,
      isScrollControlled: isScrollControlled,
      showDragHandle: showDragHandle,
      useSafeArea: useSafeArea,
      isDismissible: isDismissible,
      backgroundColor: backgroundColor,
    );
  }
  return showDialog<T>(
    context: context,
    barrierDismissible: isDismissible,
    builder: (ctx) => Dialog(
      backgroundColor: backgroundColor,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
        child: Padding(padding: const EdgeInsets.only(top: 20), child: Builder(builder: builder)),
      ),
    ),
  );
}

/// Contexto para abrir pantallas DENTRO del área de contenido del computador (desde la barra de arriba, que está fuera
/// de ella: carrito, avisos). En el celular, o si no hay área de contenido, devuelve el mismo [context].
BuildContext contextoDeContenido(BuildContext context) {
  if (!esEscritorio(context)) return context;
  return _NavegadorInternoState._actual?.currentState?.overlay?.context ?? context;
}

/// Botón para cambiar entre modo claro y oscuro (en el computador, en la barra de arriba o en el menú lateral)
class BotonTema extends StatelessWidget {
  const BotonTema({super.key, this.conTexto = false});

  final bool conTexto;

  @override
  Widget build(BuildContext context) {
    final tema = context.watch<TemaProvider>();
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    void cambiar() => tema.cambiar(oscuro ? ThemeMode.light : ThemeMode.dark);
    final icono = Icon(oscuro ? Icons.light_mode_rounded : Icons.dark_mode_rounded);
    if (conTexto) {
      return TextButton.icon(
        onPressed: cambiar,
        style: TextButton.styleFrom(foregroundColor: context.colores.textoSuave),
        icon: icono,
        label: Text(oscuro ? 'Modo claro' : 'Modo oscuro'),
      );
    }
    return IconButton(tooltip: oscuro ? 'Modo claro' : 'Modo oscuro', onPressed: cambiar, icon: icono);
  }
}
