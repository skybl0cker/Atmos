package com.skybl0cker.atmos

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.content.res.Resources
import android.graphics.Color
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.util.TypedValue
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.WindowInsets
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * Style picker for the home-screen widget. Opens when a widget is added
 * (Android 11 and older), from the widget's long-press "widget settings"
 * (Android 12+), or from the app's menu (then it restyles every widget).
 * Each choice shows a live preview drawn with the real widget layout and
 * the latest forecast.
 */
class AtmosWidgetConfigureActivity : Activity() {
    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    private val ink = Color.parseColor("#1F1A33")
    private val sub = Color.parseColor("#7A7596")

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        widgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        // Backing out of a brand-new widget's picker cancels adding it.
        setResult(RESULT_CANCELED, result())
        setContentView(content())
    }

    private fun result() = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)

    private fun choose(style: WidgetStyle) {
        val ids = if (widgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
            intArrayOf(widgetId)
        } else {
            AtmosWidgetProvider.allIds(this)
        }
        AtmosWidgetProvider.setStyle(this, ids, style)
        setResult(RESULT_OK, result())
        finish()
    }

    private fun dp(v: Int): Int = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics,
    ).toInt()

    private fun font(res: Int, fallback: Typeface): Typeface =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                resources.getFont(res)
            } catch (e: Resources.NotFoundException) {
                fallback
            }
        } else {
            fallback
        }

    private fun label(text: String, sp: Float, color: Int, medium: Boolean = false) =
        TextView(this).apply {
            this.text = text
            setTextColor(color)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, sp)
            typeface = if (medium) {
                font(R.font.poppins_medium, Typeface.DEFAULT_BOLD)
            } else {
                font(R.font.poppins_regular, Typeface.DEFAULT)
            }
        }

    private fun content(): View {
        val current = AtmosWidgetProvider.styleFor(this, widgetId)
        val data = WidgetData.load(this)
        val list = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(24), dp(20), dp(28))
        }
        list.addView(label(getString(R.string.widget_config_title), 26f, ink, medium = true))
        list.addView(
            label(
                "Pick a look. Previews use your latest forecast. Resize the widget " +
                    "on your home screen to show more or less.",
                14f, sub,
            ).apply { setPadding(0, dp(6), 0, dp(18)) }
        )
        for (style in WidgetStyle.entries) list.addView(card(style, style == current, data))

        return ScrollView(this).apply {
            clipToPadding = false
            addView(list)
            // Android 15+ draws behind the status and navigation bars.
            setOnApplyWindowInsetsListener { view, insets ->
                val (top, bottom) = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    val bars = insets.getInsets(WindowInsets.Type.systemBars())
                    bars.top to bars.bottom
                } else {
                    @Suppress("DEPRECATION")
                    insets.systemWindowInsetTop to insets.systemWindowInsetBottom
                }
                view.setPadding(0, top, 0, bottom)
                insets
            }
        }
    }

    private fun card(style: WidgetStyle, selected: Boolean, data: WidgetData): View {
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundResource(
                if (selected) R.drawable.widget_config_card_selected else R.drawable.widget_config_card
            )
            setPadding(dp(12), dp(12), dp(12), dp(14))
            isClickable = true
            isFocusable = true
            contentDescription = style.label + if (selected) ", current style" else ""
            setOnClickListener { choose(style) }
            layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                bottomMargin = dp(14)
            }
        }

        // A patch of "home screen" so the transparent and glass looks read
        // the way they will on a wallpaper.
        val stage = FrameLayout(this).apply {
            setBackgroundResource(
                if (style == WidgetStyle.CLEAR_DARK) {
                    R.drawable.widget_config_wallpaper_light
                } else {
                    R.drawable.widget_config_wallpaper
                }
            )
            setPadding(dp(14), dp(14), dp(14), dp(14))
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        }
        val preview = try {
            AtmosWidgetProvider.views(this, WidgetSize.WIDE, style, data, launch = false)
                .apply(this, stage)
                .apply { isClickable = false }
        } catch (e: Exception) {
            // A preview that can't be drawn shouldn't stop the picker.
            label(style.label, 16f, Color.WHITE, medium = true)
        }
        stage.addView(preview, FrameLayout.LayoutParams(MATCH_PARENT, dp(150)))
        card.addView(stage, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        card.addView(
            label(style.label + if (selected) "  ✓" else "", 16f, ink, medium = true)
                .apply { setPadding(dp(4), dp(12), dp(4), 0) }
        )
        card.addView(label(style.blurb, 13f, sub).apply { setPadding(dp(4), dp(2), dp(4), 0) })
        return card
    }
}
