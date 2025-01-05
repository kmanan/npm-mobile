import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/proxy_host.dart';
import '../services/api_service.dart';
import 'login_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ApiService _apiService = ApiService();
  List<ProxyHost> _proxyHosts = [];
  bool _isLoading = true;

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
    const storage = FlutterSecureStorage();
    await storage.delete(key: 'auth_token');
    // Note: We don't delete 'server_url' so it persists for next login

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const LoginScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nginx Proxy Manager'),
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
                    return Card(
                      margin: const EdgeInsets.all(8.0),
                      child: ListTile(
                        title: Text(host.domainNames.first),
                        subtitle: Text(
                          '${host.forwardScheme}://${host.forwardHost}:${host.forwardPort}',
                        ),
                        trailing: Switch(
                          value: host.enabled,
                          onChanged: (value) {
                            // TODO: Implement enable/disable functionality
                          },
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}