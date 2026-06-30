import 'route_definition.dart';

class RouteSeedData {
  const RouteSeedData._();

  static List<RouteDefinition> defaultRoutes() {
    return <RouteDefinition>[
      RouteDefinition(
        id: '00000000-0000-0000-0000-000000000001',
        category: '徒歩',
        routeName: '正門ルート',
        goalBounds: const RouteBounds(
          minLatitude: 36.5460,
          minLongitude: 136.7050,
          maxLatitude: 36.5465,
          maxLongitude: 136.7056,
        ),
        startBounds: const RouteBounds(
          minLatitude: 36.5448,
          minLongitude: 136.7042,
          maxLatitude: 36.5453,
          maxLongitude: 136.7049,
        ),
        maxVelocityThreshold: 12.0,
        avgVelocityThreshold: 8.0,
      ),
      RouteDefinition(
        id: '00000000-0000-0000-0000-000000000002',
        category: '自転車',
        routeName: '研究棟ルート',
        goalBounds: const RouteBounds(
          minLatitude: 36.5456,
          minLongitude: 136.7061,
          maxLatitude: 36.5461,
          maxLongitude: 136.7068,
        ),
        startBounds: const RouteBounds(
          minLatitude: 36.5443,
          minLongitude: 136.7052,
          maxLatitude: 36.5448,
          maxLongitude: 136.7059,
        ),
        maxVelocityThreshold: 28.0,
        avgVelocityThreshold: 18.0,
      ),
    ];
  }
}
