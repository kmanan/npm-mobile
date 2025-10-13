import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io' show Platform;

class LogService {
  static const String _logKey = 'auth_logs';

  // Cache device info to avoid repeated async calls
  static Map<String, String>? _cachedDeviceInfo;

  /// Get device and app information once and cache it
  Future<Map<String, String>> _getDeviceInfo() async {
    if (_cachedDeviceInfo != null) {
      return _cachedDeviceInfo!;
    }

    try {
      final deviceInfo = DeviceInfoPlugin();
      final packageInfo = await PackageInfo.fromPlatform();

      Map<String, String> info = {
        'App Version': '${packageInfo.version}+${packageInfo.buildNumber}',
      };

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        info.addAll({
          'Platform': 'Android',
          'OS Version':
              'Android ${androidInfo.version.release} (SDK ${androidInfo.version.sdkInt})',
          'Manufacturer': androidInfo.manufacturer,
          'Brand': androidInfo.brand,
          'Model': androidInfo.model,
          'Device': androidInfo.device,
          'Product': androidInfo.product,
          'Physical Device': androidInfo.isPhysicalDevice.toString(),
        });
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        info.addAll({
          'Platform': 'iOS',
          'OS Version': '${iosInfo.systemName} ${iosInfo.systemVersion}',
          'Manufacturer': 'Apple',
          'Model': iosInfo.model,
          'Device Name': iosInfo.name,
          'Physical Device': iosInfo.isPhysicalDevice.toString(),
          'System': iosInfo.utsname.machine,
        });
      }

      _cachedDeviceInfo = info;
      return info;
    } catch (e) {
      return {
        'Platform': Platform.isAndroid
            ? 'Android'
            : (Platform.isIOS ? 'iOS' : 'Unknown'),
        'Error': 'Failed to get device info: $e',
      };
    }
  }

  String _formatDeviceInfo(Map<String, String> deviceInfo) {
    return deviceInfo.entries.map((e) => '${e.key}: ${e.value}').join('\n');
  }

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
      final deviceInfo = await _getDeviceInfo();

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

DEVICE INFO:
${_formatDeviceInfo(deviceInfo)}
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
      final deviceInfo = await _getDeviceInfo();

      final logEntry = '''
$timestamp
Type: BIOMETRIC_EVENT
Event: $event
Details: $details
${additionalInfo?.entries.map((e) => '${e.key}: ${e.value}').join('\n') ?? ''}

DEVICE INFO:
${_formatDeviceInfo(deviceInfo)}
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

  Future<void> logMigrationEvent({
    required String event,
    required String details,
    Map<String, dynamic>? additionalInfo,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = DateTime.now().toIso8601String();
      final deviceInfo = await _getDeviceInfo();

      final logEntry = '''
$timestamp
Type: MIGRATION_EVENT
Event: $event
Details: $details
${additionalInfo?.entries.map((e) => '${e.key}: ${e.value}').join('\n') ?? ''}

DEVICE INFO:
${_formatDeviceInfo(deviceInfo)}
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
