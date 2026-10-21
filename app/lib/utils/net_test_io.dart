import 'dart:io';

import 'package:http/http.dart' as http;

import '../services/net_io.dart' as net;

String _short(Object e) => '${e.runtimeType}: ${'$e'.split('\n').first}';

/// Step by step: the server name's address, a plain connection, the secure (HTTPS) connection,
/// the /health answer, and Google for comparison. Each line shows the time it took.
Future<String> connectionTest(String baseUrl) async {
  final out = StringBuffer();
  final uri = Uri.parse(baseUrl);
  final host = uri.host;
  final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
  var sw = Stopwatch()..start();
  try {
    final a = await InternetAddress.lookup(host).timeout(const Duration(seconds: 10));
    out.writeln('1 Address: ${a.map((e) => e.address).join(', ')} (${sw.elapsedMilliseconds} ms)');
  } catch (e) {
    out.writeln('1 Address: failed after ${sw.elapsedMilliseconds} ms (${_short(e)})');
  }
  sw = Stopwatch()..start();
  try {
    final s = await Socket.connect(host, port, timeout: const Duration(seconds: 10));
    out.writeln('2 Connect: ok, ${s.remoteAddress.address} (${sw.elapsedMilliseconds} ms)');
    s.destroy();
  } catch (e) {
    out.writeln('2 Connect: failed after ${sw.elapsedMilliseconds} ms (${_short(e)})');
  }
  if (uri.scheme == 'https') {
    sw = Stopwatch()..start();
    try {
      final s = await SecureSocket.connect(host, port, timeout: const Duration(seconds: 10));
      out.writeln('3 Secure: ok, ${s.peerCertificate?.issuer ?? ''} (${sw.elapsedMilliseconds} ms)');
      s.destroy();
    } catch (e) {
      out.writeln('3 Secure: failed after ${sw.elapsedMilliseconds} ms (${_short(e)})');
    }
  }
  for (final u in ['$baseUrl/health', 'https://www.google.com/generate_204']) {
    sw = Stopwatch()..start();
    final name = u.contains('google') ? '5 Google' : '4 Server';
    try {
      final r = await http.get(Uri.parse(u)).timeout(const Duration(seconds: 15));
      final body = r.body.length > 50 ? r.body.substring(0, 50) : r.body;
      out.writeln('$name: ${r.statusCode} (${sw.elapsedMilliseconds} ms) $body');
    } catch (e) {
      out.writeln('$name: failed after ${sw.elapsedMilliseconds} ms (${_short(e)})');
    }
  }
  // 6: the way the app itself connects (fallbacks included).
  sw = Stopwatch()..start();
  try {
    final r = await net.makeHttpClient().get(Uri.parse('$baseUrl/health')).timeout(const Duration(seconds: 60));
    out.writeln('6 App: ${r.statusCode} (${sw.elapsedMilliseconds} ms) via ${net.connectionNote(host)}');
  } catch (e) {
    out.writeln('6 App: failed after ${sw.elapsedMilliseconds} ms (${_short(e)})');
  }
  return out.toString().trim();
}
