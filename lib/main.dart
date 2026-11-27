import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'bus_stop_search.dart';
import 'favorite_editor.dart';
import 'transit.dart';
import 'transit_board.dart';
import 'transit_theme.dart';
import 'widget_settings.dart';

void main() {
  final route = WidgetsFlutterBinding.ensureInitialized()
      .platformDispatcher
      .defaultRouteName;
  runApp(MyApp(configuringWidget: route == widgetSettingsRoute));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.configuringWidget = false});

  final bool configuringWidget;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode mode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    loadTheme();
  }

  Future<void> loadTheme() async {
    try {
      final channel = widget.configuringWidget
          ? widgetSettingsChannel
          : transitChannel;
      final saved = await channel.invokeMethod<String>('theme');
      if (mounted && mode == ThemeMode.system && saved != null) {
        setState(
          () => mode = saved == 'dark' ? ThemeMode.dark : ThemeMode.light,
        );
      }
    } catch (_) {
      // Use system appearance if the preference is unavailable.
    }
  }

  Future<void> changeTheme(bool dark) async {
    await transitChannel.invokeMethod<void>(
      'setTheme',
      dark ? 'dark' : 'light',
    );
    if (mounted) setState(() => mode = dark ? ThemeMode.dark : ThemeMode.light);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '언제와',
    debugShowCheckedModeBanner: false,
    initialRoute: '/',
    theme: TransitPalette.light.theme(Brightness.light),
    darkTheme: TransitPalette.dark.theme(Brightness.dark),
    themeMode: mode,
    home: widget.configuringWidget
        ? const WidgetSettingsPage()
        : ArrivalBoard(onThemeChanged: changeTheme),
  );
}

class ArrivalBoard extends StatefulWidget {
  const ArrivalBoard({super.key, required this.onThemeChanged});

  final Future<void> Function(bool dark) onThemeChanged;

  @override
  State<ArrivalBoard> createState() => _ArrivalBoardState();
}

class _ArrivalBoardState extends State<ArrivalBoard>
    with WidgetsBindingObserver {
  List<Favorite> favorites = [];
  Map<String, Arrivals> readings = {};
  bool ready = false;
  bool loadingFailed = false;
  String filter = 'all';
  String? focusedId;
  bool refreshing = false;
  bool foreground = true;
  Timer? timer;
  int revision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    startTimer();
  }

  void startTimer() {
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (ModalRoute.of(context)?.isCurrent == true) refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) {
      startTimer();
      if (ModalRoute.of(context)?.isCurrent == true) refresh();
    } else {
      timer?.cancel();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> load() async {
    setState(() => loadingFailed = false);
    try {
      final data = await transitChannel.invokeMapMethod<String, Object?>(
        'load',
      );
      if (data == null) throw StateError('Saved stops unavailable');
      if (!mounted) return;
      setState(() {
        favorites = (data['favorites'] as List<Object?>)
            .cast<Map<Object?, Object?>>()
            .map(Favorite.fromMap)
            .toList();
        ready = true;
      });
      await refresh();
    } catch (_) {
      if (mounted) setState(() => loadingFailed = true);
    }
  }

  Future<void> refresh({bool restart = false}) async {
    if (!ready || !foreground || (refreshing && !restart)) return;
    final run = ++revision;
    setState(() => refreshing = true);
    await Future.wait(
      favorites.map((favorite) async {
        Arrivals result;
        try {
          final data = await transitChannel.invokeMapMethod<Object?, Object?>(
            'arrivals',
            favorite.toMap(),
          );
          result = data == null
              ? const Arrivals('unavailable')
              : Arrivals.fromMap(data);
        } catch (_) {
          result = const Arrivals('unavailable');
        }
        if (mounted && run == revision) {
          setState(() => readings[favorite.id] = result);
        }
      }),
    );
    if (mounted && run == revision) setState(() => refreshing = false);
  }

  Future<void> save(
    List<Favorite> next, {
    Favorite? original,
    Favorite? replacement,
  }) async {
    try {
      await transitChannel.invokeMethod<void>('saveFavorites', {
        'favorites': next.map((favorite) => favorite.toMap()).toList(),
        'oldId': original?.id,
        'newId': replacement?.id,
      });
      if (!mounted) return;
      setState(() {
        favorites = next;
        if (replacement != null) {
          if (filter != 'all' && filter != replacement.kind) filter = 'all';
          focusedId = replacement.id;
        }
        readings.removeWhere(
          (id, _) => !next.any((favorite) => favorite.id == id),
        );
      });
      await refresh(restart: true);
    } catch (_) {
      feedback('저장할 수 없어요. 다시 시도해 주세요.');
    }
  }

  Future<void> edit({Favorite? original, String? kind}) async {
    final favorite = await Navigator.of(context).push<Favorite>(
      MaterialPageRoute(
        builder: (_) => FavoriteEditor(
          original: original,
          initialKind: kind ?? (filter == 'bus' ? 'bus' : 'subway'),
        ),
      ),
    );
    if (mounted && favorite != null) await saveFavorite(favorite, original);
  }

  Future<void> saveFavorite(Favorite favorite, [Favorite? original]) async {
    if (favorites.any(
      (item) => item.id == favorite.id && item.id != original?.id,
    )) {
      feedback('이미 저장한 구간이에요.');
      return;
    }
    await save(
      original == null
          ? [...favorites, favorite]
          : favorites
                .map((item) => item.id == original.id ? favorite : item)
                .toList(),
      original: original,
      replacement: favorite,
    );
  }

  Future<void> search() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: const Text('버스 정류장 이름·번호'),
              onTap: () => Navigator.pop(context, 'stop'),
            ),
            ListTile(
              leading: const Icon(busIcon),
              title: const Text('버스 노선 번호'),
              onTap: () => Navigator.pop(context, 'bus'),
            ),
            ListTile(
              leading: const Icon(trainIcon),
              title: const Text('지하철역·노선'),
              onTap: () => Navigator.pop(context, 'subway'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice != 'stop') {
      await edit(kind: choice);
      return;
    }
    final favorite = await Navigator.of(context).push<Favorite>(
      MaterialPageRoute(builder: (_) => const BusStopSearchPage()),
    );
    if (mounted && favorite != null) await saveFavorite(favorite);
  }

  Future<void> remove(Favorite favorite) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${favorite.title} 삭제'),
        content: const Text('이 구간을 사용 중인 홈 화면 위젯에서 다른 구간을 선택할 수 있어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (mounted && accepted == true) {
      await save(favorites.where((item) => item.id != favorite.id).toList());
    }
  }

  Future<void> pin(Favorite favorite) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (context) => WidgetSettingsPage(
        favorites: favorites,
        selectedId: favorite.id,
        initialDisplay: WidgetDisplay(
          dark: Theme.of(context).brightness == Brightness.dark,
          remaining: true,
        ),
      ),
    ),
  );

  Future<void> toggleTheme(bool dark) async {
    try {
      await widget.onThemeChanged(dark);
    } catch (_) {
      feedback('앱 테마를 저장하지 못했어요.');
    }
  }

  void feedback(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final palette = TransitPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final shown = favorites
        .where((favorite) => filter == 'all' || favorite.kind == filter)
        .toList();
    final focus =
        shown.where((favorite) => favorite.id == focusedId).firstOrNull ??
        shown.firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: TransitPalette.marker,
                borderRadius: BorderRadius.all(Radius.circular(9)),
              ),
              child: SizedBox.square(
                dimension: 29,
                child: Icon(
                  Icons.place_rounded,
                  size: 21,
                  color: TransitPalette.markerInk,
                ),
              ),
            ),
            SizedBox(width: 8),
            Text(
              '언제와',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => toggleTheme(!dark),
            tooltip: dark ? '밝은 앱 테마로 전환' : '어두운 앱 테마로 전환',
            icon: Icon(
              dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            ),
          ),
          IconButton(
            onPressed: ready && !refreshing ? refresh : null,
            tooltip: '새로고침',
            icon: refreshing
                ? const SizedBox.square(
                    dimension: 19,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 5),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 7, 16, 20),
                children: [
                  Text(
                    '서울 대중교통',
                    style: TextStyle(
                      color: palette.ink,
                      fontSize: 27,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.7,
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: ready ? search : null,
                    icon: const Icon(Icons.search_rounded, size: 21),
                    label: const Text('정류장·역 또는 버스 번호 찾기'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      alignment: Alignment.centerLeft,
                      backgroundColor: palette.surface,
                      foregroundColor: palette.muted,
                      side: BorderSide(color: palette.divider),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      modeChip('all', '전체', Icons.layers_outlined, palette),
                      modeChip('bus', '버스', busIcon, palette),
                      modeChip('subway', '지하철', trainIcon, palette),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (focus != null)
                    TransitRouteMap(
                      key: ValueKey('diagram/${focus.id}'),
                      favorite: focus,
                      onOpenRoute: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => BusRoutePage(favorite: focus),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '저장한 정류장',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      if (ready)
                        TextButton.icon(
                          onPressed: edit,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('구간 추가'),
                        ),
                    ],
                  ),
                  if (loadingFailed)
                    TextButton(
                      onPressed: load,
                      child: const Text('정류장을 불러오지 못했어요. 다시 시도'),
                    )
                  else if (!ready)
                    const LinearProgressIndicator()
                  else if (shown.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        '저장한 정류장이 없어요.',
                        style: TextStyle(color: palette.muted),
                      ),
                    ),
                  for (final favorite in shown)
                    Padding(
                      key: ValueKey(favorite.id),
                      padding: const EdgeInsets.only(bottom: 9),
                      child: TransitArrivalRow(
                        favorite: favorite,
                        reading:
                            readings[favorite.id] ?? const Arrivals('loading'),
                        selected: favorite.id == focus?.id,
                        onSelect: () => setState(() => focusedId = favorite.id),
                        onPin: () => pin(favorite),
                        onEdit: () => edit(original: favorite),
                        onRemove: () => remove(favorite),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget modeChip(
    String value,
    String label,
    IconData icon,
    TransitPalette palette,
  ) {
    final selected = filter == value;
    return ChoiceChip(
      avatar: Icon(
        icon,
        size: 16,
        color: selected ? palette.accent : palette.muted,
      ),
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: palette.accentContainer,
      side: BorderSide(color: selected ? Colors.transparent : palette.divider),
      onSelected: (_) => setState(() => filter = value),
    );
  }
}
