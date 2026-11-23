package com.example.smart_public_transportation

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
                        "subwaySet" to store.key("subway").isNotEmpty(),
                        "busSet" to store.key("bus").isNotEmpty(),
                    )
                }
                "saveFavorites" -> background(result) {
                    val favorites = call.argument<List<Map<*, *>>>("favorites").orEmpty().map(Favorite::from)
                    store.save(favorites, call.argument("oldId"), call.argument("newId"))
                    TransitWidget.checkSelections(applicationContext, favorites)
                    null
                }
                "saveKeys" -> {
                    val subway = call.argument<String>("subway")
                    val bus = call.argument<String>("bus")
                    store.setKeys(subway ?: store.key("subway"), bus ?: store.key("bus"))
                    TransitWidget.reloadAll(applicationContext)
                    result.success(null)
                }
                "busRoutes" -> background(result) {
                    BusCatalog.search(applicationContext, call.arguments as String)
                }
                "busStops" -> background(result) {
                    BusCatalog.stops(applicationContext, call.arguments as String)
                }
                "arrivals" -> background(result) {
                    val favorite = Favorite.from(call.arguments as Map<*, *>)
                    TransitWidget.fetch(applicationContext, favorite).fields()
                }
                "pin" -> result.success(TransitWidget.pin(this, call.arguments as String))
                else -> result.notImplemented()
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
