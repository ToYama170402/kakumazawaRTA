import 'package:flutter/material.dart';

import 'routes/route_repository.dart';
import 'routes/route_screen.dart';
import 'runs/secure_run_lab_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'kakumazawaRTA',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: MainMenuScreen(repository: RouteRepository.production()),
    );
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
