import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/proxy_host.dart';

class ApiService {
  final Dio _dio = Dio();
  final _storage = const FlutterSecureStorage();
  bool isDemoMode = false;

  ApiService() {
    _setupDio();
    _loadSavedUrl();
  }

  Future<void> _loadSavedUrl() async {
    if (!isDemoMode) {
      final savedUrl = await _storage.read(key: 'server_url');
      if (savedUrl != null) {
        updateBaseUrl(savedUrl);
      }
    }
  }

  void _setupDio() {
    _dio.options.validateStatus = (status) {
      return status != null && status < 500;
    };
  }

  void updateBaseUrl(String url) {
    if (!isDemoMode) {
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'http://$url';
      }
      if (!url.contains(':')) {
        url = '$url:81';
      }
      _dio.options.baseUrl = url;
    }
  }

  Future<void> saveServerUrl(String url) async {
    if (!isDemoMode) {
      await _storage.write(key: 'server_url', value: url);
    }
  }

  Future<void> clearServerUrl() async {
    await _storage.delete(key: 'server_url');
  }

  Future<String?> getSavedServerUrl() async {
    return await _storage.read(key: 'server_url');
  }
  Future<bool> checkDemoMode() async {
    final token = await _storage.read(key: 'auth_token');
    isDemoMode = token == 'demo_token';
    print('Checking demo mode: $isDemoMode'); // Debug print
    return isDemoMode;
  }

  Future<bool> login(String serverUrl, String email, String password) async {
    try {
      print('Login attempt with: $email'); // Debug print
      
      // Demo mode check
      if (email == "demo@playstore.com" && password == "demopass123") {
        print('Setting demo mode to true'); // Debug print
        isDemoMode = true;
        await _storage.write(key: 'auth_token', value: 'demo_token');
        return true;
      }

      // Rest of your existing login code...

      if (!isDemoMode) {
        updateBaseUrl(serverUrl);
        await saveServerUrl(serverUrl);
        
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
      }
      
      return false;
    } catch (e) {
      print('Login error: $e');
      return false;
    }
  }

  Future<List<ProxyHost>> getProxyHosts() async {
    try {
      // Check demo mode status first
      await checkDemoMode();
      print('Getting proxy hosts. isDemoMode: $isDemoMode'); // Debug print

      if (isDemoMode) {
        print('Returning demo hosts'); // Debug print
        return [
          ProxyHost(
            id: 1,
            domainNames: ["demo1.example.com"],
            forwardScheme: "https",
            forwardHost: "192.168.1.100",
            forwardPort: 443,
            accessListId: null,
            certificateId: 1,
            sslForced: true,
            enabled: true,
          ),
          ProxyHost(
            id: 2,
            domainNames: ["demo2.example.com"],
            forwardScheme: "http",
            forwardHost: "192.168.1.101",
            forwardPort: 80,
            accessListId: null,
            certificateId: null,
            sslForced: false,
            enabled: true,
          ),
        ];
      }


      // Only try API call if not in demo mode
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