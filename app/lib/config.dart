import 'package:flutter/foundation.dart' show kIsWeb;

/// Where the app finds the server.
/// - Chrome on the laptop (START.bat): http://localhost:3100
/// - Android emulator: the laptop is 10.0.2.2
/// - A real phone or the online server: flutter run --dart-define=API_URL=http://192.168.1.5:3100
class AppConfig {
  static const _fromCommand = String.fromEnvironment('API_URL');
  static String get apiUrl =>
      _fromCommand.isNotEmpty ? _fromCommand : (kIsWeb ? 'http://localhost:3100' : 'http://10.0.2.2:3100');
  static const stationName = 'Mangao Water Refilling Station';
}
