import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'dart:io' show Platform;
import '../services/log_service.dart';
import '../services/instance_service.dart';
import '../models/npm_instance.dart';

class AuthService {
  // Enhanced configuration for compatibility with non-Google Android devices
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      // Reset storage on error instead of failing silently
      resetOnError: true,
      // Use more compatible encryption settings
      keyCipherAlgorithm: KeyCipherAlgorithm.RSA_ECB_PKCS1Padding,
      storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );
  final LocalAuthentication _localAuth = LocalAuthentication();
  final LogService _logService = LogService();
  final InstanceService _instanceService = InstanceService();

  // Storage keys - Legacy (for migration)
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

      // Save credentials
      await Future.wait([
        _storage.write(key: _keyServerUrl, value: serverUrl),
        _storage.write(key: _keyEmail, value: email),
        _storage.write(key: _keyEncryptedPassword, value: encrypted.base64),
        _storage.write(key: _keyEncryptionIV, value: iv.base64),
        _storage.write(
            key: _keyBiometricEnabled, value: enableBiometric.toString()),
      ]);

      // VERIFY the save actually worked
      final verifyUrl = await _storage.read(key: _keyServerUrl);
      final verifyEmail = await _storage.read(key: _keyEmail);
      final verifyPassword = await _storage.read(key: _keyEncryptedPassword);

      if (verifyUrl != serverUrl ||
          verifyEmail != email ||
          verifyPassword != encrypted.base64) {
        // Storage write failed silently - log it
        await _logService.logBiometricEvent(
          event: 'SAVE_CREDENTIALS_VERIFICATION_FAILED',
          details:
              'Credentials were not saved correctly - storage may be broken',
          additionalInfo: {
            'server_url_saved': verifyUrl == serverUrl,
            'email_saved': verifyEmail == email,
            'password_saved': verifyPassword == encrypted.base64,
          },
        );
        throw Exception(
            'Failed to save credentials - storage verification failed');
      }

      await _logService.logBiometricEvent(
        event: 'SAVE_CREDENTIALS',
        details: 'Credentials saved and verified successfully',
        additionalInfo: {
          'biometrics_enabled': enableBiometric,
          'server_saved': true,
          'email_saved': true,
          'password_saved': true,
          'iv_saved': true,
          'verification_passed': true,
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

  /// Check if secure storage is working properly
  /// Call this once on app start to log storage health
  Future<bool> checkStorageHealth() async {
    try {
      final testKey = '_health_check_${DateTime.now().millisecondsSinceEpoch}';
      final testValue = 'test_${DateTime.now().millisecondsSinceEpoch}';

      // Try to write
      await _storage.write(key: testKey, value: testValue);

      // Try to read back
      final readValue = await _storage.read(key: testKey);

      // Clean up
      await _storage.delete(key: testKey);

      final isHealthy = readValue == testValue;

      await _logService.logBiometricEvent(
        event: 'STORAGE_HEALTH_CHECK',
        details: isHealthy
            ? 'Storage is working correctly'
            : 'Storage is NOT working - read/write mismatch',
        additionalInfo: {
          'write_success': true,
          'read_success': readValue != null,
          'data_matches': isHealthy,
          'test_value_written': testValue,
          'test_value_read': readValue ?? 'null',
        },
      );

      return isHealthy;
    } catch (e) {
      await _logService.logBiometricEvent(
        event: 'STORAGE_HEALTH_CHECK_ERROR',
        details: 'Storage health check failed with error',
        additionalInfo: {
          'error': e.toString(),
          'error_type': e.runtimeType.toString(),
        },
      );
      return false;
    }
  }

  // ============================================================================
  // MULTI-INSTANCE METHODS
  // ============================================================================

  /// Check if migration from legacy storage is needed
  Future<bool> needsMigration() async {
    final hasLegacyUrl = await _storage.read(key: _keyServerUrl) != null;
    final hasInstanceList = await _instanceService.getInstanceIdList();
    return hasLegacyUrl && hasInstanceList.isEmpty;
  }

  /// Migrate from legacy single-instance storage to multi-instance
  Future<void> migrateFromLegacyStorage() async {
    try {
      await _logService.logMigrationEvent(
        event: 'MIGRATION_START',
        details: 'Starting migration from legacy storage',
      );

      // Read legacy data
      final serverUrl = await _storage.read(key: _keyServerUrl);
      final email = await _storage.read(key: _keyEmail);
      final encryptedPassword = await _storage.read(key: _keyEncryptedPassword);
      final encryptionIV = await _storage.read(key: _keyEncryptionIV);
      final biometricEnabled = await _storage.read(key: _keyBiometricEnabled);
      final authToken = await _storage.read(key: 'auth_token');

      if (serverUrl == null || email == null) {
        // No legacy data to migrate
        await _logService.logMigrationEvent(
          event: 'MIGRATION_SKIP',
          details: 'No legacy data found to migrate',
        );
        return;
      }

      // Generate new instance
      final instanceId = _instanceService.generateInstanceId();
      final instanceName = 'Default Instance';

      // Write instance data
      await Future.wait([
        _storage.write(key: 'instance_${instanceId}_name', value: instanceName),
        _storage.write(
            key: 'instance_${instanceId}_server_url', value: serverUrl),
        _storage.write(key: 'instance_${instanceId}_email', value: email),
        if (encryptedPassword != null)
          _storage.write(
              key: 'instance_${instanceId}_encrypted_password',
              value: encryptedPassword),
        if (encryptionIV != null)
          _storage.write(
              key: 'instance_${instanceId}_encryption_iv', value: encryptionIV),
        _storage.write(
            key: 'instance_${instanceId}_biometric_enabled',
            value: biometricEnabled ?? 'false'),
        if (authToken != null)
          _storage.write(
              key: 'instance_${instanceId}_auth_token', value: authToken),
        _storage.write(
            key: 'instance_${instanceId}_created_at',
            value: DateTime.now().toIso8601String()),
        _storage.write(
            key: 'instance_${instanceId}_last_used',
            value: DateTime.now().toIso8601String()),
      ]);

      // Add to instance list and set as active
      await _instanceService.addToInstanceList(instanceId);
      await _instanceService.setActiveInstanceId(instanceId);

      // Verify migration
      final verifyUrl =
          await _storage.read(key: 'instance_${instanceId}_server_url');
      if (verifyUrl == serverUrl) {
        // Migration successful, clean up legacy keys
        await Future.wait([
          _storage.delete(key: _keyServerUrl),
          _storage.delete(key: _keyEmail),
          _storage.delete(key: _keyEncryptedPassword),
          _storage.delete(key: _keyEncryptionIV),
          _storage.delete(key: _keyBiometricEnabled),
          _storage.delete(key: 'auth_token'),
        ]);

        await _logService.logMigrationEvent(
          event: 'MIGRATION_SUCCESS',
          details: 'Migration completed successfully',
          additionalInfo: {
            'instanceId': instanceId,
            'biometricPreserved': biometricEnabled == 'true',
          },
        );
      } else {
        throw Exception('Migration verification failed');
      }
    } catch (e) {
      await _logService.logMigrationEvent(
        event: 'MIGRATION_ERROR',
        details: 'Migration failed',
        additionalInfo: {'error': e.toString()},
      );
      // Don't rethrow - app should still work with legacy keys
    }
  }

  /// Create a new instance
  Future<String> createInstance({
    required String name,
    required String serverUrl,
    required String email,
    required String password,
    required bool enableBiometric,
  }) async {
    try {
      await _instanceService.validateInstanceData(name, serverUrl, email);

      final instanceId = _instanceService.generateInstanceId();

      // Get or create encryption key
      String? encryptionKey = await _storage.read(key: _keyEncryptionKey);
      if (encryptionKey == null) {
        encryptionKey = encrypt.Key.fromSecureRandom(32).base64;
        await _storage.write(key: _keyEncryptionKey, value: encryptionKey);
      }

      final key = encrypt.Key.fromBase64(encryptionKey);
      final iv = encrypt.IV.fromSecureRandom(16);
      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      final encrypted = encrypter.encrypt(password, iv: iv);

      // Save instance data
      await Future.wait([
        _storage.write(key: 'instance_${instanceId}_name', value: name),
        _storage.write(
            key: 'instance_${instanceId}_server_url', value: serverUrl),
        _storage.write(key: 'instance_${instanceId}_email', value: email),
        _storage.write(
            key: 'instance_${instanceId}_encrypted_password',
            value: encrypted.base64),
        _storage.write(
            key: 'instance_${instanceId}_encryption_iv', value: iv.base64),
        _storage.write(
            key: 'instance_${instanceId}_biometric_enabled',
            value: enableBiometric.toString()),
        _storage.write(
            key: 'instance_${instanceId}_created_at',
            value: DateTime.now().toIso8601String()),
        _storage.write(
            key: 'instance_${instanceId}_last_used',
            value: DateTime.now().toIso8601String()),
      ]);

      await _instanceService.addToInstanceList(instanceId);

      await _logService.logBiometricEvent(
        event: 'INSTANCE_CREATED',
        details: 'New instance created',
        additionalInfo: {'instanceId': instanceId, 'name': name},
      );

      return instanceId;
    } catch (e) {
      await _logService.logBiometricEvent(
        event: 'INSTANCE_CREATE_ERROR',
        details: 'Error creating instance',
        additionalInfo: {'error': e.toString()},
      );
      rethrow;
    }
  }

  /// Update an existing instance
  Future<void> updateInstance({
    required String instanceId,
    String? name,
    String? serverUrl,
    String? email,
    String? password,
    bool? enableBiometric,
  }) async {
    try {
      final updates = <Future<void>>[];

      if (name != null) {
        updates.add(
            _storage.write(key: 'instance_${instanceId}_name', value: name));
      }
      if (serverUrl != null) {
        updates.add(_storage.write(
            key: 'instance_${instanceId}_server_url', value: serverUrl));
      }
      if (email != null) {
        updates.add(
            _storage.write(key: 'instance_${instanceId}_email', value: email));
      }
      if (password != null) {
        String? encryptionKey = await _storage.read(key: _keyEncryptionKey);
        if (encryptionKey == null) {
          encryptionKey = encrypt.Key.fromSecureRandom(32).base64;
          await _storage.write(key: _keyEncryptionKey, value: encryptionKey);
        }

        final key = encrypt.Key.fromBase64(encryptionKey);
        final iv = encrypt.IV.fromSecureRandom(16);
        final encrypter = encrypt.Encrypter(encrypt.AES(key));
        final encrypted = encrypter.encrypt(password, iv: iv);

        updates.add(_storage.write(
            key: 'instance_${instanceId}_encrypted_password',
            value: encrypted.base64));
        updates.add(_storage.write(
            key: 'instance_${instanceId}_encryption_iv', value: iv.base64));
      }
      if (enableBiometric != null) {
        updates.add(_storage.write(
            key: 'instance_${instanceId}_biometric_enabled',
            value: enableBiometric.toString()));
      }

      await Future.wait(updates);

      await _logService.logBiometricEvent(
        event: 'INSTANCE_UPDATED',
        details: 'Instance updated',
        additionalInfo: {'instanceId': instanceId},
      );
    } catch (e) {
      await _logService.logBiometricEvent(
        event: 'INSTANCE_UPDATE_ERROR',
        details: 'Error updating instance',
        additionalInfo: {'instanceId': instanceId, 'error': e.toString()},
      );
      rethrow;
    }
  }

  /// Delete an instance
  Future<void> deleteInstance(String instanceId) async {
    try {
      // Delete all instance keys
      await Future.wait([
        _storage.delete(key: 'instance_${instanceId}_name'),
        _storage.delete(key: 'instance_${instanceId}_server_url'),
        _storage.delete(key: 'instance_${instanceId}_email'),
        _storage.delete(key: 'instance_${instanceId}_encrypted_password'),
        _storage.delete(key: 'instance_${instanceId}_encryption_iv'),
        _storage.delete(key: 'instance_${instanceId}_biometric_enabled'),
        _storage.delete(key: 'instance_${instanceId}_auth_token'),
        _storage.delete(key: 'instance_${instanceId}_created_at'),
        _storage.delete(key: 'instance_${instanceId}_last_used'),
      ]);

      // Remove from instance list
      await _instanceService.removeFromInstanceList(instanceId);

      // If this was the active instance, clear it
      final activeId = await _instanceService.getActiveInstanceId();
      if (activeId == instanceId) {
        await _instanceService.clearActiveInstance();
      }

      await _logService.logBiometricEvent(
        event: 'INSTANCE_DELETED',
        details: 'Instance deleted',
        additionalInfo: {'instanceId': instanceId},
      );
    } catch (e) {
      await _logService.logBiometricEvent(
        event: 'INSTANCE_DELETE_ERROR',
        details: 'Error deleting instance',
        additionalInfo: {'instanceId': instanceId, 'error': e.toString()},
      );
      rethrow;
    }
  }

  /// Get credentials for a specific instance
  Future<Map<String, String?>> getInstanceCredentials(String instanceId) async {
    try {
      final encryptionKey = await _storage.read(key: _keyEncryptionKey);
      final encryptedPassword =
          await _storage.read(key: 'instance_${instanceId}_encrypted_password');
      final encryptionIV =
          await _storage.read(key: 'instance_${instanceId}_encryption_iv');
      final serverUrl =
          await _storage.read(key: 'instance_${instanceId}_server_url');
      final email = await _storage.read(key: 'instance_${instanceId}_email');

      String? decryptedPassword;
      if (encryptionKey != null &&
          encryptedPassword != null &&
          encryptionIV != null) {
        try {
          final key = encrypt.Key.fromBase64(encryptionKey);
          final iv = encrypt.IV.fromBase64(encryptionIV);
          final encrypter = encrypt.Encrypter(encrypt.AES(key));
          decryptedPassword = encrypter.decrypt64(encryptedPassword, iv: iv);
        } catch (e) {
          await _logService.logBiometricEvent(
            event: 'DECRYPTION_ERROR',
            details: 'Error decrypting password for instance',
            additionalInfo: {'instanceId': instanceId, 'error': e.toString()},
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
        event: 'GET_INSTANCE_CREDENTIALS_ERROR',
        details: 'Error retrieving instance credentials',
        additionalInfo: {'instanceId': instanceId, 'error': e.toString()},
      );
      return {
        'serverUrl': null,
        'email': null,
        'password': null,
      };
    }
  }

  /// Check if biometric is enabled for a specific instance
  Future<bool> isInstanceBiometricEnabled(String instanceId) async {
    final enabled =
        await _storage.read(key: 'instance_${instanceId}_biometric_enabled');
    return enabled?.toLowerCase() == 'true';
  }

  /// Get all instances
  Future<List<NpmInstance>> getAllInstances() async {
    return await _instanceService.getAllInstances();
  }

  /// Get active instance
  Future<NpmInstance?> getActiveInstance() async {
    return await _instanceService.getActiveInstance();
  }

  /// Set active instance
  Future<void> setActiveInstance(String instanceId) async {
    await _instanceService.setActiveInstanceId(instanceId);
  }

  /// Get active instance ID
  Future<String?> getActiveInstanceId() async {
    return await _instanceService.getActiveInstanceId();
  }
}
