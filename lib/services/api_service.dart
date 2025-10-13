import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/proxy_host.dart';
import '../models/error_details.dart';
import '../services/log_service.dart';
import '../services/instance_service.dart';
import 'dart:async';

class ApiService {
  final Dio _dio = Dio();
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
  final _logService = LogService();
  final _instanceService = InstanceService();
  bool isDemoMode = false;

  ApiService() {
    _setupDio();
    _loadSavedUrl();
  }

  Future<void> _loadSavedUrl() async {
    if (!isDemoMode) {
      // Try to load from active instance first
      final activeInstanceId = await _instanceService.getActiveInstanceId();
      if (activeInstanceId != null) {
        final savedUrl =
            await _storage.read(key: 'instance_${activeInstanceId}_server_url');
        if (savedUrl != null) {
          updateBaseUrl(savedUrl);
          return;
        }
      }
      // Fallback to legacy server_url for backward compatibility
      final savedUrl = await _storage.read(key: 'server_url');
      if (savedUrl != null) {
        updateBaseUrl(savedUrl);
      }
    }
  }

  void _setupDio() {
    _dio.options.validateStatus = (status) => true;
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
      final activeInstanceId = await _instanceService.getActiveInstanceId();
      if (activeInstanceId != null) {
        await _storage.write(
            key: 'instance_${activeInstanceId}_server_url', value: url);
      } else {
        // Fallback to legacy for backward compatibility
        await _storage.write(key: 'server_url', value: url);
      }
    }
  }

  Future<void> clearServerUrl() async {
    await _storage.delete(key: 'server_url');
  }

  Future<String?> getSavedServerUrl() async {
    final activeInstanceId = await _instanceService.getActiveInstanceId();
    if (activeInstanceId != null) {
      return await _storage.read(
          key: 'instance_${activeInstanceId}_server_url');
    }
    return await _storage.read(key: 'server_url');
  }

  Future<bool> checkDemoMode() async {
    final activeInstanceId = await _instanceService.getActiveInstanceId();
    String? token;
    if (activeInstanceId != null) {
      token =
          await _storage.read(key: 'instance_${activeInstanceId}_auth_token');
    } else {
      token = await _storage.read(key: 'auth_token');
    }
    isDemoMode = token == 'demo_token';
    print('Checking demo mode: $isDemoMode'); // Debug print
    return isDemoMode;
  }

  /// Save auth token for a specific instance
  Future<void> saveInstanceAuthToken(String instanceId, String token) async {
    await _storage.write(
        key: 'instance_${instanceId}_auth_token', value: token);
  }

  /// Get auth token for a specific instance
  Future<String?> getInstanceAuthToken(String instanceId) async {
    return await _storage.read(key: 'instance_${instanceId}_auth_token');
  }

  /// Clear auth token for a specific instance
  Future<void> clearInstanceAuthToken(String instanceId) async {
    await _storage.delete(key: 'instance_${instanceId}_auth_token');
  }

  /// Get active instance ID
  Future<String?> getActiveInstanceId() async {
    return await _instanceService.getActiveInstanceId();
  }

  /// Switch to a different instance
  Future<void> switchInstance(String instanceId) async {
    // Clear old authorization header
    _dio.options.headers.remove('Authorization');

    // Set new active instance
    await _instanceService.setActiveInstanceId(instanceId);

    // Load new instance URL
    final newUrl =
        await _storage.read(key: 'instance_${instanceId}_server_url');
    if (newUrl != null) {
      updateBaseUrl(newUrl);
    }

    // Load new instance token
    final token = await getInstanceAuthToken(instanceId);
    if (token != null && token != 'demo_token') {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }
  }

  Future<bool> login(String serverUrl, String email, String password) async {
    try {
      // Update and save the server URL first
      updateBaseUrl(serverUrl);
      await saveServerUrl(serverUrl);

      // First try to reach the server with a shorter timeout
      try {
        await Future.any([
          _checkServerReachable(serverUrl),
          Future.delayed(const Duration(seconds: 5)).then((_) {
            throw TimeoutException('Server check timed out');
          }),
        ]);
      } on TimeoutException {
        await _logService.logAuthFailure(
          errorMessage:
              'Could not reach server at $serverUrl within 5 seconds. Please verify the server is running and accessible.',
          errorType: 'SERVER_UNREACHABLE_TIMEOUT',
          serverUrl: serverUrl,
          responseData: 'Server did not respond to initial connection attempt',
          email: email,
        );
        return false;
      }

      // If server is reachable, proceed with login attempt
      try {
        return await Future.any([
          _performLogin(serverUrl, email, password),
          Future.delayed(const Duration(seconds: 10)).then((_) {
            throw TimeoutException('Authentication timed out');
          }),
        ]);
      } on TimeoutException {
        await _logService.logAuthFailure(
          errorMessage:
              'Server is reachable but authentication took too long. The server might be overloaded.',
          errorType: 'AUTH_TIMEOUT',
          serverUrl: serverUrl,
          responseData: 'Authentication process exceeded 10 second timeout',
          email: email,
        );
        return false;
      }
    } catch (e) {
      final errorDetails = _getErrorDetails(e, serverUrl);
      await _logService.logAuthFailure(
        errorMessage: errorDetails.message,
        errorType: errorDetails.type,
        serverUrl: serverUrl,
        responseData: errorDetails.data,
        email: email,
      );
      return false;
    }
  }

  // Move the existing login logic to a separate method
  Future<bool> _performLogin(
      String serverUrl, String email, String password) async {
    if (email == "demo@playstore.com" && password == "demopass123") {
      isDemoMode = true;
      final activeInstanceId = await _instanceService.getActiveInstanceId();
      if (activeInstanceId != null) {
        await saveInstanceAuthToken(activeInstanceId, 'demo_token');
      } else {
        await _storage.write(key: 'auth_token', value: 'demo_token');
      }
      return true;
    }

    if (!isDemoMode) {
      // First, validate the URL is reachable
      try {
        updateBaseUrl(serverUrl);
        await _dio.get(
          '/api/tokens',
          options: Options(
            validateStatus: (_) => true,
            sendTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
          ),
        );
      } catch (e) {
        if (e is DioException) {
          final errorMessage = switch (e.type) {
            DioExceptionType.connectionTimeout =>
              'Server connection timed out. Please check if the URL is correct and the server is running.',
            DioExceptionType.connectionError =>
              'Could not connect to server. Please verify the URL and port are correct.',
            DioExceptionType.badCertificate =>
              'SSL certificate error. The server\'s security certificate is not trusted.',
            _ => 'Server is not reachable at $serverUrl. Error: ${e.message}'
          };
          await _logService.logAuthFailure(
            errorMessage: errorMessage,
            errorType: 'CONNECTION_ERROR',
            serverUrl: serverUrl,
            responseData: e.message ?? 'No error details available',
            email: email,
          );
          return false;
        }
        rethrow;
      }

      final response = await _dio.post(
        '/api/tokens',
        data: {
          'identity': email,
          'secret': password,
        },
        options: Options(
          contentType: Headers.jsonContentType,
          validateStatus: (_) => true,
        ),
      );

      final statusCode = response.statusCode ?? 0;

      if (statusCode != 200) {
        String errorType;
        String errorMessage;
        String responseDataString;

        try {
          // Safely convert response data to string for logging
          if (response.data is Map) {
            responseDataString = response.data['error']?.toString() ??
                response.data['message']?.toString() ??
                'No error message provided';
          } else {
            responseDataString =
                response.data?.toString() ?? 'No response data';
          }

          if (statusCode == 401 || statusCode == 403) {
            errorType = 'AUTH_ERROR';
            if (response.data is Map) {
              final message = response.data['message']?.toString() ?? '';

              if (message.contains('User not found')) {
                errorMessage =
                    'Email address not found. Please check your email.';
              } else if (message.contains('Password does not match')) {
                errorMessage =
                    'Incorrect password. Please check your password.';
              } else {
                print('Auth Response: ${response.data}');
                errorMessage =
                    message.isNotEmpty ? message : 'Authentication failed';
              }
            } else {
              errorMessage =
                  'Authentication failed. Please check your credentials.';
            }
          } else if (statusCode == 404) {
            errorType = 'SERVER_ERROR';
            errorMessage =
                'Nginx Proxy Manager API not found at this URL. Please verify the server URL and port.';
          } else if (statusCode >= 500) {
            errorType = 'SERVER_ERROR';
            errorMessage = 'Server error occurred. Please try again later.';
          } else {
            errorType = 'UNKNOWN_ERROR';
            errorMessage =
                'Server returned unexpected response (Status: $statusCode)';
          }

          await _logService.logAuthFailure(
            errorMessage: errorMessage,
            errorType: errorType,
            statusCode: statusCode,
            serverUrl: serverUrl,
            responseData: responseDataString,
            email: email,
          );
        } catch (e) {
          // If there's any error in parsing the response, log that instead
          await _logService.logAuthFailure(
            errorMessage: 'Error parsing server response',
            errorType: 'PARSE_ERROR',
            statusCode: statusCode,
            serverUrl: serverUrl,
            responseData: e.toString(),
            email: email,
          );
        }
        return false;
      }

      if (response.data != null && response.data['token'] != null) {
        final token = response.data['token'];
        final activeInstanceId = await _instanceService.getActiveInstanceId();
        print(
            'Login successful - saving token. Active instance: $activeInstanceId');
        if (activeInstanceId != null) {
          await saveInstanceAuthToken(activeInstanceId, token);
          print('Token saved for instance: $activeInstanceId');
          // Verify it was saved
          final verifyToken = await getInstanceAuthToken(activeInstanceId);
          print('Token verification - saved correctly: ${verifyToken != null}');
        } else {
          await _storage.write(key: 'auth_token', value: token);
          print('Token saved to legacy storage');
        }
        _dio.options.headers['Authorization'] = 'Bearer $token';
        return true;
      }
    }

    return false;
  }

  ErrorDetails _getErrorDetails(dynamic error, String serverUrl) {
    if (error is DioException) {
      return switch (error.type) {
        DioExceptionType.connectionTimeout => ErrorDetails(
            'Connection timed out while trying to reach $serverUrl',
            'TIMEOUT_ERROR',
            error.message ?? ''),
        DioExceptionType.sendTimeout => ErrorDetails(
            'Request timed out while sending data to server',
            'TIMEOUT_ERROR',
            error.message ?? ''),
        DioExceptionType.receiveTimeout => ErrorDetails(
            'Server took too long to respond',
            'TIMEOUT_ERROR',
            error.message ?? ''),
        DioExceptionType.badCertificate => ErrorDetails(
            'Invalid SSL certificate from server',
            'SSL_ERROR',
            error.message ?? ''),
        DioExceptionType.connectionError => ErrorDetails(
            'Failed to connect to server. Please check URL and port.',
            'CONNECTION_ERROR',
            error.message ?? ''),
        _ => ErrorDetails(
            'Network error occurred: ${error.message}',
            'NETWORK_ERROR',
            error.response?.data?.toString() ?? error.message ?? ''),
      };
    }
    return ErrorDetails(
      'Unexpected error: ${error.toString()}',
      'UNKNOWN_ERROR',
      error.toString(),
    );
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

      // Ensure we have the base URL loaded
      await _loadSavedUrl();

      // Only try API call if not in demo mode
      final activeInstanceId = await _instanceService.getActiveInstanceId();
      String? token;
      if (activeInstanceId != null) {
        token = await getInstanceAuthToken(activeInstanceId);
        print(
            'Got token for instance $activeInstanceId: ${token != null ? "yes" : "no"}');
      } else {
        token = await _storage.read(key: 'auth_token');
        print('Got legacy token: ${token != null ? "yes" : "no"}');
      }
      if (token == null) {
        print('No auth token found - cannot fetch proxy hosts');
        throw Exception('No auth token found');
      }

      print('Making API call to ${_dio.options.baseUrl}/api/nginx/proxy-hosts');

      final response = await _dio.get(
        '/api/nginx/proxy-hosts',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      print('Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        print('Got ${data.length} proxy hosts');
        return data.map((json) => ProxyHost.fromJson(json)).toList();
      }
      print('Non-200 response: ${response.statusCode}');
      return [];
    } catch (e) {
      print('Error fetching proxy hosts: $e');
      return [];
    }
  }

  Future<bool> toggleProxyHost(int hostId, bool enabled) async {
    try {
      if (isDemoMode) {
        // In demo mode, just return true to simulate success
        return true;
      }

      final activeInstanceId = await _instanceService.getActiveInstanceId();
      String? token;
      if (activeInstanceId != null) {
        token = await getInstanceAuthToken(activeInstanceId);
      } else {
        token = await _storage.read(key: 'auth_token');
      }
      if (token == null) throw Exception('No auth token found');

      final response = await _dio.put(
        '/api/nginx/proxy-hosts/$hostId',
        data: {
          'enabled': enabled,
        },
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error toggling proxy host: $e');
      return false;
    }
  }

  Future<bool> updateProxyHost({
    required int id,
    required List<String> domainNames,
    required String forwardScheme,
    required String forwardHost,
    required int forwardPort,
    required bool sslForced,
    bool? enabled,
    int? certificateId,
    int? accessListId,
  }) async {
    try {
      if (isDemoMode) {
        return true;
      }

      final activeInstanceId = await _instanceService.getActiveInstanceId();
      String? token;
      if (activeInstanceId != null) {
        token = await getInstanceAuthToken(activeInstanceId);
      } else {
        token = await _storage.read(key: 'auth_token');
      }
      if (token == null) throw Exception('No auth token found');

      final response = await _dio.put(
        '/api/nginx/proxy-hosts/$id',
        data: {
          'domain_names': domainNames,
          'forward_scheme': forwardScheme,
          'forward_host': forwardHost,
          'forward_port': forwardPort,
          'ssl_forced': sslForced,
          if (enabled != null) 'enabled': enabled,
          if (certificateId != null) 'certificate_id': certificateId,
          if (accessListId != null) 'access_list_id': accessListId,
        },
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          validateStatus: (status) => true,
        ),
      );

      if (response.statusCode != 200) {
        print('Error updating proxy host: ${response.data}');
        return false;
      }

      return true;
    } catch (e) {
      print('Error updating proxy host: $e');
      return false;
    }
  }

  /// Create a new proxy host
  Future<ProxyHost?> createProxyHost({
    required List<String> domainNames,
    required String forwardScheme,
    required String forwardHost,
    required int forwardPort,
    required bool sslForced,
    bool? enabled,
    int? certificateId,
    int? accessListId,
    bool blockExploits = true,
    bool cachingEnabled = false,
    bool allowWebsocketUpgrade = false,
    bool http2Support = false,
    String advancedConfig = '',
  }) async {
    try {
      if (isDemoMode) {
        // In demo mode, return a fake host with a random ID
        return ProxyHost(
          id: DateTime.now().millisecondsSinceEpoch,
          domainNames: domainNames,
          forwardScheme: forwardScheme,
          forwardHost: forwardHost,
          forwardPort: forwardPort,
          accessListId: accessListId,
          certificateId: certificateId,
          sslForced: sslForced,
          enabled: enabled ?? true,
        );
      }

      final activeInstanceId = await _instanceService.getActiveInstanceId();
      String? token;
      if (activeInstanceId != null) {
        token = await getInstanceAuthToken(activeInstanceId);
      } else {
        token = await _storage.read(key: 'auth_token');
      }
      if (token == null) throw Exception('No auth token found');

      final response = await _dio.post(
        '/api/nginx/proxy-hosts',
        data: {
          'domain_names': domainNames,
          'forward_scheme': forwardScheme,
          'forward_host': forwardHost,
          'forward_port': forwardPort,
          'ssl_forced': sslForced,
          'enabled': enabled ?? true,
          'access_list_id': accessListId ?? 0,
          'certificate_id': certificateId ?? 0,
          'block_exploits': blockExploits,
          'caching_enabled': cachingEnabled,
          'allow_websocket_upgrade': allowWebsocketUpgrade,
          'http2_support': http2Support,
          'advanced_config': advancedConfig,
          'hsts_enabled': false,
          'hsts_subdomains': false,
          'meta': {
            'letsencrypt_agree': false,
            'dns_challenge': false,
            'letsencrypt_email': '',
          },
        },
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          validateStatus: (status) => true,
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Parse the response and return the created ProxyHost
        return ProxyHost.fromJson(response.data);
      } else {
        print('Error creating proxy host: ${response.data}');
        return null;
      }
    } catch (e) {
      print('Error creating proxy host: $e');
      return null;
    }
  }

  // Add this new method to check server reachability
  Future<void> _checkServerReachable(String serverUrl) async {
    try {
      updateBaseUrl(serverUrl);
      await _dio.get(
        '/api/tokens',
        options: Options(
          validateStatus: (_) => true,
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (e is DioException) {
        final errorMessage = switch (e.type) {
          DioExceptionType.connectionTimeout =>
            'Server connection timed out. Server might be down or unreachable.',
          DioExceptionType.connectionError =>
            'Could not establish connection. Please verify the URL and port.',
          DioExceptionType.badCertificate =>
            'SSL certificate error. The server\'s security certificate is not trusted.',
          _ => 'Server is not reachable at $serverUrl. Error: ${e.message}'
        };
        throw Exception(errorMessage);
      }
      rethrow;
    }
  }
}
