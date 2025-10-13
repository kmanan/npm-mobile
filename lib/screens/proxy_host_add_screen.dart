import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';

class ProxyHostAddScreen extends StatefulWidget {
  const ProxyHostAddScreen({super.key});

  @override
  State<ProxyHostAddScreen> createState() => _ProxyHostAddScreenState();
}

class _ProxyHostAddScreenState extends State<ProxyHostAddScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiService = ApiService();

  // Form controllers
  final _domainController = TextEditingController();
  final _forwardHostController = TextEditingController();
  final _forwardPortController = TextEditingController();

  // Form state
  String _forwardScheme = 'http';
  bool _sslForced = false;
  bool _blockExploits = true;
  bool _enabled = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _domainController.dispose();
    _forwardHostController.dispose();
    _forwardPortController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Parse domain names (comma-separated or one per line)
      final domainsText = _domainController.text.trim();
      final domainNames = domainsText
          .split(RegExp(r'[,\n]'))
          .map((d) => d.trim())
          .where((d) => d.isNotEmpty)
          .toList();

      if (domainNames.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please enter at least one domain name'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      final forwardPort = int.tryParse(_forwardPortController.text.trim());
      if (forwardPort == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid port number'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      final createdHost = await _apiService.createProxyHost(
        domainNames: domainNames,
        forwardScheme: _forwardScheme,
        forwardHost: _forwardHostController.text.trim(),
        forwardPort: forwardPort,
        sslForced: _sslForced,
        enabled: _enabled,
        blockExploits: _blockExploits,
      );

      if (!mounted) return;

      if (createdHost != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Proxy host "${domainNames.first}" created successfully'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // Return true to indicate success
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Failed to create proxy host. Please check your inputs.'),
            duration: Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Add Proxy Host'),
        actions: [
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _handleSave,
              tooltip: 'Save',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Domain Names
                    Text(
                      'Domain Names',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _domainController,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText:
                            'example.com\nwww.example.com\n(one per line or comma-separated)',
                        hintStyle: const TextStyle(color: Colors.grey),
                        filled: true,
                        fillColor: Colors.grey[900],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter at least one domain name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // Forward Scheme
                    Text(
                      'Forward Scheme',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      selected: {_forwardScheme},
                      onSelectionChanged: (Set<String> newSelection) {
                        setState(() => _forwardScheme = newSelection.first);
                      },
                      segments: const [
                        ButtonSegment(
                          value: 'http',
                          label: Text('HTTP'),
                          icon: Icon(Icons.http),
                        ),
                        ButtonSegment(
                          value: 'https',
                          label: Text('HTTPS'),
                          icon: Icon(Icons.https),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Forward Host
                    Text(
                      'Forward Hostname / IP',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _forwardHostController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: '192.168.1.100 or hostname',
                        hintStyle: const TextStyle(color: Colors.grey),
                        filled: true,
                        fillColor: Colors.grey[900],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a hostname or IP address';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // Forward Port
                    Text(
                      'Forward Port',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _forwardPortController,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        hintText: '80, 443, 8080, etc.',
                        hintStyle: const TextStyle(color: Colors.grey),
                        filled: true,
                        fillColor: Colors.grey[900],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a port number';
                        }
                        final port = int.tryParse(value.trim());
                        if (port == null || port < 1 || port > 65535) {
                          return 'Port must be between 1 and 65535';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // Options
                    Text(
                      'Options',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      color: Colors.grey[900],
                      child: Column(
                        children: [
                          SwitchListTile(
                            title: const Text(
                              'Force SSL',
                              style: TextStyle(color: Colors.white),
                            ),
                            subtitle: const Text(
                              'Redirect HTTP to HTTPS',
                              style: TextStyle(color: Colors.grey),
                            ),
                            value: _sslForced,
                            onChanged: (value) {
                              setState(() => _sslForced = value);
                            },
                          ),
                          const Divider(height: 1),
                          SwitchListTile(
                            title: const Text(
                              'Block Exploits',
                              style: TextStyle(color: Colors.white),
                            ),
                            subtitle: const Text(
                              'Block common exploit attempts',
                              style: TextStyle(color: Colors.grey),
                            ),
                            value: _blockExploits,
                            onChanged: (value) {
                              setState(() => _blockExploits = value);
                            },
                          ),
                          const Divider(height: 1),
                          SwitchListTile(
                            title: const Text(
                              'Enabled',
                              style: TextStyle(color: Colors.white),
                            ),
                            subtitle: const Text(
                              'Activate this proxy host immediately',
                              style: TextStyle(color: Colors.grey),
                            ),
                            value: _enabled,
                            onChanged: (value) {
                              setState(() => _enabled = value);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _handleSave,
                        icon: const Icon(Icons.add),
                        label: const Text('Create Proxy Host'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
