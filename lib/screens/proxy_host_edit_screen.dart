import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/proxy_host.dart';
import '../services/api_service.dart';

class ProxyHostEditScreen extends StatefulWidget {
  final ProxyHost proxyHost;

  const ProxyHostEditScreen({
    super.key,
    required this.proxyHost,
  });

  @override
  State<ProxyHostEditScreen> createState() => _ProxyHostEditScreenState();
}

class _ProxyHostEditScreenState extends State<ProxyHostEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiService = ApiService();
  bool _isLoading = false;
  late TextEditingController _domainController;
  late TextEditingController _forwardHostController;
  late TextEditingController _forwardPortController;
  late String _forwardScheme;
  late bool _sslForced;

  @override
  void initState() {
    super.initState();
    _domainController =
        TextEditingController(text: widget.proxyHost.domainNames.first);
    _forwardHostController =
        TextEditingController(text: widget.proxyHost.forwardHost);
    _forwardPortController =
        TextEditingController(text: widget.proxyHost.forwardPort.toString());
    _forwardScheme = widget.proxyHost.forwardScheme;
    _sslForced = widget.proxyHost.sslForced;
  }

  @override
  void dispose() {
    _domainController.dispose();
    _forwardHostController.dispose();
    _forwardPortController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final success = await _apiService.updateProxyHost(
        id: widget.proxyHost.id,
        domainNames: [_domainController.text.trim()],
        forwardScheme: _forwardScheme,
        forwardHost: _forwardHostController.text.trim(),
        forwardPort: int.parse(_forwardPortController.text.trim()),
        sslForced: _sslForced,
        certificateId: widget.proxyHost.certificateId,
        accessListId: widget.proxyHost.accessListId,
        enabled: widget.proxyHost.enabled,
      );

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Proxy host updated successfully')),
        );
        Navigator.pop(context, true); // Return true to indicate success
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update proxy host')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('An error occurred while updating')),
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
        title: const Text('Edit Proxy Host'),
        actions: [
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveChanges,
              tooltip: 'Save Changes',
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            TextFormField(
              controller: _domainController,
              decoration: const InputDecoration(
                labelText: 'Domain Name',
                border: OutlineInputBorder(),
                helperText: 'e.g., example.com',
              ),
              enabled: !_isLoading,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a domain name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _forwardScheme,
              decoration: const InputDecoration(
                labelText: 'Forward Scheme',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'http', child: Text('HTTP')),
                DropdownMenuItem(value: 'https', child: Text('HTTPS')),
              ],
              onChanged: _isLoading
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _forwardScheme = value);
                      }
                    },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _forwardHostController,
              decoration: const InputDecoration(
                labelText: 'Forward Host',
                border: OutlineInputBorder(),
                helperText: 'IP address or hostname',
              ),
              enabled: !_isLoading,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a forward host';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _forwardPortController,
              decoration: const InputDecoration(
                labelText: 'Forward Port',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              enabled: !_isLoading,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a port number';
                }
                final port = int.tryParse(value);
                if (port == null || port < 1 || port > 65535) {
                  return 'Please enter a valid port number (1-65535)';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Force SSL'),
              subtitle: const Text('Redirect HTTP to HTTPS'),
              value: _sslForced,
              onChanged: _isLoading
                  ? null
                  : (value) {
                      setState(() => _sslForced = value);
                    },
            ),
          ],
        ),
      ),
    );
  }
}
