/// Reads config exclusively from compile-time `--dart-define` values.
///
/// Local dev: pass them on the flutter command line, e.g.
///   flutter run -d chrome --web-port=5000 \
///     --dart-define=AUTH0_DOMAIN=dev-xxx.us.auth0.com \
///     --dart-define=AUTH0_CLIENT_ID=... \
///     --dart-define=AUTH0_AUDIENCE=https://api.regimenu.net \
///     --dart-define=API_BASE_URL=https://api.regimenu.net/api
///
/// Netlify: same keys are set in Site settings → Environment variables, and
/// netlify.toml expands them into --dart-define args at build time.
class Config {
  const Config._();

  static const String auth0Domain =
      String.fromEnvironment('AUTH0_DOMAIN');

  static const String auth0ClientId =
      String.fromEnvironment('AUTH0_CLIENT_ID');

  static const String auth0Audience =
      String.fromEnvironment('AUTH0_AUDIENCE');

  static const String apiBaseUrl =
      String.fromEnvironment('API_BASE_URL');
}
