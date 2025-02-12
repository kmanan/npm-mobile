import 'package:shared_preferences/shared_preferences.dart';

class LogService {
  static const String _logKey = 'auth_logs';

  Future<void> logAuthFailure({
    required String errorMessage,
    required String errorType,
    int? statusCode,
    String? serverUrl,
    String? responseData,
    String? email,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = DateTime.now().toIso8601String();

      // Mask email for privacy but keep domain for debugging
      final maskedEmail = email != null
          ? '${email.split('@').first.replaceRange(1, null, '*****')}@${email.split('@').last}'
          : 'Not provided';

      final logEntry = '''
$timestamp
Type: AUTH_FAILURE
Error Type: $errorType
Message: $errorMessage
Server URL: ${serverUrl ?? 'Unknown'}
Status Code: ${statusCode ?? 'N/A'}
Email: $maskedEmail
Response: ${responseData ?? 'No response data'}
----------------------------------------''';

      final logs = prefs.getStringList(_logKey) ?? [];
      logs.add(logEntry);

      if (logs.length > 50) {
        logs.removeAt(0);
      }

      await prefs.setStringList(_logKey, logs);
    } catch (e) {
      print('Error writing to log: $e');
    }
  }

  Future<void> logBiometricEvent({
    required String event,
    required String details,
    Map<String, dynamic>? additionalInfo,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = DateTime.now().toIso8601String();

      final logEntry = '''
$timestamp
Type: BIOMETRIC_EVENT
Event: $event
Details: $details
${additionalInfo?.entries.map((e) => '${e.key}: ${e.value}').join('\n') ?? ''}
----------------------------------------''';

      final logs = prefs.getStringList(_logKey) ?? [];
      logs.add(logEntry);

      if (logs.length > 50) {
        logs.removeAt(0);
      }

      await prefs.setStringList(_logKey, logs);
    } catch (e) {
      print('Error writing to log: $e');
    }
  }

  Future<List<String>> getLogs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_logKey) ?? [];
  }

  Future<void> clearLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_logKey);
  }
}
