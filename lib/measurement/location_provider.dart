import 'position.dart';

abstract class LocationProvider {
  /// Returns the current location. Implementations may wrap platform APIs.
  Future<GeoPoint> getCurrentLocation();
}
