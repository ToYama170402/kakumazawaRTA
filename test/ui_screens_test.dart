import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hoge/measurement/location_provider.dart';
import 'package:hoge/measurement/position.dart';
import 'package:hoge/rankings/ranking.dart';
import 'package:hoge/routes/route_cache_storage.dart';
import 'package:hoge/routes/route_definition.dart';
import 'package:hoge/routes/route_remote_data_source.dart';
import 'package:hoge/routes/route_repository.dart';
import 'package:hoge/ui/main_screen.dart';
import 'package:hoge/ui/measuring_screen.dart';
import 'package:hoge/ui/name_entry_screen.dart';
import 'package:hoge/ui/ranking_screen.dart';

RouteDefinition fixtureRoute() {
  return const RouteDefinition(
    id: 'route-1',
    category: '徒歩',
    routeName: '角間キャンパス線',
    startBounds: RouteBounds(
      minLatitude: 36.50,
      minLongitude: 136.70,
      maxLatitude: 36.51,
      maxLongitude: 136.71,
    ),
    goalBounds: RouteBounds(
      minLatitude: 36.60,
      minLongitude: 136.70,
      maxLatitude: 36.61,
      maxLongitude: 136.71,
    ),
    maxVelocityThreshold: 10,
    avgVelocityThreshold: 8,
  );
}

class _FakeRemote implements RouteRemoteDataSource {
  @override
  Future<List<RouteDefinition>> fetchRoutes() async =>
      const <RouteDefinition>[];
}

class _ScriptedLocationProvider implements LocationProvider {
  _ScriptedLocationProvider(this.points);

  final List<GeoPoint> points;
  int _index = 0;

  @override
  Future<GeoPoint> getCurrentLocation() async {
    final point = points[_index < points.length ? _index : points.length - 1];
    _index++;
    return point;
  }
}

class _FakeRankingRepository implements RankingRepository {
  final List<String> requestedPeriods = <String>[];

  @override
  Future<List<RankingEntry>> fetch({
    required String period,
    String? organizationCode,
  }) async {
    requestedPeriods.add(period);
    if (period == 'all') {
      return const <RankingEntry>[
        RankingEntry(
          rank: 1,
          runId: 'run-old',
          nickname: '歴代覇者',
          organizationCode: 'science',
          totalSeconds: 300,
          rankGrade: 'S',
          termIdentifier: '2026-05',
        ),
      ];
    }
    return const <RankingEntry>[
      RankingEntry(
        rank: 1,
        runId: 'run-1',
        nickname: '今月一位',
        organizationCode: 'science',
        totalSeconds: 320,
        rankGrade: 'S',
        termIdentifier: '2026-06',
      ),
      RankingEntry(
        rank: 2,
        runId: 'run-2',
        nickname: '今月二位',
        organizationCode: 'engineering',
        totalSeconds: 400,
        rankGrade: 'A',
        termIdentifier: '2026-06',
      ),
    ];
  }
}

void main() {
  testWidgets('メイン画面: 種目別ルートから計測画面へ進める', (tester) async {
    final repository = RouteRepository(
      remoteDataSource: _FakeRemote(),
      cacheStorage: MemoryRouteCacheStorage([fixtureRoute()]),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MainScreen(
          repository: repository,
          rankingsRepository: _FakeRankingRepository(),
          locationProvider: _ScriptedLocationProvider(const []),
          organizationDisplayName: '融合学域',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('徒歩'), findsOneWidget);
    expect(find.text('角間キャンパス線'), findsOneWidget);

    await tester.tap(find.text('計測開始'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(MeasuringScreen), findsOneWidget);
    expect(find.text('開始ボタンを押してください'), findsOneWidget);
  });

  testWidgets('計測フロー: 入域で開始、ゴールで停止し、ネーム入力を経て確定する', (tester) async {
    final base = DateTime.utc(2026, 6, 30, 8);
    GeoPoint at(double lat, double lng, int sec) => GeoPoint(
      latitude: lat,
      longitude: lng,
      timestamp: base.add(Duration(seconds: sec)),
    );
    final provider = _ScriptedLocationProvider([
      at(36.0, 136.0, 0), // 範囲外
      at(36.505, 136.705, 1), // start 入域
      at(36.55, 136.705, 2), // 途中
      at(36.605, 136.705, 3), // goal 到達
    ]);

    List<GeoPoint>? finishedHistory;
    String? finishedNickname;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => MeasuringScreen(
                        route: fixtureRoute(),
                        locationProvider: provider,
                        organizationDisplayName: '融合学域',
                        onFinished: (history, nickname) async {
                          finishedHistory = history;
                          finishedNickname = nickname;
                        },
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('計測開始'));
    await tester.pump();

    // 1秒周期サンプリングを進める
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    }

    // ゴール後はネーム入力画面にいる
    expect(find.byType(NameEntryScreen), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'たろう');
    await tester.tap(find.text('この内容で登録する'));
    await tester.pumpAndSettle();

    expect(finishedNickname, 'たろう');
    expect(finishedHistory, isNotNull);
    // 範囲外の点は含まず、start〜goal の3点が履歴になる
    expect(finishedHistory!.length, 3);
    expect(find.byType(MeasuringScreen), findsNothing);
  });

  testWidgets('順位表画面: 今月/歴代の切り替えと一覧表示', (tester) async {
    final repository = _FakeRankingRepository();

    await tester.pumpWidget(
      MaterialApp(home: RankingScreen(repository: repository)),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('今月一位'), findsOneWidget);
    expect(find.text('今月二位'), findsOneWidget);

    await tester.tap(find.text('歴代'));
    await tester.pump();
    await tester.pump();

    expect(find.text('歴代覇者'), findsOneWidget);
    expect(repository.requestedPeriods, contains('all'));
  });

  test('RankingEntry.fromJson は整数秒も double で読む', () {
    final entry = RankingEntry.fromJson(<String, dynamic>{
      'rank': 1,
      'run_id': 'run-1',
      'nickname': 'a',
      'organization_code': 'science',
      'total_seconds': 300,
      'rank_grade': null,
      'term_identifier': '2026-06',
    });
    expect(entry.totalSeconds, 300.0);
    expect(entry.rankGrade, isNull);
  });
}
