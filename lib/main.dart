import 'package:flutter/material.dart';

import 'routes/route_repository.dart';
import 'routes/route_screen.dart';
import 'runs/secure_run_lab_screen.dart';
import 'runs/pending_runs_database.dart';
import 'runs/run_submission_request.dart';
import 'runs/submit_run_http_uploader.dart';
import 'runs/startup_retry_gate.dart';
import 'runs/secure_run_submitter.dart';
import 'security/encrypted_run_storage.dart';
import 'security/run_key_manager.dart';
import 'security/secure_run_session_manager.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final submitter = _buildStartupRetrySubmitter();
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
        child: MainMenuScreen(repository: RouteRepository.production()),
      ),
    );
  }
}

SecureRunSubmitter? _buildStartupRetrySubmitter() {
  try {
    final sessionManager = SecureRunSessionManager(
      keyManager: FlutterSecureRunKeyManager(),
      storage: FileEncryptedRunStorage(),
    );
    return SecureRunSubmitter(
      secureRunSessionManager: sessionManager,
      uploader: HttpSubmitRunUploader(),
      requestFactory: const DemoRunSubmissionRequestFactory(),
      pendingRunQueue: SqlitePendingRunQueue(),
    );
  } catch (_) {
    return null;
  }
}

class MainMenuScreen extends StatelessWidget {
  const MainMenuScreen({super.key, required this.repository});

  final RouteRepository repository;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('kakumazawaRTA')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('実装済み機能', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'ルート同期と、走行データの暗号化・復号フローを確認できます。',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RouteSyncScreen(repository: repository),
                  ),
                );
              },
              child: const Text('ルート同期を開く'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SecureRunLabScreen(),
                  ),
                );
              },
              child: const Text('暗号化フローを開く'),
            ),
          ],
        ),
      ),
    );
  }
}
