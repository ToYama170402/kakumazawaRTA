import 'package:flutter_test/flutter_test.dart';
import 'package:hoge/runs/retry_schedule.dart';

void main() {
  group('calculateRetryBackoff', () {
    test('returns 5 minutes for retryCount=0', () {
      final backoff = calculateRetryBackoff(0);
      expect(backoff, Duration(minutes: 5));
    });

    test('returns 15 minutes for retryCount=1', () {
      final backoff = calculateRetryBackoff(1);
      expect(backoff, Duration(minutes: 15));
    });

    test('returns 1 hour for retryCount=2', () {
      final backoff = calculateRetryBackoff(2);
      expect(backoff, Duration(hours: 1));
    });

    test('throws StateError for retryCount=3', () {
      expect(() => calculateRetryBackoff(3), throwsA(isA<StateError>()));
    });

    test('throws StateError for retryCount > 3', () {
      expect(() => calculateRetryBackoff(5), throwsA(isA<StateError>()));
    });

    test('exponential backoff progression is correct', () {
      final backoff0 = calculateRetryBackoff(0);
      final backoff1 = calculateRetryBackoff(1);
      final backoff2 = calculateRetryBackoff(2);

      expect(backoff0.inMinutes, 5);
      expect(backoff1.inMinutes, 15);
      expect(backoff2.inMinutes, 60);

      // Verify progression increases
      expect(backoff1.inSeconds > backoff0.inSeconds, true);
      expect(backoff2.inSeconds > backoff1.inSeconds, true);
    });
  });
}
