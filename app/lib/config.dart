import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

/// Where the app finds the server.
/// - Built by GitHub (APK and web app): the online server in deploy/server-url.txt (--dart-define=API_URL=...)
/// - Chrome on the laptop (START.bat): http://localhost:3100
/// - Android emulator: the laptop is 10.0.2.2
/// - Backup: on the Welcome screen, long-press the logo to type another address, e.g. the laptop on the
///   same Wi-Fi or hotspot (http://192.168.x.x:3100). "Use default" goes back to the built-in one.
class AppConfig {
  static const _fromCommand = String.fromEnvironment('API_URL');
  static const _kServer = 'serverUrl';
  static String? _chosen;

  static String get defaultUrl =>
      _fromCommand.isNotEmpty ? _fromCommand : (kIsWeb ? 'http://localhost:3100' : 'http://10.0.2.2:3100');
  static String get apiUrl => _chosen ?? defaultUrl;
  static bool get custom => _chosen != null;
  static const stationName = 'Mangao Water Refilling Station';

  /// App version, set by the GitHub build (e.g. 1.0.13); shown on Welcome and My Account so testers
  /// can check they have the newest version.
  static const version = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

  /// Reads the address chosen on this phone (called when the app opens).
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _chosen = prefs.getString(_kServer);
  }

  /// "192.168.1.5:3100" -> "http://192.168.1.5:3100"; null if it does not look like an address.
  static String? clean(String text) {
    var t = text.trim();
    while (t.endsWith('/')) {
      t = t.substring(0, t.length - 1);
    }
    if (t.isEmpty) return null;
    if (!t.startsWith('http://') && !t.startsWith('https://')) t = 'http://$t';
    final u = Uri.tryParse(t);
    if (u == null || u.host.isEmpty) return null;
    return t;
  }

  /// Saves another server address (null = back to the built-in one).
  static Future<void> choose(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url == null || url == defaultUrl) {
      _chosen = null;
      await prefs.remove(_kServer);
    } else {
      _chosen = url;
      await prefs.setString(_kServer, url);
    }
  }
}
