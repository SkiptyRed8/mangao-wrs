import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'roots.dart';

// How the Android app connects to the server. Chrome on the same phone can reach the server when the
// app cannot, because Chrome has its own up-to-date certificate list and can look up server names in
// its own way. The app does the same here:
//  1. it trusts the phone's certificates plus the root certificates in roots.dart;
//  2. it connects normally first; if the phone's name lookup leads nowhere, it asks Google or
//     Cloudflare for the server's address over HTTPS (DNS over HTTPS) and connects to that address.

SecurityContext? _ctx;

SecurityContext get _context {
  final existing = _ctx;
  if (existing != null) return existing;
  final c = SecurityContext(withTrustedRoots: true);
  for (final pem in trustedRootsPem) {
    try {
      c.setTrustedCertificatesBytes(utf8.encode(pem));
    } catch (_) {
      // already in the phone's list
    }
  }
  return _ctx = c;
}

/// Server names where the phone's own lookup did not work in this run of the app.
final Set<String> _lookupFailed = {};
final Map<String, (List<InternetAddress>, DateTime)> _found = {};

/// The addresses of [host] from DNS over HTTPS (Cloudflare, then Google). Empty if none answered.
Future<List<InternetAddress>> _lookupOverHttps(String host) async {
  final hit = _found[host];
  if (hit != null && DateTime.now().difference(hit.$2) < const Duration(minutes: 10)) return hit.$1;
  const services = [
    'https://1.1.1.1/dns-query?type=A&name=',
    'https://8.8.8.8/resolve?type=A&name=',
    'https://dns.google/resolve?type=A&name=',
    'https://cloudflare-dns.com/dns-query?type=A&name=',
  ];
  for (final s in services) {
    final c = HttpClient(context: _context)..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await c.getUrl(Uri.parse('$s${Uri.encodeQueryComponent(host)}')).timeout(const Duration(seconds: 8));
      req.headers.set('accept', 'application/dns-json');
      final res = await req.close().timeout(const Duration(seconds: 8));
      final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 8));
      final j = jsonDecode(body);
      final ips = <InternetAddress>[];
      if (j is Map && j['Answer'] is List) {
        for (final a in j['Answer'] as List) {
          if (a is Map && a['type'] == 1 && a['data'] is String) {
            final ip = InternetAddress.tryParse(a['data'] as String);
            if (ip != null) ips.add(ip);
          }
        }
      }
      if (ips.isNotEmpty) {
        _found[host] = (ips, DateTime.now());
        return ips;
      }
    } catch (_) {
      // try the next service
    } finally {
      c.close(force: true);
    }
  }
  return const [];
}

Future<Socket> _plain(Object host, int port, bool secure, String name) async {
  if (!secure) return Socket.connect(host, port, timeout: const Duration(seconds: 8));
  if (host is String) {
    return SecureSocket.connect(host, port, context: _context, timeout: const Duration(seconds: 8));
  }
  final s = await Socket.connect(host, port, timeout: const Duration(seconds: 8));
  try {
    return await SecureSocket.secure(s, host: name, context: _context).timeout(const Duration(seconds: 10));
  } catch (_) {
    s.destroy();
    rethrow;
  }
}

/// Opens a connection to [host]: the normal way first, then through the DNS-over-HTTPS addresses.
Future<Socket> _open(String host, int port, bool secure) async {
  final literal = InternetAddress.tryParse(host) != null;
  Object? firstError;
  if (literal || !_lookupFailed.contains(host)) {
    try {
      return await _plain(host, port, secure, host).timeout(const Duration(seconds: 12));
    } catch (e) {
      firstError = e;
      if (literal) rethrow;
      _lookupFailed.add(host);
    }
  }
  for (final ip in await _lookupOverHttps(host)) {
    try {
      return await _plain(ip, port, secure, host).timeout(const Duration(seconds: 15));
    } catch (e) {
      firstError ??= e;
    }
  }
  // Nothing else worked: the normal way once more (the network may be back).
  _lookupFailed.remove(host);
  try {
    return await _plain(host, port, secure, host).timeout(const Duration(seconds: 12));
  } catch (e) {
    throw firstError ?? e;
  }
}

HttpClient _httpClient() {
  final c = HttpClient(context: _context)
    ..connectionTimeout = const Duration(seconds: 40)
    ..idleTimeout = const Duration(seconds: 15)
    ..findProxy = (_) => 'DIRECT';
  c.connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) async {
    final secure = uri.scheme == 'https' || uri.scheme == 'wss';
    // A live-update address (wss://) arrives here as https with port 0: use the normal port then.
    final port = uri.hasPort && uri.port != 0 ? uri.port : (secure ? 443 : 80);
    return ConnectionTask.fromSocket(_open(uri.host, port, secure), () {});
  };
  return c;
}

/// The HTTP client used for every request of the app (REST API, export files).
http.Client makeHttpClient() => IOClient(_httpClient());

/// The live-update connection (WebSocket), made the same way.
WebSocketChannel openWebSocket(Uri uri) =>
    IOWebSocketChannel.connect(uri, customClient: _httpClient(), connectTimeout: const Duration(seconds: 40));

/// For the team's connection test: which way the app reached the server.
String connectionNote(String host) {
  if (!_lookupFailed.contains(host)) return 'normal name lookup';
  final hit = _found[host];
  return hit == null ? 'name lookup failed' : 'DNS over HTTPS (${hit.$1.map((a) => a.address).join(', ')})';
}
