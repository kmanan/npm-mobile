import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/proxy_host.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'proxy_host_edit_screen.dart';

const _toggleTimeout = Duration(seconds: 10);

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  List<ProxyHost> _proxyHosts = [];
  bool _isLoading = true;
  Set<int> _loadingHosts = {};

  @override
  void initState() {
    super.initState();
    _loadProxyHosts();
  }

  Future<void> _loadProxyHosts() async {
    try {
      final hosts = await _apiService.getProxyHosts();
      if (mounted) {
        setState(() {
          _proxyHosts = hosts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load proxy hosts')),
        );
      }
    }
  }

  Future<void> _handleLogout() async {
    await _authService.handleLogout();

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const LoginScreen(),
        ),
      );
    }
  }

  Future<void> _toggleHost(ProxyHost host, int index, bool value) async {
    // Show loading for this specific host
    setState(() {
      _loadingHosts.add(host.id);
    });

    try {
      // Add timeout to the API call
      final success = await _apiService
          .toggleProxyHost(host.id, value)
          .timeout(_toggleTimeout);

      if (!mounted) return;

      if (success) {
        setState(() {
          _proxyHosts[index] = ProxyHost(
            id: host.id,
            domainNames: host.domainNames,
            forwardScheme: host.forwardScheme,
            forwardHost: host.forwardHost,
            forwardPort: host.forwardPort,
            accessListId: host.accessListId,
            certificateId: host.certificateId,
            sslForced: host.sslForced,
            enabled: value,
          );
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(value
                ? 'Proxy host enabled successfully'
                : 'Proxy host disabled successfully'),
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update proxy host status'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is TimeoutException
              ? 'Request timed out. Please try again.'
              : 'Error updating proxy host status'),
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      // Always remove loading state, even if there's an error
      if (mounted) {
        setState(() {
          _loadingHosts.remove(host.id);
        });
      }
    }
  }

  String _getDomainUrl(ProxyHost host) {
    return '${host.forwardScheme}://${host.domainNames.first}';
  }

  String _getDirectUrl(ProxyHost host) {
    return '${host.forwardScheme}://${host.forwardHost}:${host.forwardPort}';
  }

  Future<void> _launchUrl(String url) async {
    try {
      await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open $url'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _editProxyHost(ProxyHost host) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => ProxyHostEditScreen(proxyHost: host),
      ),
    );

    if (result == true && mounted) {
      // Refresh the list if edit was successful
      setState(() => _isLoading = true);
      _loadProxyHosts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Row(
          children: [
            Image.asset(
              'assets/icon/icon.png',
              width: 30, // Smaller size for AppBar
              height: 30,
            ),
            const SizedBox(width: 8), // Space between icon and text
            const Text('Nginx Mobile Dashboard'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isLoading = true);
              _loadProxyHosts();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _handleLogout,
            tooltip: 'Logout',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _proxyHosts.isEmpty
              ? const Center(child: Text('No proxy hosts found'))
              : ListView.builder(
                  itemCount: _proxyHosts.length,
                  itemBuilder: (context, index) {
                    final host = _proxyHosts[index];
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 8.0,
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.language, size: 20),
                                    onPressed: () =>
                                        _launchUrl(_getDomainUrl(host)),
                                    tooltip: _getDomainUrl(host),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 40,
                                      minHeight: 40,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      host.domainNames.first,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 20),
                                    onPressed: () => _editProxyHost(host),
                                    tooltip: 'Edit',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 40,
                                      minHeight: 40,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _loadingHosts.contains(host.id)
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Switch(
                                          value: host.enabled,
                                          onChanged: (value) =>
                                              _toggleHost(host, index, value),
                                        ),
                                ],
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.link, size: 20),
                                    onPressed: () =>
                                        _launchUrl(_getDirectUrl(host)),
                                    tooltip: _getDirectUrl(host),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 40,
                                      minHeight: 40,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      _getDirectUrl(host),
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
    );
  }
}
