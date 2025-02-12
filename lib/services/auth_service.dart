import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'dart:io' show Platform;
import '../services/log_service.dart';

class AuthService {
  static const _storage = FlutterSecureStorage();
  final LocalAuthentication _localAuth = LocalAuthentication();
  final LogService _logService = LogService();

  // Storage keys
  static const String _keyServerUrl = 'server_url';
  static const String _keyEmail = 'email';
  static const String _keyEncryptedPassword = 'encrypted_password';
  static const String _keyBiometricEnabled = 'biometric_enabled';
  static const String _keyEncryptionKey = 'encryption_key';
  static const String _keyEncryptionIV = 'encryption_iv';

  // Check if biometric authentication is available
  Future<bool> isBiometricAvailable() async {
    try {
      if (!await _localAuth.isDeviceSupported()) {
        await _logService.logBiometricEvent(
          event: 'DEVICE_SUPPORT_CHECK',
          details: 'Device does not support biometrics',
        );
        return false;
      }

      if (!await _localAuth.canCheckBiometrics) {
        await _logService.logBiometricEvent(
          event: 'BIOMETRIC_CHECK',
          details: 'Cannot check biometrics on this device',
        );
        return false;
      }

      final availableBiometrics = await _localAuth.getAvailableBiometrics();
      await _logService.logBiometricEvent(
        event: 'AVAILABLE_BIOMETRICS',
        details: 'Available biometric types',
        additionalInfo: {
          'types': availableBiometrics.map((e) => e.toString()).toList()
        },
      );

      return availableBiometrics.isNotEmpty;
    } catch (e) {
      await _logService.logBiometricEvent(
        event: 'BIOMETRIC_CHECK_ERROR',
        details: 'Error checking biometric availability',
        additionalInfo: {'error': e.toString()},
      );
      return false;
    }
  }

  // Authenticate using biometrics
  Future<bool> authenticateWithBiometrics() async {
    try {
      if (!await isBiometricAvailable()) {
        await _logService.logBiometricEvent(
          event: 'AUTH_ATTEMPT',
          details: 'Biometrics not available',
        );
        return false;
      }

      if (!await isBiometricEnabled()) {
        await _logService.logBiometricEvent(
          event: 'AUTH_ATTEMPT',
          details: 'Biometrics not enabled in preferences',
        );
        return false;
      }

      final success = await _localAuth.authenticate(
        localizedReason: Platform.isIOS
            ? 'Use Face ID to sign in'
            : 'Use fingerprint to sign in',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
          useErrorDialogs: true,
        ),
      );

      await _logService.logBiometricEvent(
        event: 'AUTH_RESULT',
        details:
            success ? 'Authentication successful' : 'Authentication failed',
      );

      return success;
    } catch (e) {
      await _logService.logBiometricEvent(
        event: 'AUTH_ERROR',
        details: 'Error during authentication',
        additionalInfo: {'error': e.toString()},
      );
      return false;
    }
  }

  // Save credentials
  Future<void> saveCredentials({
    required String serverUrl,
    required String email,
    required String password,
    required bool enableBiometric,
  }) async {
    try {
      String? encryptionKey = await _storage.read(key: _keyEncryptionKey);
      if (encryptionKey == null) {
        encryptionKey = encrypt.Key.fromSecureRandom(32).base64;
        await _storage.write(key: _keyEncryptionKey, value: encryptionKey);
      }

      final key = encrypt.Key.fromBase64(encryptionKey);
      final iv = encrypt.IV.fromSecureRandom(16);
      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      final encrypted = encrypter.encrypt(password, iv: iv);

      await Future.wait([
        _storage.write(key: _keyServerUrl, value: serverUrl),
        _storage.write(key: _keyEmail, value: email),
        _storage.write(key: _keyEncryptedPassword, value: encrypted.base64),
        _storage.write(key: _keyEncryptionIV, value: iv.base64),
        _storage.write(
            key: _keyBiometricEnabled, value: enableBiometric.toString()),
      ]);

      await _logService.logBiometricEvent(
        event: 'SAVE_CREDENTIALS',
        details: 'Credentials saved successfully',
        additionalInfo: {
          'biometrics_enabled': enableBiometric,
          'server_saved': true,
          'email_saved': true,
          'password_saved': true,
          'iv_saved': true,
        },
      );
    } catch (e) {
      await _logService.logBiometricEvent(
        event: 'SAVE_CREDENTIALS_ERROR',
        details: 'Error saving credentials',
        additionalInfo: {'error': e.toString()},
      );
      rethrow;
    }
  }

  // Get saved credentials
  Future<Map<String, String?>> getSavedCredentials() async {
    try {
      await _logService.logBiometricEvent(
        event: 'GET_CREDENTIALS_START',
        details: 'Starting to retrieve saved credentials',
      );

      final encryptionKey = await _storage.read(key: _keyEncryptionKey);
      final encryptedPassword = await _storage.read(key: _keyEncryptedPassword);
      final encryptionIV = await _storage.read(key: _keyEncryptionIV);
      final serverUrl = await _storage.read(key: _keyServerUrl);
      final email = await _storage.read(key: _keyEmail);

      if (encryptionKey == null) {
        await _logService.logBiometricEvent(
          event: 'CREDENTIALS_ERROR',
          details: 'Encryption key is missing',
        );
      }

      if (encryptedPassword == null) {
        await _logService.logBiometricEvent(
          event: 'CREDENTIALS_ERROR',
          details: 'Encrypted password is missing',
        );
      }

      if (encryptionIV == null) {
        await _logService.logBiometricEvent(
          event: 'CREDENTIALS_ERROR',
          details: 'Encryption IV is missing',
        );
      }

      if (serverUrl == null) {
        await _logService.logBiometricEvent(
          event: 'CREDENTIALS_ERROR',
          details: 'Server URL is missing',
        );
      }

      if (email == null) {
        await _logService.logBiometricEvent(
          event: 'CREDENTIALS_ERROR',
          details: 'Email is missing',
        );
      }

      await _logService.logBiometricEvent(
        event: 'CREDENTIALS_CHECK',
        details: 'Checking stored credentials',
        additionalInfo: {
          'has_encryption_key': encryptionKey != null,
          'has_encrypted_password': encryptedPassword != null,
          'has_encryption_iv': encryptionIV != null,
          'has_server_url': serverUrl != null,
          'has_email': email != null,
        },
      );

      String? decryptedPassword;
      if (encryptionKey != null &&
          encryptedPassword != null &&
          encryptionIV != null) {
        try {
          final key = encrypt.Key.fromBase64(encryptionKey);
          final iv = encrypt.IV.fromBase64(encryptionIV);
          final encrypter = encrypt.Encrypter(encrypt.AES(key));
          decryptedPassword = encrypter.decrypt64(encryptedPassword, iv: iv);

          await _logService.logBiometricEvent(
            event: 'PASSWORD_DECRYPTION',
            details: 'Password decryption successful',
          );
        } catch (e) {
          await _logService.logBiometricEvent(
            event: 'DECRYPTION_ERROR',
            details: 'Error decrypting password',
            additionalInfo: {'error': e.toString()},
          );
        }
      }

      return {
        'serverUrl': serverUrl,
        'email': email,
        'password': decryptedPassword,
      };
    } catch (e) {
      await _logService.logBiometricEvent(
        event: 'GET_CREDENTIALS_ERROR',
        details: 'Error retrieving credentials',
        additionalInfo: {'error': e.toString()},
      );
      return {
        'serverUrl': null,
        'email': null,
        'password': null,
      };
    }
  }

  // Check if biometric login is enabled
  Future<bool> isBiometricEnabled() async {
    final enabled = await _storage.read(key: _keyBiometricEnabled);
    final isEnabled = enabled?.toLowerCase() == 'true';
    print('Checking if biometrics enabled in preferences: $isEnabled');
    return isEnabled;
  }

  // Clear all saved credentials
  Future<void> clearCredentials() async {
    await Future.wait([
      _storage.delete(key: _keyServerUrl),
      _storage.delete(key: _keyEmail),
      _storage.delete(key: _keyEncryptedPassword),
      _storage.delete(key: _keyBiometricEnabled),
      _storage.delete(key: _keyEncryptionKey),
      _storage.delete(key: _keyEncryptionIV),
    ]);
  }

  // Handle logout - only clear auth token
  Future<void> handleLogout() async {
    await _storage.delete(key: 'auth_token');
  }

  // Clear only the saved password but keep server and email
  Future<void> clearPassword() async {
    await Future.wait([
      _storage.delete(key: _keyEncryptedPassword),
      _storage.delete(key: _keyBiometricEnabled),
      _storage.delete(key: _keyEncryptionKey),
      _storage.delete(key: _keyEncryptionIV),
    ]);
  }
}
