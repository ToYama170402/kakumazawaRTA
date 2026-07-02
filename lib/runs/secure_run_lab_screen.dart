import 'dart:async';

import 'package:flutter/material.dart';

import '../measurement/measurement_controller.dart';
import '../measurement/position.dart';
import '../routes/route_definition.dart';
import 'secure_measurement_orchestrator.dart';
import 'run_submission_request.dart';
import 'secure_run_submitter.dart';
import '../security/encrypted_run_storage.dart';
import '../security/run_key_manager.dart';
import '../security/secure_run_session_manager.dart';

class SecureRunLabScreen extends StatefulWidget {
  const SecureRunLabScreen({super.key});

  @override
  State<SecureRunLabScreen> createState() => _SecureRunLabScreenState();
}

class _SecureRunLabScreenState extends State<SecureRunLabScreen> {
  late final MeasurementController _measurementController;
  late final SecureRunSessionManager _sessionManager;
  late final SecureMeasurementOrchestrator _orchestrator;
  late final SecureRunSubmitter _submitter;
  late final StreamSubscription<SecureMeasurementState> _stateSubscription;

  final List<String> _logs = <String>[];
  String? _runId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _measurementController = MeasurementController(
      startBounds: const RouteBounds(
        minLatitude: 0,
        minLongitude: 0,
        maxLatitude: 1,
        maxLongitude: 1,
      ),
      goalBounds: const RouteBounds(
        minLatitude: 9,
        minLongitude: 9,
        maxLatitude: 10,
        maxLongitude: 10,
      ),
    );
    _sessionManager = SecureRunSessionManager(
      keyManager: InMemoryRunKeyManager(),
      storage: MemoryEncryptedRunStorage(),
    );
    _orchestrator = SecureMeasurementOrchestrator(
      measurementController: _measurementController,
      secureRunSessionManager: _sessionManager,
    );
    _submitter = SecureRunSubmitter(
      secureRunSessionManager: _sessionManager,
      uploader: InMemoryRunUploader(),
      requestFactory: const DemoRunSubmissionRequestFactory(),
    );
    _stateSubscription = _orchestrator.states.listen((state) {
      if (!mounted) {
        return;
      }
      setState(() {
        switch (state.type) {
          case 'armed':
            _runId = state.runId;
            _logs.add('run ${state.runId} を開始しました。');
            break;
          case 'encrypted':
            _runId = state.runId;
            _logs.add('run ${state.runId} を暗号化保存しました。');
            break;
          case 'failed':
            _logs.add('処理失敗: ${state.error}');
            break;
        }
      });
    });
  }

  @override
  void dispose() {
    unawaited(_stateSubscription.cancel());
    _orchestrator.dispose();
    _measurementController.dispose();
    super.dispose();
  }

  Future<void> _feedPoint(GeoPoint point) async {
    setState(() {
      _busy = true;
    });
    _measurementController.onLocation(point);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    if (mounted) {
      setState(() {
        _busy = false;
      });
    }
  }

  Future<void> _submit() async {
    final runId = _runId;
    if (runId == null) {
      return;
    }

    setState(() {
      _busy = true;
    });
    try {
      await _submitter.submit(runId);
      if (mounted) {
        setState(() {
          _logs.add('run $runId を送信し、ローカルデータを削除しました。');
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _logs.add('送信失敗: $error');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('暗号化フロー')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('走行単位の鍵生成と保存', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              '開始地点と終了地点を順に流すと、走行履歴が暗号化され、送信時に復号されます。',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('現在の runId: ${_runId ?? "未開始"}'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  _measurementController.pressStart();
                                  setState(() {
                                    _logs.add('走行開始を受け付けました。');
                                  });
                                },
                          child: const Text('走行開始'),
                        ),
                        FilledButton.tonal(
                          onPressed: _busy
                              ? null
                              : () => _feedPoint(
                                  GeoPoint(
                                    latitude: 0.5,
                                    longitude: 0.5,
                                    timestamp: DateTime.now().toUtc(),
                                  ),
                                ),
                          child: const Text('開始地点'),
                        ),
                        FilledButton.tonal(
                          onPressed: _busy
                              ? null
                              : () => _feedPoint(
                                  GeoPoint(
                                    latitude: 5.0,
                                    longitude: 5.0,
                                    timestamp: DateTime.now().toUtc(),
                                  ),
                                ),
                          child: const Text('途中地点'),
                        ),
                        FilledButton.tonal(
                          onPressed: _busy
                              ? null
                              : () => _feedPoint(
                                  GeoPoint(
                                    latitude: 9.5,
                                    longitude: 9.5,
                                    timestamp: DateTime.now().toUtc(),
                                  ),
                                ),
                          child: const Text('ゴール地点'),
                        ),
                        FilledButton(
                          onPressed: _busy || _runId == null ? null : _submit,
                          child: const Text('送信'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('ログ', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            if (_logs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('まだ操作ログはありません。')),
              )
            else
              ..._logs.reversed.map(
                (line) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('・$line'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
