import 'dart:async';

import 'package:flutter/material.dart';

import 'favorite_editor.dart';
import 'transit.dart';

const ink = Color(0xff102b30);
const canvas = Color(0xfff2f5f1);
const teal = Color(0xff0b6759);
const mint = Color(0xffa6e9d5);
const muted = Color(0xff506762);

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '언제와',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      scaffoldBackgroundColor: canvas,
      colorScheme: ColorScheme.fromSeed(
        seedColor: teal,
      ).copyWith(primary: teal),
      appBarTheme: const AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(15)),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
    ),
    home: const ArrivalBoard(),
  );
}

class ArrivalBoard extends StatefulWidget {
  const ArrivalBoard({super.key});

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

  Future<void> pin(Favorite favorite) async {
    try {
      final requested = await transitChannel.invokeMethod<bool>(
        'pin',
        favorite.id,
      );
      if (requested != true) feedback('홈 화면을 길게 누르고 위젯 목록에서 ‘언제와’를 찾아주세요.');
    } catch (_) {
      feedback('홈 화면 위젯을 추가할 수 없어요.');
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
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: ink,
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              child: SizedBox(
                width: 38,
                height: 38,
                child: Icon(
                  Icons.departure_board_outlined,
                  color: mint,
                  size: 21,
                ),
              ),
            ),
            SizedBox(width: 10),
            Text(
              '언제와',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
              ),
            ),
          ],
        ),
        actions: [
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
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  overview(),
                  const SizedBox(height: 24),
                  const Text(
                    '즐겨찾는 구간',
                    style: TextStyle(
                      color: ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (loadingFailed)
                    TextButton(
                      onPressed: load,
                      child: const Text('구간을 불러오지 못했어요. 다시 시도'),
                    )
                  else if (!ready)
                    const LinearProgressIndicator()
                  else if (favorites.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        '자주 타는 버스나 지하철을 추가해 주세요.',
                        style: TextStyle(color: muted),
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
                  if (ready) ...[
                    const SizedBox(height: 3),
                    FilledButton.icon(
                      onPressed: edit,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('구간 추가'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget overview() {
    final connected = subwaySet && busSet;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xff102b30), Color(0xff19433e)],
        ),
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '내 도착판',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 29,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                    ),
                  ),
                  if (connected)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        '서울 버스 · 지하철 도착 정보',
                        style: TextStyle(color: mint, fontSize: 13),
                      ),
                    )
                  else
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: mint,
                        padding: EdgeInsets.zero,
                        alignment: Alignment.centerLeft,
                      ),
                      onPressed: ready ? connect : null,
                      label: const Text('실시간 연결 설정'),
                      icon: const Icon(Icons.link, size: 17),
                    ),
                ],
              ),
            ),
            IconButton.filledTonal(
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xff345752),
                foregroundColor: Colors.white,
              ),
              onPressed: ready && !refreshing ? refresh : null,
              tooltip: '새로고침',
              icon: refreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: mint,
                      ),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
          ],
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

  @override
  Widget build(BuildContext context) {
    final accent = favorite.isBus ? const Color(0xff84520e) : teal;
    final tint = favorite.isBus
        ? const Color(0xffffedcf)
        : const Color(0xffd9f1e8);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xffdce6dd)),
        borderRadius: BorderRadius.circular(21),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    favorite.isBus
                        ? Icons.directions_bus_rounded
                        : Icons.train_rounded,
                    color: accent,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        favorite.line,
                        style: TextStyle(
                          color: accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        favorite.title,
                        style: const TextStyle(
                          color: ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.45,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '구간 옵션',
                  onSelected: (value) =>
                      value == 'edit' ? onEdit() : onRemove(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('구간 수정')),
                    PopupMenuItem(value: 'remove', child: Text('구간 삭제')),
                  ],
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 8),
              child: Text(
                favorite.direction,
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ),
            if (reading.items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(statusText, style: const TextStyle(color: muted)),
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (index, arrival) in reading.items.indexed) ...[
                    if (index > 0) const SizedBox(width: 8),
                    Expanded(child: arrivalBox(arrival, accent, tint, index)),
                  ],
                ],
              ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    reading.status == 'sample'
                        ? '예시 데이터'
                        : reading.checkedAt != null && reading.status == 'live'
                        ? '${seoulClock(reading.checkedAt!)} 조회'
                        : '',
                    style: const TextStyle(
                      color: muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onPin,
                  icon: const Icon(Icons.widgets_outlined, size: 16),
                  label: const Text('위젯 추가'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget arrivalBox(Arrival arrival, Color accent, Color tint, int index) {
    final sample = reading.status == 'sample';
    final expected = sample
        ? (favorite.isBus ? ['5분 후', '12분 후'] : ['3분 후', '8분 후'])[index]
        : arrival.expected;
    final clock = arrival.time == null || sample
        ? null
        : seoulClock(arrival.time!);
    final details = [
      if (clock != null) '$clock 예정',
      if (arrival.detail.isNotEmpty && !sample) arrival.detail,
    ];
    return Container(
      decoration: BoxDecoration(
        color: index == 0 ? tint : canvas,
        borderRadius: BorderRadius.circular(13),
      ),
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            index == 0 ? '첫 도착' : '다음 도착',
            style: const TextStyle(
              color: muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            expected,
            style: TextStyle(
              color: index == 0 ? accent : ink,
              fontSize: 17,
              fontWeight: FontWeight.w900,
              letterSpacing: -.65,
            ),
          ),
          if (details.isNotEmpty)
            Text(
              details.join(' · '),
              style: const TextStyle(color: muted, fontSize: 11),
            ),
        ],
      ),
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
          const Text(
            '서울시 도착 정보를 불러오려면 이용할 교통수단의 API 키를 입력해 주세요.',
            style: TextStyle(color: ink, fontSize: 16),
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
          const Text(
            'API 키는 이 기기에 저장되며, 조회할 때 서울시 공식 HTTP 주소로 전송돼요.',
            style: TextStyle(color: muted),
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
