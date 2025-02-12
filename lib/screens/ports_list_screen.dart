import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/proxy_host.dart';
import '../services/api_service.dart';
import '../services/ip_names_service.dart';
import 'login_screen.dart';

class PortsListScreen extends StatefulWidget {
  const PortsListScreen({super.key});

  @override
  State<PortsListScreen> createState() => _PortsListScreenState();
}

class _PortsListScreenState extends State<PortsListScreen> {
  final ApiService _apiService = ApiService();
  late final IpNamesService _ipNamesService;
  Map<String, List<ProxyHost>> _groupedHosts = {};
  Map<String, List<ProxyHost>> _filteredGroupedHosts = {};
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  Map<String, String> _ipNames = {};

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeServices() async {
    _ipNamesService = await IpNamesService.create();
    _ipNames = _ipNamesService.getAllNames();
    _loadAndGroupProxyHosts();
  }

  void _filterHosts(String query) {
    if (query.isEmpty) {
      setState(() => _filteredGroupedHosts = Map.from(_groupedHosts));
      return;
    }

    final searchLower = query.toLowerCase();
    final filtered = <String, List<ProxyHost>>{};

    _groupedHosts.forEach((ip, hosts) {
      // Check if IP matches
      if (ip.toLowerCase().contains(searchLower)) {
        filtered[ip] = hosts;
        return;
      }

      // Filter hosts by port or domain name
      final matchingHosts = hosts
          .where((host) =>
              host.forwardPort.toString().contains(searchLower) ||
              host.domainNames
                  .any((domain) => domain.toLowerCase().contains(searchLower)))
          .toList();

      if (matchingHosts.isNotEmpty) {
        filtered[ip] = matchingHosts;
      }
    });

    setState(() => _filteredGroupedHosts = filtered);
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

  Future<void> _loadAndGroupProxyHosts() async {
    try {
      final hosts = await _apiService.getProxyHosts();
      if (mounted) {
        final grouped = <String, List<ProxyHost>>{};
        for (var host in hosts) {
          final ip = host.forwardHost;
          if (!grouped.containsKey(ip)) {
            grouped[ip] = [];
          }
          grouped[ip]!.add(host);
        }

        // Sort ports for each IP
        for (var ip in grouped.keys) {
          grouped[ip]!.sort((a, b) => a.forwardPort.compareTo(b.forwardPort));
        }

        setState(() {
          _groupedHosts = grouped;
          _filteredGroupedHosts = Map.from(grouped); // Initialize filtered data
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

  Future<void> _editIpName(String ip) async {
    final currentName = _ipNames[ip] ?? '';
    final TextEditingController nameController =
        TextEditingController(text: currentName);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Name for $ip'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Friendly Name',
            hintText: 'Enter a friendly name for this IP',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          if (currentName.isNotEmpty)
            TextButton(
              onPressed: () {
                _ipNamesService.removeFriendlyName(ip);
                Navigator.pop(context, '');
              },
              child: const Text('REMOVE'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );

    if (result != null) {
      if (result.isEmpty) {
        await _ipNamesService.removeFriendlyName(ip);
      } else {
        await _ipNamesService.setFriendlyName(ip, result);
      }
      setState(() {
        _ipNames = _ipNamesService.getAllNames();
      });
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
              width: 30,
              height: 30,
            ),
            const SizedBox(width: 8),
            const Text('Ports List'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isLoading = true);
              _loadAndGroupProxyHosts();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _handleLogout,
            tooltip: 'Logout',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              onChanged: _filterHosts,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search by IP, port, or app name',
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          _searchController.clear();
                          _filterHosts('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredGroupedHosts.isEmpty
                    ? const Center(
                        child: Text(
                          'No matching results found',
                          style: TextStyle(color: Colors.white),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredGroupedHosts.length,
                        itemBuilder: (context, index) {
                          final ip =
                              _filteredGroupedHosts.keys.elementAt(index);
                          final hosts = _filteredGroupedHosts[ip]!;
                          final friendlyName = _ipNames[ip];

                          return Card(
                            margin: const EdgeInsets.all(8.0),
                            child: ExpansionTile(
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (friendlyName != null &&
                                            friendlyName.isNotEmpty)
                                          Text(
                                            friendlyName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        Text(
                                          ip,
                                          style: TextStyle(
                                            fontSize: friendlyName != null &&
                                                    friendlyName.isNotEmpty
                                                ? 14
                                                : 18,
                                            color: friendlyName != null &&
                                                    friendlyName.isNotEmpty
                                                ? Colors.grey
                                                : null,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 20),
                                    onPressed: () => _editIpName(ip),
                                    tooltip: 'Edit IP Name',
                                  ),
                                ],
                              ),
                              subtitle: Text('${hosts.length} ports'),
                              children: hosts
                                  .map((host) => ListTile(
                                        title: Text('Port ${host.forwardPort}'),
                                        subtitle: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                                'App: ${host.domainNames.first}'),
                                            Text(
                                              'Status: ${host.enabled ? "Enabled" : "Disabled"}',
                                              style: TextStyle(
                                                color: host.enabled
                                                    ? Colors.green
                                                    : Colors.red,
                                              ),
                                            ),
                                          ],
                                        ),
                                        trailing: Icon(
                                          host.enabled
                                              ? Icons.check_circle
                                              : Icons.cancel,
                                          color: host.enabled
                                              ? Colors.green
                                              : Colors.red,
                                        ),
                                      ))
                                  .toList(),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
