package com.skybl0cker.atmos

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class AtmosWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.atmos_widget).apply {
                setTextViewText(R.id.widget_place,
                    widgetData.getString("place", "Atmos"))
                setTextViewText(R.id.widget_temp,
                    widgetData.getString("temp", "--°"))
                setTextViewText(R.id.widget_icon,
                    widgetData.getString("icon", "☀"))
                setTextViewText(R.id.widget_condition,
                    widgetData.getString("condition", "--"))
                setTextViewText(R.id.widget_hilo,
                    widgetData.getString("hilo", ""))

                val launchIntent =
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
                setOnClickPendingIntent(R.id.widget_place, launchIntent)
                setOnClickPendingIntent(R.id.widget_temp, launchIntent)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
