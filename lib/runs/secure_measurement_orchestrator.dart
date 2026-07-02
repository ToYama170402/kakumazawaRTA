import 'dart:async';

import '../measurement/measurement_controller.dart';
import '../security/secure_run_session_manager.dart';

class SecureMeasurementState {
  const SecureMeasurementState({required this.type, this.runId, this.error});

  final String type; // 'armed', 'encrypted', 'failed'
  final String? runId;
  final Object? error;

  factory SecureMeasurementState.armed(String runId) {
    return SecureMeasurementState(type: 'armed', runId: runId);
  }

  factory SecureMeasurementState.encrypted(String runId) {
    return SecureMeasurementState(type: 'encrypted', runId: runId);
  }

  factory SecureMeasurementState.failed(Object error) {
    return SecureMeasurementState(type: 'failed', error: error);
  }
}

class SecureMeasurementOrchestrator {
  SecureMeasurementOrchestrator({
    required MeasurementController measurementController,
    required SecureRunSessionManager secureRunSessionManager,
  }) : _measurementController = measurementController,
       _secureRunSessionManager = secureRunSessionManager {
    _subscription = _measurementController.events.listen(_handleEvent);
  }

  final MeasurementController _measurementController;
  final SecureRunSessionManager _secureRunSessionManager;

  final StreamController<SecureMeasurementState> _states =
      StreamController<SecureMeasurementState>.broadcast();
  Stream<SecureMeasurementState> get states => _states.stream;

  StreamSubscription<MeasurementEvent>? _subscription;
  String? _activeRunId;

  Future<void> _handleEvent(MeasurementEvent event) async {
    try {
      if (event.type == 'started') {
        final runId = await _secureRunSessionManager.startRun();
        _activeRunId = runId;
        _states.add(SecureMeasurementState.armed(runId));
        return;
      }

      if (event.type == 'stopped') {
        final runId = _activeRunId;
        final history = event.locationHistory;
        if (runId == null || history == null) {
          throw StateError('Invalid measurement stop state');
        }

        await _secureRunSessionManager.stopRunAndStoreEncrypted(history);
        _activeRunId = null;
        _states.add(SecureMeasurementState.encrypted(runId));
      }
    } catch (error) {
      _states.add(SecureMeasurementState.failed(error));
    }
  }

  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_states.close());
  }
}
