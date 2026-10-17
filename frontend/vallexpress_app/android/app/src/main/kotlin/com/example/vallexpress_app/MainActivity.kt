package com.example.vallexpress_app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Canal "vallexpress/bateria" (lib/services/permisos_celular.dart): saber si Android puede cerrar la app para
    // ahorrar batería y abrir sus ajustes. El repartidor necesita "Sin restricciones" para que su GPS no se corte
    // (Xiaomi, Samsung y otros cierran apps aunque tengan una notificación fija).
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vallexpress/bateria").setMethodCallHandler { llamada, resultado ->
            when (llamada.method) {
                "sinRestricciones" -> {
                    val energia = getSystemService(Context.POWER_SERVICE) as PowerManager
                    resultado.success(energia.isIgnoringBatteryOptimizations(packageName))
                }
                "abrirAjustes" -> {
                    // La pantalla de la app en Ajustes: ahí está "Batería" / "Ahorro de batería" en todas las marcas
                    val intento = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intento)
                    resultado.success(true)
                }
                else -> resultado.notImplemented()
            }
        }
    }
}
