# Multi-Instance NPM Support - Implementation Plan

**Version:** 1.0  
**Date:** October 12, 2025  
**App Version:** 1.0.3+10  
**Flutter SDK:** >=3.2.3 <4.0.0  

---

## Executive Summary

This document provides a complete implementation plan for adding multi-instance support to the Nginx Mobile Dashboard app, allowing users to manage multiple Nginx Proxy Manager (NPM) instances while preserving the existing biometric authentication feature. This plan ensures no existing functionality is broken and maintains full backward compatibility for existing users.

---

## Current Architecture Analysis

### Authentication Flow
1. User enters credentials on `LoginScreen`
2. `AuthService.saveCredentials()` stores to `FlutterSecureStorage` with flat keys
3. `ApiService.login()` authenticates and stores auth token
4. Biometric auth auto-fills credentials on subsequent launches
5. `ApiService` maintains single server URL context

### Storage Keys (Current)
```
- server_url (used by both AuthService and ApiService)
- email
- encrypted_password
- encryption_key (AES-256)
- encryption_iv (unique per save)
- biometric_enabled (boolean string)
- auth_token (session token)
```

### Critical Dependencies
- **flutter_secure_storage: 9.2.3** - Stores credentials securely
- **local_auth: 2.3.0** - Biometric authentication
- **encrypt: 5.0.3** - AES password encryption
- **dio: 5.7.0** - HTTP client with base URL management

---

## Design Decisions

### 1. Storage Architecture
**Decision:** Use instance-based namespaced keys with UUID identifiers

**Rationale:**
- Maintains existing security (per-instance encryption)
- No storage limits on iOS Keychain or Android EncryptedSharedPreferences
- Easy to add/remove instances
- Backward compatible via migration

**Structure:**
```
Global Keys:
- active_instance_id: "uuid-string"
- instance_list: "uuid1,uuid2,uuid3" (comma-separated)

Per Instance Keys:
- instance_{uuid}_name: "Production Server"
- instance_{uuid}_server_url: "https://npm.example.com:81"
- instance_{uuid}_email: "user@example.com"
- instance_{uuid}_encrypted_password: "base64-encrypted"
- instance_{uuid}_encryption_iv: "base64-iv"
- instance_{uuid}_biometric_enabled: "true"
- instance_{uuid}_auth_token: "bearer-token"
```

### 2. Biometric Authentication Scope
**Decision:** Biometric auth applies per-instance, auto-authenticates active instance

**Rationale:**
- Maintains current UX for single-instance users
- Each instance can have biometric independently enabled/disabled
- User selects instance, then biometric unlocks that instance's credentials
- No ambiguity about which instance is being accessed

### 3. Instance Switching
**Decision:** Require re-authentication when switching instances

**Rationale:**
- Security: Each instance is a separate server with separate credentials
- Clear session boundary - prevents accidental operations on wrong instance
- Auth token is server-specific, must be refreshed per instance

### 4. Migration Strategy
**Decision:** Seamless automatic migration on first launch after upgrade

**Rationale:**
- Zero user friction for existing users
- Preserves all saved credentials and biometric settings
- Creates first instance from legacy keys, then removes them

---

## Feature Requirements

### FR-1: Instance Management
- Add new NPM instance with credentials
- Edit instance name and credentials
- Delete instance (with confirmation)
- View list of all configured instances
- Maximum 50 instances (reasonable limit)

### FR-2: Instance Selection
- Select active instance from login screen
- Show active instance name in app bar
- Quick switch between instances (requires re-login)
- Remember last active instance

### FR-3: Biometric Authentication
- Enable/disable biometric auth per instance
- Auto-authenticate active instance on app launch (if enabled)
- Show which instance biometric is enabled for
- Preserve all existing biometric functionality

### FR-4: Backward Compatibility
- Automatic migration of existing single-instance users
- No data loss during migration
- Existing biometric settings preserved
- App functions identically for users with one instance

### FR-5: User Experience
- Clear visual indication of active instance
- Prevent accidental deletion of active instance
- Show instance count on login screen
- Confirmation dialogs for destructive actions

---

## Files to Modify

### 1. `lib/services/auth_service.dart`
**Changes Required:** Major refactoring  
**Reason:** Core credential storage logic

**New Methods:**
```dart
// Instance Management
Future<String> createInstance({required String name, required String serverUrl, required String email, required String password, required bool enableBiometric})
Future<void> updateInstance({required String instanceId, String? name, String? serverUrl, String? email, String? password, bool? enableBiometric})
Future<void> deleteInstance(String instanceId)
Future<List<NpmInstance>> getAllInstances()
Future<NpmInstance?> getInstance(String instanceId)

// Active Instance Management
Future<void> setActiveInstance(String instanceId)
Future<String?> getActiveInstanceId()
Future<NpmInstance?> getActiveInstance()

// Instance-Specific Auth
Future<Map<String, String?>> getInstanceCredentials(String instanceId)
Future<bool> isInstanceBiometricEnabled(String instanceId)

// Migration
Future<void> migrateFromLegacyStorage()
Future<bool> needsMigration()
```

**Modified Methods:**
- `saveCredentials()` - Update to use instance-based keys
- `getSavedCredentials()` - Get from active instance
- `isBiometricEnabled()` - Check active instance
- `clearCredentials()` - Clear active instance only
- `handleLogout()` - Clear active instance auth token

**Removed Methods:**
- None (maintain backward compatibility internally)

---

### 2. `lib/services/api_service.dart`
**Changes Required:** Moderate refactoring  
**Reason:** Handle per-instance base URLs and auth tokens

**New Methods:**
```dart
Future<void> switchInstance(String instanceId)
Future<String?> getActiveInstanceId()
Future<void> saveInstanceAuthToken(String instanceId, String token)
Future<String?> getInstanceAuthToken(String instanceId)
Future<void> clearInstanceAuthToken(String instanceId)
```

**Modified Methods:**
- `login()` - Accept instanceId parameter, save token per instance
- `_loadSavedUrl()` - Load from active instance
- `saveServerUrl()` - Save to active instance
- `getSavedServerUrl()` - Get from active instance
- `getProxyHosts()` - Use active instance auth token
- `toggleProxyHost()` - Use active instance auth token
- `updateProxyHost()` - Use active instance auth token

**Key Changes:**
- Store auth tokens per instance: `instance_{uuid}_auth_token`
- Update `_dio.options.baseUrl` when switching instances
- Maintain demo mode functionality

---

### 3. `lib/screens/login_screen.dart`
**Changes Required:** Significant UI/UX changes  
**Reason:** Add instance selector and management

**New UI Components:**
```dart
// Instance selector dropdown (above server URL field)
Widget _buildInstanceSelector()

// Instance management buttons
Widget _buildInstanceManagementBar()
Widget _buildAddInstanceButton()
Widget _buildEditInstanceButton()
Widget _buildDeleteInstanceButton()
```

**Modified UI Components:**
- `_buildBiometricButton()` - Show instance name in tooltip
- Server URL field - Auto-populate from selected instance
- Email field - Auto-populate from selected instance
- Remember Me checkbox - Per instance

**New State Variables:**
```dart
String? _selectedInstanceId;
List<NpmInstance> _instances = [];
bool _showInstanceManagement = false;
```

**New Methods:**
```dart
Future<void> _loadInstances()
Future<void> _selectInstance(String instanceId)
Future<void> _showAddInstanceDialog()
Future<void> _showEditInstanceDialog(NpmInstance instance)
Future<void> _showDeleteInstanceDialog(NpmInstance instance)
Future<void> _handleInstanceLogin()
```

**Modified Methods:**
- `initState()` - Load instances, check migration
- `_checkBiometrics()` - Check active instance biometric setting
- `_tryBiometricAuth()` - Use active instance credentials
- `_handleLogin()` - Save to selected instance
- `_showBiometricPrompt()` - Save to active instance

---

### 4. `lib/screens/dashboard_screen.dart`
**Changes Required:** Minor UI changes  
**Reason:** Show active instance name

**Modified UI Components:**
- AppBar title - Show instance name with server name
- Add instance switcher menu item

**New Methods:**
```dart
Future<void> _showInstanceSwitcher()
String _getInstanceDisplayName()
```

**Modified Methods:**
- `build()` - Update AppBar title
- `_handleLogout()` - Clear active instance session only

---

### 5. `lib/screens/main_screen.dart`
**Changes Required:** Minimal  
**Reason:** Pass instance context to child screens if needed

**Potential Changes:**
- Add instance info to state (if needed for consistent display)

---

### 6. `lib/models/npm_instance.dart`
**Changes Required:** New file  
**Reason:** Data model for NPM instances

**Content:**
```dart
class NpmInstance {
  final String id;
  final String name;
  final String serverUrl;
  final String email;
  final bool biometricEnabled;
  final DateTime createdAt;
  final DateTime lastUsed;

  NpmInstance({
    required this.id,
    required this.name,
    required this.serverUrl,
    required this.email,
    required this.biometricEnabled,
    required this.createdAt,
    required this.lastUsed,
  });

  Map<String, dynamic> toJson();
  factory NpmInstance.fromJson(Map<String, dynamic> json);
  NpmInstance copyWith({...});
}
```

---

### 7. `lib/services/instance_service.dart`
**Changes Required:** New file  
**Reason:** Centralized instance management logic

**Purpose:**
- Validate instance data
- Generate UUIDs
- Handle instance list operations
- Coordinate between AuthService and ApiService

**Key Methods:**
```dart
String generateInstanceId()
Future<void> validateInstanceData(String name, String serverUrl, String email)
Future<List<NpmInstance>> getInstanceList()
Future<void> addToInstanceList(String instanceId)
Future<void> removeFromInstanceList(String instanceId)
```

---

### 8. `lib/screens/instance_management_screen.dart`
**Changes Required:** New file  
**Reason:** Dedicated screen for instance management

**Purpose:**
- Full-screen instance management interface
- Add/edit/delete instances
- Reorder instances (optional)
- Export/import instance configs (future enhancement)

---

## Implementation Phases

### Phase 1: Foundation (Days 1-2)
**Goal:** Set up data models and storage infrastructure

**Tasks:**
1. Create `lib/models/npm_instance.dart`
2. Create `lib/services/instance_service.dart`
3. Add UUID generation (use `uuid` package or implement simple generator)
4. Write unit tests for instance model
5. Implement basic instance list storage (no encryption yet)

**Acceptance Criteria:**
- NpmInstance model complete with JSON serialization
- Can store/retrieve instance list
- UUID generation working

---

### Phase 2: Auth Service Refactoring (Days 3-5)
**Goal:** Implement instance-based credential storage

**Tasks:**
1. Add new instance-based storage methods to `AuthService`
2. Implement migration logic from legacy storage
3. Update existing methods to use active instance
4. Add comprehensive logging for migration
5. Test migration with various legacy states

**Acceptance Criteria:**
- All new AuthService methods implemented
- Migration preserves credentials and biometric settings
- Legacy keys cleaned up after migration
- Existing biometric flow works with active instance

**Testing Scenarios:**
- Fresh install (no migration needed)
- Existing user with biometric enabled
- Existing user without biometric
- Existing user with saved credentials
- Existing user without saved credentials

---

### Phase 3: API Service Updates (Days 6-7)
**Goal:** Handle per-instance API contexts

**Tasks:**
1. Add instance-aware auth token storage
2. Update login flow to accept instanceId
3. Implement instance switching logic
4. Update all API methods to use active instance token
5. Ensure demo mode still works

**Acceptance Criteria:**
- Auth tokens stored per instance
- Base URL updates when switching instances
- All API calls use correct instance context
- Demo mode unaffected

---

### Phase 4: Login Screen UI (Days 8-11)
**Goal:** Add instance selection and management UI

**Tasks:**
1. Design instance selector UI (dropdown or list)
2. Implement add instance flow
3. Implement edit instance flow
4. Implement delete instance flow
5. Update biometric flow for selected instance
6. Add instance count badge
7. Polish UI/UX

**Acceptance Criteria:**
- Can add new instances from login screen
- Can select instance before login
- Biometric works with selected instance
- Delete requires confirmation
- UI is intuitive and clean

**Design Considerations:**
- Show instance count: "3 Instances"
- Active instance highlighted
- Quick add button accessible
- Edit/delete via long-press or swipe

---

### Phase 5: Dashboard Updates (Days 12-13)
**Goal:** Show active instance context in app

**Tasks:**
1. Update AppBar to show instance name
2. Add instance switcher to menu
3. Implement switch instance flow (with logout)
4. Update logout to be instance-aware

**Acceptance Criteria:**
- Active instance name visible in AppBar
- Can switch instances from dashboard
- Switching requires re-authentication
- Logout only clears active instance session

---

### Phase 6: Testing & Polish (Days 14-16)
**Goal:** Comprehensive testing and bug fixes

**Tasks:**
1. Test all flows with 1 instance (backward compatibility)
2. Test all flows with 5+ instances
3. Test migration scenarios
4. Test biometric on both iOS and Android
5. Test instance switching
6. Test delete active instance scenario
7. Fix any bugs found
8. Performance testing
9. UI polish

**Test Cases:**
- Legacy migration preserves data
- Single instance user experience unchanged
- Multi-instance switching works
- Biometric per instance works
- Delete non-active instance
- Delete active instance (should prevent or handle gracefully)
- Rapid instance switching
- Network errors during instance operations
- Storage corruption scenarios

---

### Phase 7: Documentation (Day 17)
**Goal:** Update user-facing and developer documentation

**Tasks:**
1. Update README.md with multi-instance feature
2. Update privacy.md if needed
3. Add inline code documentation
4. Create user guide screenshots
5. Update CHANGELOG

---

## Data Migration Strategy

### Detection
```dart
Future<bool> needsMigration() async {
  final hasLegacyUrl = await _storage.read(key: 'server_url') != null;
  final hasInstanceList = await _storage.read(key: 'instance_list') != null;
  return hasLegacyUrl && !hasInstanceList;
}
```

### Migration Steps
1. Check for legacy `server_url` key
2. If exists and no `instance_list`:
   - Generate new UUID for first instance
   - Read all legacy keys (server_url, email, encrypted_password, etc.)
   - Create instance with name "Default Instance" or server URL
   - Write instance-based keys with legacy data
   - Set as active instance
   - Delete legacy keys
   - Log migration success
3. If migration fails:
   - Log error with details
   - Do NOT delete legacy keys
   - Show user error message with support contact

### Migration Logging
```dart
await _logService.logMigrationEvent(
  event: 'MIGRATION_START',
  details: 'Starting migration from legacy storage',
);

// ... migration steps ...

await _logService.logMigrationEvent(
  event: 'MIGRATION_SUCCESS',
  details: 'Migration completed successfully',
  additionalInfo: {
    'instanceId': newInstanceId,
    'biometricPreserved': biometricEnabled,
  },
);
```

---

## Edge Cases & Error Handling

### EC-1: Delete Active Instance
**Scenario:** User tries to delete the currently active instance

**Solution:**
- Show warning: "This is your active instance. Deleting it will log you out."
- On confirm: Clear session, delete instance, redirect to login
- If other instances exist: Auto-select first remaining instance
- If no other instances: Full logout, clean state

### EC-2: Active Instance ID Invalid
**Scenario:** Stored active_instance_id doesn't match any instance

**Solution:**
- Log error with details
- Clear active_instance_id
- If instances exist: Prompt user to select one
- If no instances: Treat as fresh install

### EC-3: Migration Failure
**Scenario:** Migration encounters error mid-process

**Solution:**
- Transaction-like approach: All or nothing
- Don't delete legacy keys until migration verified
- On error: Show user-friendly message
- Provide fallback: Manual login without migration

### EC-4: Storage Corruption
**Scenario:** Instance data is corrupted or incomplete

**Solution:**
- Validate all required fields when loading instance
- Skip corrupted instances with error log
- Show user: "Some instances could not be loaded"
- Provide option to reset instance storage

### EC-5: Instance Limit Reached
**Scenario:** User tries to add 51st instance

**Solution:**
- Show error: "Maximum 50 instances allowed"
- Suggest deleting unused instances
- Provide management screen link

### EC-6: Biometric After Instance Switch
**Scenario:** User switches instance with biometric enabled

**Solution:**
- Always require biometric for new instance if enabled
- Don't auto-switch without user action
- Clear indication which instance is being accessed

### EC-7: Network Error During Instance Add
**Scenario:** Adding instance but can't reach server

**Solution:**
- Don't save instance until login succeeds
- Show error: "Could not connect to server. Please verify URL."
- Keep dialog open with data preserved
- Allow retry or cancel

### EC-8: Duplicate Instance
**Scenario:** User tries to add instance with same server URL

**Solution:**
- Warn but allow: "An instance with this URL already exists"
- Instances are independent (different credentials allowed)
- Suggest reviewing existing instances

---

## Security Considerations

### SC-1: Encryption Key Isolation
**Current:** Single encryption key for all passwords  
**Risk:** If key compromised, all passwords exposed  
**Mitigation:** Continue using single key (acceptable for device-local storage)  
**Future Enhancement:** Per-instance encryption keys

### SC-2: Biometric Bypass
**Risk:** Biometric might unlock wrong instance  
**Mitigation:** Always verify instance ID before credential retrieval  
**Implementation:** Check active_instance_id before getSavedCredentials()

### SC-3: Instance Enumeration
**Risk:** Malicious app could enumerate instances  
**Mitigation:** FlutterSecureStorage provides OS-level protection  
**Note:** iOS Keychain and Android EncryptedSharedPreferences are sandboxed

### SC-4: Auth Token Leakage
**Risk:** Switching instances might leave token in memory  
**Mitigation:** Explicitly clear Dio headers on instance switch  
**Implementation:** 
```dart
_dio.options.headers.remove('Authorization');
await clearInstanceAuthToken(oldInstanceId);
```

### SC-5: Migration Data Loss
**Risk:** Failed migration could lose credentials  
**Mitigation:** Never delete legacy keys until migration verified  
**Implementation:** Verify new instance data readable before cleanup

---

## UI/UX Flow Diagrams

### Login Flow (New User - No Instances)
```
1. App Launch
2. Login Screen
3. Show "No instances configured"
4. Show "Add Instance" button
5. User taps Add Instance
6. Show instance form (name, server URL, email, password)
7. User submits
8. Validate and login
9. Success: Save instance, set active, navigate to dashboard
10. Prompt for biometric setup
```

### Login Flow (Existing User - Single Instance)
```
1. App Launch
2. Check migration needed
3. If yes: Migrate legacy data
4. Login Screen
5. Instance auto-selected (only one)
6. Auto-populate server URL and email
7. If biometric enabled: Auto-trigger biometric
8. Success: Navigate to dashboard
```

### Login Flow (Multi-Instance User)
```
1. App Launch
2. Login Screen
3. Show instance selector with active instance selected
4. Show instance count badge: "3 Instances"
5. Auto-populate server URL and email from selected instance
6. If biometric enabled for selected: Show biometric button
7. User can:
   - Proceed with selected instance
   - Switch to different instance (dropdown)
   - Add new instance
   - Manage instances (edit/delete)
8. Login with credentials or biometric
9. Success: Navigate to dashboard
```

### Instance Switching Flow
```
1. User in Dashboard
2. Taps instance name in AppBar (or menu)
3. Show instance switcher modal
4. List all instances with active highlighted
5. User selects different instance
6. Show confirmation: "Switch to [Instance Name]? This will log you out."
7. User confirms
8. Clear active instance session
9. Set new active instance
10. Navigate to Login Screen
11. Auto-populate credentials if saved
12. If biometric enabled: Offer biometric login
```

### Add Instance Flow
```
1. From Login Screen, tap "Add Instance"
2. Show dialog/sheet:
   - Instance Name (default: server URL)
   - Server URL
   - Email
   - Password
   - Enable Biometric toggle
3. Validate inputs
4. Attempt login
5. If success:
   - Generate UUID
   - Save instance data
   - Add to instance list
   - Set as active instance
   - Navigate to dashboard
6. If fail:
   - Show error
   - Keep dialog open
   - Allow retry
```

### Delete Instance Flow
```
1. User long-presses instance in list
2. Show options: Edit | Delete
3. User taps Delete
4. If active instance:
   - Show warning: "This will log you out"
5. Show confirmation: "Delete [Instance Name]?"
6. User confirms
7. Delete instance data:
   - All instance_{uuid}_* keys
   - Remove from instance_list
8. If was active:
   - Clear active_instance_id
   - If other instances exist: Set first as active
   - If no instances: Full logout
9. If on dashboard: Navigate to login
10. Refresh instance list
```

---

## Testing Checklist

### Unit Tests
- [ ] NpmInstance model serialization/deserialization
- [ ] InstanceService UUID generation
- [ ] InstanceService validation logic
- [ ] AuthService instance CRUD operations
- [ ] AuthService migration logic
- [ ] ApiService instance-aware token management

### Integration Tests
- [ ] Full login flow with instance selection
- [ ] Instance switching with session management
- [ ] Biometric authentication with multiple instances
- [ ] Migration from legacy to multi-instance

### UI Tests
- [ ] Instance selector displays correctly
- [ ] Add instance dialog validation
- [ ] Edit instance updates properly
- [ ] Delete instance confirmation works
- [ ] Instance switcher from dashboard

### Platform Tests (iOS)
- [ ] Biometric (Face ID/Touch ID) works per instance
- [ ] Keychain storage handles multiple instances
- [ ] Instance switching doesn't leak data
- [ ] App backgrounding preserves instance context

### Platform Tests (Android)
- [ ] Biometric (Fingerprint/Face) works per instance
- [ ] EncryptedSharedPreferences handles multiple instances
- [ ] Instance switching doesn't leak data
- [ ] App backgrounding preserves instance context

### Edge Case Tests
- [ ] Delete active instance
- [ ] Invalid active instance ID
- [ ] Migration with corrupted data
- [ ] Add instance during network failure
- [ ] Rapid instance switching
- [ ] Storage at capacity
- [ ] Biometric disabled during instance switch

### Regression Tests
- [ ] Single instance user experience unchanged
- [ ] Existing biometric flow works
- [ ] Demo mode still functions
- [ ] All existing API calls work
- [ ] Logout flow correct
- [ ] Settings persistence

---

## Performance Considerations

### Storage Operations
- **Current:** 6 storage operations per credential save
- **New:** 6+ storage operations per instance save
- **Impact:** Negligible (FlutterSecureStorage is fast)
- **Optimization:** Batch writes with Future.wait() (already implemented)

### Instance List Loading
- **Scenario:** Loading 50 instances on login screen
- **Operations:** 1 read for instance_list + 50 reads for instance details
- **Impact:** ~50-100ms on modern devices
- **Optimization:** Cache instance list in memory after first load

### Instance Switching
- **Operations:** Clear old token, set active ID, load new instance, update Dio
- **Impact:** ~20-50ms
- **User Perception:** Instant (happens during navigation)

### Memory Usage
- **Current:** Minimal (credentials loaded on-demand)
- **New:** Instance list cached in memory (~1-5KB for 50 instances)
- **Impact:** Negligible

---

## Rollback Plan

### If Critical Issues Found After Release

**Scenario 1: Migration Breaks Existing Users**
- Release hotfix with migration disabled
- Revert to legacy storage temporarily
- Fix migration logic
- Re-enable in next release

**Scenario 2: Multi-Instance Causes Data Loss**
- Add instance data backup/export feature
- Provide recovery tool
- Fix data loss bug
- Release with data recovery guide

**Scenario 3: Biometric Stops Working**
- Identify affected instances
- Provide manual credential entry
- Fix biometric integration
- Test thoroughly before release

**Mitigation:**
- Comprehensive beta testing with opt-in users
- Staged rollout (10% → 50% → 100%)
- Detailed logging for diagnostics
- Keep legacy code path for emergency fallback

---

## Version Compatibility

### App Version Updates
- **Current:** 1.0.3+10
- **With Feature:** 1.1.0+11 (minor version bump for new feature)

### Minimum SDK Versions
- **iOS:** 12.0+ (unchanged, local_auth requirement)
- **Android:** API 21+ (Android 5.0+, unchanged, min_sdk_android setting)

### Package Compatibility
All existing packages support multi-instance:
- flutter_secure_storage: 9.2.3 ✓
- local_auth: 2.3.0 ✓
- encrypt: 5.0.3 ✓
- dio: 5.7.0 ✓

No package upgrades required.

---

## Success Metrics

### Functionality
- [ ] Users can add multiple NPM instances
- [ ] Users can switch between instances
- [ ] Biometric works per instance
- [ ] Migration completes for 100% of existing users
- [ ] Zero data loss during migration

### Performance
- [ ] Login screen loads in <500ms with 10 instances
- [ ] Instance switching completes in <100ms
- [ ] No memory leaks with repeated switching

### Stability
- [ ] Zero crashes related to multi-instance feature
- [ ] <0.1% storage corruption rate
- [ ] 99.9% successful migrations

### User Experience
- [ ] Single-instance users see no change in UX
- [ ] Multi-instance users can manage instances easily
- [ ] Instance context always clear in UI
- [ ] No accidental operations on wrong instance

---

## Code Review Checklist

### Before Merging
- [ ] All new methods have documentation comments
- [ ] Error handling for all storage operations
- [ ] Logging for all critical operations
- [ ] Input validation for all user-provided data
- [ ] Confirmation dialogs for destructive actions
- [ ] No hardcoded strings (use localization if added)
- [ ] Consistent naming conventions
- [ ] No code duplication
- [ ] All TODOs resolved or ticketed
- [ ] Migration logic thoroughly tested
- [ ] Backward compatibility verified
- [ ] Security review passed
- [ ] Performance profiling done
- [ ] UI reviewed on multiple screen sizes
- [ ] Accessibility considered (screen readers, etc.)

---

## Post-Implementation Tasks

### After Merging to Main
1. Update CHANGELOG.md with feature details
2. Create release notes for v1.1.0
3. Update screenshots in app stores
4. Update app descriptions to mention multi-instance support
5. Create user guide/tutorial for multi-instance feature
6. Monitor crash reports for 2 weeks post-release
7. Gather user feedback on new feature
8. Plan enhancements based on feedback

### Future Enhancements (Post v1.1.0)
- Export/import instance configurations
- Instance groups/folders
- Instance-specific settings (theme, notifications)
- Sync instances across devices (cloud backup)
- Quick instance switcher widget
- Instance usage statistics
- Shared instances (team/family sharing)

---

## Developer Notes

### Key Implementation Details

**UUID Generation:**
```dart
// Use timestamp + random for unique IDs
String generateInstanceId() {
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final random = Random().nextInt(999999);
  return 'npm_${timestamp}_$random';
}
```

**Migration Timing:**
- Execute on first app launch after upgrade
- Execute synchronously before showing login screen
- Show loading indicator during migration
- Log all migration events

**Instance List Format:**
- Store as comma-separated UUID string
- Parse into List<String> when needed
- Maintain insertion order
- Limit to 50 entries

**Active Instance Logic:**
- Always validate active_instance_id exists in instance_list
- Default to first instance if validation fails
- Update lastUsed timestamp on instance activation
- Clear active_instance_id on full logout

**Biometric Per Instance:**
- Check instance_{uuid}_biometric_enabled, not global flag
- Prompt per instance after first login
- Allow toggle in instance edit screen
- Show biometric badge on instances with it enabled

**Error Messages:**
- User-friendly, actionable messages
- Specific to context (e.g., "Could not connect to Production Server")
- Suggest next steps (e.g., "Please check the server URL and try again")
- Include instance name when relevant

---

## Risks & Mitigation

### Risk 1: Complex Migration
**Impact:** High (could break existing users)  
**Probability:** Medium  
**Mitigation:** 
- Extensive testing with various legacy states
- Don't delete legacy data until verified
- Detailed logging
- Staged rollout

### Risk 2: User Confusion
**Impact:** Medium (users might not understand multi-instance)  
**Probability:** Medium  
**Mitigation:**
- Keep UI simple and intuitive
- Use clear labels ("Server", "Instance")
- Provide onboarding for new feature
- Single-instance users see minimal changes

### Risk 3: Storage Limits
**Impact:** Low (rare edge case)  
**Probability:** Very Low  
**Mitigation:**
- Enforce 50 instance limit
- Show storage usage if approaching limits
- Provide cleanup tools

### Risk 4: Performance Degradation
**Impact:** Low (app might slow down)  
**Probability:** Very Low  
**Mitigation:**
- Cache instance list in memory
- Lazy load instance details
- Profile with 50 instances
- Optimize if needed

### Risk 5: Biometric Issues
**Impact:** High (critical feature)  
**Probability:** Low  
**Mitigation:**
- Thorough testing on real devices
- Fallback to password always available
- Clear error messages
- Beta test extensively

---

## Communication Plan

### Internal Team
- Daily standups during implementation
- Code reviews for each phase
- Demo after Phase 4 (UI complete)
- QA handoff after Phase 6

### Beta Testers
- Recruit 20-30 beta testers
- Provide TestFlight/Play Beta build
- Gather feedback via form
- Iterate based on feedback

### Users (Release)
- In-app announcement after update
- "What's New" section highlighting multi-instance
- Tutorial on first launch (optional, can skip)
- Support documentation updated

---

## Appendix A: Storage Key Reference

### Global Keys
| Key | Type | Example Value | Description |
|-----|------|---------------|-------------|
| `active_instance_id` | String | `npm_1697123456789_123456` | UUID of currently active instance |
| `instance_list` | String | `uuid1,uuid2,uuid3` | Comma-separated list of instance UUIDs |

### Per-Instance Keys (where {uuid} = instance ID)
| Key | Type | Example Value | Description |
|-----|------|---------------|-------------|
| `instance_{uuid}_name` | String | `Production Server` | User-friendly instance name |
| `instance_{uuid}_server_url` | String | `https://npm.example.com:81` | Full server URL with protocol and port |
| `instance_{uuid}_email` | String | `admin@example.com` | User email/username for this instance |
| `instance_{uuid}_encrypted_password` | String | `base64EncodedEncryptedPassword` | AES-256 encrypted password |
| `instance_{uuid}_encryption_iv` | String | `base64EncodedIV` | Initialization vector for password decryption |
| `instance_{uuid}_biometric_enabled` | String | `true` / `false` | Whether biometric auth is enabled for this instance |
| `instance_{uuid}_auth_token` | String | `Bearer eyJ0eXAiOiJKV...` | Session auth token for API calls |
| `instance_{uuid}_created_at` | String | `2025-10-12T10:30:00Z` | ISO 8601 timestamp of instance creation |
| `instance_{uuid}_last_used` | String | `2025-10-12T15:45:00Z` | ISO 8601 timestamp of last access |

### Legacy Keys (Deprecated, Removed After Migration)
| Key | Description |
|-----|-------------|
| `server_url` | Single server URL |
| `email` | Single email |
| `encrypted_password` | Single encrypted password |
| `encryption_key` | Shared encryption key (kept for all instances) |
| `encryption_iv` | Single encryption IV |
| `biometric_enabled` | Single biometric flag |
| `auth_token` | Single auth token |

**Note:** `encryption_key` is kept as global and shared across all instances for simplicity. Each instance gets its own unique `encryption_iv` for security.

---

## Appendix B: Example Code Snippets

### Migration Implementation
```dart
Future<void> migrateFromLegacyStorage() async {
  try {
    await _logService.logMigrationEvent(
      event: 'MIGRATION_START',
      details: 'Starting migration from legacy storage',
    );

    // Read legacy data
    final serverUrl = await _storage.read(key: 'server_url');
    final email = await _storage.read(key: 'email');
    final encryptedPassword = await _storage.read(key: 'encrypted_password');
    final encryptionIV = await _storage.read(key: 'encryption_iv');
    final biometricEnabled = await _storage.read(key: 'biometric_enabled');
    final authToken = await _storage.read(key: 'auth_token');

    if (serverUrl == null || email == null) {
      // No legacy data to migrate
      return;
    }

    // Generate new instance
    final instanceId = generateInstanceId();
    final instanceName = 'Default Instance';

    // Write instance data
    await Future.wait([
      _storage.write(key: 'instance_$instanceId\_name', value: instanceName),
      _storage.write(key: 'instance_$instanceId\_server_url', value: serverUrl),
      _storage.write(key: 'instance_$instanceId\_email', value: email),
      if (encryptedPassword != null)
        _storage.write(key: 'instance_$instanceId\_encrypted_password', value: encryptedPassword),
      if (encryptionIV != null)
        _storage.write(key: 'instance_$instanceId\_encryption_iv', value: encryptionIV),
      _storage.write(key: 'instance_$instanceId\_biometric_enabled', value: biometricEnabled ?? 'false'),
      if (authToken != null)
        _storage.write(key: 'instance_$instanceId\_auth_token', value: authToken),
      _storage.write(key: 'instance_$instanceId\_created_at', value: DateTime.now().toIso8601String()),
      _storage.write(key: 'instance_$instanceId\_last_used', value: DateTime.now().toIso8601String()),
    ]);

    // Set as active instance
    await _storage.write(key: 'active_instance_id', value: instanceId);
    await _storage.write(key: 'instance_list', value: instanceId);

    // Verify migration
    final verifyUrl = await _storage.read(key: 'instance_$instanceId\_server_url');
    if (verifyUrl == serverUrl) {
      // Migration successful, clean up legacy keys
      await Future.wait([
        _storage.delete(key: 'server_url'),
        _storage.delete(key: 'email'),
        _storage.delete(key: 'encrypted_password'),
        _storage.delete(key: 'encryption_iv'),
        _storage.delete(key: 'biometric_enabled'),
        _storage.delete(key: 'auth_token'),
      ]);

      await _logService.logMigrationEvent(
        event: 'MIGRATION_SUCCESS',
        details: 'Migration completed successfully',
        additionalInfo: {
          'instanceId': instanceId,
          'biometricPreserved': biometricEnabled == 'true',
        },
      );
    } else {
      throw Exception('Migration verification failed');
    }
  } catch (e) {
    await _logService.logMigrationEvent(
      event: 'MIGRATION_ERROR',
      details: 'Migration failed',
      additionalInfo: {'error': e.toString()},
    );
    // Don't rethrow - app should still work with legacy keys
  }
}
```

### Instance Selector UI
```dart
Widget _buildInstanceSelector() {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: _instances.map((instance) {
            return DropdownMenuItem(
              value: instance.id,
              child: Row(
                children: [
                  if (instance.biometricEnabled)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.fingerprint, size: 16),
                    ),
                  Expanded(
                    child: Text(
                      instance.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (instanceId) {
            if (instanceId != null) {
              _selectInstance(instanceId);
            }
          },
        ),
        if (_instances.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${_instances.length} instances configured',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 11,
              ),
            ),
          ),
      ],
    ),
  );
}
```

---

## Appendix C: Test Scenarios Detail

### Test Scenario 1: Fresh Install
**Steps:**
1. Install app on clean device
2. Open app
3. Should see "No instances configured" message
4. Tap "Add Instance"
5. Fill in credentials
6. Login successful
7. Instance saved and set as active
8. Dashboard loads

**Expected Result:** Smooth onboarding, single instance created

---

### Test Scenario 2: Legacy User Migration
**Preconditions:** Device has app v1.0.3 with saved credentials

**Steps:**
1. Update app to v1.1.0
2. Open app
3. Migration runs automatically
4. Login screen shows with instance pre-selected
5. Biometric still works (if was enabled)
6. Login successful
7. Dashboard loads with same data

**Expected Result:** Seamless upgrade, no data loss, biometric preserved

---

### Test Scenario 3: Add Second Instance
**Preconditions:** User has one instance configured

**Steps:**
1. From login screen, tap "Add Instance"
2. Enter name: "Staging Server"
3. Enter server URL, email, password
4. Tap "Add"
5. Login attempt to new instance
6. If successful, instance added to list
7. New instance becomes active
8. Dashboard shows staging server data

**Expected Result:** New instance added, can switch between instances

---

### Test Scenario 4: Delete Active Instance
**Preconditions:** User has 2 instances, one is active

**Steps:**
1. From login screen, long-press active instance
2. Tap "Delete"
3. See warning: "This will log you out"
4. Confirm deletion
5. Instance deleted
6. Remaining instance becomes active
7. Login screen refreshes

**Expected Result:** Safe deletion with warning, automatic re-selection

---

### Test Scenario 5: Biometric Per Instance
**Preconditions:** User has 2 instances

**Steps:**
1. Instance A: Enable biometric
2. Instance B: Keep biometric disabled
3. Logout and return to login screen
4. Select Instance A - biometric button visible
5. Biometric auth works
6. Logout
7. Select Instance B - no biometric button
8. Must enter password manually

**Expected Result:** Biometric settings are independent per instance

---

## Appendix D: UI Mockups Description

### Login Screen (Multi-Instance)
```
+----------------------------------+
|  [App Icon]                      |
|  Nginx Mobile Dashboard          |
|                                  |
|  NPM Instance       [Add New]    |
|  [Dropdown: Production Server v] |
|  3 instances configured          |
|                                  |
|  Server URL                      |
|  [https://npm.example.com:81]    |
|  [Paste] [Clear]                 |
|                                  |
|  Email                           |
|  [admin@example.com            ] |
|                                  |
|  Password                        |
|  [••••••••••]           [Paste]  |
|                                  |
|  [✓] Remember Me                 |
|                                  |
|  [     Login     ]               |
|                                  |
|  [🔒 Sign in with Face ID]       |
|                                  |
+----------------------------------+
```

### Dashboard (Instance Context)
```
+----------------------------------+
| [Icon] Production Server    [↻][⚙]|
+----------------------------------+
| Domain: app.example.com          |
| → https://192.168.1.100:443      |
| [Edit]                     [ON]  |
|----------------------------------|
| Domain: api.example.com          |
| → http://192.168.1.101:80        |
| [Edit]                     [OFF] |
|----------------------------------|
|                                  |
+----------------------------------+
| [Dashboard]      [Ports]         |
+----------------------------------+
```

### Instance Switcher Modal
```
+----------------------------------+
|  Switch NPM Instance             |
+----------------------------------+
|  ● Production Server (Active)    |
|    https://npm.example.com       |
|                                  |
|  ○ Staging Server                |
|    https://staging.npm.local     |
|                                  |
|  ○ Home Server                   |
|    http://192.168.1.10:81        |
|                                  |
|  [+ Add New Instance]            |
|                                  |
|  [Cancel]                        |
+----------------------------------+
```

---

## Final Notes

This implementation plan is designed to be comprehensive yet flexible. As development progresses, some details may need adjustment based on discoveries during implementation. However, the core architecture and approach should remain stable.

**Key Success Factors:**
1. Thorough testing of migration logic
2. Clear UI/UX for instance management
3. Maintaining backward compatibility
4. Comprehensive error handling
5. Detailed logging for debugging

**Remember:**
- Every code change should preserve existing functionality
- Migration is the riskiest part - test extensively
- User experience should be intuitive for both single and multi-instance users
- Security must not be compromised
- Performance must remain excellent

**Questions or Issues:**
Document any questions or issues encountered during implementation in the project's issue tracker. Update this document if major architectural changes are needed.

---

**Document Version:** 1.0  
**Last Updated:** October 12, 2025  
**Next Review:** After Phase 3 completion

