import 'package:flutter_test/flutter_test.dart';

import 'package:hoge/measurement/measurement_controller.dart';
import 'package:hoge/measurement/position.dart';
import 'package:hoge/routes/route_definition.dart';
import 'package:hoge/runs/secure_measurement_orchestrator.dart';
import 'package:hoge/security/encrypted_run_storage.dart';
import 'package:hoge/security/run_key_manager.dart';
import 'package:hoge/security/secure_run_session_manager.dart';

void main() {
  test(
    'measurement events trigger key generation and encrypted storage',
    () async {
      final controller = MeasurementController(
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

      final storage = MemoryEncryptedRunStorage();
      final sessionManager = SecureRunSessionManager(
        keyManager: InMemoryRunKeyManager(),
        storage: storage,
      );

      final orchestrator = SecureMeasurementOrchestrator(
        measurementController: controller,
        secureRunSessionManager: sessionManager,
      );

      final states = <SecureMeasurementState>[];
      final sub = orchestrator.states.listen(states.add);

      controller.pressStart();
      controller.onLocation(
        GeoPoint(latitude: 0.5, longitude: 0.5, timestamp: DateTime.utc(2026)),
      );
      controller.onLocation(
        GeoPoint(latitude: 5.0, longitude: 5.0, timestamp: DateTime.utc(2026)),
      );
      controller.onLocation(
        GeoPoint(latitude: 9.5, longitude: 9.5, timestamp: DateTime.utc(2026)),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(states.any((s) => s.type == 'armed'), isTrue);
      expect(states.any((s) => s.type == 'encrypted'), isTrue);

      final encryptedState = states.lastWhere((s) => s.type == 'encrypted');
      final runId = encryptedState.runId!;

      final record = await storage.readByRunId(runId);
      expect(record, isNotNull);

      await sub.cancel();
      orchestrator.dispose();
      controller.dispose();
    },
  );
}
