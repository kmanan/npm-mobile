import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:io' show Platform;
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/log_service.dart';
import '../utils/share_logs.dart';
import 'main_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _apiService = ApiService();
  final _authService = AuthService();
  final _logService = LogService();
  bool _isLoading = false;
  bool _rememberMe = false;
  bool _biometricsAvailable = false;

  final _serverFocusNode = FocusNode();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
    _loadSavedCredentials();
  }

  Future<void> _checkBiometrics() async {
    final available = await _authService.isBiometricAvailable();
    print('Initial biometrics check - Available: $available');

    if (available && mounted) {
      final enabled = await _authService.isBiometricEnabled();
      print('Biometrics enabled in preferences: $enabled');

      final credentials = await _authService.getSavedCredentials();
      print(
          'Saved credentials check - Server: ${credentials['serverUrl'] != null}, '
          'Email: ${credentials['email'] != null}, '
          'Password: ${credentials['password'] != null}');

      setState(() => _biometricsAvailable = true);

      if (credentials['password'] != null && enabled && mounted) {
        print('Attempting automatic biometric authentication');
        _tryBiometricAuth();
      } else {
        print('Not attempting automatic biometric auth - '
            'Password exists: ${credentials['password'] != null}, '
            'Biometrics enabled: $enabled');
      }
    } else {
      print('Biometrics not available or widget not mounted');
    }
  }

  Future<void> _tryBiometricAuth() async {
    try {
      print('Starting biometric authentication attempt');
      final credentials = await _authService.getSavedCredentials();
      print(
          'Retrieved credentials - Server: ${credentials['serverUrl'] != null}, Email: ${credentials['email'] != null}, Password: ${credentials['password'] != null}');

      if (credentials['password'] == null) {
        print('No saved password found');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'No saved credentials found. Please login with password first.'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      final enabled = await _authService.isBiometricEnabled();
      print('Biometrics enabled check: $enabled');

      if (!enabled) {
        print('Biometrics not enabled in preferences');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Biometric authentication is not enabled. Please login with password and enable biometrics.'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      print('Attempting biometric authentication');
      final success = await _authService.authenticateWithBiometrics();
      print('Biometric authentication result: $success');

      if (success && mounted) {
        print('Authentication successful, setting credentials');
        setState(() {
          _serverController.text = credentials['serverUrl'] ?? '';
          _emailController.text = credentials['email'] ?? '';
          _passwordController.text = credentials['password'] ?? '';
          _rememberMe = true;
        });
        _handleLogin();
      } else if (mounted) {
        print('Authentication failed or widget not mounted');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Biometric authentication failed. Please try again or use password.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Error during biometric authentication: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error during biometric authentication: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _loadSavedCredentials() async {
    final credentials = await _authService.getSavedCredentials();
    if (mounted) {
      setState(() {
        _serverController.text = credentials['serverUrl'] ?? '';
        _emailController.text = credentials['email'] ?? '';
        // Don't set password here, only with biometric auth
      });
    }
  }

  Future<void> _showBiometricPrompt() async {
    final shouldEnable = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Enable Face ID'),
            content: const Text(
                'Would you like to enable Face ID for faster login next time?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('NO'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('YES'),
              ),
            ],
          ),
        ) ??
        false;

    if (shouldEnable) {
      await _authService.saveCredentials(
        serverUrl: _serverController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        enableBiometric: true,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Face ID enabled successfully'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Widget _buildShareLogsButton() {
    return TextButton.icon(
      onPressed: () => shareLogs(context),
      icon: const Icon(Icons.share),
      label: const Text('Share Authentication Logs'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SingleChildScrollView(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    Image.asset(
                      'assets/icon/icon.png',
                      width: 100,
                      height: 100,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Nginx Mobile Dashboard',
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                    if (_biometricsAvailable) ...[
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        icon: Platform.isIOS
                            ? const Icon(Icons.face)
                            : const Icon(Icons.fingerprint),
                        label: Text(Platform.isIOS
                            ? 'Sign in with Face ID'
                            : 'Sign in with Biometrics'),
                        onPressed: _tryBiometricAuth,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Or sign in with credentials',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _serverController,
                      focusNode: _serverFocusNode,
                      decoration: InputDecoration(
                        labelText: 'Server URL',
                        hintText: 'example.com or 192.168.1.1',
                        border: const OutlineInputBorder(),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.paste),
                              onPressed: !_isLoading ? _pasteServerUrl : null,
                            ),
                            IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: !_isLoading ? _clearServerUrl : null,
                            ),
                          ],
                        ),
                      ),
                      enabled: !_isLoading,
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) {
                        FocusScope.of(context).requestFocus(_emailFocusNode);
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter server URL';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailController,
                      focusNode: _emailFocusNode,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      enabled: !_isLoading,
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) {
                        FocusScope.of(context).requestFocus(_passwordFocusNode);
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      focusNode: _passwordFocusNode,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.paste),
                          onPressed: !_isLoading ? _pastePassword : null,
                        ),
                      ),
                      obscureText: true,
                      enabled: !_isLoading,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) {
                        if (!_isLoading) _handleLogin();
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your password';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Checkbox(
                          value: _rememberMe,
                          onChanged: (value) {
                            setState(() => _rememberMe = value ?? false);
                          },
                        ),
                        const Text('Remember Me'),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleLogin,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Login'),
                      ),
                    ),
                    _buildShareLogsButton(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pasteServerUrl() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _serverController.text = data!.text!;
    }
  }

  Future<void> _clearServerUrl() async {
    await _authService.clearCredentials();
    if (mounted) {
      setState(() {
        _serverController.clear();
        _emailController.clear();
        _passwordController.clear();
        _rememberMe = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All saved credentials cleared'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _pastePassword() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _passwordController.text = data!.text!;
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final success = await _apiService.login(
        _serverController.text.trim(),
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );

      if (!mounted) return;

      if (success) {
        if (_rememberMe) {
          if (_biometricsAvailable) {
            print('Showing biometric enable prompt after successful login');
            await _showBiometricPrompt();
          } else {
            print('Saving credentials without biometrics');
            await _authService.saveCredentials(
              serverUrl: _serverController.text.trim(),
              email: _emailController.text.trim(),
              password: _passwordController.text.trim(),
              enableBiometric: false,
            );
          }
        } else {
          print('Remember me not checked, clearing any saved credentials');
          await _authService.clearCredentials();
        }

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const MainScreen(),
          ),
        );
      } else {
        await _logService.logAuthFailure(
          errorMessage: 'Authentication failed',
          errorType: 'AUTH_ERROR',
          statusCode: null,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Login failed. Please check your credentials.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      await _logService.logAuthFailure(
        errorMessage: e.toString(),
        errorType: 'UNKNOWN_ERROR',
        statusCode: null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('An error occurred during login'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _serverFocusNode.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _serverController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
