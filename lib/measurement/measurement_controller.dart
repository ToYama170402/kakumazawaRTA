import 'dart:async';

import '../routes/route_definition.dart';
import 'position.dart';

/// Events emitted by [MeasurementController].
class MeasurementEvent {
  const MeasurementEvent._(this.type, this.locationHistory);

  final String type; // 'started' or 'stopped'
  final List<GeoPoint>? locationHistory;

  factory MeasurementEvent.started() => MeasurementEvent._('started', null);
  factory MeasurementEvent.stopped(List<GeoPoint> history) =>
      MeasurementEvent._('stopped', List.unmodifiable(history));
}

/// Controls start/stop logic based on `startBounds` / `goalBounds`.
class MeasurementController {
  MeasurementController({required this.startBounds, required this.goalBounds});

  final RouteBounds startBounds;
  final RouteBounds goalBounds;

  bool _startPressed = false;
  bool _measuring = false;
  final List<GeoPoint> _history = <GeoPoint>[];

  final StreamController<MeasurementEvent> _events =
      StreamController<MeasurementEvent>.broadcast();
  Stream<MeasurementEvent> get events => _events.stream;

  /// Called when user presses the start button.
  void pressStart() {
    _startPressed = true;
  }

  /// Feed a new location sample into the controller.
  void onLocation(GeoPoint p) {
    if (!_startPressed) return;

    if (!_measuring) {
      if (_inside(startBounds, p)) {
        _measuring = true;
        _history.clear();
        _history.add(p);
        _events.add(MeasurementEvent.started());
      }
    } else {
      _history.add(p);
      if (_inside(goalBounds, p)) {
        _measuring = false;
        _startPressed = false;
        _events.add(MeasurementEvent.stopped(List<GeoPoint>.from(_history)));
        _history.clear();
      }
    }
  }

  bool _inside(RouteBounds bounds, GeoPoint p) {
    return p.latitude >= bounds.minLatitude &&
        p.latitude <= bounds.maxLatitude &&
        p.longitude >= bounds.minLongitude &&
        p.longitude <= bounds.maxLongitude;
  }

  void dispose() {
    _events.close();
  }
}
