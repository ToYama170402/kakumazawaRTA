import 'dart:convert';
import 'dart:io';

/// 順位表の1件分（rankings API の rankings 要素に対応）。
class RankingEntry {
  const RankingEntry({
    required this.rank,
    required this.runId,
    required this.nickname,
    required this.organizationCode,
    required this.totalSeconds,
    required this.rankGrade,
    required this.termIdentifier,
  });

  final int rank;
  final String runId;
  final String nickname;
  final String organizationCode;
  final double totalSeconds;
  final String? rankGrade;
  final String termIdentifier;

  factory RankingEntry.fromJson(Map<String, dynamic> json) {
    return RankingEntry(
      rank: (json['rank'] as num).toInt(),
      runId: json['run_id'] as String,
      nickname: json['nickname'] as String,
      organizationCode: json['organization_code'] as String,
      totalSeconds: (json['total_seconds'] as num).toDouble(),
      rankGrade: json['rank_grade'] as String?,
      termIdentifier: json['term_identifier'] as String,
    );
  }
}

/// rankings API へのアクセス抽象。テストではフェイクに差し替える。
abstract class RankingRepository {
  /// period は "current"（今月）/ "all"（歴代）/ "YYYY-MM"。
  Future<List<RankingEntry>> fetch({
    required String period,
    String? organizationCode,
  });
}

class HttpRankingRepository implements RankingRepository {
  HttpRankingRepository({Uri? endpoint})
    : endpoint = endpoint ?? _defaultEndpoint();

  final Uri? endpoint;

  static Uri? _defaultEndpoint() {
    const endpointValue = String.fromEnvironment('RANKINGS_ENDPOINT');
    if (endpointValue.isEmpty) {
      return null;
    }
    return Uri.parse(endpointValue);
  }

  @override
  Future<List<RankingEntry>> fetch({
    required String period,
    String? organizationCode,
  }) async {
    final uri = endpoint;
    if (uri == null) {
      throw const RankingConfigurationException(
        'RANKINGS_ENDPOINT is not configured.',
      );
    }

    final query = <String, String>{'period': period};
    if (organizationCode != null && organizationCode.isNotEmpty) {
      query['organization_code'] = organizationCode;
    }
    final requestUri = uri.replace(
      queryParameters: {...uri.queryParameters, ...query},
    );

    final client = HttpClient();
    try {
      final request = await client.getUrl(requestUri);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Unexpected status ${response.statusCode}: $body',
          uri: requestUri,
        );
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
        throw const FormatException('Rankings response is not successful.');
      }
      final raw = decoded['rankings'];
      if (raw is! List) {
        throw const FormatException('Rankings payload must be a list.');
      }
      return raw
          .whereType<Map<String, dynamic>>()
          .map(RankingEntry.fromJson)
          .toList(growable: false);
    } finally {
      client.close(force: true);
    }
  }
}

class RankingConfigurationException implements Exception {
  const RankingConfigurationException(this.message);

  final String message;

  @override
  String toString() => 'RankingConfigurationException: $message';
}
