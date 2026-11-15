package com.skybl0cker.atmos

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "com.skybl0cker.atmos/widget"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // The forecast itself is saved by the Dart side
                    // (shared_preferences "widget_payload"); this redraws.
                    "updateWidget" -> {
                        AtmosWidgetProvider.updateAll(this)
                        result.success(null)
                    }
                    "openWidgetStyles" -> {
                        startActivity(Intent(this, AtmosWidgetConfigureActivity::class.java))
                        result.success(null)
                    }
                    "widgetCount" -> result.success(AtmosWidgetProvider.allIds(this).size)
                    else -> result.notImplemented()
                }
            }
    }
}
