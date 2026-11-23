import 'package:flutter/services.dart';

const transitChannel = MethodChannel('transit/transport');

class Favorite {
  const Favorite({
    required this.kind,
    required this.line,
    required this.title,
    required this.direction,
    required this.routeId,
    required this.stopId,
    required this.selector,
  });

  factory Favorite.fromMap(Map<Object?, Object?> data) => Favorite(
    kind: data['kind'] as String,
    line: data['line'] as String,
    title: data['title'] as String,
    direction: data['direction'] as String,
    routeId: data['routeId'] as String,
    stopId: data['stopId'] as String,
    selector: data['selector'] as String,
  );

  final String kind;
  final String line;
  final String title;
  final String direction;
  final String routeId;
  final String stopId;
  final String selector;

  String get id => '$kind/$routeId/$stopId/$selector';
  bool get isBus => kind == 'bus';

  Map<String, String> toMap() => {
    'kind': kind,
    'line': line,
    'title': title,
    'direction': direction,
    'routeId': routeId,
    'stopId': stopId,
    'selector': selector,
  };
}

class Arrival {
  Arrival(Map<Object?, Object?> data)
    : time = data['at'] as int?,
      message = data['message'] as String,
      detail = data['detail'] as String;

  final int? time;
  final String message;
  final String detail;

  String get expected {
    final at = time;
    if (at == null) return message;
    final seconds = (at - DateTime.now().millisecondsSinceEpoch) / 1000;
    if (seconds < 0) return '예정 시각 지남';
    if (seconds < 60) return '곧 도착';
    return '${(seconds / 60).ceil()}분 후';
  }
}

class Arrivals {
  const Arrivals(this.status, [this.checkedAt, this.items = const []]);

  factory Arrivals.fromMap(Map<Object?, Object?> data) => Arrivals(
    data['status'] as String,
    data['checkedAt'] as int?,
    (data['arrivals'] as List<Object?>)
        .cast<Map<Object?, Object?>>()
        .map(Arrival.new)
        .toList(),
  );

  final String status;
  final int? checkedAt;
  final List<Arrival> items;
}

String seoulClock(int millis) {
  final time = DateTime.fromMillisecondsSinceEpoch(
    millis,
    isUtc: true,
  ).add(const Duration(hours: 9));
  return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}
