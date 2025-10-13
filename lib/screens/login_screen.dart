import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Platform;
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/log_service.dart';
import '../services/subscription_service.dart';
import '../utils/share_logs.dart';
import '../models/npm_instance.dart';
import 'main_screen.dart';
import 'paywall_screen.dart';

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
  bool _rememberMe = true;
  bool _biometricsAvailable = false;
  List<NpmInstance> _instances = [];
  String? _selectedInstanceId;

  final _serverFocusNode = FocusNode();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _checkStorageHealth();
    _checkMigration();
    _loadInstances();
  }

  Future<void> _checkStorageHealth() async {
    final isHealthy = await _authService.checkStorageHealth();
    if (!isHealthy) {
      print('WARNING: Secure storage is not working properly on this device');
    }
  }

  Future<void> _checkMigration() async {
    final needsMigration = await _authService.needsMigration();
    if (needsMigration) {
      await _authService.migrateFromLegacyStorage();
    }
  }

  Future<void> _loadInstances() async {
    final instances = await _authService.getAllInstances();
    if (mounted) {
      setState(() {
        _instances = instances;
        if (_instances.isNotEmpty) {
          // Select the most recently used instance (first in list)
          _selectedInstanceId = _instances.first.id;
          _loadInstanceCredentials(_instances.first);
        }
      });
      if (_instances.isNotEmpty) {
        _checkBiometrics();
      }
    }
  }

  Future<void> _loadInstanceCredentials(NpmInstance instance) async {
    final credentials = await _authService.getInstanceCredentials(instance.id);
    if (mounted) {
      setState(() {
        _serverController.text = credentials['serverUrl'] ?? '';
        _emailController.text = credentials['email'] ?? '';
        // Don't set password here, only with biometric auth
      });
    }
  }

  Future<void> _selectInstance(String instanceId) async {
    final instance = _instances.firstWhere((inst) => inst.id == instanceId);
    setState(() {
      _selectedInstanceId = instanceId;
    });
    await _authService.setActiveInstance(instanceId);
    await _loadInstanceCredentials(instance);
    await _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    final available = await _authService.isBiometricAvailable();
    print('Initial biometrics check - Available: $available');

    if (available && mounted && _selectedInstanceId != null) {
      final enabled =
          await _authService.isInstanceBiometricEnabled(_selectedInstanceId!);
      print('Biometrics enabled for instance: $enabled');

      final credentials =
          await _authService.getInstanceCredentials(_selectedInstanceId!);
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
      print(
          'Biometrics not available or widget not mounted or no instance selected');
    }
  }

  Future<void> _tryBiometricAuth() async {
    try {
      if (_selectedInstanceId == null) {
        print('No instance selected');
        return;
      }

      print('Starting biometric authentication attempt');
      final credentials =
          await _authService.getInstanceCredentials(_selectedInstanceId!);
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

      final enabled =
          await _authService.isInstanceBiometricEnabled(_selectedInstanceId!);
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

  Future<void> _showBiometricPrompt() async {
    if (_selectedInstanceId == null) return;

    final shouldEnable = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Enable Biometric Login'),
            content: const Text(
                'Would you like to enable biometric login for faster access next time?'),
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
      await _authService.updateInstance(
        instanceId: _selectedInstanceId!,
        password: _passwordController.text.trim(),
        enableBiometric: true,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Biometric login enabled successfully'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _showAddInstanceDialog() async {
    final subscriptionService = SubscriptionService();
    final instanceCount = _instances.length;

    // Check if user can add more instances
    final canAdd = await subscriptionService.canAddInstance(instanceCount);

    if (!canAdd) {
      // Show paywall
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => const PaywallScreen(feature: 'multi_instance'),
        ),
      );

      if (result != true) {
        return; // User didn't subscribe or start trial
      }
    }

    final nameController = TextEditingController();
    final serverController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    bool enableBiometric = false;
    final biometricAvailable = await _authService.isBiometricAvailable();

    if (!mounted) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add NPM Instance'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Instance Name',
                    hintText: 'Production Server',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: serverController,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'example.com or 192.168.1.1',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                if (biometricAvailable)
                  CheckboxListTile(
                    title: const Text('Enable Biometric Login'),
                    value: enableBiometric,
                    onChanged: (value) {
                      setState(() {
                        enableBiometric = value ?? false;
                      });
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty ||
                    serverController.text.trim().isEmpty ||
                    emailController.text.trim().isEmpty ||
                    passwordController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please fill in all fields'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  return;
                }

                try {
                  // First test login
                  final loginSuccess = await _apiService.login(
                    serverController.text.trim(),
                    emailController.text.trim(),
                    passwordController.text.trim(),
                  );

                  if (!loginSuccess) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Could not connect to server. Please verify credentials.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                    return;
                  }

                  // Create instance
                  final instanceId = await _authService.createInstance(
                    name: nameController.text.trim(),
                    serverUrl: serverController.text.trim(),
                    email: emailController.text.trim(),
                    password: passwordController.text.trim(),
                    enableBiometric: enableBiometric,
                  );

                  // Set as active instance
                  await _authService.setActiveInstance(instanceId);

                  if (context.mounted) {
                    Navigator.pop(context, true);
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                }
              },
              child: const Text('ADD'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      await _loadInstances();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const MainScreen(),
          ),
        );
      }
    }
  }

  Future<void> _showDeleteInstanceDialog(NpmInstance instance) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Instance'),
        content: Text(
            'Are you sure you want to delete "${instance.name}"?\n\nThis will remove all saved credentials for this instance.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _authService.deleteInstance(instance.id);
        await _loadInstances();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Instance deleted successfully'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting instance: $e'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
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
                        label: const Text('Sign in with Biometrics'),
                        onPressed: _tryBiometricAuth,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Or sign in with credentials',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    // Instance selector
                    if (_instances.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'NPM Instance',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 12,
                            ),
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add New'),
                            onPressed: _showAddInstanceDialog,
                          ),
                        ],
                      ),
                      DropdownButtonFormField<String>(
                        value: _selectedInstanceId,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        dropdownColor: Colors.grey[900],
                        items: _instances.map((instance) {
                          return DropdownMenuItem(
                            value: instance.id,
                            child: Text(
                              '${instance.biometricEnabled ? "🔒 " : ""}${instance.name}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (instanceId) {
                          if (instanceId != null) {
                            _selectInstance(instanceId);
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_instances.length} instance${_instances.length != 1 ? 's' : ''} configured',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 11,
                            ),
                          ),
                          if (_selectedInstanceId != null)
                            TextButton.icon(
                              icon: const Icon(Icons.delete, size: 16),
                              label: const Text('Delete',
                                  style: TextStyle(fontSize: 11)),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              onPressed: () {
                                final instance = _instances.firstWhere(
                                  (inst) => inst.id == _selectedInstanceId,
                                );
                                _showDeleteInstanceDialog(instance);
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ] else ...[
                      Text(
                        'No instances configured',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Add First Instance'),
                        onPressed: _showAddInstanceDialog,
                      ),
                      const SizedBox(height: 16),
                    ],
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
                      autofillHints: const [AutofillHints.username],
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
                      autofillHints: const [AutofillHints.password],
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
    _serverController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Server URL cleared'),
        duration: Duration(seconds: 2),
      ),
    );
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
      // If no instance exists, create one first
      if (_selectedInstanceId == null) {
        final instanceId = await _authService.createInstance(
          name: _serverController.text.trim(),
          serverUrl: _serverController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
          enableBiometric: false,
        );
        await _authService.setActiveInstance(instanceId);
        setState(() {
          _selectedInstanceId = instanceId;
        });
      }

      final success = await _apiService.login(
        _serverController.text.trim(),
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );

      if (!mounted) return;

      if (success) {
        if (_rememberMe && _selectedInstanceId != null) {
          if (_biometricsAvailable) {
            final biometricsEnabled = await _authService
                .isInstanceBiometricEnabled(_selectedInstanceId!);
            if (!biometricsEnabled) {
              print('Showing biometric enable prompt after successful login');
              await _showBiometricPrompt();
            } else {
              print(
                  'Biometrics already enabled, updating instance without prompt');
              await _authService.updateInstance(
                instanceId: _selectedInstanceId!,
                password: _passwordController.text.trim(),
                enableBiometric: true,
              );
            }
          } else {
            print('Updating instance credentials without biometrics');
            await _authService.updateInstance(
              instanceId: _selectedInstanceId!,
              password: _passwordController.text.trim(),
              enableBiometric: false,
            );
          }
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
