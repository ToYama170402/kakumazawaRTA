import 'dart:convert';
import 'dart:io';

import 'run_submission_request.dart';

abstract class SubmitRunUploader {
  Future<void> upload(RunSubmissionRequest request);
}

class HttpSubmitRunUploader implements SubmitRunUploader {
  HttpSubmitRunUploader({Uri? endpoint})
    : endpoint = endpoint ?? _defaultEndpoint();

  final Uri? endpoint;

  static Uri? _defaultEndpoint() {
    const endpointValue = String.fromEnvironment('SUBMIT_RUN_ENDPOINT');
    if (endpointValue.isEmpty) {
      return null;
    }
    return Uri.parse(endpointValue);
  }

  @override
  Future<void> upload(RunSubmissionRequest request) async {
    final uri = endpoint;
    if (uri == null) {
      throw const SubmitRunConfigurationException(
        'SUBMIT_RUN_ENDPOINT is not configured.',
      );
    }

    final client = HttpClient();
    try {
      final httpRequest = await client.postUrl(uri);
      httpRequest.headers.contentType = ContentType.json;
      httpRequest.write(jsonEncode(request.toJson()));

      final response = await httpRequest.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await response.transform(utf8.decoder).join();
        throw HttpException(
          'Unexpected status ${response.statusCode}: $body',
          uri: uri,
        );
      }
    } finally {
      client.close(force: true);
    }
  }
}

class SubmitRunConfigurationException implements Exception {
  const SubmitRunConfigurationException(this.message);

  final String message;

  @override
  String toString() => 'SubmitRunConfigurationException: $message';
}
