package com.example.smart_public_transportation

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.zip.GZIPInputStream

internal data class Favorite(
    val kind: String,
    val line: String,
    val title: String,
    val direction: String,
    val routeId: String,
    val stopId: String,
    val selector: String,
) {
    val id: String get() = "$kind/$routeId/$stopId/$selector"

    fun fields() = mapOf(
        "id" to id, "kind" to kind, "line" to line, "title" to title,
        "direction" to direction, "routeId" to routeId, "stopId" to stopId,
        "selector" to selector,
    )

    companion object {
        fun from(data: Map<*, *>) = Favorite(
            data["kind"] as String, data["line"] as String, data["title"] as String,
            data["direction"] as String, data["routeId"] as String, data["stopId"] as String,
            data["selector"] as String,
        )

        fun from(data: JSONObject) = from(data.keys().asSequence().associateWith { data.getString(it) })

        val subwaySample = Favorite(
            "subway", "6호선", "녹사평역", "응암 방면", "1006", "녹사평", "상행",
        )
    }
}

internal data class Arrival(val at: Long?, val message: String, val detail: String = "") {
    fun fields() = mapOf("at" to at, "message" to message, "detail" to detail)
}

internal data class Snapshot(
    val status: String,
    val checkedAt: Long = System.currentTimeMillis(),
    val arrivals: List<Arrival> = emptyList(),
) {
    fun fields() = mapOf(
        "status" to status, "checkedAt" to checkedAt, "arrivals" to arrivals.map(Arrival::fields),
    )
}

internal class TransitStore(context: Context) {
    private val preferences = context.getSharedPreferences("transit", Context.MODE_PRIVATE)

    fun favorites(): List<Favorite> {
        val stored = preferences.getString("favorites", null) ?: return listOf(
            Favorite.subwaySample,
            BusCatalog.stops(context, "102900004").first { it["ars"] == "03567" }
                .let { BusCatalog.favorite("102900004", "용산03", it) },
        )
        val items = JSONArray(stored)
        return List(items.length()) { Favorite.from(items.getJSONObject(it)) }
    }

    fun save(favorites: List<Favorite>, oldId: String?, newId: String?) {
        val valid = favorites.map(Favorite::id).toSet()
        val editor = preferences.edit()
            .putString("favorites", JSONArray(favorites.map { JSONObject(it.fields()) }).toString())
        preferences.all.filterKeys { it.startsWith("widget_") }.forEach { (key, selection) ->
            when {
                oldId != null && selection == oldId && newId != null -> editor.putString(key, newId)
                selection !is String || selection !in valid -> editor.remove(key)
                else -> Unit
            }
        }
        editor.apply()
    }

    fun key(kind: String) = preferences.getString("key_$kind", "").orEmpty()

    fun setKeys(subway: String, bus: String) {
        preferences.edit().putString("key_subway", subway).putString("key_bus", bus).apply()
    }

    fun selection(widgetId: Int) = preferences.getString("widget_$widgetId", null)

    fun select(widgetId: Int, favoriteId: String) {
        preferences.edit().putString("widget_$widgetId", favoriteId).apply()
    }

    fun remove(widgetIds: IntArray) {
        val editor = preferences.edit()
        widgetIds.forEach { editor.remove("widget_$it") }
        editor.apply()
    }

    private val context = context.applicationContext
}

internal object BusCatalog {
    @Volatile private var catalog: JSONArray? = null

    private fun routes(context: Context): JSONArray = catalog ?: synchronized(this) {
        catalog ?: context.assets.open("seoul_bus_routes.json.gz").use { input ->
            GZIPInputStream(input).bufferedReader(Charsets.UTF_8).use { JSONArray(it.readText()) }
        }.also { catalog = it }
    }

    fun search(context: Context, query: String): List<Map<String, String>> {
        val needle = query.filterNot(Char::isWhitespace)
        if (needle.isEmpty()) return emptyList()
        val routes = routes(context)
        val matches = (0 until routes.length()).asSequence().map { routes.getJSONObject(it) }
            .filter { it.getString("name").contains(needle, ignoreCase = true) }
            .sortedBy { !it.getString("name").startsWith(needle, ignoreCase = true) }
        return matches.take(40).map {
            val stops = it.getJSONArray("stops")
            mapOf(
                "id" to it.getString("id"),
                "name" to it.getString("name"),
                "ends" to "${stops.getJSONArray(0).getString(3)} 출발",
            )
        }.toList()
    }

    fun stops(context: Context, id: String): List<Map<String, String>> {
        val routes = routes(context)
        val route = (0 until routes.length()).asSequence().map { routes.getJSONObject(it) }
            .firstOrNull { it.getString("id") == id } ?: return emptyList()
        val rows = route.getJSONArray("stops")
        return List(rows.length()) { index ->
            val row = rows.getJSONArray(index)
            val next = if (index + 1 < rows.length()) rows.getJSONArray(index + 1).getString(3) else ""
            mapOf(
                "order" to row.getString(0), "id" to row.getString(1), "ars" to row.getString(2),
                "name" to row.getString(3).trimEnd('.'), "next" to next.trimEnd('.'),
            )
        }
    }

    fun favorite(id: String, name: String, stop: Map<String, String>): Favorite {
        val next = stop.getValue("next")
        return Favorite(
            "bus", name, stop.getValue("name"),
            if (next.isEmpty()) "종점" else "$next 방면",
            id, stop.getValue("id"), stop.getValue("order"),
        )
    }
}
