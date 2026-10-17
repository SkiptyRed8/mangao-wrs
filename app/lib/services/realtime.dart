import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';

/// One message from the server: 'order' (an order changed), 'notification' (new alert),
/// 'location' (a rider moved) or 'refresh' (stock or tank changed).
class RtEvent {
  final String name;
  final Map<String, dynamic> data;
  const RtEvent(this.name, this.data);
}

/// Real-time updates (step 35) over a WebSocket to the Java server: ws://server:3100/ws?token=...
/// (guests: ?guest=GUEST_CODE). Each message is JSON { "event": name, "data": {...} }.
/// Screens listen to [events] and reload by themselves; they still check every minute in case the
/// connection drops. The connection comes back by itself after a few seconds.
class Realtime {
  WebSocketChannel? _ws;
  StreamSubscription? _sub;
  Timer? _retry;
  Timer? _ping;
  Uri? _uri;
  bool _connected = false;
  final _events = StreamController<RtEvent>.broadcast();

  Stream<RtEvent> get events => _events.stream;
  bool get connected => _connected;

  /// Logged-in users connect with their token; guests with the guest phone code.
  void connect({String? token, String? guest}) {
    disconnect();
    if (token == null && guest == null) return;
    final base = AppConfig.apiUrl.replaceFirst(RegExp(r'^http'), 'ws');
    final q = token != null ? 'token=${Uri.encodeQueryComponent(token)}' : 'guest=${Uri.encodeQueryComponent(guest!)}';
    _uri = Uri.parse('$base/ws?$q');
    _open();
  }

  void _open() {
    final uri = _uri;
    if (uri == null) return;
    try {
      final ws = WebSocketChannel.connect(uri);
      _ws = ws;
      _sub = ws.stream.listen(
        (msg) {
          _connected = true;
          try {
            final m = jsonDecode(msg as String);
            if (m is Map && m['event'] is String) {
              final data = m['data'] is Map ? Map<String, dynamic>.from(m['data'] as Map) : <String, dynamic>{};
              _events.add(RtEvent(m['event'] as String, data));
            }
          } catch (_) {
            // not a message for us
          }
        },
        onDone: _lost,
        onError: (_) => _lost(),
        cancelOnError: true,
      );
      ws.ready.then((_) {
        _connected = true;
      }).catchError((_) {
        // stream onError handles a failed connection
      });
      _ping?.cancel();
      _ping = Timer.periodic(const Duration(seconds: 25), (_) {
        try {
          _ws?.sink.add('ping');
        } catch (_) {}
      });
    } catch (_) {
      _lost();
    }
  }

  void _lost() {
    _connected = false;
    _ping?.cancel();
    _sub?.cancel();
    _sub = null;
    _ws = null;
    if (_uri == null) return; // logged out
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 3), _open);
  }

  void disconnect() {
    _uri = null;
    _retry?.cancel();
    _ping?.cancel();
    _sub?.cancel();
    _sub = null;
    try {
      _ws?.sink.close();
    } catch (_) {}
    _ws = null;
    _connected = false;
  }

  /// Calls [onChange] (at most every half second) when one of [names] arrives.
  StreamSubscription<RtEvent> listen(void Function(RtEvent e) onChange, {Set<String> names = const {'order', 'refresh'}}) {
    Timer? wait;
    RtEvent? last;
    return events.where((e) => names.contains(e.name)).listen((e) {
      last = e;
      wait?.cancel();
      wait = Timer(const Duration(milliseconds: 500), () => onChange(last!));
    });
  }
}

/// The one connection used by every screen.
final realtime = Realtime();
