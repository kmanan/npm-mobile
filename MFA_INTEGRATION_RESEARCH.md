# Nginx Proxy Manager MFA Integration Research

## Executive Summary

Nginx Proxy Manager v2.13.6 introduced **TOTP-based two-factor authentication** (PR #5109). This document provides a comprehensive analysis of the new MFA API and how to integrate it into the mobile app without breaking existing functionality like platform-specific biometrics.

---

## Current App Authentication Flow

### Overview of Existing Implementation

Based on the codebase analysis:

1. **`ApiService.login()`** (`lib/services/api_service.dart`)
   - Sends `POST /api/tokens` with `{ identity: email, secret: password }`
   - Receives `{ token, expires }` on success
   - Stores token in secure storage per instance

2. **`AuthService`** (`lib/services/auth_service.dart`)
   - Manages device-level biometric authentication via `local_auth` package
   - Stores encrypted credentials in `FlutterSecureStorage`
   - Biometrics is **device-level only** - it unlocks stored credentials, not related to NPM server

3. **Login Flow** (`lib/screens/login_screen.dart`)
   - Multi-instance support with instance selector
   - Optional biometric quick-login for returning users
   - "Remember Me" functionality

### Key Files Affected by MFA Integration

| File | Purpose |
|------|---------|
| `lib/services/api_service.dart` | API calls - needs MFA challenge handling |
| `lib/screens/login_screen.dart` | UI - needs TOTP input screen |
| `lib/services/auth_service.dart` | No changes needed - device biometrics unchanged |
| `lib/models/npm_instance.dart` | May need `mfaEnabled` field |

---

## Nginx Proxy Manager MFA API (v2.13.6+)

### New API Endpoints

#### 1. Login with MFA Challenge

**`POST /api/tokens`** - Modified behavior

**Request:**
```json
{
  "identity": "user@example.com",
  "secret": "password123"
}
```

**Response WITHOUT 2FA enabled:**
```json
{
  "token": "eyJhbGciOiJSUzI1NiIs...",
  "expires": "2024-01-15T12:00:00.000Z"
}
```

**Response WITH 2FA enabled:**
```json
{
  "requires_2fa": true,
  "challenge_token": "eyJhbGciOiJSUzI1NiIs..."
}
```

#### 2. Verify 2FA Code

**`POST /api/tokens/2fa`**

**Request:**
```json
{
  "challenge_token": "eyJhbGciOiJSUzI1NiIs...",
  "code": "123456"
}
```

**Response:**
```json
{
  "token": "eyJhbGciOiJSUzI1NiIs...",
  "expires": "2024-01-15T12:00:00.000Z"
}
```

#### 3. Get 2FA Status

**`GET /api/users/{userId}/2fa`**

**Response:**
```json
{
  "enabled": true,
  "backup_codes_remaining": 8
}
```

#### 4. Start 2FA Setup

**`POST /api/users/{userId}/2fa`**

**Response:**
```json
{
  "secret": "JBSWY3DPEHPK3PXP",
  "otpauth_url": "otpauth://totp/Nginx%20Proxy%20Manager:user@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Nginx%20Proxy%20Manager"
}
```

#### 5. Enable 2FA

**`POST /api/users/{userId}/2fa/enable`**

**Request:**
```json
{
  "code": "123456"
}
```

**Response:**
```json
{
  "backup_codes": [
    "A1B2C3D4",
    "E5F6G7H8",
    "..."
  ]
}
```

#### 6. Disable 2FA

**`DELETE /api/users/{userId}/2fa?code=123456`**

**Response:** `true`

#### 7. Regenerate Backup Codes

**`POST /api/users/{userId}/2fa/backup-codes`**

**Request:**
```json
{
  "code": "123456"
}
```

**Response:**
```json
{
  "backup_codes": [
    "A1B2C3D4",
    "E5F6G7H8",
    "..."
  ]
}
```

---

## Integration Strategy

### Phase 1: Login Flow Modification (Required)

The app **must** handle the new MFA challenge response to work with NPM v2.13.6+ when users have 2FA enabled.

#### Modified Login Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                      User Opens App                              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              Device Biometrics Enabled?                          │
│              (Existing local_auth check)                         │
└─────────────────────────────────────────────────────────────────┘
        │                                       │
       YES                                      NO
        │                                       │
        ▼                                       ▼
┌───────────────────┐               ┌───────────────────────────┐
│ Authenticate with │               │ Show Login Form           │
│ Face ID/Fingerprint│               │ (email, password)         │
└───────────────────┘               └───────────────────────────┘
        │                                       │
        ▼                                       │
┌───────────────────┐                           │
│ Get Stored        │                           │
│ Credentials       │                           │
└───────────────────┘                           │
        │                                       │
        └───────────────┬───────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│                POST /api/tokens                                  │
│                {identity, secret}                                │
└─────────────────────────────────────────────────────────────────┘
                        │
        ┌───────────────┴───────────────┐
        │                               │
        ▼                               ▼
┌───────────────────┐       ┌───────────────────────────────────┐
│ {token, expires}  │       │ {requires_2fa: true,              │
│ (No MFA)          │       │  challenge_token: "..."}          │
└───────────────────┘       └───────────────────────────────────┘
        │                               │
        │                               ▼
        │               ┌───────────────────────────────────────┐
        │               │       Show TOTP Input Screen          │
        │               │       (6-digit code entry)            │
        │               └───────────────────────────────────────┘
        │                               │
        │                               ▼
        │               ┌───────────────────────────────────────┐
        │               │       POST /api/tokens/2fa            │
        │               │       {challenge_token, code}         │
        │               └───────────────────────────────────────┘
        │                               │
        │                               ▼
        │               ┌───────────────────────────────────────┐
        │               │       {token, expires}                │
        │               └───────────────────────────────────────┘
        │                               │
        └───────────────┬───────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Store Token & Navigate to Main                 │
└─────────────────────────────────────────────────────────────────┘
```

### Phase 2: 2FA Management (Optional Enhancement)

Allow users to manage their 2FA settings from within the app.

#### Features to Add

1. **View 2FA Status** - Show if 2FA is enabled
2. **Setup 2FA** - Display QR code for authenticator app
3. **Enable 2FA** - Verify and activate
4. **Disable 2FA** - Deactivate with code verification
5. **Backup Codes** - Display and regenerate backup codes

---

## Compatibility Considerations

### Biometric Authentication Compatibility

**No conflicts!** The existing biometric implementation is **device-level only**:

| Feature | Scope | Affected by NPM MFA? |
|---------|-------|---------------------|
| Face ID / Fingerprint | Device unlock | ❌ NO |
| Stored password encryption | Local secure storage | ❌ NO |
| NPM TOTP 2FA | Server authentication | ✅ YES (new) |

**Flow with both enabled:**
1. User opens app
2. Device biometrics unlock stored credentials (existing)
3. App sends credentials to NPM server
4. If NPM 2FA enabled → show TOTP input (new)
5. Verify TOTP → get auth token

### Backward Compatibility

The new MFA login flow is **backward compatible**:

- **NPM < v2.13.6**: Returns `{token, expires}` (no change)
- **NPM >= v2.13.6 without 2FA**: Returns `{token, expires}` (no change)
- **NPM >= v2.13.6 with 2FA**: Returns `{requires_2fa, challenge_token}` (new handling needed)

**Detection Strategy:**
```dart
// Check response structure
if (response.containsKey('requires_2fa') && response['requires_2fa'] == true) {
  // Handle MFA challenge
} else if (response.containsKey('token')) {
  // Normal login success
}
```

---

## Implementation Recommendations

### Required Changes

#### 1. `api_service.dart` - Modify `_performLogin()` method

**Current behavior:** Returns `bool` success/failure

**New behavior:** Return a result object that can indicate:
- Login success
- Login failure
- MFA challenge required (with challenge_token)

**Suggested approach:**
```dart
// New return type
class LoginResult {
  final bool success;
  final bool requiresMfa;
  final String? token;
  final String? challengeToken;
  final String? error;
  
  // Constructors for different states
  LoginResult.success(this.token);
  LoginResult.mfaRequired(this.challengeToken);
  LoginResult.failure(this.error);
}
```

#### 2. `api_service.dart` - Add new method for 2FA verification

```dart
Future<LoginResult> verify2FA(String challengeToken, String code) async {
  final response = await _dio.post(
    '/api/tokens/2fa',
    data: {
      'challenge_token': challengeToken,
      'code': code,
    },
  );
  // Handle response...
}
```

#### 3. `login_screen.dart` - Add TOTP input UI

**Options:**
- Show TOTP input as a dialog/modal
- Navigate to a separate TOTP verification screen
- Inline expansion in login form

**Recommended:** Modal dialog for minimal UI disruption

### Optional Enhancements

#### 4. 2FA Settings Screen

New screen to allow users to:
- View 2FA status
- Set up 2FA (display QR code)
- Enable/disable 2FA
- View/regenerate backup codes

#### 5. Model Updates

Add to `NpmInstance`:
```dart
class NpmInstance {
  // ... existing fields
  final bool? serverMfaEnabled; // Track if server has MFA enabled
}
```

---

## Testing Checklist

### Login Flow Tests

- [ ] Login to NPM < v2.13.6 works unchanged
- [ ] Login to NPM >= v2.13.6 without 2FA works unchanged
- [ ] Login to NPM >= v2.13.6 with 2FA shows TOTP input
- [ ] Valid TOTP code completes login
- [ ] Invalid TOTP code shows error, allows retry
- [ ] Backup code works as TOTP alternative
- [ ] Challenge token expiry (5 min) handled gracefully

### Biometric Compatibility Tests

- [ ] Device biometrics still unlock stored credentials
- [ ] Biometric login + NPM 2FA flow works correctly
- [ ] "Remember Me" functionality preserved

### Multi-Instance Tests

- [ ] Each instance handles MFA independently
- [ ] Switching instances with different MFA states works

---

## Dependencies to Consider

### Current Dependencies (from pubspec.lock)
- `local_auth` - Device biometrics (no changes needed)
- `flutter_secure_storage` - Credential storage (no changes needed)
- `dio` - HTTP client (no changes needed)
- `encrypt` - Password encryption (no changes needed)

### No New Dependencies Required

The MFA integration only requires:
- Modified API response handling
- New UI for TOTP input
- No new packages needed

---

## Timeline Estimate

| Phase | Task | Effort |
|-------|------|--------|
| 1 | Modify login API handling | 2-3 hours |
| 1 | Add TOTP input UI | 2-3 hours |
| 1 | Testing & fixes | 2-3 hours |
| 2 | 2FA settings screen (optional) | 4-6 hours |
| 2 | QR code display for setup (optional) | 2-3 hours |

**Minimum viable implementation:** ~6-9 hours

---

## References

- **NPM PR #5109:** [Add TOTP-based two-factor authentication](https://github.com/NginxProxyManager/nginx-proxy-manager/pull/5109)
- **NPM v2.13.6 Release:** [Release Notes](https://github.com/NginxProxyManager/nginx-proxy-manager/releases/tag/v2.13.6)
- **Backend 2FA Implementation:** `backend/internal/2fa.js`
- **Backend Token Routes:** `backend/routes/tokens.js`
- **Backend User Routes:** `backend/routes/users.js`
