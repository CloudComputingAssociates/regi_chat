import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Reads config values with this precedence:
///   1. compile-time `--dart-define` (used by netlify.toml in production)
///   2. runtime `.env` via flutter_dotenv (used in local dev)
/// Returns empty string if neither source has it.
class Config {
  const Config._();

  static String _read(String key, String fromEnv) {
    if (fromEnv.isNotEmpty) return fromEnv;
    return dotenv.env[key] ?? '';
  }

  static String get auth0Domain => _read(
        'AUTH0_DOMAIN',
        const String.fromEnvironment('AUTH0_DOMAIN'),
      );

  static String get auth0ClientId => _read(
        'AUTH0_CLIENT_ID',
        const String.fromEnvironment('AUTH0_CLIENT_ID'),
      );

  static String get auth0Audience => _read(
        'AUTH0_AUDIENCE',
        const String.fromEnvironment('AUTH0_AUDIENCE'),
      );

  static String get apiBaseUrl => _read(
        'API_BASE_URL',
        const String.fromEnvironment('API_BASE_URL'),
      );
}
