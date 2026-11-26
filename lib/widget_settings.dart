import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'transit.dart';
import 'transit_theme.dart';

const widgetSettingsRoute = '/widget-settings';
const widgetSettingsChannel = MethodChannel('transit/widget_settings');

enum WidgetField {
  line('노선 번호'),
  stop('정류장·역 이름'),
  direction('탑승 방향·다음 정류장'),
  first('첫 도착'),
  next('다음 도착'),
  updated('조회 시각'),
  refresh('새로고침 버튼');

  const WidgetField(this.label);
  final String label;
}

class WidgetDisplay {
  const WidgetDisplay({
    this.dark = true,
    this.remaining = false,
    this.hidden = const {},
  });

  factory WidgetDisplay.fromMap(Map<Object?, Object?> data) {
    final names = (data['hidden'] as List<Object?>?) ?? const [];
    return WidgetDisplay(
      dark: data['theme'] != 'light',
      remaining: data['timeFormat'] == 'remaining',
      hidden: WidgetField.values
          .where((field) => names.contains(field.name))
          .toSet(),
    );
  }

  final bool dark;
  final bool remaining;
  final Set<WidgetField> hidden;

  bool shows(WidgetField field) => !hidden.contains(field);
  bool get showsArrival => shows(WidgetField.first) || shows(WidgetField.next);

  WidgetDisplay copyWith({
    bool? dark,
    bool? remaining,
    Set<WidgetField>? hidden,
  }) => WidgetDisplay(
    dark: dark ?? this.dark,
    remaining: remaining ?? this.remaining,
    hidden: hidden ?? this.hidden,
  );

  Map<String, Object?> toMap() => {
    'theme': dark ? 'dark' : 'light',
    'timeFormat': remaining ? 'remaining' : 'clock',
    'hidden': hidden.map((field) => field.name).toList(),
  };
}

class WidgetSettingsPage extends StatefulWidget {
  const WidgetSettingsPage({
    super.key,
    this.favorites,
    this.selectedId,
    this.initialDisplay = const WidgetDisplay(),
  });

  final List<Favorite>? favorites;
  final String? selectedId;
  final WidgetDisplay initialDisplay;

  @override
  State<WidgetSettingsPage> createState() => _WidgetSettingsPageState();
}

class _WidgetSettingsPageState extends State<WidgetSettingsPage> {
  List<Favorite>? favorites;
  String? selectedId;
  late WidgetDisplay display;
  bool saving = false;
  bool loadFailed = false;

  bool get configuringExistingWidget => widget.favorites == null;

  @override
  void initState() {
    super.initState();
    favorites = widget.favorites;
    selectedId = widget.selectedId;
    display = widget.initialDisplay;
    if (configuringExistingWidget) load();
  }

  Future<void> load() async {
    setState(() => loadFailed = false);
    try {
      final settings = await widgetSettingsChannel
          .invokeMapMethod<Object?, Object?>('load');
      if (settings == null) throw StateError('Widget settings are unavailable');
      final saved = (settings['favorites'] as List<Object?>)
          .cast<Map<Object?, Object?>>()
          .map(Favorite.fromMap)
          .toList();
      final selected = saved
          .where((favorite) => favorite.id == settings['favoriteId'])
          .firstOrNull;
      if (!mounted) return;
      setState(() {
        favorites = saved;
        selectedId = selected?.id ?? saved.firstOrNull?.id;
        display = WidgetDisplay.fromMap(
          settings['display'] as Map<Object?, Object?>,
        );
      });
    } catch (_) {
      if (mounted) setState(() => loadFailed = true);
    }
  }

  Future<void> save() async {
    final id = selectedId;
    if (id == null || saving) return;
    final payload = {'favoriteId': id, 'display': display.toMap()};
    setState(() => saving = true);
    try {
      if (configuringExistingWidget) {
        await widgetSettingsChannel.invokeMethod<void>('save', payload);
        return;
      }
      final pinned = await transitChannel.invokeMethod<bool>('pin', payload);
      if (!mounted) return;
      if (pinned == true) {
        Navigator.pop(context);
      } else {
        feedback('홈 화면을 길게 누르고 위젯 목록에서 ‘언제와’를 찾아 주세요.');
      }
    } catch (_) {
      if (mounted) feedback('위젯 설정을 저장하지 못했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> openApp() async {
    try {
      await widgetSettingsChannel.invokeMethod<void>('openApp');
    } catch (_) {
      if (mounted) feedback('앱을 열지 못했어요.');
    }
  }

  void feedback(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final saved = favorites;
    final selected = saved
        ?.where((favorite) => favorite.id == selectedId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        leading: configuringExistingWidget
            ? BackButton(onPressed: SystemNavigator.pop)
            : null,
        title: const Text('위젯 설정'),
      ),
      bottomNavigationBar: selected == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(18, 8, 18, 10),
              child: FilledButton.icon(
                onPressed: saving ? null : save,
                icon: Icon(
                  configuringExistingWidget
                      ? Icons.check_rounded
                      : Icons.add_to_home_screen_rounded,
                ),
                label: Text(
                  configuringExistingWidget ? '위젯 설정 저장' : '홈 화면에 추가',
                ),
              ),
            ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: loadFailed
                ? Center(
                    child: TextButton(
                      onPressed: load,
                      child: const Text('설정을 불러오지 못했어요. 다시 시도'),
                    ),
                  )
                : saved == null
                ? const Center(child: CircularProgressIndicator())
                : selected == null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('언제와 앱에서 위젯에 표시할 구간을 먼저 저장해 주세요.'),
                        if (configuringExistingWidget)
                          TextButton(
                            onPressed: openApp,
                            child: const Text('앱 열기'),
                          ),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
                    children: [
                      heading(context, '미리보기'),
                      const SizedBox(height: 8),
                      _WidgetPreview(favorite: selected, display: display),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<String>(
                        initialValue: selected.id,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '표시할 정류장·역',
                        ),
                        items: [
                          for (final favorite in saved)
                            DropdownMenuItem(
                              value: favorite.id,
                              child: Text(
                                '${favorite.line} · ${favorite.title} · ${favorite.direction}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: saving
                            ? null
                            : (value) => setState(() => selectedId = value),
                      ),
                      const SizedBox(height: 20),
                      heading(context, '위젯 테마'),
                      const SizedBox(height: 8),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: false,
                            icon: Icon(Icons.light_mode_outlined),
                            label: Text('밝게'),
                          ),
                          ButtonSegment(
                            value: true,
                            icon: Icon(Icons.dark_mode_outlined),
                            label: Text('어둡게'),
                          ),
                        ],
                        selected: {display.dark},
                        onSelectionChanged: saving
                            ? null
                            : (value) => setState(() {
                                display = display.copyWith(dark: value.single);
                              }),
                      ),
                      const SizedBox(height: 18),
                      heading(context, '도착 시간 표시 방식'),
                      const SizedBox(height: 8),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('도착 시각')),
                          ButtonSegment(value: true, label: Text('남은 시간')),
                        ],
                        selected: {display.remaining},
                        onSelectionChanged: saving || !display.showsArrival
                            ? null
                            : (value) => setState(() {
                                display = display.copyWith(
                                  remaining: value.single,
                                );
                              }),
                      ),
                      if (display.remaining && display.showsArrival)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text('남은 시간은 마지막으로 조회했을 때를 기준으로 표시해요.'),
                        ),
                      const SizedBox(height: 18),
                      heading(context, '표시 항목'),
                      for (final field in WidgetField.values)
                        SwitchListTile(
                          key: ValueKey(field),
                          title: Text(field.label),
                          contentPadding: EdgeInsets.zero,
                          value: display.shows(field),
                          onChanged: saving
                              ? null
                              : (show) => setState(() {
                                  final hidden = {...display.hidden};
                                  if (show) {
                                    hidden.remove(field);
                                  } else {
                                    hidden.add(field);
                                  }
                                  display = display.copyWith(hidden: hidden);
                                }),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget heading(BuildContext context, String title) => Text(
    title,
    style: Theme.of(context).textTheme.titleSmall
        ?.copyWith(fontWeight: FontWeight.w800),
  );
}

class _WidgetPreview extends StatelessWidget {
  const _WidgetPreview({required this.favorite, required this.display});

  final Favorite favorite;
  final WidgetDisplay display;

  @override
  Widget build(BuildContext context) {
    final palette = display.dark ? TransitPalette.dark : TransitPalette.light;
    final first = display.shows(WidgetField.first);
    final next = display.shows(WidgetField.next);
    final line = display.shows(WidgetField.line);
    final stop = display.shows(WidgetField.stop);
    final direction = display.shows(WidgetField.direction);
    final refresh = display.shows(WidgetField.refresh);
    final header = line || stop || direction || refresh;
    final updated = display.shows(WidgetField.updated);
    final firstValue = display.remaining
        ? (favorite.isBus ? '5분 후' : '3분 후')
        : (favorite.isBus ? '08:35' : '08:33');
    final nextValue = display.remaining
        ? (favorite.isBus ? '12분 후' : '8분 후')
        : (favorite.isBus ? '08:42' : '08:38');
    return Container(
      key: const ValueKey('widget-preview'),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.divider),
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header)
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (line || stop)
                        Row(
                          children: [
                            if (line)
                              Container(
                                constraints: const BoxConstraints(
                                  maxWidth: 100,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: favorite.isBus
                                      ? palette.busContainer
                                      : palette.subwayContainer,
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: Text(
                                  favorite.line,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: favorite.isBus
                                        ? palette.bus
                                        : palette.subway,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            if (line && stop) const SizedBox(width: 7),
                            if (stop)
                              Expanded(
                                child: Text(
                                  favorite.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: palette.ink,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      if (direction)
                        Text(
                          favorite.direction,
                          style: TextStyle(color: palette.muted, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                if (refresh)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: CircleAvatar(
                      radius: 17,
                      backgroundColor: TransitPalette.marker,
                      foregroundColor: TransitPalette.markerInk,
                      child: Icon(Icons.refresh_rounded, size: 20),
                    ),
                  ),
              ],
            ),
          if (header && (first || next))
            Divider(color: palette.divider, height: 16),
          if (first || next)
            Row(
              children: [
                if (first)
                  Expanded(
                    child: timing(palette, '첫 도착', firstValue, primary: true),
                  ),
                if (first && next) const SizedBox(width: 8),
                if (next) Expanded(child: timing(palette, '다음 도착', nextValue)),
              ],
            ),
          if (updated || first || next)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                updated ? '예시 데이터 · 08:30 조회' : '예시 데이터',
                style: TextStyle(color: palette.muted, fontSize: 11),
              ),
            ),
          if (!header && !updated && !first && !next)
            Text(
              '위젯 설정',
              style: TextStyle(color: palette.ink, fontWeight: FontWeight.w800),
            ),
        ],
      ),
    );
  }

  Widget timing(
    TransitPalette palette,
    String label,
    String time, {
    bool primary = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(color: palette.muted, fontSize: 11)),
      Text(
        time,
        style: TextStyle(
          color: primary ? palette.accent : palette.ink,
          fontSize: primary ? 27 : 21,
          fontWeight: FontWeight.w900,
        ),
      ),
    ],
  );
}
