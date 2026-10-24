import 'package:web/web.dart' as web;

web.AudioContext? _audio;

/// Dos tonos cortos ("ding-ding") generados por el navegador; no necesita archivos de sonido.
/// El navegador solo deja sonar después de que la persona tocó la página alguna vez (siempre pasa: inició sesión).
void ding() {
  try {
    final audio = _audio ??= web.AudioContext();
    if (audio.state == 'suspended') audio.resume();
    final ahora = audio.currentTime;
    for (final (i, frecuencia) in [880.0, 1320.0].indexed) {
      final inicio = ahora + i * 0.18;
      final tono = audio.createOscillator()
        ..type = 'sine'
        ..frequency.value = frecuencia;
      final volumen = audio.createGain();
      volumen.gain
        ..setValueAtTime(0.0001, inicio)
        ..exponentialRampToValueAtTime(0.35, inicio + 0.02)
        ..exponentialRampToValueAtTime(0.0001, inicio + 0.25);
      tono.connect(volumen);
      volumen.connect(audio.destination);
      tono.start(inicio);
      tono.stop(inicio + 0.3);
    }
  } catch (_) {
    // navegador sin audio: queda el aviso en pantalla
  }
}
