import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:smart_public_transportation/main.dart';
import 'package:smart_public_transportation/transit.dart';
import 'package:smart_public_transportation/widget_settings.dart';

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

  testWidgets('앱 테마와 위젯의 구간·표시 옵션을 Android에 전달한다', (tester) async {
    final requests = <MethodCall>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(transitChannel, (
      call,
    ) async {
      requests.add(call);
      return switch (call.method) {
        'theme' => 'light',
        'setTheme' => null,
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
    await tester.tap(find.byTooltip('어두운 앱 테마로 전환'));
    await tester.pumpAndSettle();
    expect(requests.last.method, 'setTheme');
    expect(requests.last.arguments, 'dark');
    expect(find.byTooltip('밝은 앱 테마로 전환'), findsOneWidget);

    await tester.tap(find.text('위젯 추가'));
    await tester.pumpAndSettle();
    expect(find.text('미리보기'), findsOneWidget);
    await tester.tap(find.text('밝게'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('도착 시각'), 120);
    await tester.tap(find.text('도착 시각'));
    await tester.pumpAndSettle();

    final direction = find.byKey(const ValueKey(WidgetField.direction));
    await tester.scrollUntilVisible(direction, 140);
    await tester.tap(direction);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(direction).value, isFalse);
    await tester.tap(find.text('홈 화면에 추가'));
    await tester.pumpAndSettle();
    expect(requests.last.method, 'pin');
    expect(requests.last.arguments, {
      'favoriteId': subway.id,
      'display': {
        'theme': 'light',
        'timeFormat': 'clock',
        'hidden': ['direction'],
      },
    });
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

  testWidgets('정류장 번호로 검색하고 같은 방향에 반복 정차하는 노선의 순번을 저장한다', (tester) async {
    const stop = '101000331';
    const name = '남산예장버스환승주차장';
    const direction = '충무로역2번출구 방면';
    Map<Object?, Object?>? saved;
    var searches = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(transitChannel, (
      call,
    ) async {
      switch (call.method) {
        case 'load':
          return {'favorites': [], 'subwaySet': false, 'busSet': false};
        case 'searchBusStops':
          expect(call.arguments, '02291');
          if (++searches == 1) throw PlatformException(code: 'transit');
          return [
            {'id': stop, 'name': name, 'ars': '02291'},
          ];
        case 'busRoutesAtStop':
          expect(call.arguments, stop);
          return [
            for (final order in ['1', '8'])
              Favorite(
                kind: 'bus',
                line: '01B',
                title: name,
                direction: direction,
                routeId: '106000004',
                stopId: stop,
                selector: order,
              ).toMap(),
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
    await tester.tap(find.text('정류장으로 찾기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '02291');
    await tester.pump();
    await tester.tap(find.byTooltip('정류장 검색'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('정류장을 불러오지 못했어요. 다시 시도'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '02291'));
    await tester.pumpAndSettle();
    expect(find.text('$direction · 노선의 1번째 정류장'), findsOneWidget);
    final secondVisit = find.text('$direction · 노선의 8번째 정류장');
    await tester.tap(secondVisit);
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    await tester.tap(secondVisit);
    await tester.pumpAndSettle();
    await tester.tap(find.text('구간 저장'));
    await tester.pumpAndSettle();

    final favorite = (saved!['favorites'] as List).single as Map;
    expect(favorite['stopId'], stop);
    expect(favorite['routeId'], '106000004');
    expect(favorite['selector'], '8');
    expect(find.text(name), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
