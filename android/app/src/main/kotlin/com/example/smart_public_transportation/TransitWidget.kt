package com.example.smart_public_transportation

import android.app.Activity
import android.app.AlertDialog
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
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
                    TransitStore(context).select(id, favoriteId)
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
        private data class Cached(val generation: Int, val snapshot: Snapshot)
        private val snapshots = ConcurrentHashMap<String, Cached>()
        private val locks = ConcurrentHashMap<String, Any>()
        @Volatile private var generation = 0
        private const val refreshAction = "com.example.smart_public_transportation.REFRESH_TRANSIT"
        private const val pinnedAction = "com.example.smart_public_transportation.PINNED_TRANSIT"

        private fun provider(context: Context) = ComponentName(context, TransitWidget::class.java)

        private fun ids(context: Context) = AppWidgetManager.getInstance(context).getAppWidgetIds(provider(context))

        internal fun pin(activity: Activity, favoriteId: String): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
            val manager = AppWidgetManager.getInstance(activity)
            if (!manager.isRequestPinAppWidgetSupported) return false
            val request = Intent(activity, TransitWidget::class.java).setAction(pinnedAction)
                .setData(Uri.parse("transit://pin/${UUID.randomUUID()}"))
                .putExtra("favorite", favoriteId)
            val flags = PendingIntent.FLAG_ONE_SHOT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
            val callback = PendingIntent.getBroadcast(activity, 0, request, flags)
            return manager.requestPinAppWidget(provider(activity), null, callback)
        }

        internal fun fetch(context: Context, favorite: Favorite): Snapshot {
            val store = TransitStore(context)
            val lock = locks.computeIfAbsent(favorite.id) { Any() }
            return synchronized(lock) {
                val version = generation
                val key = store.key(favorite.kind)
                val cached = snapshots[favorite.id]?.takeIf { it.generation == version }?.snapshot
                val age = cached?.let { System.currentTimeMillis() - it.checkedAt }
                val current = if (cached != null && age != null && age in 0..4_000) cached
                    else SeoulArrivals.refresh(favorite, key)
                if (generation == version && store.favorites().any { it.id == favorite.id }) {
                    snapshots[favorite.id] = Cached(version, current)
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
                val snapshot = favorite?.let { selected -> snapshots[selected.id]?.snapshot }
                render(context, it, favorite, snapshot)
            }
        }

        internal fun reloadAll(context: Context) {
            generation++
            snapshots.clear()
            executor.execute {
                val store = TransitStore(context)
                val selected = ids(context).groupBy(store::selection)
                store.favorites().filter { it.id in selected }.forEach { favorite ->
                    selected[favorite.id]?.forEach { render(context, it, favorite, null) }
                    executor.execute { fetch(context, favorite) }
                }
            }
        }

        internal fun setup(context: Context, id: Int, favorite: Favorite) {
            TransitStore(context).select(id, favorite.id)
            render(context, id, favorite, null)
            executor.execute { fetch(context, favorite) }
        }

        private fun render(context: Context, id: Int, favorite: Favorite?, snapshot: Snapshot?) {
            val views = RemoteViews(context.packageName, R.layout.transit_widget)
            val configure = Intent(context, WidgetSettingsActivity::class.java)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
            val settings = PendingIntent.getActivity(context, id, configure,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val launch = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            views.setOnClickPendingIntent(R.id.widget_main, if (favorite == null) settings else launch)
            views.setOnClickPendingIntent(R.id.widget_refresh, if (favorite == null) settings else
                PendingIntent.getBroadcast(context, id, Intent(context, TransitWidget::class.java)
                    .setAction(refreshAction).putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            views.setContentDescription(R.id.widget_refresh, if (favorite == null) "구간 선택" else "도착 정보 새로고침")

            views.setTextViewText(R.id.widget_line, favorite?.line ?: "언제와")
            views.setTextColor(R.id.widget_line, if (favorite?.kind == "bus") 0xFFF6C983.toInt() else 0xFF86E6D4.toInt())
            views.setTextViewText(R.id.widget_title, favorite?.title ?: "구간 선택")
            views.setTextViewText(R.id.widget_direction, favorite?.direction ?: "버스 또는 지하철을 골라 주세요")
            val first = snapshot?.arrivals?.firstOrNull()
            val second = snapshot?.arrivals?.getOrNull(1)
            val sample = snapshot?.status == "sample"
            views.setTextViewText(R.id.widget_eta, when {
                sample -> if (favorite?.kind == "bus") "예시 5분 후" else "예시 3분 후"
                first != null -> first.at?.let(::formatClock)?.let { "$it 예정" } ?: first.message
                favorite == null -> "눌러서 설정"
                snapshot == null -> "조회 중"
                snapshot.status == "needsKey" -> "API 키 필요"
                snapshot.status == "invalidKey" -> "API 키 확인"
                snapshot.status == "empty" -> "도착 정보 없음"
                else -> "다시 조회해 주세요"
            })
            views.setTextViewText(R.id.widget_next, when {
                sample -> if (favorite?.kind == "bus") "다음 12분 후" else "다음 8분 후"
                second != null -> "다음 ${second.at?.let(::formatClock) ?: second.message}"
                else -> ""
            })
            views.setViewVisibility(R.id.widget_next, if (second == null) View.GONE else View.VISIBLE)
            val updated = when (snapshot?.status) {
                "sample" -> "예시 데이터"
                "live", "empty" -> "${formatClock(snapshot.checkedAt)} 조회 · 눌러서 갱신"
                else -> ""
            }
            views.setTextViewText(R.id.widget_updated, updated)
            AppWidgetManager.getInstance(context).updateAppWidget(id, views)
        }

        private fun formatClock(at: Long) = SimpleDateFormat("HH:mm", Locale.KOREA).apply {
            timeZone = TimeZone.getTimeZone("Asia/Seoul")
        }.format(Date(at))
    }
}

class WidgetSettingsActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        val result = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
        setResult(RESULT_CANCELED, result)
        val info = AppWidgetManager.getInstance(this).getAppWidgetInfo(id)
        if (info?.provider != ComponentName(this, TransitWidget::class.java)) {
            finish()
            return
        }
        val favorites = TransitStore(this).favorites()
        val dialog = AlertDialog.Builder(this).setTitle("위젯에 표시할 구간")
            .setNegativeButton("취소") { _, _ -> finish() }
            .setOnCancelListener { finish() }
        if (favorites.isEmpty()) {
            dialog.setMessage("언제와 앱에서 버스 또는 지하철 구간을 먼저 저장해 주세요.")
                .setPositiveButton("앱 열기") { _, _ ->
                    startActivity(Intent(this, MainActivity::class.java))
                    finish()
                }
        } else {
            val labels = favorites.map { "${it.line} · ${it.title}\n${it.direction}" }.toTypedArray()
            dialog.setItems(labels) { _, position ->
                TransitWidget.setup(applicationContext, id, favorites[position])
                setResult(RESULT_OK, result)
                finish()
            }
        }
        dialog.show()
    }
}
