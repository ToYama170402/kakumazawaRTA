import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class RunKeyManager {
  Future<void> generateForRun(String runId);

  Future<SecretKey> getForRun(String runId);

  Future<void> deleteForRun(String runId);
}

class FlutterSecureRunKeyManager implements RunKeyManager {
  FlutterSecureRunKeyManager({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const int keyLength = 32;
  static const String _prefix = 'run_key_';

  final FlutterSecureStorage _storage;

  @override
  Future<void> generateForRun(String runId) async {
    final bytes = _randomBytes(keyLength);
    await _storage.write(key: '$_prefix$runId', value: base64Encode(bytes));
  }

  @override
  Future<SecretKey> getForRun(String runId) async {
    final encoded = await _storage.read(key: '$_prefix$runId');
    if (encoded == null || encoded.isEmpty) {
      throw StateError('No key found for run: $runId');
    }
    return SecretKey(base64Decode(encoded));
  }

  @override
  Future<void> deleteForRun(String runId) async {
    await _storage.delete(key: '$_prefix$runId');
  }

  List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }
}

class InMemoryRunKeyManager implements RunKeyManager {
  final Map<String, List<int>> _keys = <String, List<int>>{};

  @override
  Future<void> generateForRun(String runId) async {
    final random = Random.secure();
    _keys[runId] = List<int>.generate(
      FlutterSecureRunKeyManager.keyLength,
      (_) => random.nextInt(256),
      growable: false,
    );
  }

  @override
  Future<SecretKey> getForRun(String runId) async {
    final bytes = _keys[runId];
    if (bytes == null) {
      throw StateError('No key found for run: $runId');
    }
    return SecretKey(List<int>.from(bytes, growable: false));
  }

  @override
  Future<void> deleteForRun(String runId) async {
    _keys.remove(runId);
  }
}
