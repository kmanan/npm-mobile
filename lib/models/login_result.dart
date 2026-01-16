/// Result of a login attempt to NPM server
/// Handles three states: success, MFA required, or failure
class LoginResult {
  final bool success;
  final bool requiresMfa;
  final String? token;
  final String? challengeToken;
  final String? error;

  LoginResult._({
    required this.success,
    required this.requiresMfa,
    this.token,
    this.challengeToken,
    this.error,
  });

  /// Login succeeded, token received
  factory LoginResult.success(String token) {
    return LoginResult._(
      success: true,
      requiresMfa: false,
      token: token,
    );
  }

  /// MFA verification required
  factory LoginResult.mfaRequired(String challengeToken) {
    return LoginResult._(
      success: false,
      requiresMfa: true,
      challengeToken: challengeToken,
    );
  }

  /// Login failed
  factory LoginResult.failure(String error) {
    return LoginResult._(
      success: false,
      requiresMfa: false,
      error: error,
    );
  }
}
