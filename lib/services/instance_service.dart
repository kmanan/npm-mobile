import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/npm_instance.dart';
import '../services/log_service.dart';

class InstanceService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
      keyCipherAlgorithm: KeyCipherAlgorithm.RSA_ECB_PKCS1Padding,
      storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );
  final LogService _logService = LogService();

  // Storage keys
  static const String _keyActiveInstanceId = 'active_instance_id';
  static const String _keyInstanceList = 'instance_list';

  /// Generate a unique instance ID
  String generateInstanceId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(999999);
    return 'npm_${timestamp}_$random';
  }

  /// Validate instance data
  Future<void> validateInstanceData(
      String name, String serverUrl, String email) async {
    if (name.trim().isEmpty) {
      throw Exception('Instance name cannot be empty');
    }
    if (serverUrl.trim().isEmpty) {
      throw Exception('Server URL cannot be empty');
    }
    if (email.trim().isEmpty) {
      throw Exception('Email cannot be empty');
    }
  }

  /// Get list of all instance IDs
  Future<List<String>> getInstanceIdList() async {
    final instanceListStr = await _storage.read(key: _keyInstanceList);
    if (instanceListStr == null || instanceListStr.isEmpty) {
      return [];
    }
    return instanceListStr.split(',');
  }

  /// Add instance ID to the list
  Future<void> addToInstanceList(String instanceId) async {
    final currentList = await getInstanceIdList();
    if (!currentList.contains(instanceId)) {
      currentList.add(instanceId);
      await _storage.write(key: _keyInstanceList, value: currentList.join(','));
      await _logService.logMigrationEvent(
        event: 'INSTANCE_ADDED',
        details: 'Instance added to list',
        additionalInfo: {'instanceId': instanceId},
      );
    }
  }

  /// Remove instance ID from the list
  Future<void> removeFromInstanceList(String instanceId) async {
    final currentList = await getInstanceIdList();
    currentList.remove(instanceId);
    if (currentList.isEmpty) {
      await _storage.delete(key: _keyInstanceList);
    } else {
      await _storage.write(key: _keyInstanceList, value: currentList.join(','));
    }
    await _logService.logMigrationEvent(
      event: 'INSTANCE_REMOVED',
      details: 'Instance removed from list',
      additionalInfo: {'instanceId': instanceId},
    );
  }

  /// Get all instances with their metadata
  Future<List<NpmInstance>> getAllInstances() async {
    final instanceIds = await getInstanceIdList();
    final instances = <NpmInstance>[];

    for (final id in instanceIds) {
      try {
        final name = await _storage.read(key: 'instance_${id}_name');
        final serverUrl = await _storage.read(key: 'instance_${id}_server_url');
        final email = await _storage.read(key: 'instance_${id}_email');
        final biometricEnabledStr =
            await _storage.read(key: 'instance_${id}_biometric_enabled');
        final createdAtStr =
            await _storage.read(key: 'instance_${id}_created_at');
        final lastUsedStr =
            await _storage.read(key: 'instance_${id}_last_used');

        if (name != null && serverUrl != null && email != null) {
          instances.add(NpmInstance(
            id: id,
            name: name,
            serverUrl: serverUrl,
            email: email,
            biometricEnabled: biometricEnabledStr?.toLowerCase() == 'true',
            createdAt: createdAtStr != null
                ? DateTime.parse(createdAtStr)
                : DateTime.now(),
            lastUsed: lastUsedStr != null
                ? DateTime.parse(lastUsedStr)
                : DateTime.now(),
          ));
        }
      } catch (e) {
        await _logService.logMigrationEvent(
          event: 'INSTANCE_LOAD_ERROR',
          details: 'Error loading instance',
          additionalInfo: {'instanceId': id, 'error': e.toString()},
        );
      }
    }

    // Sort by last used (most recent first)
    instances.sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
    return instances;
  }

  /// Get a specific instance by ID
  Future<NpmInstance?> getInstance(String instanceId) async {
    try {
      final name = await _storage.read(key: 'instance_${instanceId}_name');
      final serverUrl =
          await _storage.read(key: 'instance_${instanceId}_server_url');
      final email = await _storage.read(key: 'instance_${instanceId}_email');
      final biometricEnabledStr =
          await _storage.read(key: 'instance_${instanceId}_biometric_enabled');
      final createdAtStr =
          await _storage.read(key: 'instance_${instanceId}_created_at');
      final lastUsedStr =
          await _storage.read(key: 'instance_${instanceId}_last_used');

      if (name != null && serverUrl != null && email != null) {
        return NpmInstance(
          id: instanceId,
          name: name,
          serverUrl: serverUrl,
          email: email,
          biometricEnabled: biometricEnabledStr?.toLowerCase() == 'true',
          createdAt: createdAtStr != null
              ? DateTime.parse(createdAtStr)
              : DateTime.now(),
          lastUsed: lastUsedStr != null
              ? DateTime.parse(lastUsedStr)
              : DateTime.now(),
        );
      }
      return null;
    } catch (e) {
      await _logService.logMigrationEvent(
        event: 'INSTANCE_GET_ERROR',
        details: 'Error getting instance',
        additionalInfo: {'instanceId': instanceId, 'error': e.toString()},
      );
      return null;
    }
  }

  /// Get active instance ID
  Future<String?> getActiveInstanceId() async {
    return await _storage.read(key: _keyActiveInstanceId);
  }

  /// Set active instance ID
  Future<void> setActiveInstanceId(String instanceId) async {
    await _storage.write(key: _keyActiveInstanceId, value: instanceId);
    // Update last used timestamp
    await _storage.write(
      key: 'instance_${instanceId}_last_used',
      value: DateTime.now().toIso8601String(),
    );
    await _logService.logMigrationEvent(
      event: 'ACTIVE_INSTANCE_SET',
      details: 'Active instance changed',
      additionalInfo: {'instanceId': instanceId},
    );
  }

  /// Get active instance
  Future<NpmInstance?> getActiveInstance() async {
    final activeId = await getActiveInstanceId();
    if (activeId == null) return null;
    return await getInstance(activeId);
  }

  /// Clear active instance
  Future<void> clearActiveInstance() async {
    await _storage.delete(key: _keyActiveInstanceId);
  }
}




