# Add Proxy Host Feature - Implementation Plan
**Version:** 1.0  
**Date:** October 12, 2025  
**App Version:** 1.0.3+10  
**Feature:** Create new NPM proxy hosts from mobile app

---

## Overview

Currently, the app only allows enabling/disabling existing proxy hosts. This feature adds the ability to create new proxy hosts directly from the mobile app, matching the functionality available in the NPM web interface.

---

## NPM API Analysis

### Endpoint
```
POST /api/nginx/proxy-hosts
```

### Required Authentication
- Bearer token (same token used for existing API calls)
- Already implemented in `ApiService`

### Request Payload Structure
```json
{
  "domain_names": ["example.com", "www.example.com"],
  "forward_scheme": "http",
  "forward_host": "192.168.1.100",
  "forward_port": 80,
  "access_list_id": 0,
  "certificate_id": 0,
  "ssl_forced": false,
  "caching_enabled": false,
  "block_exploits": true,
  "advanced_config": "",
  "meta": {
    "letsencrypt_agree": false,
    "dns_challenge": false,
    "letsencrypt_email": ""
  },
  "allow_websocket_upgrade": false,
  "http2_support": false,
  "hsts_enabled": false,
  "hsts_subdomains": false,
  "enabled": true
}
```

### Response
```json
{
  "id": 123,
  "created_on": "2025-10-12 15:30:00",
  "modified_on": "2025-10-12 15:30:00",
  "owner_user_id": 1,
  "domain_names": ["example.com"],
  "forward_scheme": "http",
  "forward_host": "192.168.1.100",
  "forward_port": 80,
  "access_list_id": 0,
  "certificate_id": 0,
  "ssl_forced": 0,
  "caching_enabled": 0,
  "block_exploits": 1,
  "advanced_config": "",
  "meta": {},
  "allow_websocket_upgrade": 0,
  "http2_support": 0,
  "hsts_enabled": 0,
  "hsts_subdomains": 0,
  "enabled": 1
}
```

---

## Current Codebase Analysis

### Existing Related Files
1. **`lib/models/proxy_host.dart`** - Data model for proxy hosts (read-only)
2. **`lib/services/api_service.dart`** - API client with `updateProxyHost()` method
3. **`lib/screens/dashboard_screen.dart`** - Lists hosts with edit functionality
4. **`lib/screens/proxy_host_edit_screen.dart`** - Edits existing hosts
5. **`lib/screens/ports_list_screen.dart`** - Groups hosts by IP/port

### Current ProxyHost Model
```dart
class ProxyHost {
  final int id;
  final List<String> domainNames;
  final String forwardScheme;
  final String forwardHost;
  final int forwardPort;
  final int? accessListId;
  final int? certificateId;
  final bool sslForced;
  final bool enabled;
}
```

**Note:** The model only includes basic fields. NPM API supports additional fields that aren't currently modeled.

### Existing API Method for Update
```dart
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
})
```

---

## Implementation Plan

### Phase 1: Extend Data Model (Optional)

**File:** `lib/models/proxy_host.dart`

**Decision:** Keep existing model minimal since the app doesn't currently use advanced NPM features.

**Reasoning:**
- Current model covers essential fields used in the app
- Advanced fields (caching, HSTS, HTTP/2) add complexity without immediate value
- Can extend later if needed

**Action:** No changes needed to model for basic functionality.

---

### Phase 2: Add API Method for Creating Hosts

**File:** `lib/services/api_service.dart`

**Add new method after `updateProxyHost()`:**

```dart
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

    final token = await _storage.read(key: 'auth_token');
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
```

**Why this structure:**
- Matches existing `updateProxyHost()` signature for consistency
- Includes sensible defaults (block_exploits: true, caching: false)
- Returns created `ProxyHost` object or null on failure
- Handles demo mode consistently
- Minimal API surface - only essential fields required

---

### Phase 3: Create Add Host Screen

**New File:** `lib/screens/proxy_host_add_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/proxy_host.dart';
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
            content: Text('Proxy host "${domainNames.first}" created successfully'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // Return true to indicate success
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to create proxy host. Please check your inputs.'),
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
                        hintText: 'example.com\nwww.example.com\n(one per line or comma-separated)',
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
```

**Key Features:**
- Clean, modern UI matching existing app design
- Form validation for all inputs
- Multiple domain names support (comma or newline separated)
- HTTP/HTTPS scheme selector
- Common options: SSL forced, block exploits, enabled
- Port validation (1-65535)
- Loading state during creation
- Success/error feedback
- Returns boolean to indicate success for parent screen refresh

---

### Phase 4: Add Navigation to Add Host Screen

**File:** `lib/screens/dashboard_screen.dart`

**Add import at top:**
```dart
import 'proxy_host_add_screen.dart';
```

**Add floating action button in the `build()` method:**

**Current:**
```dart
return Scaffold(
  backgroundColor: Colors.black,
  appBar: AppBar(
    // ... existing code
  ),
  body: _isLoading
      ? const Center(child: CircularProgressIndicator())
      : _proxyHosts.isEmpty
          ? const Center(child: Text('No proxy hosts found'))
          : ListView.builder(
              // ... existing code
            ),
);
```

**Change to:**
```dart
return Scaffold(
  backgroundColor: Colors.black,
  appBar: AppBar(
    // ... existing code
  ),
  body: _isLoading
      ? const Center(child: CircularProgressIndicator())
      : _proxyHosts.isEmpty
          ? const Center(child: Text('No proxy hosts found'))
          : ListView.builder(
              // ... existing code
            ),
  floatingActionButton: FloatingActionButton(
    onPressed: _addProxyHost,
    backgroundColor: Colors.blue,
    child: const Icon(Icons.add),
    tooltip: 'Add Proxy Host',
  ),
);
```

**Add method to handle navigation:**
```dart
Future<void> _addProxyHost() async {
  final result = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (context) => const ProxyHostAddScreen(),
    ),
  );

  if (result == true && mounted) {
    // Refresh the list if a host was added
    setState(() => _isLoading = true);
    _loadProxyHosts();
  }
}
```

---

### Phase 5: Add Navigation to Ports List Screen (Optional)

**File:** `lib/screens/ports_list_screen.dart`

**Same changes as dashboard:**

1. Add import
2. Add `floatingActionButton` to Scaffold
3. Add `_addProxyHost()` method
4. Refresh list on return

This provides consistent access to add functionality from both screens.

---

## Testing Plan

### Unit Tests (Manual)

1. **Valid Input Test**
   - Domain: `test.example.com`
   - Scheme: `http`
   - Host: `192.168.1.100`
   - Port: `8080`
   - Expected: Host created successfully

2. **Multiple Domains Test**
   - Domains: `app.example.com, www.example.com, example.com`
   - Expected: All domains added to single host

3. **HTTPS Forward Test**
   - Scheme: `https`
   - Port: `443`
   - Expected: Host forwards to HTTPS backend

4. **Port Validation Test**
   - Invalid ports: `0`, `65536`, `-1`, `abc`
   - Expected: Validation errors shown

5. **Empty Domain Test**
   - Domain: (empty)
   - Expected: Validation error

6. **SSL Forced Test**
   - Enable "Force SSL"
   - Expected: `ssl_forced: true` in API call

7. **Demo Mode Test**
   - Login with demo credentials
   - Create host
   - Expected: Fake host created, no API call

### Integration Tests

1. **End-to-End Host Creation**
   - Navigate from dashboard → Add screen
   - Fill form with valid data
   - Submit
   - Verify: New host appears in dashboard list
   - Verify: Host appears in ports list

2. **Creation Error Handling**
   - Create host with duplicate domain
   - Expected: Error message shown
   - Verify: Form remains filled
   - Verify: Can retry

3. **Network Error Test**
   - Disable network
   - Try to create host
   - Expected: Timeout error shown gracefully

### Platform Tests

- **Android:** Verify form inputs work correctly
- **iOS:** Verify form inputs work correctly
- **Both:** Verify loading states
- **Both:** Verify navigation back to dashboard refreshes list

---

## Error Scenarios

### Scenario 1: Duplicate Domain
**NPM Response:** `400 - Domain already exists`

**Handling:**
```dart
if (response.statusCode == 400) {
  // Show user-friendly error
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('This domain already exists. Please use a different domain.'),
      backgroundColor: Colors.orange,
    ),
  );
}
```

### Scenario 2: Invalid Forward Host
**NPM Response:** `400 - Invalid forward host`

**Handling:** Already handled by form validation + generic error message.

### Scenario 3: Auth Token Expired
**NPM Response:** `401 - Unauthorized`

**Handling:** Existing error handling in ApiService should handle this, but consider:
```dart
if (response.statusCode == 401) {
  // Token expired, need to re-login
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (context) => const LoginScreen()),
    (route) => false,
  );
}
```

### Scenario 4: Server Unreachable
**Dio Exception:** Connection timeout

**Handling:** Already handled by try-catch block with generic error message.

---

## UI/UX Considerations

### Design Consistency
- Match existing app theme (black background, grey cards)
- Use same color scheme (blue primary, grey accents)
- Consistent padding and margins with edit screen
- Same AppBar style with icon

### Form UX
- Auto-focus on first field
- Tab navigation between fields
- Keyboard type appropriate for each field (text vs numbers)
- Clear validation error messages
- Submit on keyboard "done" action (if feasible)

### Feedback
- Loading spinner while creating
- Success snackbar with host name
- Error snackbar with actionable message
- Haptic feedback on success (optional)

### Navigation
- Back button in AppBar (automatic)
- Save icon in AppBar (alternative to bottom button)
- Floating action button in dashboard (easy discovery)
- Return to dashboard on success (with refresh)

---

## Advanced Features (Future Enhancements)

These are NOT part of the initial implementation but could be added later:

### 1. SSL Certificate Management
- Let's Encrypt certificate request
- Certificate selection from existing certificates
- Certificate upload

### 2. Advanced Configuration
- Custom Nginx config text area
- Access list selection
- Caching options
- WebSocket support toggle
- HTTP/2 support toggle

### 3. Template System
- Save host configurations as templates
- Quick-create from template
- Share templates between instances

### 4. Validation Enhancements
- Check if domain is reachable before creating
- Verify forward host is accessible
- DNS lookup validation
- Port scan to verify service is running

### 5. Batch Operations
- Create multiple hosts at once
- Import from CSV/JSON
- Clone existing host configuration

---

## Files Modified Summary

### New Files (1)
1. `lib/screens/proxy_host_add_screen.dart` - New screen for adding hosts

### Modified Files (2)
1. `lib/services/api_service.dart` - Add `createProxyHost()` method
2. `lib/screens/dashboard_screen.dart` - Add FAB and navigation

### Optional Modified Files (1)
1. `lib/screens/ports_list_screen.dart` - Add FAB and navigation (for consistency)

**Total:** 1 new file, 2-3 modified files

---

## Implementation Timeline

### Phase 1: API Method (1 hour)
- Add `createProxyHost()` to ApiService
- Test with Postman/curl against real NPM instance
- Verify response parsing

### Phase 2: Add Screen UI (3 hours)
- Create ProxyHostAddScreen widget
- Implement form fields and validation
- Add styling to match app theme
- Implement save logic

### Phase 3: Navigation (30 minutes)
- Add FAB to dashboard
- Implement navigation and refresh logic
- Test end-to-end flow

### Phase 4: Testing (2 hours)
- Test all validation scenarios
- Test error handling
- Test on both Android and iOS
- Test demo mode

### Phase 5: Polish (1 hour)
- Fix any UI issues
- Improve error messages
- Add loading states
- Final testing

**Total Estimate:** 7.5 hours

---

## Rollout Strategy

### Beta Testing
1. Release to 5-10 beta testers
2. Have them create 2-3 hosts each
3. Verify hosts appear in NPM web interface
4. Gather feedback on UX

### Gradual Rollout
1. 10% of users (monitor for errors)
2. 50% of users (if no issues)
3. 100% of users

### Monitoring
- Track `createProxyHost()` API call success rate
- Monitor error logs for creation failures
- Track time spent on add screen (UX metric)
- Track form abandonment rate

---

## Success Criteria

✅ Users can create new proxy hosts from mobile app  
✅ All required fields properly validated  
✅ Created hosts immediately visible in dashboard  
✅ Error messages are clear and actionable  
✅ Loading states prevent duplicate submissions  
✅ Demo mode creates fake hosts without API calls  
✅ UI matches existing app design  
✅ Works on both Android and iOS  
✅ No crashes or data loss scenarios  
✅ Created hosts match web interface functionality  

---

## Known Limitations

### Current Implementation
1. **No SSL certificate management** - Users must use NPM web interface for Let's Encrypt
2. **No access list selection** - Always creates with no access list
3. **No advanced config** - No custom Nginx configuration support
4. **No caching options** - Always creates with caching disabled
5. **Basic validation only** - Doesn't check if domain/host is actually reachable

### Why These Limitations Are Acceptable
- Initial version focuses on core functionality (80% use case)
- Advanced features can be added based on user demand
- Web interface still available for complex configurations
- Keeps mobile UI simple and fast
- Reduces development time significantly

### When to Add Advanced Features
- If > 30% of users request SSL certificate management
- If users report needing access lists frequently
- If advanced config is commonly needed
- After initial version proves stable

---

## Appendix: API Request Example

### Minimal Request (What We Send)
```json
{
  "domain_names": ["example.com"],
  "forward_scheme": "http",
  "forward_host": "192.168.1.100",
  "forward_port": 80,
  "ssl_forced": false,
  "enabled": true,
  "access_list_id": 0,
  "certificate_id": 0,
  "block_exploits": true,
  "caching_enabled": false,
  "allow_websocket_upgrade": false,
  "http2_support": false,
  "advanced_config": "",
  "hsts_enabled": false,
  "hsts_subdomains": false,
  "meta": {
    "letsencrypt_agree": false,
    "dns_challenge": false,
    "letsencrypt_email": ""
  }
}
```

### Full Request (NPM Web Interface Sends)
```json
{
  "domain_names": ["example.com"],
  "forward_scheme": "http",
  "forward_host": "192.168.1.100",
  "forward_port": 80,
  "access_list_id": 0,
  "certificate_id": 0,
  "ssl_forced": 0,
  "caching_enabled": 0,
  "block_exploits": 1,
  "advanced_config": "",
  "meta": {
    "letsencrypt_agree": false,
    "dns_challenge": false,
    "letsencrypt_email": "",
    "nginx_online": true,
    "nginx_err": null
  },
  "allow_websocket_upgrade": 0,
  "http2_support": 0,
  "forward_port": 80,
  "locations": [],
  "hsts_enabled": 0,
  "hsts_subdomains": 0,
  "enabled": 1,
  "use_default_location": true
}
```

**Note:** We send a simplified version that NPM accepts. Optional fields are set to sensible defaults.

---

**End of Document**

