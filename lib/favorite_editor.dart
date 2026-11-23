import 'package:flutter/material.dart';

import 'transit.dart';

class FavoriteEditor extends StatefulWidget {
  const FavoriteEditor({super.key, this.original});

  final Favorite? original;

  @override
  State<FavoriteEditor> createState() => _FavoriteEditorState();
}

class _FavoriteEditorState extends State<FavoriteEditor> {
  static const lines = {
    '1001': '1호선',
    '1002': '2호선',
    '1003': '3호선',
    '1004': '4호선',
    '1005': '5호선',
    '1006': '6호선',
    '1007': '7호선',
    '1008': '8호선',
    '1009': '9호선',
    '1032': 'GTX-A',
    '1063': '경의중앙선',
    '1065': '공항철도',
    '1067': '경춘선',
    '1075': '수인분당선',
    '1077': '신분당선',
    '1092': '우이신설선',
    '1093': '서해선',
    '1081': '경강선',
    '1094': '신림선',
  };

  final station = TextEditingController();
  final busQuery = TextEditingController();
  final stopQuery = TextEditingController();
  late String kind;
  String? line;
  String? direction;
  List<Map<String, String>> routes = [];
  List<Map<String, String>> stops = [];
  Map<String, String>? busRoute;
  Map<String, String>? busStop;
  bool loading = false;
  String? notice;
  final form = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final original = widget.original;
    kind = original?.kind ?? 'subway';
    if (original == null) return;
    if (original.isBus) {
      busQuery.text = original.line;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await searchRoutes();
        if (!mounted) return;
        final route = routes
            .where((route) => route['id'] == original.routeId)
            .firstOrNull;
        if (route == null || kind != 'bus') return;
        await selectRoute(route);
        if (!mounted || busRoute != route) return;
        setState(() {
          busStop = stops
              .where((stop) => stop['order'] == original.selector)
              .firstOrNull;
        });
      });
    } else {
      station.text = original.stopId;
      line = original.routeId;
      direction = original.selector;
    }
  }

  @override
  void dispose() {
    station.dispose();
    busQuery.dispose();
    stopQuery.dispose();
    super.dispose();
  }

  Future<void> searchRoutes() async {
    final query = busQuery.text.trim();
    if (query.isEmpty || loading) return;
    setState(() {
      loading = true;
      notice = null;
      busRoute = null;
      busStop = null;
      routes = [];
      stops = [];
      stopQuery.clear();
    });
    try {
      final data = await transitChannel.invokeListMethod<Map<Object?, Object?>>(
        'busRoutes',
        query,
      );
      if (!mounted) return;
      setState(() {
        routes = (data ?? []).map(Map<String, String>.from).toList();
        if (routes.isEmpty) notice = '일치하는 노선이 없어요.';
      });
    } catch (_) {
      if (mounted) setState(() => notice = '노선을 불러오지 못했어요.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> selectRoute(Map<String, String> route) async {
    setState(() {
      loading = true;
      notice = null;
      busRoute = route;
      busStop = null;
      stops = [];
      stopQuery.clear();
    });
    try {
      final data = await transitChannel.invokeListMethod<Map<Object?, Object?>>(
        'busStops',
        route['id'],
      );
      if (!mounted) return;
      setState(() {
        stops = (data ?? []).map(Map<String, String>.from).toList();
        if (stops.isEmpty) notice = '이 노선에 등록된 정류장이 없어요.';
      });
    } catch (_) {
      if (mounted) setState(() => notice = '정류장을 불러오지 못했어요.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String get stationName {
    final raw = station.text.trim();
    return switch (raw) {
      '녹사평역' => '녹사평',
      '서울역' => '서울',
      _ => raw,
    };
  }

  Map<String, String> get directions => line == '1002'
      ? {'내선': '내선순환', '외선': '외선순환', '상행': '지선 상행', '하행': '지선 하행'}
      : line == '1006' && stationName == '녹사평'
      ? {'상행': '응암 방면', '하행': '봉화산·신내 방면'}
      : {'상행': '상행', '하행': '하행'};

  void save() {
    if (kind == 'bus') {
      final route = busRoute!;
      final stop = busStop!;
      final next = stop['next']!;
      Navigator.pop(
        context,
        Favorite(
          kind: kind,
          line: route['name']!,
          title: stop['name']!,
          direction: next.isEmpty ? '종점' : '$next 방면',
          routeId: route['id']!,
          stopId: stop['id']!,
          selector: stop['order']!,
        ),
      );
      return;
    }
    if (!form.currentState!.validate()) return;
    final name = stationName;
    Navigator.pop(
      context,
      Favorite(
        kind: kind,
        line: lines[line]!,
        title: name.endsWith('역') ? name : '$name역',
        direction: directions[direction]!,
        routeId: line!,
        stopId: name,
        selector: direction!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = kind == 'bus'
        ? busStop != null
        : line != null && direction != null;
    return Scaffold(
      appBar: AppBar(title: Text(widget.original == null ? '구간 추가' : '구간 수정')),
      body: SafeArea(
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'subway',
                    label: Text('지하철'),
                    icon: Icon(Icons.train_outlined),
                  ),
                  ButtonSegment(
                    value: 'bus',
                    label: Text('버스'),
                    icon: Icon(Icons.directions_bus_outlined),
                  ),
                ],
                selected: {kind},
                onSelectionChanged: widget.original == null && !loading
                    ? (values) => setState(() => kind = values.single)
                    : null,
              ),
              const SizedBox(height: 24),
              if (kind == 'subway') ...subwayFields() else ...busFields(),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: ready && !loading ? save : null,
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('구간 저장'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> subwayFields() => [
    TextFormField(
      controller: station,
      decoration: const InputDecoration(
        labelText: '역 이름',
        hintText: '녹사평, 서울, 서울대입구',
        helperText: '서울시 API에 등록된 역 이름을 입력해 주세요.',
        prefixIcon: Icon(Icons.search),
      ),
      onChanged: (_) => setState(() {}),
      validator: (value) =>
          (value ?? '').trim().isEmpty ? '역 이름을 입력해 주세요.' : null,
      maxLength: 50,
    ),
    DropdownButtonFormField<String>(
      initialValue: line,
      decoration: const InputDecoration(labelText: '노선'),
      items: [
        for (final entry in lines.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: (value) => setState(() {
        line = value;
        direction = null;
      }),
    ),
    const SizedBox(height: 16),
    DropdownButtonFormField<String>(
      key: ValueKey(line),
      initialValue: direction,
      decoration: const InputDecoration(labelText: '탑승 방향'),
      items: [
        for (final entry in directions.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: line == null
          ? null
          : (value) => setState(() => direction = value),
    ),
  ];

  List<Widget> busFields() {
    final query = stopQuery.text.trim().replaceAll(' ', '');
    final shown = stops.where(
      (stop) =>
          stop['name']!.replaceAll(' ', '').contains(query) ||
          stop['ars']!.contains(query),
    );
    return [
      TextField(
        controller: busQuery,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => searchRoutes(),
        decoration: InputDecoration(
          labelText: '버스 번호',
          hintText: '용산03',
          prefixIcon: const Icon(Icons.directions_bus_outlined),
          suffixIcon: IconButton(
            onPressed: loading ? null : searchRoutes,
            tooltip: '노선 검색',
            icon: const Icon(Icons.search),
          ),
        ),
      ),
      if (loading)
        const Padding(
          padding: EdgeInsets.only(top: 14),
          child: LinearProgressIndicator(),
        ),
      if (notice case final message?)
        Padding(padding: const EdgeInsets.only(top: 12), child: Text(message)),
      if (routes.isNotEmpty) ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<Map<String, String>>(
          key: ValueKey(routes),
          initialValue: busRoute,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '노선'),
          items: [
            for (final route in routes)
              DropdownMenuItem(
                value: route,
                child: Text(
                  "${route['name']} · ${route['ends']}",
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: loading
              ? null
              : (route) {
                  if (route != null) selectRoute(route);
                },
        ),
      ],
      if (stops.isNotEmpty) ...[
        const SizedBox(height: 16),
        TextField(
          controller: stopQuery,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: '정류장 검색',
            hintText: '삼각지역 또는 03567',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 8),
        if (shown.isEmpty) const ListTile(title: Text('일치하는 정류장이 없어요.')),
        RadioGroup<String>(
          groupValue: busStop?['order'],
          onChanged: (order) => setState(() {
            busStop = stops.firstWhere((stop) => stop['order'] == order);
          }),
          child: Column(
            children: [
              for (final stop in shown)
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: stop['order']!,
                  title: Text(stop['name']!),
                  subtitle: Text(
                    [
                      if (stop['ars']!.isNotEmpty && stop['ars'] != '0')
                        stop['ars']!,
                      if (stop['next']!.isNotEmpty)
                        "${stop['next']} 방면"
                      else
                        '종점',
                    ].join(' · '),
                  ),
                ),
            ],
          ),
        ),
      ],
    ];
  }
}
