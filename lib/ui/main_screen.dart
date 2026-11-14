import 'package:flutter/material.dart';

import '../measurement/location_provider.dart';
import '../measurement/position.dart';
import '../rankings/ranking.dart';
import '../routes/route_definition.dart';
import '../routes/route_repository.dart';
import '../routes/route_screen.dart';
import '../runs/secure_run_lab_screen.dart';
import 'measuring_screen.dart';
import 'ranking_screen.dart';

/// 計測完了後に走行を確定させる処理（暗号化＋送信。失敗時は再送キューへ）。
typedef FinishRun =
    Future<void> Function({
      required RouteDefinition route,
      required List<GeoPoint> history,
      required String nickname,
    });

/// メイン画面（Issue #45）。
///
/// 種目別にルートを選び、計測画面へ進む。順位表・手動再送・ルート同期・
/// 暗号化ラボへの導線も持つ。手動再送は Issue #44 の手動トリガー。
class MainScreen extends StatefulWidget {
  const MainScreen({
    super.key,
    required this.repository,
    required this.rankingsRepository,
    required this.locationProvider,
    required this.organizationDisplayName,
    this.finishRun,
    this.retryAction,
  });

  final RouteRepository repository;
  final RankingRepository rankingsRepository;
  final LocationProvider locationProvider;
  final String organizationDisplayName;
  final FinishRun? finishRun;
  final Future<void> Function()? retryAction;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  List<RouteDefinition> _routes = const <RouteDefinition>[];
  bool _loading = true;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    final result = await widget.repository.loadCachedRoutes();
    if (!mounted) {
      return;
    }
    setState(() {
      _routes = result.routes;
      _loading = false;
    });
  }

  Future<void> _onFinished(
    RouteDefinition route,
    List<GeoPoint> history,
    String nickname,
  ) async {
    final finishRun = widget.finishRun;
    if (finishRun == null) {
      return;
    }
    try {
      await finishRun(route: route, history: history, nickname: nickname);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('記録を送信しました。')));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('送信できなかったため、再送待ちに保存しました。')),
      );
    }
  }

  Future<void> _retry() async {
    final retryAction = widget.retryAction;
    if (retryAction == null || _retrying) {
      return;
    }
    setState(() {
      _retrying = true;
    });
    try {
      await retryAction();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('再送を試行しました。')));
    } finally {
      if (mounted) {
        setState(() {
          _retrying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = <String, List<RouteDefinition>>{};
    for (final route in _routes) {
      categories.putIfAbsent(route.category, () => []).add(route);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('kakumazawaRTA')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('種目を選んで計測開始', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => RankingScreen(
                          repository: widget.rankingsRepository,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.leaderboard),
                  label: const Text('順位表'),
                ),
                OutlinedButton.icon(
                  onPressed: _retrying ? null : _retry,
                  icon: const Icon(Icons.send),
                  label: const Text('未送信データを再送'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            RouteSyncScreen(repository: widget.repository),
                      ),
                    );
                  },
                  icon: const Icon(Icons.sync),
                  label: const Text('ルート同期'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SecureRunLabScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.lock),
                  label: const Text('暗号化ラボ'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_routes.isEmpty)
              const Text('ルートがありません。先にルート同期を行ってください。')
            else
              ...categories.entries.expand(
                (entry) => [
                  Text(entry.key, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  ...entry.value.map(
                    (route) => Card(
                      child: ListTile(
                        title: Text(route.routeName),
                        subtitle: Text(
                          '最高 ${route.maxVelocityThreshold.toStringAsFixed(0)} km/h'
                          ' ・ 平均 ${route.avgVelocityThreshold.toStringAsFixed(0)} km/h',
                        ),
                        trailing: FilledButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => MeasuringScreen(
                                  route: route,
                                  locationProvider: widget.locationProvider,
                                  organizationDisplayName:
                                      widget.organizationDisplayName,
                                  onFinished: (history, nickname) =>
                                      _onFinished(route, history, nickname),
                                ),
                              ),
                            );
                          },
                          child: const Text('計測開始'),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
