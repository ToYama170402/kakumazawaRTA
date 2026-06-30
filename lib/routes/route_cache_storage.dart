import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'route_definition.dart';

abstract class RouteCacheStorage {
  Future<List<RouteDefinition>> read();

  Future<void> write(List<RouteDefinition> routes);
}

class FileRouteCacheStorage implements RouteCacheStorage {
  FileRouteCacheStorage({Future<Directory> Function()? directoryProvider})
    : directoryProvider = directoryProvider ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() directoryProvider;

  @override
  Future<List<RouteDefinition>> read() async {
    final file = await _cacheFile();
    if (!await file.exists()) {
      return const <RouteDefinition>[];
    }

    final content = await file.readAsString();
    final decoded = jsonDecode(content);
    if (decoded is! List) {
      return const <RouteDefinition>[];
    }

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(RouteDefinition.fromJson)
        .toList(growable: false);
  }

  @override
  Future<void> write(List<RouteDefinition> routes) async {
    final file = await _cacheFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(routes.map((route) => route.toJson()).toList()),
    );
  }

  Future<File> _cacheFile() async {
    final directory = await directoryProvider();
    return File('${directory.path}${Platform.pathSeparator}routes_cache.json');
  }
}

class MemoryRouteCacheStorage implements RouteCacheStorage {
  MemoryRouteCacheStorage([List<RouteDefinition>? initialRoutes])
    : _routes = List<RouteDefinition>.unmodifiable(
        initialRoutes ?? const <RouteDefinition>[],
      );

  List<RouteDefinition> _routes;

  @override
  Future<List<RouteDefinition>> read() async {
    return List<RouteDefinition>.unmodifiable(_routes);
  }

  @override
  Future<void> write(List<RouteDefinition> routes) async {
    _routes = List<RouteDefinition>.unmodifiable(routes);
  }
}
