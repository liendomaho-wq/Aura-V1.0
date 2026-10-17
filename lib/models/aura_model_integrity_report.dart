class AuraModelIntegrityReport {
  const AuraModelIntegrityReport({
    required this.verified,
    required this.signatureVerified,
    required this.modelVersion,
    required this.sha256,
    required this.message,
  });

  final bool verified;
  final bool signatureVerified;
  final String modelVersion;
  final String sha256;
  final String message;
}
