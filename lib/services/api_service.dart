import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/proxy_host.dart';
import '../models/error_details.dart';
import '../services/log_service.dart';
import 'dart:async';

class ApiService {
  final Dio _dio = Dio();
  final _storage = const FlutterSecureStorage();
  final _logService = LogService();
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
      await _storage.write(key: 'auth_token', value: 'demo_token');
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
        await _storage.write(key: 'auth_token', value: response.data['token']);
        _dio.options.headers['Authorization'] =
            'Bearer ${response.data['token']}';
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

  Future<bool> toggleProxyHost(int hostId, bool enabled) async {
    try {
      if (isDemoMode) {
        // In demo mode, just return true to simulate success
        return true;
      }

      final token = await _storage.read(key: 'auth_token');
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
