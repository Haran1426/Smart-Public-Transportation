package com.example.smart_public_transportation

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class WidgetSettingsActivity : FlutterActivity() {
    private val widgetId get() = intent.getIntExtra(
        AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID,
    )

    private fun widgetResult() = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)

    private fun ownsWidget(): Boolean =
        AppWidgetManager.getInstance(this).getAppWidgetInfo(widgetId)?.provider ==
            ComponentName(this, TransitWidget::class.java)

    override fun getInitialRoute() = "/widget-settings"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED, widgetResult())
        if (!ownsWidget()) finish()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val store = TransitStore(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "transit/widget_settings")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "theme" -> result.success(store.theme())
                    "openApp" -> {
                        startActivity(Intent(this, MainActivity::class.java))
                        result.success(null)
                        finish()
                    }
                    "load" -> background(result) {
                        mapOf(
                            "favoriteId" to store.selection(widgetId),
                            "favorites" to store.favorites().map(Favorite::fields),
                            "display" to store.display(widgetId).fields(),
                        )
                    }
                    "save" -> background(result, finishAfter = true) {
                        val favoriteId = call.argument<String>("favoriteId")
                        val favorite = store.favorites().first { it.id == favoriteId }
                        val display = WidgetDisplay.from(call.argument<Map<*, *>>("display"))
                        TransitWidget.setup(applicationContext, widgetId, favorite, display)
                        null
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun background(
        result: MethodChannel.Result,
        finishAfter: Boolean = false,
        operation: () -> Any?,
    ) {
        TransitWidget.executor.execute {
            try {
                check(ownsWidget())
                val response = operation()
                runOnUiThread {
                    result.success(response)
                    if (finishAfter && !isFinishing) {
                        setResult(RESULT_OK, widgetResult())
                        finish()
                    }
                }
            } catch (_: Exception) {
                runOnUiThread { result.error("widget_settings", "위젯을 설정하지 못했어요.", null) }
            }
        }
    }
}
