package com.example.smart_public_transportation

import android.app.Activity
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

class TransitWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, widgetIds: IntArray) {
        updateAsync(context, widgetIds)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        TransitStore(context).remove(appWidgetIds)
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            refreshAction, pinnedAction -> {
                val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
                if (id !in ids(context)) return
                if (intent.action == pinnedAction) {
                    val favoriteId = intent.getStringExtra("favorite") ?: return
                    val display = WidgetDisplay.decode(intent.getStringExtra("display"))
                    TransitStore(context).select(id, favoriteId, display)
                } else if (TransitStore(context).display(id).shows("updated")) {
                    val progress = RemoteViews(context.packageName, R.layout.transit_widget).apply {
                        setTextViewText(R.id.widget_updated, "조회 중")
                        setViewVisibility(R.id.widget_updated, View.VISIBLE)
                    }
                    AppWidgetManager.getInstance(context).partiallyUpdateAppWidget(id, progress)
                }
                updateAsync(context, intArrayOf(id))
            }
            else -> super.onReceive(context, intent)
        }
    }

    private fun updateAsync(context: Context, widgetIds: IntArray) {
        val pending = goAsync()
        val app = context.applicationContext
        executor.execute {
            try {
                val store = TransitStore(app)
                val favorites = store.favorites().associateBy(Favorite::id)
                val selected = widgetIds.groupBy { store.selection(it)?.let(favorites::get) }
                selected[null]?.forEach { render(app, it, null, null) }
                val work = selected.keys.filterNotNull().map { favorite ->
                    executor.submit { fetch(app, favorite) }
                }
                work.forEach { it.get() }
            } finally {
                pending.finish()
            }
        }
    }

    companion object {
        internal val executor = Executors.newCachedThreadPool()
        private val snapshots = ConcurrentHashMap<String, Snapshot>()
        private val locks = ConcurrentHashMap<String, Any>()
        private const val refreshAction = "com.example.smart_public_transportation.REFRESH_TRANSIT"
        private const val pinnedAction = "com.example.smart_public_transportation.PINNED_TRANSIT"

        private fun provider(context: Context) = ComponentName(context, TransitWidget::class.java)

        private fun ids(context: Context) = AppWidgetManager.getInstance(context).getAppWidgetIds(provider(context))

        internal fun pin(activity: Activity, favoriteId: String, display: WidgetDisplay): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
            val manager = AppWidgetManager.getInstance(activity)
            if (!manager.isRequestPinAppWidgetSupported) return false
            val request = Intent(activity, TransitWidget::class.java).setAction(pinnedAction)
                .setData(Uri.parse("transit://pin/${UUID.randomUUID()}"))
                .putExtra("favorite", favoriteId)
                .putExtra("display", display.encode())
            val flags = PendingIntent.FLAG_ONE_SHOT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
            val callback = PendingIntent.getBroadcast(activity, 0, request, flags)
            return manager.requestPinAppWidget(provider(activity), null, callback)
        }

        internal fun fetch(context: Context, favorite: Favorite): Snapshot {
            val store = TransitStore(context)
            val lock = locks.computeIfAbsent(favorite.id) { Any() }
            return synchronized(lock) {
                val cached = snapshots[favorite.id]
                val age = cached?.let { System.currentTimeMillis() - it.checkedAt }
                val current = if (cached != null && age != null && age in 0..4_000) cached
                    else SeoulArrivals.refresh(favorite)
                if (store.favorites().any { it.id == favorite.id }) {
                    snapshots[favorite.id] = current
                    ids(context).filter { store.selection(it) == favorite.id }.forEach {
                        render(context, it, favorite, current)
                    }
                }
                current
            }
        }

        internal fun checkSelections(context: Context, favorites: List<Favorite>) {
            val store = TransitStore(context)
            val valid = favorites.associateBy(Favorite::id)
            snapshots.keys.retainAll(valid.keys)
            ids(context).forEach {
                val favorite = store.selection(it)?.let(valid::get)
                val snapshot = favorite?.let { selected -> snapshots[selected.id] }
                render(context, it, favorite, snapshot)
            }
        }

        internal fun setup(context: Context, id: Int, favorite: Favorite, display: WidgetDisplay) {
            TransitStore(context).select(id, favorite.id, display)
            render(context, id, favorite, null)
            executor.execute { fetch(context, favorite) }
        }

        private data class WidgetColors(
            val background: Int,
            val divider: Int,
            val text: Int,
            val muted: Int,
            val eta: Int,
            val chip: Int,
            val line: Int,
        )

        private fun colors(dark: Boolean, bus: Boolean): WidgetColors = if (dark) {
            WidgetColors(
                R.drawable.transit_widget_background, R.color.transit_panel_line,
                R.color.transit_panel_text, R.color.transit_panel_muted, R.color.transit_panel_eta,
                if (bus) R.drawable.transit_widget_route_bus else R.drawable.transit_widget_route,
                if (bus) R.color.transit_route_bus else R.color.transit_route_subway,
            )
        } else {
            WidgetColors(
                R.drawable.transit_widget_light_background, R.color.transit_panel_light_line,
                R.color.transit_panel_light_text, R.color.transit_panel_light_muted, R.color.transit_panel_light_eta,
                if (bus) R.drawable.transit_widget_route_light_bus else R.drawable.transit_widget_route_light_subway,
                if (bus) R.color.transit_route_light_bus else R.color.transit_route_light_subway,
            )
        }

        private fun render(context: Context, id: Int, favorite: Favorite?, snapshot: Snapshot?) {
            val display = TransitStore(context).display(id)
            val colors = colors(display.dark, favorite?.kind == "bus")
            val views = RemoteViews(context.packageName, R.layout.transit_widget)
            val configured = favorite != null
            val showLine = !configured || display.shows("line")
            val showStop = !configured || display.shows("stop")
            val showDirection = !configured || display.shows("direction")
            val showRefresh = !configured || display.shows("refresh")
            val showHeader = showLine || showStop || showDirection || showRefresh
            val wantsTimes = !configured || display.shows("first") || display.shows("next")
            val first = snapshot?.arrivals?.firstOrNull()?.takeIf { display.shows("first") }
            val second = snapshot?.arrivals?.getOrNull(1)?.takeIf { display.shows("next") }
            val showFirst = wantsTimes && (first != null || second == null)
            val showTimes = showFirst || second != null
            val footer = if (snapshot == null) "" else sourceText(display, snapshot, showTimes)
            val empty = !showHeader && !showTimes && footer.isEmpty()

            val configure = Intent(context, WidgetSettingsActivity::class.java)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
            val settings = PendingIntent.getActivity(context, id, configure,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val launch = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            views.setOnClickPendingIntent(R.id.widget_main, if (!configured || empty) settings else launch)
            views.setOnClickPendingIntent(R.id.widget_refresh, if (!configured) settings else
                PendingIntent.getBroadcast(context, id, Intent(context, TransitWidget::class.java)
                    .setAction(refreshAction).putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            views.setContentDescription(R.id.widget_refresh, if (configured) "도착 정보 새로고침" else "구간 선택")
            views.setImageViewResource(
                R.id.widget_refresh,
                if (configured) R.drawable.transit_refresh else R.drawable.transit_widget_add,
            )

            views.setInt(android.R.id.background, "setBackgroundResource", colors.background)
            views.setInt(R.id.widget_line, "setBackgroundResource", colors.chip)
            views.setInt(R.id.widget_divider, "setBackgroundColor", context.getColor(colors.divider))
            views.setTextColor(R.id.widget_line, context.getColor(colors.line))
            views.setTextColor(R.id.widget_eta, context.getColor(colors.eta))
            for (text in listOf(R.id.widget_title, R.id.widget_next, R.id.widget_empty_options)) {
                views.setTextColor(text, context.getColor(colors.text))
            }
            for (text in listOf(R.id.widget_direction, R.id.widget_eta_label, R.id.widget_next_label, R.id.widget_updated)) {
                views.setTextColor(text, context.getColor(colors.muted))
            }

            val visibility = mapOf(
                R.id.widget_header to showHeader,
                R.id.widget_identity to (showLine || showStop),
                R.id.widget_line to showLine,
                R.id.widget_title to showStop,
                R.id.widget_direction to showDirection,
                R.id.widget_refresh to showRefresh,
                R.id.widget_divider to (showHeader && showTimes),
                R.id.widget_arrivals to showTimes,
                R.id.widget_first_group to showFirst,
                R.id.widget_eta_label to (first != null),
                R.id.widget_next_group to (second != null),
                R.id.widget_updated to footer.isNotEmpty(),
                R.id.widget_empty_options to empty,
            )
            visibility.forEach { (view, visible) ->
                views.setViewVisibility(view, if (visible) View.VISIBLE else View.GONE)
            }

            views.setTextViewText(R.id.widget_line, favorite?.line ?: context.getString(R.string.transit_name))
            views.setTextViewText(R.id.widget_title, favorite?.title ?: "구간 선택")
            views.setTextViewText(R.id.widget_direction, favorite?.direction ?: "버스 또는 지하철을 골라 주세요")
            views.setTextViewText(R.id.widget_eta_label, arrivalLabel("첫 도착", first, display, snapshot))
            views.setTextViewText(R.id.widget_next_label, arrivalLabel("다음 도착", second, display, snapshot))
            views.setTextViewText(
                R.id.widget_eta,
                if (first != null && snapshot != null) formatArrival(first, snapshot, display)
                else statusText(configured, snapshot),
            )
            views.setTextViewText(
                R.id.widget_next,
                if (second != null && snapshot != null) formatArrival(second, snapshot, display) else "",
            )
            views.setTextViewText(R.id.widget_updated, footer)
            AppWidgetManager.getInstance(context).updateAppWidget(id, views)
        }

        private fun statusText(configured: Boolean, snapshot: Snapshot?) = when {
            !configured -> "눌러서 설정"
            snapshot == null -> "조회 중"
            snapshot.status == "offline" -> "실시간 정보 준비 중"
            snapshot.status in setOf("empty", "live", "sample") -> "도착 정보 없음"
            else -> "다시 조회해 주세요"
        }

        private fun arrivalLabel(title: String, arrival: Arrival?, display: WidgetDisplay, snapshot: Snapshot?) =
            if (display.remaining && !display.shows("updated") && arrival?.at != null && snapshot?.status == "live") {
                "$title · 조회 기준"
            } else title

        private fun sourceText(display: WidgetDisplay, snapshot: Snapshot, showTimes: Boolean): String {
            val timestamp = if (display.shows("updated") && snapshot.status in setOf("sample", "live", "empty")) {
                val suffix = if (display.remaining && showTimes && snapshot.status == "live") "기준" else "조회"
                "${formatClock(snapshot.checkedAt)} $suffix"
            } else ""
            val sample = snapshot.status == "sample" && (showTimes || timestamp.isNotEmpty())
            return listOf(if (sample) "예시 데이터" else "", timestamp).filter(String::isNotEmpty).joinToString(" · ")
        }

        private fun formatArrival(arrival: Arrival, snapshot: Snapshot, display: WidgetDisplay): String {
            val at = arrival.at ?: return arrival.message
            if (!display.remaining) return formatClock(at)
            val delta = at - snapshot.checkedAt
            if (delta <= 0L) return "예정 시각 지남"
            if (delta < 60_000L) return "곧 도착"
            return "${(delta + 59_999L) / 60_000L}분 후"
        }

        private fun formatClock(at: Long) = SimpleDateFormat("HH:mm", Locale.KOREA).apply {
            timeZone = TimeZone.getTimeZone("Asia/Seoul")
        }.format(Date(at))
    }
}
