// Connection test for the project team (Server address box): shows what this phone sees when it
// connects to the server. The web version has no such test (the browser does the connecting).
export 'net_test_web.dart' if (dart.library.io) 'net_test_io.dart';
