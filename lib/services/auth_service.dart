import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'dart:io' show Platform;

class AuthService {
  static const _storage = FlutterSecureStorage();
  final LocalAuthentication _localAuth = LocalAuthentication();

  // Storage keys
  static const String _keyServerUrl = 'server_url';
  static const String _keyEmail = 'email';
  static const String _keyEncryptedPassword = 'encrypted_password';
  static const String _keyBiometricEnabled = 'biometric_enabled';
  static const String _keyEncryptionKey = 'encryption_key';

  // Check if biometric authentication is available
  Future<bool> isBiometricAvailable() async {
    try {
      if (!await _localAuth.isDeviceSupported()) return false;
      if (!await _localAuth.canCheckBiometrics) return false;

      final availableBiometrics = await _localAuth.getAvailableBiometrics();
      return availableBiometrics.contains(BiometricType.fingerprint);
    } catch (e) {
      return false;
    }
  }

  // Authenticate using biometrics
  Future<bool> authenticateWithBiometrics() async {
    try {
      if (!await isBiometricAvailable()) return false;
      if (!await isBiometricEnabled()) return false;

      return await _localAuth.authenticate(
        localizedReason: 'Use fingerprint to sign in',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
          useErrorDialogs: true,
        ),
      );
    } catch (e) {
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
    // Only generate a new key if one doesn't exist
    String? encryptionKey = await _storage.read(key: _keyEncryptionKey);
    if (encryptionKey == null) {
      encryptionKey = encrypt.Key.fromSecureRandom(32).base64;
      await _storage.write(key: _keyEncryptionKey, value: encryptionKey);
    }

    // Encrypt the password
    final key = encrypt.Key.fromBase64(encryptionKey);
    final iv = encrypt.IV.fromLength(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    final encrypted = encrypter.encrypt(password, iv: iv);

    // Save all credentials
    await Future.wait([
      _storage.write(key: _keyServerUrl, value: serverUrl),
      _storage.write(key: _keyEmail, value: email),
      _storage.write(key: _keyEncryptedPassword, value: encrypted.base64),
      _storage.write(
          key: _keyBiometricEnabled, value: enableBiometric.toString()),
    ]);

    print('Credentials saved successfully');
  }

  // Get saved credentials
  Future<Map<String, String?>> getSavedCredentials() async {
    final encryptionKey = await _storage.read(key: _keyEncryptionKey);
    String? decryptedPassword;

    final encryptedPassword = await _storage.read(key: _keyEncryptedPassword);
    if (encryptionKey != null && encryptedPassword != null) {
      try {
        final key = encrypt.Key.fromBase64(encryptionKey);
        final iv = encrypt.IV.fromLength(16);
        final encrypter = encrypt.Encrypter(encrypt.AES(key));
        decryptedPassword = encrypter.decrypt64(encryptedPassword, iv: iv);
      } catch (e) {
        print('Error decrypting password: $e');
      }
    }

    final serverUrl = await _storage.read(key: _keyServerUrl);
    final email = await _storage.read(key: _keyEmail);

    print('Retrieved credentials - '
        'Server URL exists: ${serverUrl != null}, '
        'Email exists: ${email != null}, '
        'Password exists: ${decryptedPassword != null}');

    return {
      'serverUrl': serverUrl,
      'email': email,
      'password': decryptedPassword,
    };
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
    ]);
  }

  // Clear only the saved password but keep server and email
  Future<void> clearPassword() async {
    await Future.wait([
      _storage.delete(key: _keyEncryptedPassword),
      _storage.delete(key: _keyBiometricEnabled),
      _storage.delete(key: _keyEncryptionKey),
    ]);
  }
}
