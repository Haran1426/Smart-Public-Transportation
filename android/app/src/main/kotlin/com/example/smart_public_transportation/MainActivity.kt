package com.example.smart_public_transportation

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val store = TransitStore(applicationContext)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "transit/transport")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "load" -> background(result) {
                    mapOf(
                        "favorites" to store.favorites().map(Favorite::fields),
                    )
                }
                "saveFavorites" -> background(result) {
                    val favorites = call.argument<List<Map<*, *>>>("favorites").orEmpty().map(Favorite::from)
                    store.save(favorites, call.argument("oldId"), call.argument("newId"))
                    TransitWidget.checkSelections(applicationContext, favorites)
                    null
                }
                "busRoutes" -> background(result) {
                    BusCatalog.search(applicationContext, call.arguments as String)
                }
                "busStops" -> background(result) {
                    BusCatalog.stops(applicationContext, call.arguments as String)
                }
                "searchBusStops" -> background(result) {
                    BusCatalog.searchStops(applicationContext, call.arguments as String)
                }
                "busRoutesAtStop" -> background(result) {
                    BusCatalog.routesAtStop(applicationContext, call.arguments as String).map(Favorite::fields)
                }
                "arrivals" -> background(result) {
                    val favorite = Favorite.from(call.arguments as Map<*, *>)
                    TransitWidget.fetch(applicationContext, favorite).fields()
                }
                "openStopMap" -> {
                    val stop = call.arguments as? String
                    result.success(!stop.isNullOrBlank() && openStopMap(stop))
                }
                "theme" -> result.success(store.theme())
                "setTheme" -> {
                    store.setTheme(call.arguments as String)
                    result.success(null)
                }
                "pin" -> {
                    val favoriteId = call.argument<String>("favoriteId")
                    val display = WidgetDisplay.from(call.argument<Map<*, *>>("display"))
                    result.success(favoriteId != null && TransitWidget.pin(this, favoriteId, display))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun openStopMap(stop: String): Boolean {
        val query = "서울 $stop"
        val web = Uri.parse("https://www.google.com/maps/search/").buildUpon()
            .appendQueryParameter("api", "1").appendQueryParameter("query", query).build()
        return try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("geo:0,0?q=${Uri.encode(query)}")))
            true
        } catch (_: ActivityNotFoundException) {
            try {
                startActivity(Intent(Intent.ACTION_VIEW, web))
                true
            } catch (_: ActivityNotFoundException) {
                false
            }
        }
    }

    private fun background(result: MethodChannel.Result, action: () -> Any?) {
        TransitWidget.executor.execute {
            try {
                val response = action()
                runOnUiThread { result.success(response) }
            } catch (_: Exception) {
                runOnUiThread { result.error("transit", "요청을 처리하지 못했어요. 다시 시도해 주세요.", null) }
            }
        }
    }
}
