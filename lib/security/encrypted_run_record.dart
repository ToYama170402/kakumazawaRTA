class EncryptedRunRecord {
  const EncryptedRunRecord({
    required this.runId,
    required this.nonceBase64,
    required this.ciphertextBase64,
    required this.macBase64,
    required this.createdAt,
  });

  final String runId;
  final String nonceBase64;
  final String ciphertextBase64;
  final String macBase64;
  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'run_id': runId,
      'nonce_b64': nonceBase64,
      'ciphertext_b64': ciphertextBase64,
      'mac_b64': macBase64,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory EncryptedRunRecord.fromJson(Map<String, dynamic> json) {
    return EncryptedRunRecord(
      runId: json['run_id'] as String,
      nonceBase64: json['nonce_b64'] as String,
      ciphertextBase64: json['ciphertext_b64'] as String,
      macBase64: json['mac_b64'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
