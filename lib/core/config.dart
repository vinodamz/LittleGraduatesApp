/// Build-time settings. Override for a local server with
/// `flutter run --dart-define=LG_BASE_URL=http://10.0.2.2:8765`.
class AppConfig {
  static const baseUrl = String.fromEnvironment(
    'LG_BASE_URL',
    defaultValue: 'https://mtt.thelittlegraduates.in',
  );

  /// How often the driver's phone sends its position while a trip runs.
  static const locationUploadInterval = Duration(seconds: 15);

  /// How often open trip screens refresh from the server.
  static const tripRefreshInterval = Duration(seconds: 30);
}
