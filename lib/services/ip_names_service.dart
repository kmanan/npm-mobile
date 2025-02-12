import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class IpNamesService {
  static const String _storageKey = 'ip_friendly_names';
  final SharedPreferences _prefs;

  IpNamesService(this._prefs);

  static Future<IpNamesService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return IpNamesService(prefs);
  }

  // Get friendly name for an IP
  String? getFriendlyName(String ip) {
    final names = _getStoredNames();
    return names[ip];
  }

  // Set friendly name for an IP
  Future<bool> setFriendlyName(String ip, String name) async {
    final names = _getStoredNames();
    names[ip] = name;
    return _saveNames(names);
  }

  // Remove friendly name for an IP
  Future<bool> removeFriendlyName(String ip) async {
    final names = _getStoredNames();
    names.remove(ip);
    return _saveNames(names);
  }

  // Get all stored names
  Map<String, String> getAllNames() {
    return _getStoredNames();
  }

  // Private helper to get stored names
  Map<String, String> _getStoredNames() {
    final String? storedData = _prefs.getString(_storageKey);
    if (storedData == null) return {};

    try {
      final Map<String, dynamic> decoded = json.decode(storedData);
      return Map<String, String>.from(decoded);
    } catch (e) {
      return {};
    }
  }

  // Private helper to save names
  Future<bool> _saveNames(Map<String, String> names) {
    return _prefs.setString(_storageKey, json.encode(names));
  }
}
