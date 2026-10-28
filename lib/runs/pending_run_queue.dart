import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'retry_schedule.dart';

class PendingRunRecord {
  const PendingRunRecord({
    required this.runId,
    required this.requestPayload,
    required this.retryCount,
    required this.nextAttemptAt,
    this.isArchived = false,
  });

  final String runId;
  final String requestPayload;
  final int retryCount;
  final DateTime nextAttemptAt;
  final bool isArchived;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'run_id': runId,
      'request_payload': requestPayload,
      'retry_count': retryCount,
      'next_attempt_at': nextAttemptAt.toIso8601String(),
      'is_archived': isArchived,
    };
  }

  factory PendingRunRecord.fromJson(Map<String, dynamic> json) {
    return PendingRunRecord(
      runId: json['run_id'] as String,
      requestPayload: json['request_payload'] as String,
      retryCount: (json['retry_count'] as num).toInt(),
      nextAttemptAt: DateTime.parse(json['next_attempt_at'] as String).toUtc(),
      isArchived: (json['is_archived'] as bool?) ?? false,
    );
  }
}

abstract class PendingRunQueue {
  Future<void> enqueue(PendingRunRecord record);

  Future<List<PendingRunRecord>> dueRuns({DateTime? now});

  Future<PendingRunRecord?> readByRunId(String runId);

  Future<void> deleteByRunId(String runId);

  /// Updates retry count and schedules the next attempt time.
  ///
  /// Increments the retry count and calculates the next attempt time based on
  /// exponential backoff (5 min, 15 min, 1 hour). If the record does not exist,
  /// returns without error.
  Future<void> updateRetryCountAndSchedule(String runId);

  /// Checks if a retry should be attempted for the given record.
  ///
  /// Returns true if:
  /// - The record exists
  /// - retryCount < 3 (not yet archived)
  /// - nextAttemptAt has passed
  Future<bool> shouldRetry(String runId, {DateTime? now});

  /// Marks a record as archived (3 retries attempted).
  ///
  /// Sets isArchived=true for records with retryCount >= 3.
  /// If the record does not exist, returns without error.
  Future<void> markAsArchived(String runId);
}

class FilePendingRunQueue implements PendingRunQueue {
  FilePendingRunQueue({Future<Directory> Function()? directoryProvider})
    : directoryProvider = directoryProvider ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() directoryProvider;

  @override
  Future<void> enqueue(PendingRunRecord record) async {
    final all = await _readAll();
    all[record.runId] = record.toJson();
    await _writeAll(all);
  }

  @override
  Future<List<PendingRunRecord>> dueRuns({DateTime? now}) async {
    final current = (now ?? DateTime.now().toUtc()).toUtc();
    final all = await _readAll();
    return all.values
        .whereType<Map<String, dynamic>>()
        .map(PendingRunRecord.fromJson)
        .where((record) => !record.nextAttemptAt.isAfter(current))
        .toList(growable: false);
  }

  @override
  Future<PendingRunRecord?> readByRunId(String runId) async {
    final all = await _readAll();
    final item = all[runId];
    if (item is! Map<String, dynamic>) {
      return null;
    }
    return PendingRunRecord.fromJson(item);
  }

  @override
  Future<void> deleteByRunId(String runId) async {
    final all = await _readAll();
    all.remove(runId);
    await _writeAll(all);
  }

  @override
  Future<void> updateRetryCountAndSchedule(String runId) async {
    final record = await readByRunId(runId);
    if (record == null) {
      return;
    }

    final newRetryCount = record.retryCount + 1;
    // Calculate backoff based on the CURRENT retry count (before increment)
    // This maps: retryCount=0 -> 5min, retryCount=1 -> 15min, retryCount=2 -> 1hour
    final backoff = calculateRetryBackoff(record.retryCount);
    final nextAttemptAt = DateTime.now().toUtc().add(backoff);

    final updatedRecord = PendingRunRecord(
      runId: record.runId,
      requestPayload: record.requestPayload,
      retryCount: newRetryCount,
      nextAttemptAt: nextAttemptAt,
      isArchived: record.isArchived,
    );

    final all = await _readAll();
    all[runId] = updatedRecord.toJson();
    await _writeAll(all);
  }

  @override
  Future<bool> shouldRetry(String runId, {DateTime? now}) async {
    final record = await readByRunId(runId);
    if (record == null) {
      return false;
    }

    if (record.retryCount >= 3) {
      return false;
    }

    final current = (now ?? DateTime.now().toUtc()).toUtc();
    return !record.nextAttemptAt.isAfter(current);
  }

  @override
  Future<void> markAsArchived(String runId) async {
    final record = await readByRunId(runId);
    if (record == null) {
      return;
    }

    final archivedRecord = PendingRunRecord(
      runId: record.runId,
      requestPayload: record.requestPayload,
      retryCount: record.retryCount,
      nextAttemptAt: record.nextAttemptAt,
      isArchived: true,
    );

    final all = await _readAll();
    all[runId] = archivedRecord.toJson();
    await _writeAll(all);
  }

  Future<Map<String, dynamic>> _readAll() async {
    final file = await _queueFile();
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
    final file = await _queueFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(all));
  }

  Future<File> _queueFile() async {
    final directory = await directoryProvider();
    return File('${directory.path}${Platform.pathSeparator}pending_runs.json');
  }
}

class MemoryPendingRunQueue implements PendingRunQueue {
  final Map<String, PendingRunRecord> _records = <String, PendingRunRecord>{};

  @override
  Future<void> enqueue(PendingRunRecord record) async {
    _records[record.runId] = record;
  }

  @override
  Future<List<PendingRunRecord>> dueRuns({DateTime? now}) async {
    final current = (now ?? DateTime.now().toUtc()).toUtc();
    return _records.values
        .where((record) => !record.nextAttemptAt.isAfter(current))
        .toList(growable: false);
  }

  @override
  Future<PendingRunRecord?> readByRunId(String runId) async {
    return _records[runId];
  }

  @override
  Future<void> deleteByRunId(String runId) async {
    _records.remove(runId);
  }

  @override
  Future<void> updateRetryCountAndSchedule(String runId) async {
    final record = _records[runId];
    if (record == null) {
      return;
    }

    final newRetryCount = record.retryCount + 1;
    // Calculate backoff based on the CURRENT retry count (before increment)
    // This maps: retryCount=0 -> 5min, retryCount=1 -> 15min, retryCount=2 -> 1hour
    final backoff = calculateRetryBackoff(record.retryCount);
    final nextAttemptAt = DateTime.now().toUtc().add(backoff);

    _records[runId] = PendingRunRecord(
      runId: record.runId,
      requestPayload: record.requestPayload,
      retryCount: newRetryCount,
      nextAttemptAt: nextAttemptAt,
      isArchived: record.isArchived,
    );
  }

  @override
  Future<bool> shouldRetry(String runId, {DateTime? now}) async {
    final record = _records[runId];
    if (record == null) {
      return false;
    }

    if (record.retryCount >= 3) {
      return false;
    }

    final current = (now ?? DateTime.now().toUtc()).toUtc();
    return !record.nextAttemptAt.isAfter(current);
  }

  @override
  Future<void> markAsArchived(String runId) async {
    final record = _records[runId];
    if (record == null) {
      return;
    }

    _records[runId] = PendingRunRecord(
      runId: record.runId,
      requestPayload: record.requestPayload,
      retryCount: record.retryCount,
      nextAttemptAt: record.nextAttemptAt,
      isArchived: true,
    );
  }
}
