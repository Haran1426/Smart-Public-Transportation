package com.example.smart_public_transportation

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

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

internal data class WidgetDisplay(
    val dark: Boolean = true,
    val remaining: Boolean = false,
    private val hidden: Set<String> = emptySet(),
) {
    fun shows(field: String) = field !in hidden

    fun fields() = mapOf(
        "theme" to if (dark) "dark" else "light",
        "timeFormat" to if (remaining) "remaining" else "clock",
        "hidden" to hidden.toList(),
    )

    fun encode() = JSONObject(fields()).toString()

    companion object {
        private val fields = setOf("line", "stop", "direction", "first", "next", "updated", "refresh")

        fun from(data: Map<*, *>?) = WidgetDisplay(
            dark = data?.get("theme") != "light",
            remaining = data?.get("timeFormat") == "remaining",
            hidden = (data?.get("hidden") as? List<*>).orEmpty().filterIsInstance<String>()
                .filter { it in fields }.toSet(),
        )

        fun decode(json: String?): WidgetDisplay {
            if (json == null) return WidgetDisplay()
            return runCatching {
                val data = JSONObject(json)
                val hidden = data.optJSONArray("hidden") ?: JSONArray()
                from(mapOf(
                    "theme" to data.optString("theme"),
                    "timeFormat" to data.optString("timeFormat"),
                    "hidden" to List(hidden.length()) { hidden.getString(it) },
                ))
            }.getOrDefault(WidgetDisplay())
        }
    }
}

internal class TransitStore(context: Context) {
    private val preferences = context.getSharedPreferences("transit", Context.MODE_PRIVATE)

    fun favorites(): List<Favorite> {
        val stored = preferences.getString("favorites", null) ?: return listOf(
            Favorite.subwaySample,
            BusCatalog.sample(context),
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

    fun theme() = preferences.getString("app_theme", null)

    fun setTheme(theme: String) {
        require(theme == "light" || theme == "dark")
        preferences.edit().putString("app_theme", theme).apply()
    }

    fun display(widgetId: Int) = WidgetDisplay.decode(preferences.getString("appearance_$widgetId", null))

    fun selection(widgetId: Int) = preferences.getString("widget_$widgetId", null)

    fun select(widgetId: Int, favoriteId: String, display: WidgetDisplay) {
        preferences.edit().putString("widget_$widgetId", favoriteId)
            .putString("appearance_$widgetId", display.encode()).apply()
    }

    fun remove(widgetIds: IntArray) {
        val editor = preferences.edit()
        widgetIds.forEach { editor.remove("widget_$it").remove("appearance_$it") }
        editor.apply()
    }

    private val context = context.applicationContext
}

internal object BusCatalog {
    private const val searchLimit = 40
    @Volatile private var cache: Catalog? = null

    private data class Stop(val id: String, val order: String, val ars: String, val rawName: String, val next: String) {
        val name get() = rawName.trimEnd('.')

        fun stationFields() = mapOf("id" to id, "name" to name, "ars" to ars)
        fun fields() = stationFields() + mapOf("order" to order, "next" to next)
    }

    private data class Route(val id: String, val name: String, val stops: List<Stop>)
    private data class Visit(val route: Route, val stop: Stop) {
        fun favorite() = Favorite(
            "bus", route.name, stop.name,
            if (stop.next.isEmpty()) "종점" else "${stop.next} 방면",
            route.id, stop.id, stop.order,
        )
    }

    private class Catalog(val routes: List<Route>) {
        val routesById = routes.associateBy(Route::id)
        val visitsByStop = buildMap<String, MutableList<Visit>> {
            for (route in routes) {
                for (stop in route.stops) {
                    getOrPut(stop.id) { mutableListOf() }.add(Visit(route, stop))
                }
            }
        }
    }

    private fun catalog(context: Context): Catalog = cache ?: synchronized(this) {
        cache ?: context.assets.open("seoul_bus_routes.json").bufferedReader(Charsets.UTF_8).use { reader ->
            val rows = JSONArray(reader.readText())
            Catalog(List(rows.length()) { index ->
                val route = rows.getJSONObject(index)
                val stops = route.getJSONArray("stops")
                Route(route.getString("id"), route.getString("name"), List(stops.length()) { position ->
                    val row = stops.getJSONArray(position)
                    val next = stops.optJSONArray(position + 1)?.getString(3).orEmpty().trimEnd('.')
                    Stop(row.getString(1), row.getString(0), row.getString(2), row.getString(3), next)
                })
            })
        }.also { cache = it }
    }

    fun search(context: Context, query: String): List<Map<String, String>> {
        val needle = query.filterNot(Char::isWhitespace)
        if (needle.isEmpty()) return emptyList()
        return catalog(context).routes.asSequence()
            .filter { it.name.contains(needle, ignoreCase = true) }
            .sortedBy { !it.name.startsWith(needle, ignoreCase = true) }
            .take(searchLimit)
            .map { mapOf("id" to it.id, "name" to it.name, "ends" to "${it.stops.first().rawName} 출발") }
            .toList()
    }

    fun stops(context: Context, id: String): List<Map<String, String>> =
        catalog(context).routesById[id]?.stops.orEmpty().map(Stop::fields)

    fun searchStops(context: Context, query: String): List<Map<String, String>> {
        val needle = query.filterNot(Char::isWhitespace).lowercase()
        if (needle.isEmpty()) return emptyList()
        val byNumber = needle.all { it in '0'..'9' }
        return catalog(context).visitsByStop.values.asSequence()
            .map { it.first().stop }
            .mapNotNull { stop ->
                val label = if (byNumber) stop.ars.takeUnless { it == "0" }.orEmpty()
                    else stop.name.filterNot(Char::isWhitespace).lowercase()
                val rank = when {
                    label == needle -> 0
                    label.startsWith(needle) -> 1
                    label.contains(needle) -> 2
                    else -> return@mapNotNull null
                }
                stop to rank
            }
            .sortedWith(compareBy({ it.second }, { it.first.name }, { it.first.ars }))
            .take(searchLimit)
            .map { (stop, _) -> stop.stationFields() }
            .toList()
    }

    fun routesAtStop(context: Context, id: String): List<Favorite> =
        catalog(context).visitsByStop[id].orEmpty().sortedBy { it.route.name }.map(Visit::favorite)

    fun sample(context: Context): Favorite {
        val route = catalog(context).routesById.getValue("102900004")
        return Visit(route, route.stops.first { it.ars == "03567" }).favorite()
    }

}
