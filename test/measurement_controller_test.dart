import 'package:flutter_test/flutter_test.dart';

import 'package:hoge/measurement/measurement_controller.dart';
import 'package:hoge/measurement/position.dart';
import 'package:hoge/routes/route_definition.dart';

void main() {
  test(
    'MeasurementController starts on start_bounds and stops on goal_bounds',
    () async {
      final startBounds = const RouteBounds(
        minLatitude: 0.0,
        minLongitude: 0.0,
        maxLatitude: 1.0,
        maxLongitude: 1.0,
      );
      final goalBounds = const RouteBounds(
        minLatitude: 9.0,
        minLongitude: 9.0,
        maxLatitude: 10.0,
        maxLongitude: 10.0,
      );

      final controller = MeasurementController(
        startBounds: startBounds,
        goalBounds: goalBounds,
      );

      final events = <String>[];
      List<GeoPoint>? capturedHistory;
      controller.events.listen((e) {
        events.add(e.type);
        if (e.type == 'stopped') capturedHistory = e.locationHistory;
      });

      // Press start, but first sample is outside start bounds: nothing happens
      controller.pressStart();
      controller.onLocation(
        GeoPoint(latitude: 2.0, longitude: 2.0, timestamp: DateTime.now()),
      );
      expect(events, isEmpty);

      // Enter start bounds -> started
      controller.onLocation(
        GeoPoint(latitude: 0.5, longitude: 0.5, timestamp: DateTime.now()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, ['started']);

      // Some samples
      controller.onLocation(
        GeoPoint(latitude: 1.1, longitude: 1.1, timestamp: DateTime.now()),
      );
      controller.onLocation(
        GeoPoint(latitude: 5.0, longitude: 5.0, timestamp: DateTime.now()),
      );

      // Enter goal -> stopped
      controller.onLocation(
        GeoPoint(latitude: 9.5, longitude: 9.5, timestamp: DateTime.now()),
      );
      await Future<void>.delayed(Duration.zero);

      expect(events, ['started', 'stopped']);
      expect(capturedHistory, isNotNull);
      expect(capturedHistory!.first.latitude, closeTo(0.5, 1e-9));
      expect(capturedHistory!.last.latitude, closeTo(9.5, 1e-9));

      controller.dispose();
    },
  );
}
