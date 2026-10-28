/// Calculates the retry backoff duration based on retry count.
///
/// Implements exponential backoff schedule:
/// - retryCount=0 → 5 minutes
/// - retryCount=1 → 15 minutes
/// - retryCount=2 → 1 hour
/// - retryCount≥3 → throws StateError
///
/// Throws [StateError] if retryCount is 3 or greater (max retry attempts exceeded).
Duration calculateRetryBackoff(int retryCount) {
  switch (retryCount) {
    case 0:
      return Duration(minutes: 5);
    case 1:
      return Duration(minutes: 15);
    case 2:
      return Duration(hours: 1);
    default:
      throw StateError(
        'Retry count exceeds maximum (3). Cannot calculate backoff for retryCount=$retryCount.',
      );
  }
}
