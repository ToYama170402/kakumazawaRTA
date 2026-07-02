import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'encrypted_run_record.dart';

abstract class EncryptedRunStorage {
  Future<void> save(EncryptedRunRecord record);

  Future<EncryptedRunRecord?> readByRunId(String runId);

  Future<void> deleteByRunId(String runId);
}

class FileEncryptedRunStorage implements EncryptedRunStorage {
  FileEncryptedRunStorage({Future<Directory> Function()? directoryProvider})
    : directoryProvider = directoryProvider ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() directoryProvider;

  @override
  Future<void> save(EncryptedRunRecord record) async {
    final all = await _readAll();
    all[record.runId] = record.toJson();
    await _writeAll(all);
  }

  @override
  Future<EncryptedRunRecord?> readByRunId(String runId) async {
    final all = await _readAll();
    final item = all[runId];
    if (item is! Map<String, dynamic>) {
      return null;
    }
    return EncryptedRunRecord.fromJson(item);
  }

  @override
  Future<void> deleteByRunId(String runId) async {
    final all = await _readAll();
    all.remove(runId);
    await _writeAll(all);
  }

  Future<Map<String, dynamic>> _readAll() async {
    final file = await _cacheFile();
    if (!await file.exists()) {
      return <String, dynamic>{};
    }

    final raw = await file.readAsString();
    if (raw.isEmpty) {
      return <String, dynamic>{};
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return <String, dynamic>{};
    }
    return decoded;
  }

  Future<void> _writeAll(Map<String, dynamic> all) async {
    final file = await _cacheFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(all));
  }

  Future<File> _cacheFile() async {
    final directory = await directoryProvider();
    return File(
      '${directory.path}${Platform.pathSeparator}encrypted_runs.json',
    );
  }
}

class MemoryEncryptedRunStorage implements EncryptedRunStorage {
  final Map<String, EncryptedRunRecord> _records =
      <String, EncryptedRunRecord>{};

  @override
  Future<void> save(EncryptedRunRecord record) async {
    _records[record.runId] = record;
  }

  @override
  Future<EncryptedRunRecord?> readByRunId(String runId) async {
    return _records[runId];
  }

  @override
  Future<void> deleteByRunId(String runId) async {
    _records.remove(runId);
  }
}
