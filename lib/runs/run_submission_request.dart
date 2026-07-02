import '../measurement/position.dart';

class RunSubmissionRequest {
  const RunSubmissionRequest({
    required this.deviceIdentifier,
    required this.runId,
    required this.nickname,
    required this.organizationCode,
    required this.organizationDisplayName,
    required this.routeId,
    required this.locationHistory,
  });

  final String deviceIdentifier;
  final String runId;
  final String nickname;
  final String organizationCode;
  final String organizationDisplayName;
  final String routeId;
  final List<GeoPoint> locationHistory;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'device_identifier': deviceIdentifier,
      'run_id': runId,
      'nickname': nickname,
      'organization_code': organizationCode,
      'organization_display_name': organizationDisplayName,
      'route_id': routeId,
      'location_history': locationHistory
          .map(
            (point) => <String, dynamic>{
              'lat': point.latitude,
              'lng': point.longitude,
              't': point.timestamp.toUtc().toIso8601String(),
            },
          )
          .toList(growable: false),
    };
  }
}

abstract class RunSubmissionRequestFactory {
  RunSubmissionRequest create({
    required String runId,
    required List<GeoPoint> locationHistory,
  });
}

class DemoRunSubmissionRequestFactory implements RunSubmissionRequestFactory {
  const DemoRunSubmissionRequestFactory({
    this.deviceIdentifier = 'demo-device',
    this.nickname = 'デモ利用者',
    this.organizationCode = 'demo-org',
    this.organizationDisplayName = 'デモ組織',
    this.routeId = 'demo-route',
  });

  final String deviceIdentifier;
  final String nickname;
  final String organizationCode;
  final String organizationDisplayName;
  final String routeId;

  @override
  RunSubmissionRequest create({
    required String runId,
    required List<GeoPoint> locationHistory,
  }) {
    return RunSubmissionRequest(
      deviceIdentifier: deviceIdentifier,
      runId: runId,
      nickname: nickname,
      organizationCode: organizationCode,
      organizationDisplayName: organizationDisplayName,
      routeId: routeId,
      locationHistory: List<GeoPoint>.unmodifiable(locationHistory),
    );
  }
}
