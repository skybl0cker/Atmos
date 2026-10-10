package com.skybl0cker.atmos

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "com.skybl0cker.atmos/widget"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                if (call.method == "updateWidget") {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, String> ?: emptyMap()
                    AtmosWidgetProvider.pushUpdate(this, args)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
