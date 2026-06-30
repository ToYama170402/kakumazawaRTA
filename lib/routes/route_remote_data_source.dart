import 'dart:convert';
import 'dart:io';

import 'route_definition.dart';

abstract class RouteRemoteDataSource {
  Future<List<RouteDefinition>> fetchRoutes();
}

class HttpRouteRemoteDataSource implements RouteRemoteDataSource {
  HttpRouteRemoteDataSource({required this.endpoint});

  final Uri? endpoint;

  @override
  Future<List<RouteDefinition>> fetchRoutes() async {
    final uri = endpoint;
    if (uri == null) {
      throw const RouteRemoteConfigurationException(
        'ROUTES_ENDPOINT is not configured.',
      );
    }

    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Unexpected status ${response.statusCode}',
          uri: uri,
        );
      }

      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      final rawRoutes = decoded is Map<String, dynamic>
          ? decoded['routes']
          : decoded;
      if (rawRoutes is! List) {
        throw const FormatException(
          'Route payload must be a list or a map containing routes.',
        );
      }

      return rawRoutes
          .whereType<Map<String, dynamic>>()
          .map(RouteDefinition.fromJson)
          .toList(growable: false);
    } finally {
      client.close(force: true);
    }
  }
}

class RouteRemoteConfigurationException implements Exception {
  const RouteRemoteConfigurationException(this.message);

  final String message;

  @override
  String toString() => 'RouteRemoteConfigurationException: $message';
}
