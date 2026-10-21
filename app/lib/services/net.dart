// The app's connections to the server: special handling on Android (net_io.dart), the browser's own
// on the web (net_web.dart).
export 'net_web.dart' if (dart.library.io) 'net_io.dart';
