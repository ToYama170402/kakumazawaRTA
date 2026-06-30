import 'package:flutter_test/flutter_test.dart';
import 'dart:async';

import 'package:hoge/measurement/position_sampler.dart';
import 'package:hoge/measurement/location_provider.dart';
import 'package:hoge/measurement/position.dart';

class _FakeProvider implements LocationProvider {
  _FakeProvider(this._points);

  final List<GeoPoint> _points;
  int _i = 0;

  @override
  Future<GeoPoint> getCurrentLocation() async {
    final p = _points[_i % _points.length];
    _i += 1;
    return p;
  }
}

void main() {
  test('PositionSampler emits periodic samples', () async {
    final now = DateTime.now();
    final points = [
      GeoPoint(latitude: 0.0, longitude: 0.0, timestamp: now),
      GeoPoint(
        latitude: 1.0,
        longitude: 1.0,
        timestamp: now.add(const Duration(seconds: 1)),
      ),
      GeoPoint(
        latitude: 2.0,
        longitude: 2.0,
        timestamp: now.add(const Duration(seconds: 2)),
      ),
    ];

    final provider = _FakeProvider(points);
    final sampler = PositionSampler(
      provider: provider,
      period: const Duration(milliseconds: 10),
    );

    sampler.start();

    final received = await sampler.stream.take(3).toList();

    expect(received.length, 3);
    expect(received[0].latitude, 0.0);
    expect(received[1].latitude, 1.0);
    expect(received[2].latitude, 2.0);

    await sampler.stop();
  });
}
