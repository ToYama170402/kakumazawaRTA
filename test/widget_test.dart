import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hoge/routes/route_cache_storage.dart';
import 'package:hoge/routes/route_definition.dart';
import 'package:hoge/routes/route_remote_data_source.dart';
import 'package:hoge/routes/route_repository.dart';
import 'package:hoge/routes/route_screen.dart';

void main() {
  testWidgets(
    'startup sync loads routes and manual refresh reuses the same flow',
    (WidgetTester tester) async {
      final repository = RouteRepository(
        remoteDataSource: _FakeRouteRemoteDataSource(
          routes: <RouteDefinition>[
            _route('route-1', 'Aルート'),
            _route('route-2', 'Bルート'),
          ],
        ),
        cacheStorage: MemoryRouteCacheStorage(),
      );

      await tester.pumpWidget(
        MaterialApp(home: RouteSyncScreen(repository: repository)),
      );

      await tester.pumpAndSettle();

      expect(find.text('2 件のルート'), findsOneWidget);
      expect(find.text('Aルート'), findsOneWidget);
      expect(find.text('Bルート'), findsOneWidget);

      await tester.tap(find.text('更新'));
      await tester.pumpAndSettle();

      expect(find.text('2 件のルート'), findsOneWidget);
    },
  );

  testWidgets('measuring mode blocks updates', (WidgetTester tester) async {
    final repository = RouteRepository(
      remoteDataSource: _FakeRouteRemoteDataSource(
        routes: <RouteDefinition>[_route('route-1', 'Aルート')],
      ),
      cacheStorage: MemoryRouteCacheStorage(),
    );

    await tester.pumpWidget(
      MaterialApp(home: RouteSyncScreen(repository: repository)),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pump();

    final updateButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '更新'),
    );
    expect(updateButton.onPressed, isNull);
    expect(find.text('計測中はルート同期を行いません。'), findsOneWidget);
  });

  testWidgets('offline failures keep cached routes', (
    WidgetTester tester,
  ) async {
    final cache = MemoryRouteCacheStorage(<RouteDefinition>[
      _route('cached-route', '保存済みルート'),
    ]);
    final repository = RouteRepository(
      remoteDataSource: _ThrowingRouteRemoteDataSource(),
      cacheStorage: cache,
    );

    await tester.pumpWidget(
      MaterialApp(home: RouteSyncScreen(repository: repository)),
    );

    await tester.pumpAndSettle();

    expect(find.text('保存済みルート'), findsOneWidget);
    expect(find.text('オフライン'), findsWidgets);
  });
}

RouteDefinition _route(String id, String name) {
  return RouteDefinition(
    id: id,
    category: '徒歩',
    routeName: name,
    goalBounds: const RouteBounds(
      minLatitude: 36.0,
      minLongitude: 136.0,
      maxLatitude: 36.1,
      maxLongitude: 136.1,
    ),
    startBounds: const RouteBounds(
      minLatitude: 35.9,
      minLongitude: 135.9,
      maxLatitude: 36.0,
      maxLongitude: 136.0,
    ),
    maxVelocityThreshold: 12,
    avgVelocityThreshold: 8,
  );
}

class _FakeRouteRemoteDataSource implements RouteRemoteDataSource {
  _FakeRouteRemoteDataSource({required this.routes});

  final List<RouteDefinition> routes;

  @override
  Future<List<RouteDefinition>> fetchRoutes() async {
    return routes;
  }
}

class _ThrowingRouteRemoteDataSource implements RouteRemoteDataSource {
  @override
  Future<List<RouteDefinition>> fetchRoutes() async {
    throw const RouteRemoteConfigurationException('offline');
  }
}
