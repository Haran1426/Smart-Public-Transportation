import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_public_transportation/main.dart';
import 'package:smart_public_transportation/transit.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  const subway = Favorite(
    kind: 'subway',
    line: '6호선',
    title: '녹사평역',
    direction: '응암 방면',
    routeId: '1006',
    stopId: '녹사평',
    selector: '상행',
  );

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      transitChannel,
      null,
    );
  });

  testWidgets('예시를 표시하고 선택한 구간을 Android 위젯에 전달한다', (tester) async {
    final requests = <MethodCall>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(transitChannel, (
      call,
    ) async {
      requests.add(call);
      return switch (call.method) {
        'load' => {
          'favorites': [subway.toMap()],
          'subwaySet': false,
          'busSet': false,
        },
        'arrivals' => {
          'status': 'sample',
          'checkedAt': 0,
          'arrivals': [
            {'at': null, 'message': '', 'detail': ''},
            {'at': null, 'message': '', 'detail': ''},
          ],
        },
        'pin' => true,
        _ => throw MissingPluginException(),
      };
    });

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('녹사평역'), findsOneWidget);
    expect(find.text('예시 데이터'), findsOneWidget);
    expect(find.text('3분 후'), findsOneWidget);
    await tester.tap(find.text('위젯 추가'));
    expect(requests.last.method, 'pin');
    expect(requests.last.arguments, subway.id);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('용산03 검색에서 선택한 삼각지역 정류장과 순번을 저장한다', (tester) async {
    Map<Object?, Object?>? saved;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(transitChannel, (
      call,
    ) async {
      switch (call.method) {
        case 'load':
          return {'favorites': [], 'subwaySet': false, 'busSet': false};
        case 'busRoutes':
          expect(call.arguments, '용산03');
          return [
            {'id': '102900004', 'name': '용산03', 'ends': '하얏트호텔 출발'},
          ];
        case 'busStops':
          return [
            {
              'id': '102000234',
              'order': '10',
              'ars': '03328',
              'name': '삼각지역11번출구.전쟁기념관',
              'next': '남영역.민주화운동기념관',
            },
            {
              'id': '102900058',
              'order': '22',
              'ars': '03567',
              'name': '삼각지역',
              'next': '전쟁기념관',
            },
          ];
        case 'saveFavorites':
          saved = call.arguments as Map<Object?, Object?>;
          return null;
        case 'arrivals':
          return {'status': 'needsKey', 'checkedAt': 0, 'arrivals': []};
        default:
          throw MissingPluginException();
      }
    });

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('구간 추가'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('버스'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '용산03');
    await tester.tap(find.byTooltip('노선 검색'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('노선'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('용산03 · 하얏트호텔 출발').last);
    await tester.pumpAndSettle();
    expect(find.text('03328 · 남영역.민주화운동기념관 방면'), findsOneWidget);
    await tester.ensureVisible(find.text('삼각지역'));
    await tester.tap(find.text('삼각지역'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('구간 저장'));
    await tester.tap(find.text('구간 저장'));
    await tester.pumpAndSettle();

    final favorite = (saved!['favorites'] as List).single as Map;
    expect(favorite['stopId'], '102900058');
    expect(favorite['selector'], '22');
    expect(find.text('삼각지역'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
