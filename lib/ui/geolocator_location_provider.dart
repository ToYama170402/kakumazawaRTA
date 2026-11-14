import 'package:geolocator/geolocator.dart';

import '../measurement/location_provider.dart';
import '../measurement/position.dart';

/// 実機 GPS を [LocationProvider] として提供する本番実装。
///
/// 許可が無い場合は要求し、拒否された場合は StateError を投げる
/// （PositionSampler 側は例外を握りつぶして取得を継続する）。
class GeolocatorLocationProvider implements LocationProvider {
  const GeolocatorLocationProvider();

  @override
  Future<GeoPoint> getCurrentLocation() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('位置情報の許可が得られませんでした。');
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );
    return GeoPoint(
      latitude: position.latitude,
      longitude: position.longitude,
      timestamp: position.timestamp,
    );
  }
}
