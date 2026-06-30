import 'dart:async';

import 'location_provider.dart';
import 'position.dart';

/// Samples the given [LocationProvider] at a fixed [period].
class PositionSampler {
  PositionSampler({
    required this.provider,
    this.period = const Duration(seconds: 1),
  });

  final LocationProvider provider;
  final Duration period;

  Timer? _timer;
  final StreamController<GeoPoint> _controller =
      StreamController<GeoPoint>.broadcast();

  Stream<GeoPoint> get stream => _controller.stream;

  /// Start periodic sampling. Calling multiple times has no additional effect.
  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(period, (_) async {
      try {
        final pos = await provider.getCurrentLocation();
        if (!_controller.isClosed) {
          _controller.add(pos);
        }
      } catch (_) {
        // ignore failures; sampler continues
      }
    });
  }

  /// Stop sampling and close the stream.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _controller.close();
  }
}
