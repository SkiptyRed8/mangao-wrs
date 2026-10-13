import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config.dart';

/// One message from the server: 'order' (an order changed), 'notification' (new alert),
/// 'location' (a rider moved) or 'refresh' (stock or tank changed).
class RtEvent {
  final String name;
  final Map<String, dynamic> data;
  const RtEvent(this.name, this.data);
}

/// Real-time updates (step 35, Socket.IO). Screens listen to [events] and reload by themselves;
/// they still check every minute in case the connection drops.
class Realtime {
  io.Socket? _socket;
  final _events = StreamController<RtEvent>.broadcast();

  Stream<RtEvent> get events => _events.stream;
  bool get connected => _socket?.connected ?? false;

  /// Logged-in users connect with their token; guests with the guest phone code.
  void connect({String? token, String? guest}) {
    disconnect();
    if (token == null && guest == null) return;
    final s = io.io(
      AppConfig.apiUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth(token != null ? {'token': token} : {'guest': guest})
          .disableAutoConnect()
          .enableReconnection()
          .build(),
    );
    for (final name in const ['order', 'notification', 'location', 'refresh']) {
      s.on(name, (data) {
        final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
        _events.add(RtEvent(name, map));
      });
    }
    s.connect();
    _socket = s;
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
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
