import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'transit.dart';

class BusStopSearchPage extends StatefulWidget {
  const BusStopSearchPage({super.key});

  @override
  State<BusStopSearchPage> createState() => _BusStopSearchPageState();
}

class _BusStopSearchPageState extends State<BusStopSearchPage> {
  final query = TextEditingController();
  Future<List<Map<String, String>>?>? results;

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  void search() {
    final text = query.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      results = loadStops(text);
    });
  }

  Future<List<Map<String, String>>?> loadStops(String text) async {
    try {
      final stops = await transitChannel
          .invokeListMethod<Map<Object?, Object?>>('searchBusStops', text);
      return (stops ?? []).map(Map<String, String>.from).toList();
    } on PlatformException {
      return null;
    }
  }

  Future<void> selectStop(Map<String, String> stop) async {
    final favorite = await Navigator.of(context).push<Favorite>(
      MaterialPageRoute(
        builder: (_) =>
            _RoutesAtStopPage(stopId: stop['id']!, name: stop['name']!),
      ),
    );
    if (mounted && favorite != null) Navigator.pop(context, favorite);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('버스 정류장 찾기')),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: TextField(
              controller: query,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() => results = null),
              onSubmitted: (_) => search(),
              decoration: InputDecoration(
                labelText: '정류장 이름 또는 번호',
                hintText: '삼각지역 또는 03567',
                suffixIcon: IconButton(
                  onPressed: query.text.trim().isEmpty ? null : search,
                  tooltip: '정류장 검색',
                  icon: const Icon(Icons.search),
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, String>>?>(
              future: results,
              builder: (context, snapshot) {
                if (results == null) return const SizedBox.shrink();
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Align(
                    alignment: Alignment.topCenter,
                    child: LinearProgressIndicator(),
                  );
                }
                final stops = snapshot.data;
                if (stops == null) {
                  return Center(
                    child: TextButton(
                      onPressed: search,
                      child: const Text('정류장을 불러오지 못했어요. 다시 시도'),
                    ),
                  );
                }
                if (stops.isEmpty) {
                  return const Center(child: Text('일치하는 정류장이 없어요.'));
                }
                return ListView.builder(
                  itemCount: stops.length,
                  itemBuilder: (context, index) {
                    final stop = stops[index];
                    final number = stop['ars']!;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                      ),
                      title: Text(stop['name']!),
                      subtitle: number.isEmpty || number == '0'
                          ? null
                          : Text(number),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => selectStop(stop),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _RoutesAtStopPage extends StatefulWidget {
  const _RoutesAtStopPage({required this.stopId, required this.name});

  final String stopId;
  final String name;

  @override
  State<_RoutesAtStopPage> createState() => _RoutesAtStopPageState();
}

class _RoutesAtStopPageState extends State<_RoutesAtStopPage> {
  late Future<List<Favorite>?> routes;

  @override
  void initState() {
    super.initState();
    routes = loadRoutes();
  }

  Future<List<Favorite>?> loadRoutes() async {
    try {
      final data = await transitChannel.invokeListMethod<Map<Object?, Object?>>(
        'busRoutesAtStop',
        widget.stopId,
      );
      return (data ?? []).map(Favorite.fromMap).toList();
    } on PlatformException {
      return null;
    }
  }

  Future<void> confirm(Favorite favorite, String direction) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${favorite.line} · ${favorite.title}'),
        content: Text(direction),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('구간 저장'),
          ),
        ],
      ),
    );
    if (mounted && saved == true) Navigator.pop(context, favorite);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.name)),
    body: SafeArea(
      child: FutureBuilder<List<Favorite>?>(
        future: routes,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(),
            );
          }
          final favorites = snapshot.data;
          if (favorites == null) {
            return Center(
              child: TextButton(
                onPressed: () => setState(() {
                  routes = loadRoutes();
                }),
                child: const Text('노선을 불러오지 못했어요. 다시 시도'),
              ),
            );
          }
          if (favorites.isEmpty) {
            return const Center(child: Text('이 정류장에 등록된 노선이 없어요.'));
          }
          final directionCounts = <(String, String), int>{};
          for (final favorite in favorites) {
            final key = (favorite.line, favorite.direction);
            directionCounts.update(
              key,
              (count) => count + 1,
              ifAbsent: () => 1,
            );
          }
          return ListView.builder(
            itemCount: favorites.length,
            itemBuilder: (context, index) {
              final favorite = favorites[index];
              final repeated =
                  directionCounts[(favorite.line, favorite.direction)]! > 1;
              final direction = repeated
                  ? '${favorite.direction} · 노선의 ${favorite.selector}번째 정류장'
                  : favorite.direction;
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                title: Text(favorite.line),
                subtitle: Text(direction),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => confirm(favorite, direction),
              );
            },
          );
        },
      ),
    ),
  );
}
