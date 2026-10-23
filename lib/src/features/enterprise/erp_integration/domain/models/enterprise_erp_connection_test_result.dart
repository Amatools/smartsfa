class EnterpriseErpConnectionTestResult {
  const EnterpriseErpConnectionTestResult({
    required this.success,
    required this.statusCode,
    required this.message,
    required this.requestUrl,
    required this.requestMethod,
    required this.latencyMs,
    required this.bearerReceived,
    this.expiresInSeconds,
    this.tokenType,
    this.bearerPreview,
  });

  final bool success;
  final int? statusCode;
  final String message;
  final String requestUrl;
  final String requestMethod;
  final int latencyMs;
  final bool bearerReceived;
  final int? expiresInSeconds;
  final String? tokenType;
  final String? bearerPreview;
}
