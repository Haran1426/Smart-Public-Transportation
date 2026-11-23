package com.example.smart_public_transportation

import android.net.Uri
import android.util.Xml
import org.json.JSONArray
import org.json.JSONObject
import org.xmlpull.v1.XmlPullParser
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

internal object SeoulArrivals {
    private val duration = Regex("""(?:(\d+)\s*분\s*)?(?:(\d+)\s*초\s*)?\s*후""")
    private val noBus = listOf("정보없", "운행종료", "운행준비", "출발대기", "회차대기", "운행대기", "미운행")

    fun refresh(favorite: Favorite, key: String): Snapshot {
        val now = System.currentTimeMillis()
        if (key.isEmpty()) {
            val isSample = favorite.id == Favorite.subwaySample.id ||
                (favorite.kind == "bus" && favorite.routeId == "102900004" && favorite.title == "삼각지역")
            if (!isSample) return Snapshot("needsKey", now)
            val first = if (favorite.kind == "bus") 5 else 3
            val second = if (favorite.kind == "bus") 12 else 8
            return Snapshot("sample", now, listOf(first, second).map {
                Arrival(now + it * 60_000L, "", favorite.direction)
            })
        }
        return try {
            val arrivals = if (favorite.kind == "bus") bus(favorite, key, now) else subway(favorite, key, now)
            Snapshot(if (arrivals.isEmpty()) "empty" else "live", now, arrivals.take(2))
        } catch (failure: ApiFailure) {
            Snapshot(failure.status, now)
        } catch (_: Exception) {
            Snapshot("unavailable", now)
        }
    }

    private fun subway(favorite: Favorite, key: String, now: Long): List<Arrival> {
        val station = favorite.stopId
        val rows = subwayRows(subwayAliases[station] ?: station, key)
            ?: station.takeIf { it.length > 1 && it.endsWith("역") }?.dropLast(1)?.let {
                subwayRows(subwayAliases[it] ?: it, key)
            }
            ?: return emptyList()
        return (0 until rows.length()).asSequence().map { rows.getJSONObject(it) }
            .filter { it.optString("subwayId") == favorite.routeId && it.optString("updnLine") == favorite.selector }
            .sortedBy { it.optString("ordkey").getOrNull(1) ?: '9' }
            .distinctBy { it.optString("btrainNo").ifBlank { it.optString("ordkey") } }
            .mapNotNull { row ->
                val received = seoulTime(row.optString("recptnDt")) ?: now
                if (received < now - 120_000L || received > now + 60_000L || row.optString("arvlCd") == "2") {
                    return@mapNotNull null
                }
                val message = row.optString("arvlMsg2").takeUnless { it == "null" }.orEmpty()
                val estimate = row.optString("barvlDt").toIntOrNull()?.takeIf { it in 1..10_800 }
                    ?: messageSeconds(message)
                val imminent = row.optString("arvlCd") in listOf("0", "1")
                val at = if (imminent) null else estimate?.let { received + it * 1000L }
                if ((at != null && at < now) || (at == null && message.isBlank())) return@mapNotNull null
                val destination = row.optString("bstatnNm").takeUnless { it == "null" }.orEmpty()
                Arrival(at, message, destination.takeIf { it.isNotBlank() }?.let { "${it}행" }.orEmpty())
            }.take(2).toList()
    }

    private fun subwayRows(station: String, key: String): JSONArray? {
        val url = "http://swopenapi.seoul.go.kr/api/subway/${Uri.encode(key)}/json/realtimeStationArrival/0/40/${Uri.encode(station)}"
        val json = JSONObject(get(url))
        val error = json.optJSONObject("errorMessage") ?: json
        return when (error.optString("code")) {
            "INFO-000" -> json.optJSONArray("realtimeArrivalList")
            "INFO-200" -> null
            "INFO-100", "INFO-101" -> throw ApiFailure("invalidKey")
            else -> throw ApiFailure("unavailable")
        }
    }

    private fun bus(favorite: Favorite, key: String, now: Long): List<Arrival> {
        val url = Uri.parse("http://ws.bus.go.kr/api/rest/arrive/getArrInfoByRoute")
            .buildUpon().appendQueryParameter("serviceKey", key)
            .appendQueryParameter("stId", favorite.stopId)
            .appendQueryParameter("busRouteId", favorite.routeId)
            .appendQueryParameter("ord", favorite.selector).build().toString()
        val source = get(url)
        if (source.trimStart().startsWith('{')) {
            val json = JSONObject(source)
            if (json.optInt("status") in listOf(401, 403)) throw ApiFailure("invalidKey")
            throw ApiFailure("unavailable")
        }
        val fields = setOf("headerCd", "headerMsg", "mkTm", "arrmsg1", "arrmsg2", "exps1", "exps2")
        val values = mutableMapOf<String, String>()
        val parser = Xml.newPullParser()
        parser.setFeature(XmlPullParser.FEATURE_PROCESS_DOCDECL, false)
        parser.setInput(source.reader())
        while (parser.eventType != XmlPullParser.END_DOCUMENT) {
            if (parser.eventType == XmlPullParser.START_TAG && parser.name in fields) {
                val field = parser.name
                values.putIfAbsent(field, parser.nextText().trim())
            }
            parser.next()
        }
        when (values["headerCd"]) {
            "0" -> Unit
            "4" -> return emptyList()
            "7", "8" -> throw ApiFailure("invalidKey")
            else -> {
                val message = values["headerMsg"].orEmpty()
                throw ApiFailure(if (message.contains("인증") || message.contains("서비스키")) "invalidKey" else "unavailable")
            }
        }

        val received = seoulTime(values["mkTm"].orEmpty()) ?: now
        if (received < now - 120_000L || received > now + 60_000L) return emptyList()
        return (1..2).mapNotNull { index ->
            val message = values["arrmsg$index"].orEmpty()
            if (message.isBlank() || message == "null" || noBus.any { message.replace(" ", "").contains(it) }) {
                return@mapNotNull null
            }
            val seconds = messageSeconds(message) ?: values["exps$index"]?.toIntOrNull()?.takeIf { it in 1..10_800 }
            val at = seconds?.let { received + it * 1000L }
            if (at != null && at < now) return@mapNotNull null
            Arrival(at, message, favorite.direction)
        }
    }

    private fun messageSeconds(message: String): Int? {
        val match = duration.find(message) ?: return null
        val minutes = match.groupValues[1].toIntOrNull() ?: 0
        val seconds = match.groupValues[2].toIntOrNull() ?: 0
        if (match.groupValues.drop(1).all(String::isEmpty)) return null
        return (minutes * 60L + seconds).takeIf { it in 0..10_800 }?.toInt()
    }

    private fun seoulTime(value: String) = runCatching {
        SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.KOREA).apply {
            isLenient = false
            timeZone = TimeZone.getTimeZone("Asia/Seoul")
        }.parse(value)?.time
    }.getOrNull()

    private fun get(url: String): String {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 3_000
            connection.readTimeout = 3_000
            connection.instanceFollowRedirects = false
            when (connection.responseCode) {
                200 -> Unit
                401, 403 -> throw ApiFailure("invalidKey")
                else -> throw IOException("Arrival provider returned an unsuccessful status")
            }
            return connection.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
        } finally {
            connection.disconnect()
        }
    }

    private class ApiFailure(val status: String) : Exception()

    private val subwayAliases = mapOf(
        "응암" to "응암순환(상선)", "공릉" to "공릉(서울산업대입구)",
        "남한산성입구" to "남한산성입구(성남법원, 검찰청)", "대모산입구" to "대모산",
        "천호" to "천호(풍납토성)", "몽촌토성" to "몽촌토성(평화의문)",
    )
}
