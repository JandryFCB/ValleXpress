import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/theme.dart';
import '../../widgets/ui/ui.dart';

/// Una página del tutorial de bienvenida
class _Pagina {
  const _Pagina(this.icono, this.color, this.titulo, this.texto, [this.puntos = const []]);

  final IconData icono;
  final Color color;
  final String titulo;
  final String texto;
  final List<String> puntos;
}

/// Tutorial de bienvenida: unas pocas páginas con lo que cada perfil puede hacer en la app. Se muestra la primera
/// vez que se entra con ese perfil en el celular y se puede volver a ver desde Configuración.
class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key, required this.rol, required this.alTerminar});

  final String rol;
  final VoidCallback alTerminar;

  static String _clave(String rol) => 'tutorial_visto_v1_$rol';

  /// ¿Ya vio el tutorial de este perfil en este celular?
  static Future<bool> visto(String rol) async => (await SharedPreferences.getInstance()).getBool(_clave(rol)) ?? false;

  static Future<void> marcarVisto(String rol) async => (await SharedPreferences.getInstance()).setBool(_clave(rol), true);

  /// Abrirlo de nuevo (desde Configuración)
  static Future<void> abrir(BuildContext context, String rol) => Navigator.push(
        context,
        MaterialPageRoute(builder: (ctx) => TutorialScreen(rol: rol, alTerminar: () => Navigator.pop(ctx))),
      );

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final _paginas = PageController();
  int _actual = 0;

  List<_Pagina> get _contenido => switch (widget.rol) {
        'vendedor' => const [
            _Pagina(Icons.storefront_rounded, AppTheme.vendedorColor, '¡Bienvenido a ValleXpress!', 'Vende en línea a los clientes de Yantzaza. Esto es lo que puedes hacer:'),
            _Pagina(Icons.edit_note_rounded, AppTheme.infoColor, 'Arma tu negocio', 'En "Mi negocio" deja todo listo para vender.', [
              'Ubicación del local, horario, logo y portada',
              'Tus productos con foto, precio y stock',
              'Abre o cierra tu negocio con un toque',
            ]),
            _Pagina(Icons.notifications_active_rounded, AppTheme.warningColor, 'Recibe pedidos al instante', 'Cada pedido suena en tu celular, aunque la app esté cerrada.', [
              'Acéptalo o recházalo a tiempo (si no respondes, se cancela solo)',
              'Márcalo "Listo" y un repartidor lo recoge',
              'Sigue al repartidor en el mapa',
            ]),
            _Pagina(Icons.account_balance_wallet_rounded, AppTheme.accentColor, 'Tus cuentas, claras', 'En "Mis cuentas" ves lo que vendiste cada semana y la comisión de ValleXpress.', [
              'Paga la comisión por transferencia',
              'Sube la foto del comprobante desde la app',
              'Si una semana se vence sin pagar, dejas de recibir pedidos',
            ]),
          ],
        'repartidor' => const [
            _Pagina(Icons.two_wheeler_rounded, AppTheme.repartidorColor, '¡Bienvenido a ValleXpress!', 'Gana dinero haciendo entregas en Yantzaza, cuando tú quieras.'),
            _Pagina(Icons.verified_user_rounded, AppTheme.infoColor, 'Primero, tu aprobación', 'Para empezar verificamos tu identidad y tu vehículo.', [
              'Sube las fotos de tu cédula y una selfie con ella',
              'Si tu vehículo lleva placa: licencia y matrícula',
              'Te avisamos apenas te aprobemos',
            ]),
            _Pagina(Icons.power_settings_new_rounded, AppTheme.successColor, 'Conéctate y entrega', 'Ponte "En línea" para ver los pedidos listos para recoger.', [
              'Acepta el pedido que te convenga',
              'Recógelo en el local y llévalo al cliente',
              'Marca cada paso en la app (recogido, entregado)',
            ]),
            _Pagina(Icons.payments_rounded, AppTheme.accentColor, 'Tu dinero', 'El cliente paga en efectivo al recibir.', [
              'El costo de envío es 100 % tuyo',
              'El valor de los productos es del negocio',
              'Tu ubicación se comparte solo mientras estás en línea',
            ]),
          ],
        'administrador' => const [
            _Pagina(Icons.admin_panel_settings_rounded, AppTheme.infoColor, 'Panel de ValleXpress', 'Desde aquí manejas toda la plataforma.'),
            _Pagina(Icons.insights_rounded, AppTheme.successColor, 'Resumen', 'Las cifras del día. Toca cualquier tarjeta para ver el detalle: pedidos, ventas, ganancias, envíos y repartidores en línea.'),
            _Pagina(Icons.fact_check_rounded, AppTheme.warningColor, 'Gestión', 'Aprueba negocios y repartidores (revisa sus documentos), atiende comprobantes de pago y administra usuarios y pedidos.'),
            _Pagina(Icons.tune_rounded, AppTheme.accentColor, 'Configuración', 'Tarifas y comisión, zona de servicio, cobros a negocios, perfiles y permisos, y los términos y la privacidad.'),
          ],
        _ => const [
            _Pagina(Icons.shopping_bag_rounded, AppTheme.successColor, '¡Bienvenido a ValleXpress!', 'Pide de los negocios de Yantzaza y recíbelo en tu puerta.'),
            _Pagina(Icons.storefront_rounded, AppTheme.infoColor, 'Elige y pide', 'Explora los negocios abiertos, arma tu carrito y confirma.', [
              'Guarda tus direcciones para pedir más rápido',
              'El costo de envío lo ves antes de confirmar',
              'Puedes cancelar mientras el negocio no lo acepte',
            ]),
            _Pagina(Icons.delivery_dining_rounded, AppTheme.repartidorColor, 'Síguelo en vivo', 'Te avisamos cuando tu pedido se confirma, sale y está por llegar.', [
              'Mira al repartidor en el mapa',
              'Llámalo si lo necesitas',
            ]),
            _Pagina(Icons.payments_rounded, AppTheme.accentColor, 'Paga al recibir', 'Por ahora el pago es en efectivo al repartidor. Al terminar, califica al negocio y al repartidor.'),
          ],
      };

  Future<void> _terminar() async {
    await TutorialScreen.marcarVisto(widget.rol);
    HapticFeedback.lightImpact();
    widget.alTerminar();
  }

  @override
  void dispose() {
    _paginas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final c = context.colores;
    final paginas = _contenido;
    final ultima = _actual == paginas.length - 1;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (hecho, _) {
        if (!hecho) _terminar();
      },
      child: FondoValle(
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: TextButton(onPressed: _terminar, child: Text(ultima ? '' : 'Saltar')),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _paginas,
                  itemCount: paginas.length,
                  onPageChanged: (i) => setState(() => _actual = i),
                  itemBuilder: (_, i) {
                    final p = paginas[i];
                    // Centrado en la pantalla; si el texto no cabe (letra grande), se desplaza
                    return LayoutBuilder(
                      builder: (_, caja) => SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                      child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: caja.maxHeight - 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: p.color.withValues(alpha: 0.14)),
                            child: Icon(p.icono, size: 68, color: p.color),
                          ),
                          const SizedBox(height: 32),
                          Text(p.titulo, textAlign: TextAlign.center, style: tema.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 12),
                          Text(p.texto, textAlign: TextAlign.center, style: tema.bodyLarge?.copyWith(color: c.textoSuave)),
                          if (p.puntos.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            for (final punto in p.puntos)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.check_circle_rounded, size: 20, color: p.color),
                                    const SizedBox(width: 10),
                                    Expanded(child: Text(punto, style: tema.bodyMedium)),
                                  ],
                                ),
                              ),
                          ],
                        ],
                      ),
                      ),
                      ),
                    );
                  },
                ),
              ),
              // Puntos de avance
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < paginas.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _actual ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(color: i == _actual ? c.primario : c.borde, borderRadius: BorderRadius.circular(8)),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: BotonValle(
                  texto: ultima ? 'Empezar' : 'Siguiente',
                  icono: ultima ? Icons.check_rounded : Icons.arrow_forward_rounded,
                  onPressed: ultima ? _terminar : () => _paginas.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
