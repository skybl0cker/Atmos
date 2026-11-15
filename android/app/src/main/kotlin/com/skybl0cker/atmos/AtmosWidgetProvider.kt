package com.skybl0cker.atmos

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

/**
 * The widget's sizes. Each has its own layout; on Android 12+ the launcher
 * picks the biggest one that fits as the widget is resized ([minW] x [minH]
 * in dp), older versions pick in [forSize].
 */
enum class WidgetSize(
    val layout: Int,
    /** Hour slots in the layout (hour0..). */
    val hours: Int,
    /** Day rows in the layout (day0..). */
    val days: Int,
    /** First forecast day shown (tall skips today: its high / low is up top). */
    val dayOffset: Int,
    val dayRain: Boolean,
    val summary: Boolean,
    /** Use the portrait crop of the painting. */
    val tallArt: Boolean,
    val minW: Float,
    val minH: Float,
) {
    SLIM(R.layout.atmos_widget_slim, 0, 0, 0, false, false, false, 110f, 40f),
    SMALL(R.layout.atmos_widget_small, 0, 0, 0, false, false, true, 110f, 110f),
    TALL(R.layout.atmos_widget_tall, 0, 4, 1, false, false, true, 110f, 250f),
    WIDE(R.layout.atmos_widget_wide, 5, 0, 0, false, false, false, 200f, 110f),
    LARGE(R.layout.atmos_widget_large, 5, 5, 0, true, true, true, 200f, 300f);

    companion object {
        /** Android 11 and older: pick from the size the launcher reports. */
        fun forSize(widthDp: Int, heightDp: Int): WidgetSize = when {
            heightDp < 100 -> SLIM
            widthDp < 200 -> if (heightDp >= 250) TALL else SMALL
            heightDp >= 300 -> LARGE
            else -> WIDE
        }
    }
}

/** The looks offered in the style picker. */
enum class WidgetStyle(val key: String, val label: String, val blurb: String) {
    WATERCOLOR("watercolor", "Watercolor", "The app's painting for the weather and time of day"),
    SKY("sky", "Sky", "A soft sky colour that changes with the conditions"),
    AUTO("auto", "Match the app", "Light by day, dark at night"),
    LIGHT("light", "Light", "A white card, like the Weather Today panel"),
    DARK("dark", "Dark", "Deep night purple"),
    GLASS("glass", "Glass", "A tinted, see-through panel"),
    CLEAR("clear", "Transparent", "No background, white text for darker wallpapers"),
    CLEAR_DARK("clear_dark", "Transparent, dark text", "No background, dark text for light wallpapers");

    companion object {
        val DEFAULT = WATERCOLOR
        fun of(key: String?): WidgetStyle = entries.firstOrNull { it.key == key } ?: DEFAULT
    }
}

/** The forecast the app last saved for the widget (lib/services/widget_service.dart). */
class WidgetData(private val o: JSONObject?) {
    val ready: Boolean get() = o != null

    fun s(key: String, fallback: String = ""): String =
        o?.optString(key, "")?.takeIf { it.isNotEmpty() } ?: fallback

    fun list(key: String): List<JSONObject> = try {
        val a = JSONArray(o?.optString(key, "[]") ?: "[]")
        List(a.length()) { a.getJSONObject(it) }
    } catch (e: JSONException) {
        emptyList()
    }

    companion object {
        /**
         * Written by the Dart side through shared_preferences (so the
         * background worker can refresh it too, without the activity).
         */
        fun load(context: Context): WidgetData {
            val raw = context
                .getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getString("flutter.widget_payload", null)
            return WidgetData(
                raw?.let {
                    try {
                        JSONObject(it)
                    } catch (e: JSONException) {
                        null
                    }
                }
            )
        }
    }
}

class AtmosWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { manager.updateAppWidget(it, build(context, manager, it)) }
    }

    /** Resized (Android 11 and older re-pick the layout here). */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        newOptions: Bundle,
    ) {
        manager.updateAppWidget(id, build(context, manager, id))
    }

    override fun onDeleted(context: Context, ids: IntArray) {
        prefs(context).edit().apply {
            ids.forEach { remove("style_$it") }
            apply()
        }
    }

    /** How a style draws: background layers and text / icon colours. */
    private class Look(
        /** Root background drawable; 0 = none. */
        val frame: Int,
        val painting: Boolean,
        val sky: Boolean,
        val text: Int,
        val subtext: Int,
        val rain: Int,
        val darkIcons: Boolean,
    )

    companion object {
        private const val PREFS = "atmos_widget"
        private val DEFAULT_TINT = Color.parseColor("#5C93F2")
        private val INK = Color.parseColor("#1F1A33")

        private val HOUR_IDS = arrayOf(
            intArrayOf(R.id.hour0, R.id.hour0_time, R.id.hour0_icon, R.id.hour0_temp),
            intArrayOf(R.id.hour1, R.id.hour1_time, R.id.hour1_icon, R.id.hour1_temp),
            intArrayOf(R.id.hour2, R.id.hour2_time, R.id.hour2_icon, R.id.hour2_temp),
            intArrayOf(R.id.hour3, R.id.hour3_time, R.id.hour3_icon, R.id.hour3_temp),
            intArrayOf(R.id.hour4, R.id.hour4_time, R.id.hour4_icon, R.id.hour4_temp),
        )

        /** row, name, icon, rain, low, high. Rain only exists in the large layout. */
        private val DAY_IDS = arrayOf(
            intArrayOf(R.id.day0, R.id.day0_name, R.id.day0_icon, R.id.day0_rain, R.id.day0_lo, R.id.day0_hi),
            intArrayOf(R.id.day1, R.id.day1_name, R.id.day1_icon, R.id.day1_rain, R.id.day1_lo, R.id.day1_hi),
            intArrayOf(R.id.day2, R.id.day2_name, R.id.day2_icon, R.id.day2_rain, R.id.day2_lo, R.id.day2_hi),
            intArrayOf(R.id.day3, R.id.day3_name, R.id.day3_icon, R.id.day3_rain, R.id.day3_lo, R.id.day3_hi),
            intArrayOf(R.id.day4, R.id.day4_name, R.id.day4_icon, R.id.day4_rain, R.id.day4_lo, R.id.day4_hi),
        )

        /** The app's painted icons (tool/render_widget_icons.dart): light / dark surface. */
        private val ICONS = mapOf(
            "sun" to (R.drawable.wx_sun_l to R.drawable.wx_sun_d),
            "moon" to (R.drawable.wx_moon_l to R.drawable.wx_moon_d),
            "partly_day" to (R.drawable.wx_partly_day_l to R.drawable.wx_partly_day_d),
            "partly_night" to (R.drawable.wx_partly_night_l to R.drawable.wx_partly_night_d),
            "cloud" to (R.drawable.wx_cloud_l to R.drawable.wx_cloud_d),
            "fog" to (R.drawable.wx_fog_l to R.drawable.wx_fog_d),
            "rain" to (R.drawable.wx_rain_l to R.drawable.wx_rain_d),
            "snow" to (R.drawable.wx_snow_l to R.drawable.wx_snow_d),
            "storm" to (R.drawable.wx_storm_l to R.drawable.wx_storm_d),
        )

        private fun prefs(context: Context) =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        fun allIds(context: Context): IntArray = AppWidgetManager.getInstance(context)
            .getAppWidgetIds(ComponentName(context, AtmosWidgetProvider::class.java))

        /** The style for a widget; new widgets get the one picked last. */
        fun styleFor(context: Context, id: Int): WidgetStyle {
            val p = prefs(context)
            return WidgetStyle.of(p.getString("style_$id", null) ?: p.getString("style_default", null))
        }

        fun setStyle(context: Context, ids: IntArray, style: WidgetStyle) {
            prefs(context).edit().apply {
                ids.forEach { putString("style_$it", style.key) }
                putString("style_default", style.key)
                apply()
            }
            val manager = AppWidgetManager.getInstance(context)
            ids.forEach { manager.updateAppWidget(it, build(context, manager, it)) }
        }

        /** Redraws every widget from the saved forecast (called by the app). */
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            allIds(context).forEach { manager.updateAppWidget(it, build(context, manager, it)) }
        }

        fun build(context: Context, manager: AppWidgetManager, id: Int): RemoteViews {
            val style = styleFor(context, id)
            val data = WidgetData.load(context)
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                RemoteViews(
                    WidgetSize.entries.associate {
                        SizeF(it.minW, it.minH) to views(context, it, style, data)
                    }
                )
            } else {
                val o = manager.getAppWidgetOptions(id)
                // Portrait: width is the minimum, height the maximum.
                val w = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 180)
                val h = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 110)
                views(context, WidgetSize.forSize(w, h), style, data)
            }
        }

        private fun look(style: WidgetStyle, scene: String): Look {
            val white = Color.WHITE
            val onArt = Color.parseColor("#E6FFFFFF")
            val rainOnArt = Color.parseColor("#D6ECFF")
            return when (style) {
                WidgetStyle.WATERCOLOR ->
                    Look(R.drawable.widget_frame, true, false, white, onArt, rainOnArt, false)
                WidgetStyle.SKY ->
                    Look(R.drawable.widget_frame, false, true, white, onArt, rainOnArt, false)
                WidgetStyle.AUTO ->
                    look(if (scene == "night") WidgetStyle.DARK else WidgetStyle.LIGHT, scene)
                WidgetStyle.LIGHT -> Look(
                    R.drawable.widget_frame_light, false, false,
                    INK, Color.parseColor("#7A7596"), Color.parseColor("#3D9BFF"), false,
                )
                WidgetStyle.DARK -> Look(
                    R.drawable.widget_frame_dark, false, false,
                    white, Color.parseColor("#B0A8D6"), Color.parseColor("#7CC0FF"), true,
                )
                WidgetStyle.GLASS -> Look(
                    R.drawable.widget_frame_glass, false, false,
                    white, Color.parseColor("#D0C8F0"), Color.parseColor("#9ACFFF"), true,
                )
                WidgetStyle.CLEAR -> Look(0, false, false, white, onArt, rainOnArt, false)
                WidgetStyle.CLEAR_DARK -> Look(
                    0, false, false,
                    INK, Color.parseColor("#4A4560"), Color.parseColor("#1F7AE0"), false,
                )
            }
        }

        private fun sceneArt(scene: String, tall: Boolean): Int = when (scene) {
            "night" -> if (tall) R.drawable.widget_scene_night_tall else R.drawable.widget_scene_night_wide
            "rain" -> if (tall) R.drawable.widget_scene_rain_tall else R.drawable.widget_scene_rain_wide
            else -> if (tall) R.drawable.widget_scene_day_tall else R.drawable.widget_scene_day_wide
        }

        private fun iconRes(key: String, dark: Boolean): Int {
            val pair = ICONS[key] ?: ICONS.getValue("cloud")
            return if (dark) pair.second else pair.first
        }

        private fun tint(data: WidgetData): Int = try {
            Color.parseColor(data.s("tint", "#5C93F2"))
        } catch (e: IllegalArgumentException) {
            DEFAULT_TINT
        }

        /**
         * One layout drawn in one style. Every property is set every time:
         * launchers may re-apply an update onto the previous views, so
         * nothing can be left to the XML defaults. [launch] = false for the
         * style picker's previews (they shouldn't open the app).
         */
        fun views(
            context: Context,
            size: WidgetSize,
            style: WidgetStyle,
            data: WidgetData = WidgetData.load(context),
            launch: Boolean = true,
        ): RemoteViews {
            val v = RemoteViews(context.packageName, size.layout)
            val scene = data.s("scene", "day")
            val look = look(style, scene)
            fun shown(on: Boolean) = if (on) View.VISIBLE else View.GONE
            fun text(id: Int, value: String, color: Int) {
                v.setTextViewText(id, value)
                v.setTextColor(id, color)
            }

            // Background layers.
            v.setInt(R.id.root, "setBackgroundResource", look.frame)
            v.setViewVisibility(R.id.bg, shown(look.painting))
            v.setViewVisibility(R.id.wash, shown(look.painting))
            v.setViewVisibility(R.id.fill, shown(look.sky))
            v.setViewVisibility(R.id.shade, shown(look.sky))
            val tint = tint(data)
            if (look.painting) {
                v.setImageViewResource(R.id.bg, sceneArt(scene, size.tallArt))
                v.setInt(R.id.wash, "setColorFilter", tint)
            }
            if (look.sky) v.setInt(R.id.fill, "setColorFilter", tint)

            // Now.
            val place = data.s("place", "Atmos")
            val temp = data.s("temp", "--°")
            val condition = if (data.ready) data.s("condition") else "Open Atmos"
            text(R.id.place, place, if (size == WidgetSize.SLIM) look.subtext else look.text)
            text(R.id.temp, temp, look.text)
            text(R.id.condition, condition, look.text)
            val hilo = if (!data.ready) {
                "to load the weather"
            } else if (size == WidgetSize.LARGE) {
                listOf(data.s("hilo"), data.s("feels")).filter { it.isNotEmpty() }.joinToString("  ·  ")
            } else {
                data.s("hilo")
            }
            text(R.id.hilo, hilo, look.subtext)
            v.setImageViewResource(R.id.icon, iconRes(data.s("icon", "sun"), look.darkIcons))
            v.setContentDescription(R.id.root, "$place, $temp, $condition")
            if (size.summary) {
                text(R.id.summary, data.s("summary"), look.subtext)
                v.setViewVisibility(R.id.summary, shown(data.s("summary").isNotEmpty()))
            }

            // Next hours.
            if (size.hours > 0) {
                val hours = data.list("hours")
                v.setViewVisibility(R.id.hours, shown(hours.isNotEmpty()))
                for (i in 0 until size.hours) {
                    val ids = HOUR_IDS[i]
                    val h = hours.getOrNull(i)
                    v.setViewVisibility(ids[0], if (h == null) View.INVISIBLE else View.VISIBLE)
                    if (h == null) continue
                    text(ids[1], h.optString("t"), look.subtext)
                    v.setImageViewResource(ids[2], iconRes(h.optString("i"), look.darkIcons))
                    text(ids[3], h.optString("v"), look.text)
                }
            }

            // Days.
            if (size.days > 0) {
                val days = data.list("days")
                v.setViewVisibility(R.id.days, shown(days.size > size.dayOffset))
                for (i in 0 until size.days) {
                    val ids = DAY_IDS[i]
                    val d = days.getOrNull(i + size.dayOffset)
                    v.setViewVisibility(ids[0], if (d == null) View.INVISIBLE else View.VISIBLE)
                    if (d == null) continue
                    text(ids[1], d.optString("d"), look.text)
                    v.setImageViewResource(ids[2], iconRes(d.optString("i"), look.darkIcons))
                    if (size.dayRain) text(ids[3], d.optString("p"), look.rain)
                    text(ids[4], d.optString("l"), look.subtext)
                    text(ids[5], d.optString("h"), look.text)
                }
            }

            if (launch) {
                context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
                    v.setOnClickPendingIntent(
                        R.id.root,
                        PendingIntent.getActivity(
                            context, 0, it,
                            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                        ),
                    )
                }
            }
            return v
        }
    }
}
