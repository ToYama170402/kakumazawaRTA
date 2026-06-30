import 'package:flutter/material.dart';

import 'route_definition.dart';
import 'route_repository.dart';

class RouteSyncScreen extends StatefulWidget {
  const RouteSyncScreen({super.key, required this.repository});

  final RouteRepository repository;

  @override
  State<RouteSyncScreen> createState() => _RouteSyncScreenState();
}

class _RouteSyncScreenState extends State<RouteSyncScreen> {
  bool _isMeasuring = false;
  bool _isLoading = true;
  String _statusMessage = '起動時にルートを同期します。';
  RouteSyncStatus _status = RouteSyncStatus.failed;
  List<RouteDefinition> _routes = const <RouteDefinition>[];

  @override
  void initState() {
    super.initState();
    _loadStartupRoutes();
  }

  Future<void> _loadStartupRoutes() async {
    await _applySync(triggeredByStartup: true);
  }

  Future<void> _applySync({required bool triggeredByStartup}) async {
    if (_isMeasuring) {
      setState(() {
        _status = RouteSyncStatus.blocked;
        _statusMessage = '計測中はルート同期を行いません。';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = triggeredByStartup ? '起動時同期を実行中です。' : 'ルートを更新中です。';
    });

    final result = await widget.repository.sync(measuringActive: _isMeasuring);
    if (!mounted) {
      return;
    }

    setState(() {
      _status = result.status;
      _routes = result.routes;
      _statusMessage = result.message;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('ルート同期')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('routes の起動時同期と手動更新', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              '成功時のみローカルキャッシュを差し替えます。計測中は更新を止めます。',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _statusLabel(_status),
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        Switch.adaptive(
                          value: _isMeasuring,
                          onChanged: (value) {
                            setState(() {
                              _isMeasuring = value;
                              if (value) {
                                _status = RouteSyncStatus.blocked;
                                _statusMessage = '計測中はルート同期を行いません。';
                              }
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(_statusMessage),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: _isLoading || _isMeasuring
                              ? null
                              : () => _applySync(triggeredByStartup: false),
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh),
                          label: const Text('更新'),
                        ),
                        const SizedBox(width: 12),
                        Text('${_routes.length} 件のルート'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('ローカルキャッシュ', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            if (_routes.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('まだルートはありません。')),
              )
            else
              ..._routes.map(
                (route) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            route.routeName,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text('${route.category} ・ ${route.id}'),
                          const SizedBox(height: 8),
                          Text('開始閾値: ${_describeBounds(route.startBounds)}'),
                          Text('終了閾値: ${_describeBounds(route.goalBounds)}'),
                          const SizedBox(height: 8),
                          Text(
                            '最高速度: ${route.maxVelocityThreshold.toStringAsFixed(1)} km/h',
                          ),
                          Text(
                            '平均速度: ${route.avgVelocityThreshold.toStringAsFixed(1)} km/h',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(RouteSyncStatus status) {
    switch (status) {
      case RouteSyncStatus.synced:
        return '同期済み';
      case RouteSyncStatus.bootstrap:
        return '初期キャッシュ';
      case RouteSyncStatus.offline:
        return 'オフライン';
      case RouteSyncStatus.blocked:
        return '計測中のため停止';
      case RouteSyncStatus.failed:
        return '未同期';
    }
  }

  String _describeBounds(RouteBounds bounds) {
    return '(${bounds.minLatitude.toStringAsFixed(4)}, ${bounds.minLongitude.toStringAsFixed(4)}) - (${bounds.maxLatitude.toStringAsFixed(4)}, ${bounds.maxLongitude.toStringAsFixed(4)})';
  }
}
