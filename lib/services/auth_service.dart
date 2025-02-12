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
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      if (!isDeviceSupported) return false;

      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      if (!canCheckBiometrics) return false;

      final availableBiometrics = await _localAuth.getAvailableBiometrics();
      if (Platform.isIOS) {
        return availableBiometrics.contains(BiometricType.face) ||
            availableBiometrics.contains(BiometricType.fingerprint);
      } else {
        return availableBiometrics.isNotEmpty;
      }
    } catch (e) {
      return false;
    }
  }

  // Authenticate using biometrics
  Future<bool> authenticateWithBiometrics() async {
    try {
      final localizedReason = Platform.isIOS
          ? 'Use Face ID or Touch ID to access your Nginx dashboard'
          : 'Use biometrics to access your Nginx dashboard';

      return await _localAuth.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException catch (e) {
      print('Biometric authentication error: ${e.message}');
      return false;
    } catch (e) {
      print('Unexpected error during biometric authentication: $e');
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
    // Generate a random encryption key if not exists
    String encryptionKey = await _storage.read(key: _keyEncryptionKey) ??
        encrypt.Key.fromSecureRandom(32).base64;

    // Save the encryption key if it's new
    await _storage.write(key: _keyEncryptionKey, value: encryptionKey);

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
        // If decryption fails, return null password
      }
    }

    return {
      'serverUrl': await _storage.read(key: _keyServerUrl),
      'email': await _storage.read(key: _keyEmail),
      'password': decryptedPassword,
    };
  }

  // Check if biometric login is enabled
  Future<bool> isBiometricEnabled() async {
    final enabled = await _storage.read(key: _keyBiometricEnabled);
    return enabled?.toLowerCase() == 'true';
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
