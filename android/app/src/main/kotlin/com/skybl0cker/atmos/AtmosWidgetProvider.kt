package com.skybl0cker.atmos

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class AtmosWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs = context.getSharedPreferences("atmos_widget", Context.MODE_PRIVATE)
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.atmos_widget).apply {
                setTextViewText(R.id.widget_place, prefs.getString("place", "Atmos"))
                setTextViewText(R.id.widget_temp, prefs.getString("temp", "--°"))
                setTextViewText(R.id.widget_icon, prefs.getString("icon", "☀️"))
                setTextViewText(R.id.widget_condition, prefs.getString("condition", "--"))
                setTextViewText(R.id.widget_hilo, prefs.getString("hilo", ""))

                val launchIntent = context.packageManager
                    .getLaunchIntentForPackage(context.packageName)
                val pending = android.app.PendingIntent.getActivity(
                    context, 0, launchIntent,
                    android.app.PendingIntent.FLAG_IMMUTABLE or
                        android.app.PendingIntent.FLAG_UPDATE_CURRENT
                )
                setOnClickPendingIntent(R.id.widget_place, pending)
                setOnClickPendingIntent(R.id.widget_temp, pending)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    companion object {
        fun pushUpdate(context: Context, data: Map<String, String>) {
            val prefs = context.getSharedPreferences("atmos_widget", Context.MODE_PRIVATE)
            prefs.edit().apply {
                data.forEach { (k, v) -> putString(k, v) }
                apply()
            }
            val intent = Intent(context, AtmosWidgetProvider::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                val ids = AppWidgetManager.getInstance(context)
                    .getAppWidgetIds(ComponentName(context, AtmosWidgetProvider::class.java))
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            }
            context.sendBroadcast(intent)
        }
    }
}
