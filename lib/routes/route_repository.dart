import 'route_cache_storage.dart';
import 'route_definition.dart';
import 'route_remote_data_source.dart';
import 'route_seed_data.dart';

enum RouteSyncStatus { synced, bootstrap, offline, blocked, failed }

class RouteSyncResult {
  const RouteSyncResult({
    required this.status,
    required this.routes,
    required this.message,
    this.error,
  });

  final RouteSyncStatus status;
  final List<RouteDefinition> routes;
  final String message;
  final String? error;

  bool get hasRoutes => routes.isNotEmpty;
}

class RouteRepository {
  RouteRepository({
    required this.remoteDataSource,
    required this.cacheStorage,
    List<RouteDefinition>? bootstrapRoutes,
  }) : bootstrapRoutes = bootstrapRoutes ?? RouteSeedData.defaultRoutes();

  factory RouteRepository.production() {
    const endpointValue = String.fromEnvironment('ROUTES_ENDPOINT');
    return RouteRepository(
      remoteDataSource: HttpRouteRemoteDataSource(
        endpoint: endpointValue.isEmpty ? null : Uri.parse(endpointValue),
      ),
      cacheStorage: FileRouteCacheStorage(),
    );
  }

  final RouteRemoteDataSource remoteDataSource;
  final RouteCacheStorage cacheStorage;
  final List<RouteDefinition> bootstrapRoutes;

  Future<RouteSyncResult> loadCachedRoutes() async {
    final routes = await cacheStorage.read();
    if (routes.isNotEmpty) {
      return RouteSyncResult(
        status: RouteSyncStatus.bootstrap,
        routes: routes,
        message: 'ローカルキャッシュを表示中です。',
      );
    }

    return const RouteSyncResult(
      status: RouteSyncStatus.failed,
      routes: <RouteDefinition>[],
      message: 'ローカルキャッシュはまだありません。',
    );
  }

  Future<RouteSyncResult> sync({required bool measuringActive}) async {
    if (measuringActive) {
      final cachedRoutes = await cacheStorage.read();
      return RouteSyncResult(
        status: RouteSyncStatus.blocked,
        routes: cachedRoutes,
        message: '計測中はルート同期を停止しています。',
      );
    }

    try {
      final routes = await remoteDataSource.fetchRoutes();
      await cacheStorage.write(routes);
      return RouteSyncResult(
        status: RouteSyncStatus.synced,
        routes: routes,
        message: 'ルート同期に成功しました。',
      );
    } on RouteRemoteConfigurationException catch (error) {
      final cachedRoutes = await cacheStorage.read();
      if (cachedRoutes.isNotEmpty) {
        return RouteSyncResult(
          status: RouteSyncStatus.offline,
          routes: cachedRoutes,
          message: '同期先が未設定のため、ローカルキャッシュを表示しています。',
          error: error.toString(),
        );
      }

      if (bootstrapRoutes.isNotEmpty) {
        await cacheStorage.write(bootstrapRoutes);
        return RouteSyncResult(
          status: RouteSyncStatus.bootstrap,
          routes: bootstrapRoutes,
          message: '同期先未設定のため、初期ルートをキャッシュしました。',
          error: error.toString(),
        );
      }

      return RouteSyncResult(
        status: RouteSyncStatus.failed,
        routes: const <RouteDefinition>[],
        message: '同期先が設定されていません。',
        error: error.toString(),
      );
    } catch (error) {
      final cachedRoutes = await cacheStorage.read();
      if (cachedRoutes.isNotEmpty) {
        return RouteSyncResult(
          status: RouteSyncStatus.offline,
          routes: cachedRoutes,
          message: '同期に失敗したため、既存キャッシュを維持しました。',
          error: error.toString(),
        );
      }

      if (bootstrapRoutes.isNotEmpty) {
        await cacheStorage.write(bootstrapRoutes);
        return RouteSyncResult(
          status: RouteSyncStatus.bootstrap,
          routes: bootstrapRoutes,
          message: '同期に失敗したため、初期ルートをキャッシュしました。',
          error: error.toString(),
        );
      }

      return RouteSyncResult(
        status: RouteSyncStatus.failed,
        routes: const <RouteDefinition>[],
        message: 'ルート同期に失敗しました。',
        error: error.toString(),
      );
    }
  }
}
