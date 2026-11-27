import 'package:material_ui/material_ui.dart';

import 'transit.dart';
import 'transit_theme.dart';

const busIcon = Icons.directions_bus_rounded;
const trainIcon = Icons.train_rounded;

class TransitStop {
  const TransitStop(this.id, this.order, this.name, this.ars);

  factory TransitStop.fromMap(Map<Object?, Object?> data) => TransitStop(
    data['id'] as String,
    data['order'] as String,
    data['name'] as String,
    data['ars'] as String,
  );

  final String id;
  final String order;
  final String name;
  final String ars;

  String get displayArs => ars == '0' ? '' : ars;
}

Future<List<TransitStop>> loadBusStops(String routeId) async {
  final data = await transitChannel.invokeListMethod<Map<Object?, Object?>>(
    'busStops',
    routeId,
  );
  return (data ?? []).map(TransitStop.fromMap).toList();
}

bool isSelectedStop(TransitStop stop, Favorite favorite) =>
    stop.id == favorite.stopId && stop.order == favorite.selector;

Future<void> openStopMap(BuildContext context, String title) async {
  try {
    if (await transitChannel.invokeMethod<bool>('openStopMap', title) == true) {
      return;
    }
  } catch (_) {
    // Report missing map support the same way as an unavailable map app.
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('지도를 열 수 없어요.')));
  }
}

Color routeInk(Favorite favorite, TransitPalette palette) =>
    favorite.isBus ? palette.bus : palette.subway;

class RouteBadge extends StatelessWidget {
  const RouteBadge(this.favorite, {super.key});
  final Favorite favorite;

  @override
  Widget build(BuildContext context) {
    final palette = TransitPalette.of(context);
    final color = routeInk(favorite, palette);
    return Container(
      constraints: const BoxConstraints(maxWidth: 120),
      decoration: BoxDecoration(
        color: favorite.isBus ? palette.busContainer : palette.subwayContainer,
        borderRadius: BorderRadius.circular(7),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(favorite.isBus ? busIcon : trainIcon, size: 15, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              favorite.line,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TransitRouteMap extends StatefulWidget {
  const TransitRouteMap({
    super.key,
    required this.favorite,
    required this.onOpenRoute,
  });
  final Favorite favorite;
  final VoidCallback onOpenRoute;

  @override
  State<TransitRouteMap> createState() => _TransitRouteMapState();
}

class _TransitRouteMapState extends State<TransitRouteMap> {
  late final Future<List<TransitStop>>? stops = widget.favorite.isBus
      ? loadBusStops(widget.favorite.routeId)
      : null;

  @override
  Widget build(BuildContext context) {
    final favorite = widget.favorite;
    final palette = TransitPalette.of(context);
    final color = routeInk(favorite, palette);
    return FutureBuilder<List<TransitStop>>(
      future: stops,
      builder: (context, snapshot) {
        final route = snapshot.data ?? const <TransitStop>[];
        final index = route.indexWhere(
          (stop) => isSelectedStop(stop, favorite),
        );
        final before = index > 0 ? route[index - 1].name : null;
        final after = index >= 0 && index + 1 < route.length
            ? route[index + 1].name
            : null;
        final active = before == null ? 0 : 1;
        final labels = [
          ?before,
          favorite.title,
          if (after != null)
            after
          else if (favorite.direction != '종점')
            favorite.direction,
        ];
        final ars = index < 0 ? '' : route[index].displayArs;
        final graphLabel = favorite.isBus && index >= 0 ? '정류장 순서' : '탑승 안내';
        return DecoratedBox(
          decoration: BoxDecoration(
            color: favorite.isBus
                ? palette.busContainer
                : palette.subwayContainer,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        graphLabel,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    RouteBadge(favorite),
                  ],
                ),
                const SizedBox(height: 9),
                CustomPaint(
                  size: const Size(double.infinity, 25),
                  painter: _TrackPainter(
                    color: color,
                    canvas: palette.surface,
                    count: labels.length,
                    active: active,
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (i, name) in labels.indexed)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Text(
                            name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.ink,
                              fontWeight: i == active
                                  ? FontWeight.w900
                                  : FontWeight.w500,
                              fontSize: i == active ? 15 : 12,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  children: [
                    TextButton.icon(
                      onPressed: () => openStopMap(context, favorite.title),
                      icon: const Icon(Icons.map_outlined, size: 17),
                      label: const Text('지도에서 보기'),
                      style: TextButton.styleFrom(
                        foregroundColor: color,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                    if (favorite.isBus)
                      TextButton.icon(
                        onPressed: widget.onOpenRoute,
                        icon: const Icon(Icons.route_outlined, size: 17),
                        label: const Text('전체 노선'),
                        style: TextButton.styleFrom(
                          foregroundColor: color,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    if (ars.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        child: Text(
                          ars,
                          style: TextStyle(color: color, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TrackPainter extends CustomPainter {
  const _TrackPainter({
    required this.color,
    required this.canvas,
    required this.count,
    required this.active,
  });

  final Color color;
  final Color canvas;
  final int count;
  final int active;

  @override
  void paint(Canvas drawing, Size size) {
    Offset node(int index) =>
        Offset(size.width * (index + 0.5) / count, size.height / 2);
    if (count > 1) {
      drawing.drawLine(
        node(0),
        node(count - 1),
        Paint()
          ..color = color.withValues(alpha: .75)
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
    }
    for (var i = 0; i < count; i++) {
      drawing.drawCircle(node(i), i == active ? 10 : 6, Paint()..color = color);
      drawing.drawCircle(node(i), i == active ? 5 : 3, Paint()..color = canvas);
    }
  }

  @override
  bool shouldRepaint(_TrackPainter oldDelegate) =>
      color != oldDelegate.color ||
      canvas != oldDelegate.canvas ||
      count != oldDelegate.count ||
      active != oldDelegate.active;
}

class BusRoutePage extends StatefulWidget {
  const BusRoutePage({super.key, required this.favorite});
  final Favorite favorite;

  @override
  State<BusRoutePage> createState() => _BusRoutePageState();
}

class _BusRoutePageState extends State<BusRoutePage> {
  late Future<List<TransitStop>> route = loadBusStops(widget.favorite.routeId);
  ScrollController? scroll;

  @override
  void dispose() {
    scroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final favorite = widget.favorite;
    final palette = TransitPalette.of(context);
    final color = routeInk(favorite, palette);
    return Scaffold(
      appBar: AppBar(title: Text('${favorite.line} 정류장')),
      body: SafeArea(
        child: FutureBuilder<List<TransitStop>>(
          future: route,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      route = loadBusStops(favorite.routeId);
                    });
                  },
                  child: const Text('노선을 불러오지 못했어요. 다시 시도'),
                ),
              );
            }
            final stops = snapshot.data ?? [];
            if (stops.isEmpty) {
              return const Center(child: Text('등록된 정류장이 없어요.'));
            }
            final selectedIndex = stops.indexWhere(
              (stop) => isSelectedStop(stop, favorite),
            );
            scroll ??= ScrollController(
              initialScrollOffset: selectedIndex > 1
                  ? (selectedIndex - 1) * 60.0
                  : 0,
            );
            return ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              itemCount: stops.length,
              itemBuilder: (context, i) {
                final stop = stops[i];
                final selected = isSelectedStop(stop, favorite);
                final subtitle = [
                  if (selected) '내 탑승 정류장',
                  if (stop.displayArs.isNotEmpty) stop.displayArs,
                ].join(' · ');
                return Material(
                  color: selected ? palette.busContainer : palette.surface,
                  child: InkWell(
                    onTap: () => openStopMap(context, stop.name),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 44,
                            height: 60,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Positioned(
                                  top: i == 0 ? 30 : 0,
                                  bottom: i == stops.length - 1 ? 30 : 0,
                                  child: ColoredBox(
                                    color: color,
                                    child: const SizedBox(width: 3),
                                  ),
                                ),
                                Container(
                                  width: selected ? 17 : 12,
                                  height: selected ? 17 : 12,
                                  decoration: BoxDecoration(
                                    color: selected ? color : palette.surface,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: color, width: 2),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 7),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    stop.name,
                                    style: TextStyle(
                                      fontWeight: selected
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                    ),
                                  ),
                                  if (subtitle.isNotEmpty)
                                    Text(
                                      subtitle,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: palette.muted,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          Icon(Icons.map_outlined, color: color, size: 19),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class TransitArrivalRow extends StatelessWidget {
  const TransitArrivalRow({
    super.key,
    required this.favorite,
    required this.reading,
    required this.selected,
    required this.onSelect,
    required this.onPin,
    required this.onEdit,
    required this.onRemove,
  });

  final Favorite favorite;
  final Arrivals reading;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onPin;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  String get statusText => switch (reading.status) {
    'loading' => '조회 중',
    'offline' => '실시간 정보 준비 중',
    'empty' => '도착 정보 없음',
    _ => '조회 실패',
  };

  String expected(int index) {
    if (reading.status == 'sample') {
      return (favorite.isBus ? ['5분 후', '12분 후'] : ['3분 후', '8분 후'])[index];
    }
    return reading.items[index].expected;
  }

  @override
  Widget build(BuildContext context) {
    final palette = TransitPalette.of(context);
    final color = routeInk(favorite, palette);
    final first = reading.items.firstOrNull;
    final meta = switch (reading.status) {
      'sample' => '예시 데이터',
      'live' || 'empty' when reading.checkedAt != null =>
        '${seoulClock(reading.checkedAt!)} 조회',
      _ => null,
    };
    final next = reading.items.length > 1 ? '다음 ${expected(1)}' : null;
    return Material(
      color: palette.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: selected ? color : palette.divider),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onSelect,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RouteBadge(favorite),
                        const SizedBox(height: 6),
                        Text(
                          favorite.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          favorite.direction,
                          style: TextStyle(color: palette.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          first == null ? statusText : expected(0),
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color: first == null
                                ? palette.muted
                                : palette.accent,
                            fontSize: first == null ? 13 : 22,
                            height: 1.22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (first?.detail case final String detail
                            when detail.isNotEmpty &&
                                detail != favorite.direction &&
                                reading.status != 'sample')
                          Text(
                            detail,
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              color: palette.muted,
                              fontSize: 11,
                            ),
                          ),
                        if (next != null)
                          Text(
                            next,
                            textAlign: TextAlign.end,
                            style: TextStyle(color: palette.ink, fontSize: 12),
                          ),
                        if (meta != null)
                          Text(
                            meta,
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              color: palette.muted,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.only(left: 5, right: 3),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: onPin,
                  icon: const Icon(Icons.add_to_home_screen_rounded, size: 16),
                  label: const Text('위젯 추가'),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  tooltip: '구간 옵션',
                  icon: Icon(Icons.more_horiz_rounded, color: palette.muted),
                  onSelected: (value) =>
                      value == 'edit' ? onEdit() : onRemove(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('구간 수정')),
                    PopupMenuItem(value: 'remove', child: Text('구간 삭제')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
