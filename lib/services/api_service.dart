import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/proxy_host.dart';

class ApiService {
  final Dio _dio = Dio();
  final _storage = const FlutterSecureStorage();
  
  ApiService() {
    _setupDio();
    _loadSavedUrl();
  }

  Future<void> _loadSavedUrl() async {
    final savedUrl = await _storage.read(key: 'server_url');
    if (savedUrl != null) {
      updateBaseUrl(savedUrl);
    }
  }

  void _setupDio() {
    _dio.options.validateStatus = (status) {
      return status != null && status < 500;
    };
  }

  void updateBaseUrl(String url) {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    if (!url.contains(':')) {
      url = '$url:81';
    }
    _dio.options.baseUrl = url;
  }

  Future<void> saveServerUrl(String url) async {
    await _storage.write(key: 'server_url', value: url);
  }

  Future<void> clearServerUrl() async {
    await _storage.delete(key: 'server_url');
  }

  Future<String?> getSavedServerUrl() async {
    return await _storage.read(key: 'server_url');
  }

  Future<bool> login(String serverUrl, String email, String password) async {
    try {
      updateBaseUrl(serverUrl);
      await saveServerUrl(serverUrl);  // Save URL on successful connection
      
      final response = await _dio.post(
        '/api/tokens',
        data: {
          'identity': email,
          'secret': password,
        },
        options: Options(
          contentType: Headers.jsonContentType,
          validateStatus: (status) => true,
        ),
      );

      if (response.statusCode == 200 && response.data['token'] != null) {
        await _storage.write(key: 'auth_token', value: response.data['token']);
        _dio.options.headers['Authorization'] = 'Bearer ${response.data['token']}';
        return true;
      }
      
      print('Login failed: ${response.statusCode} - ${response.data}');
      return false;
    } catch (e) {
      print('Login error: $e');
      return false;
    }
  }

  Future<List<ProxyHost>> getProxyHosts() async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) throw Exception('No auth token found');

      final response = await _dio.get(
        '/api/nginx/proxy-hosts',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((json) => ProxyHost.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching proxy hosts: $e');
      return [];
    }
  }
}