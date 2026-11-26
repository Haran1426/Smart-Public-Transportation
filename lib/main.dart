import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'favorite_editor.dart';
import 'transit.dart';
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
  bool subwaySet = false;
  bool busSet = false;
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
      if (!mounted || data == null) return;
      setState(() {
        favorites = (data['favorites'] as List<Object?>)
            .cast<Map<Object?, Object?>>()
            .map(Favorite.fromMap)
            .toList();
        subwaySet = data['subwaySet'] == true;
        busSet = data['busSet'] == true;
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
        readings.removeWhere(
          (id, _) => !next.any((favorite) => favorite.id == id),
        );
      });
      await refresh(restart: true);
    } catch (_) {
      feedback('저장할 수 없어요. 다시 시도해 주세요.');
    }
  }

  Future<void> edit([Favorite? original]) async {
    final favorite = await Navigator.of(context).push<Favorite>(
      MaterialPageRoute(builder: (_) => FavoriteEditor(original: original)),
    );
    if (!mounted || favorite == null) return;
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

  Future<void> connect() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ConnectionPage(subwaySet: subwaySet, busSet: busSet),
      ),
    );
    if (!mounted || changed != true) return;
    setState(() => readings = {});
    revision++;
    refreshing = false;
    await load();
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
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: TransitPalette.marker,
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              child: SizedBox.square(
                dimension: 36,
                child: Icon(
                  Icons.place_rounded,
                  color: TransitPalette.markerInk,
                  size: 24,
                ),
              ),
            ),
            SizedBox(width: 9),
            Text(
              '언제와',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
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
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              onPressed: ready ? connect : null,
              tooltip: '실시간 연결 설정',
              icon: const Icon(Icons.settings_outlined),
            ),
          ),
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
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '내 도착판',
                          style: TextStyle(
                            color: palette.ink,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.2,
                          ),
                        ),
                      ),
                      IconButton.outlined(
                        style: IconButton.styleFrom(
                          backgroundColor: palette.surface,
                          foregroundColor: palette.accent,
                          side: BorderSide(color: palette.divider),
                        ),
                        onPressed: ready && !refreshing ? refresh : null,
                        tooltip: '새로고침',
                        icon: refreshing
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  if (ready && (!subwaySet || !busSet)) ...[
                    const SizedBox(height: 5),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: connect,
                        style: TextButton.styleFrom(
                          foregroundColor: palette.accent,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                        ),
                        icon: const Icon(Icons.link_rounded, size: 18),
                        label: const Text('실시간 연결 설정'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '즐겨찾는 구간',
                          style: TextStyle(
                            color: palette.ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (ready)
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 42),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                          ),
                          onPressed: edit,
                          icon: const Icon(Icons.add_rounded, size: 19),
                          label: const Text('구간 추가'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (loadingFailed)
                    TextButton(
                      onPressed: load,
                      child: const Text('구간을 불러오지 못했어요. 다시 시도'),
                    )
                  else if (!ready)
                    const LinearProgressIndicator()
                  else if (favorites.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        '홈 화면 위젯에 표시할 버스나 지하철 구간을 추가해 주세요.',
                        style: TextStyle(color: palette.muted),
                      ),
                    ),
                  for (final favorite in favorites)
                    Padding(
                      key: ValueKey(favorite.id),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ArrivalCard(
                        favorite: favorite,
                        reading:
                            readings[favorite.id] ?? const Arrivals('loading'),
                        onPin: () => pin(favorite),
                        onEdit: () => edit(favorite),
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
}

class ArrivalCard extends StatelessWidget {
  const ArrivalCard({
    super.key,
    required this.favorite,
    required this.reading,
    required this.onPin,
    required this.onEdit,
    required this.onRemove,
  });

  final Favorite favorite;
  final Arrivals reading;
  final VoidCallback onPin;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  String get statusText => switch (reading.status) {
    'loading' => '도착 정보 조회 중',
    'needsKey' => '설정에서 API 키를 연결해 주세요.',
    'invalidKey' => '설정에서 API 키를 확인해 주세요.',
    'empty' => '조회된 도착 정보가 없어요.',
    _ => '도착 정보를 불러오지 못했어요.',
  };

  String get sourceText => switch (reading.status) {
    'sample' => '예시 데이터',
    'live' || 'empty' when reading.checkedAt != null =>
      '${seoulClock(reading.checkedAt!)} 조회',
    _ => '',
  };

  @override
  Widget build(BuildContext context) {
    final palette = TransitPalette.of(context);
    final routeColor = favorite.isBus ? palette.bus : palette.subway;
    final source = sourceText;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.canvas,
        border: Border.all(color: palette.divider),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Column(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(19),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 9, 10, 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 106),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: favorite.isBus
                                  ? palette.busContainer
                                  : palette.subwayContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              child: Text(
                                favorite.line,
                                style: TextStyle(
                                  color: routeColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            favorite.title,
                            style: TextStyle(
                              color: palette.ink,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: '구간 옵션',
                          icon: Icon(
                            Icons.more_vert,
                            color: palette.muted,
                            size: 20,
                          ),
                          padding: EdgeInsets.zero,
                          onSelected: (value) =>
                              value == 'edit' ? onEdit() : onRemove(),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('구간 수정')),
                            PopupMenuItem(
                              value: 'remove',
                              child: Text('구간 삭제'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Text(
                      favorite.direction,
                      style: TextStyle(color: palette.muted, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    Divider(height: 1, color: palette.divider),
                    const SizedBox(height: 9),
                    if (reading.items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Text(
                          statusText,
                          style: TextStyle(
                            color: palette.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final (index, arrival)
                              in reading.items.indexed) ...[
                            if (index > 0) const SizedBox(width: 12),
                            Expanded(
                              child: arrivalTime(palette, arrival, index),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 3, 3, 1),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      source,
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      backgroundColor: palette.accentContainer,
                      foregroundColor: palette.accent,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: onPin,
                    icon: Icon(Icons.add_to_home_screen_rounded, size: 17),
                    label: const Text('위젯 추가'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget arrivalTime(TransitPalette palette, Arrival arrival, int index) {
    final first = index == 0;
    final sample = reading.status == 'sample';
    final expected = sample
        ? (favorite.isBus ? ['5분 후', '12분 후'] : ['3분 후', '8분 후'])[index]
        : arrival.expected;
    final details = [
      if (!sample && arrival.time != null) '${seoulClock(arrival.time!)} 예정',
      if (!sample && arrival.detail.isNotEmpty) arrival.detail,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          first ? '첫 도착' : '다음 도착',
          style: TextStyle(
            color: palette.muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          expected,
          style: TextStyle(
            color: first ? palette.accent : palette.ink,
            fontSize: first && expected.length <= 7 ? 29 : 20,
            fontWeight: FontWeight.w900,
            letterSpacing: -.6,
          ),
        ),
        if (details.isNotEmpty)
          Text(
            details.join(' · '),
            style: TextStyle(color: palette.muted, fontSize: 11),
          ),
      ],
    );
  }
}

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({
    super.key,
    required this.subwaySet,
    required this.busSet,
  });

  final bool subwaySet;
  final bool busSet;

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  final subway = TextEditingController();
  final bus = TextEditingController();
  bool removeSubway = false;
  bool removeBus = false;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    subway.dispose();
    bus.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    final subwayKey = subway.text.trim();
    final busKey = bus.text.trim();
    try {
      await transitChannel.invokeMethod<void>('saveKeys', {
        if (removeSubway || subwayKey.isNotEmpty)
          'subway': removeSubway ? '' : subwayKey,
        if (removeBus || busKey.isNotEmpty)
          'bus': removeBus
              ? ''
              : busKey.contains('%')
              ? Uri.decodeComponent(busKey)
              : busKey,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '저장할 수 없어요. 키 형식을 확인해 주세요.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('실시간 연결')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '서울시 도착 정보를 불러오려면 이용할 교통수단의 API 키를 입력해 주세요.',
            style: TextStyle(
              color: TransitPalette.of(context).ink,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 24),
          field(
            '지하철 API 키',
            '서울 열린데이터광장',
            subway,
            widget.subwaySet,
            removeSubway,
            (value) => setState(() => removeSubway = value),
          ),
          const SizedBox(height: 20),
          field(
            '버스 API 키',
            '공공데이터포털 · 버스도착정보조회',
            bus,
            widget.busSet,
            removeBus,
            (value) => setState(() => removeBus = value),
          ),
          const SizedBox(height: 22),
          Text(
            'API 키는 이 기기에 저장되며, 조회할 때 서울시 공식 HTTP 주소로 전송돼요.',
            style: TextStyle(color: TransitPalette.of(context).muted),
          ),
          if (error case final message?) ...[
            const SizedBox(height: 10),
            Text(
              message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(onPressed: busy ? null : save, child: const Text('저장')),
        ],
      ),
    ),
  );

  Widget field(
    String title,
    String source,
    TextEditingController controller,
    bool saved,
    bool remove,
    ValueChanged<bool> onRemove,
  ) => Column(
    children: [
      TextField(
        controller: controller,
        obscureText: true,
        enabled: !remove && !busy,
        enableSuggestions: false,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: title,
          helperText: source,
          hintText: saved ? '새 키를 입력하면 바뀌어요' : '발급받은 키 입력',
          prefixIcon: const Icon(Icons.key_outlined),
        ),
      ),
      if (saved)
        CheckboxListTile(
          value: remove,
          onChanged: busy ? null : (value) => onRemove(value ?? false),
          contentPadding: EdgeInsets.zero,
          title: const Text('저장된 키 삭제'),
        ),
    ],
  );
}
