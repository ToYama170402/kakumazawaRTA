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
    // サーバー (submit-run) の検証に合わせ、t は開始からの経過秒数にする。
    final origin = locationHistory.isEmpty ? null : locationHistory.first.timestamp;
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
              't': origin == null
                  ? 0.0
                  : point.timestamp.difference(origin).inMilliseconds /
                        1000.0,
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

/// 本番用: 画面で確定したニックネームとルートからリクエストを組み立てる。
class ConfiguredRunSubmissionRequestFactory
    implements RunSubmissionRequestFactory {
  const ConfiguredRunSubmissionRequestFactory({
    required this.deviceIdentifier,
    required this.nickname,
    required this.organizationCode,
    required this.organizationDisplayName,
    required this.routeId,
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
