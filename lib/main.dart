import 'package:flutter/material.dart';

import 'measurement/position.dart';
import 'rankings/ranking.dart';
import 'routes/route_definition.dart';
import 'routes/route_repository.dart';
import 'runs/pending_run_queue.dart';
import 'runs/run_submission_request.dart';
import 'runs/secure_run_submitter.dart';
import 'runs/startup_retry_gate.dart';
import 'runs/submit_run_http_uploader.dart';
import 'security/encrypted_run_storage.dart';
import 'security/run_key_manager.dart';
import 'security/secure_run_session_manager.dart';
import 'ui/geolocator_location_provider.dart';
import 'ui/main_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

/// 端末設定（--dart-define で与える。未設定時は placeholder）。
const String _organizationCode = String.fromEnvironment(
  'ORGANIZATION_CODE',
  defaultValue: 'unknown-org',
);
const String _organizationDisplayName = String.fromEnvironment(
  'ORGANIZATION_DISPLAY_NAME',
  defaultValue: '未設定の組織',
);
const String _deviceIdentifier = String.fromEnvironment(
  'DEVICE_IDENTIFIER',
  defaultValue: 'unknown-device',
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final submitter = _buildSubmitter(
      requestFactory: const DemoRunSubmissionRequestFactory(),
    );
    return MaterialApp(
      title: 'kakumazawaRTA',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: StartupRetryGate(
        retryAction: submitter == null ? () async {} : submitter.retryDueRuns,
        child: MainScreen(
          repository: RouteRepository.production(),
          rankingsRepository: HttpRankingRepository(),
          locationProvider: const GeolocatorLocationProvider(),
          organizationDisplayName: _organizationDisplayName,
          finishRun: _finishRun,
          retryAction: submitter?.retryDueRuns,
        ),
      ),
    );
  }
}

SecureRunSessionManager _buildSessionManager() {
  return SecureRunSessionManager(
    keyManager: FlutterSecureRunKeyManager(),
    storage: FileEncryptedRunStorage(),
  );
}

SecureRunSubmitter? _buildSubmitter({
  required RunSubmissionRequestFactory requestFactory,
  SecureRunSessionManager? sessionManager,
}) {
  try {
    return SecureRunSubmitter(
      secureRunSessionManager: sessionManager ?? _buildSessionManager(),
      uploader: HttpSubmitRunUploader(),
      requestFactory: requestFactory,
      pendingRunQueue: FilePendingRunQueue(),
    );
  } catch (_) {
    return null;
  }
}

/// 計測完了後の確定処理: 暗号化保存して送信する。
/// 送信に失敗した場合は submitter が再送キューへ保存し、例外が伝播する。
Future<void> _finishRun({
  required RouteDefinition route,
  required List<GeoPoint> history,
  required String nickname,
}) async {
  final sessionManager = _buildSessionManager();
  final submitter = _buildSubmitter(
    sessionManager: sessionManager,
    requestFactory: ConfiguredRunSubmissionRequestFactory(
      deviceIdentifier: _deviceIdentifier,
      nickname: nickname,
      organizationCode: _organizationCode,
      organizationDisplayName: _organizationDisplayName,
      routeId: route.id,
    ),
  );
  if (submitter == null) {
    throw StateError('送信基盤を初期化できませんでした。');
  }
  final runId = await sessionManager.startRun();
  await sessionManager.stopRunAndStoreEncrypted(history);
  await submitter.submit(runId);
}
