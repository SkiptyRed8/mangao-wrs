import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/user.dart';
import '../../services/api.dart';
import '../../services/app_state.dart';
import '../../services/realtime.dart';
import '../../theme/brand.dart';
import '../../widgets/common.dart';
import '../../widgets/delivery_map.dart';
import '../../widgets/map_widgets.dart';
import '../owner/admin_order_details.dart';
import '../shell.dart';
import '../staff/staff_todo.dart';

/// Admin Orders 7 / Staff 9: Live Map. Each rider is a sidecar that glides along the streets and turns
/// to the direction it goes, with the route to the rider's nearest stop and the minutes left (grey with
/// "Last seen" when it has not moved for 5 minutes), and numbered pins for the orders on the road. Tap the rider for the rider card (Call, the
/// orders on board); tap a pin for the order. Staff see and call only. The delivery rider sees their
/// own trip (Rider tab Live Map).
class LiveMapScreen extends StatefulWidget {
  final bool pushed;
  const LiveMapScreen({super.key, this.pushed = false});

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  final _map = MapController();
  Map<String, dynamic>? _data;
  ApiException? _error;
  Map<String, dynamic>? _pin; // the order pin tapped
  Timer? _poll;
  StreamSubscription<RtEvent>? _live;
  bool _centered = false;
  final Map<Object?, double> _heading = {}; // rider id -> direction the sidecar faces
  final Map<Object?, RouteTracker> _routes = {}; // rider id -> route to the nearest stop
  final Map<Object?, PlannedRoute> _planned = {}; // rider id -> station to that stop (light line behind)

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _load());
    _live = realtime.listen((e) {
      if (e.name == 'location' && _data != null && e.data['lat'] != null) {
        // Move the rider marker right away without asking the server again.
        setState(() {
          for (final r in _data!['riders'] as List) {
            if ((r as Map<String, dynamic>)['id'] == e.data['riderId']) {
              final before = _pos(r);
              r['lat'] = e.data['lat'];
              r['lng'] = e.data['lng'];
              r['minutesAgo'] = 0;
              final now = _pos(r);
              if (before != null && now != null && metersBetween(before, now) > 4) {
                _heading[r['id']] = nextHeading(_heading[r['id']] ?? 0, bearingBetween(before, now));
              }
            }
          }
        });
        _updateRoutes();
      } else {
        _load();
      }
    }, names: const {'order', 'location'});
  }

  @override
  void dispose() {
    _poll?.cancel();
    _live?.cancel();
    for (final t in _routes.values) {
      t.dispose();
    }
    for (final t in _planned.values) {
      t.dispose();
    }
    super.dispose();
  }

  static LatLng? _pos(Map<String, dynamic> m) =>
      m['lat'] == null ? null : LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());

  /// The rider's nearest order on board (the next stop).
  Map<String, dynamic>? _nextStop(Map<String, dynamic> rider) {
    final at = _pos(rider);
    if (at == null || _data == null) return null;
    Map<String, dynamic>? best;
    var bestM = double.infinity;
    for (final o in (_data!['orders'] as List).cast<Map<String, dynamic>>()) {
      final p = _pos(o);
      if (o['riderId'] != rider['id'] || p == null) continue;
      final m = metersBetween(at, p);
      if (m < bestM) {
        bestM = m;
        best = o;
      }
    }
    return best;
  }

  /// Asks for (or keeps) each rider's route to the next stop.
  void _updateRoutes() {
    final d = _data;
    if (d == null) return;
    for (final r in (d['riders'] as List).cast<Map<String, dynamic>>()) {
      final at = _pos(r);
      final stop = _nextStop(r);
      if (at == null || stop == null) continue;
      final t = _routes.putIfAbsent(r['id'], () => RouteTracker(() {
            if (mounted) setState(() {});
          }));
      t.update(at, _pos(stop)!);
      _heading.putIfAbsent(r['id'], () => bearingBetween(at, _pos(stop)!));
      final station = _pos(d['station'] as Map<String, dynamic>);
      if (station != null) {
        _planned
            .putIfAbsent(r['id'], () => PlannedRoute(() {
                  if (mounted) setState(() {});
                }))
            .update(station, _pos(stop)!);
      }
    }
  }

  /// Route and time left for one rider (null when there is no stop or no location).
  RouteResult? _routeOf(Map<String, dynamic> r) {
    final at = _pos(r);
    if (at == null || _nextStop(r) == null) return null;
    return _routes[r['id']]?.view(at);
  }

  Future<void> _load() async {
    try {
      final r = await app.api.get('/api/map');
      if (!mounted) return;
      setState(() {
        _data = r;
        _error = null;
      });
      _updateRoutes();
      if (!_centered) {
        _centered = true;
        final first = _points(r).firstOrNullPoint;
        if (first != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            try {
              _map.move(first, 15);
            } catch (_) {}
          });
        }
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  static _Points _points(Map<String, dynamic> d) {
    final pts = <LatLng>[];
    for (final r in d['riders'] as List) {
      final m = r as Map<String, dynamic>;
      if (m['lat'] != null) pts.add(LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble()));
    }
    for (final o in d['orders'] as List) {
      final m = o as Map<String, dynamic>;
      if (m['lat'] != null) pts.add(LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble()));
    }
    return _Points(pts);
  }

  /// The delivery rider sees the map of their own trip (no order details here: they are in Deliveries).
  bool get _rider => app.shownRole == Role.rider;

  /// "Out for delivery", "Arriving" or "Arrived" for an order on the map.
  static String _step(Map<String, dynamic> o) =>
      o['arrival'] == 'Arrived' ? 'Arrived' : (o['arrival'] == 'Arriving' ? 'Arriving' : 'Out for delivery');

  void _openOrder(int id) {
    if (_rider) return;
    if (app.isOwner && app.view == AppView.admin) {
      go(context, AdminOrderDetails(orderId: id));
    } else {
      go(context, StaffOrderDetails(orderId: id));
    }
  }

  void _riderCard(Map<String, dynamic> r) {
    final orders = [for (final o in _data!['orders'] as List) o as Map<String, dynamic>].where((o) => o['riderId'] == r['id']).toList();
    final ago = r['minutesAgo'] == null ? 'No location yet' : (r['minutesAgo'] == 0 ? 'Updated just now' : 'Updated ${r['minutesAgo']} min ago');
    final stop = _nextStop(r);
    final route = _routeOf(r);
    sheet<void>(
      context,
      r['name'] as String,
      sub: '${orders.length} ${orders.length == 1 ? 'order' : 'orders'} on board · $ago',
      (c, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (stop != null) ...[
          Row(children: [
            const Icon(Icons.two_wheeler, color: Brand.blue, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Next stop: pin ${stop['n']}, ${stop['name']}${route == null ? '' : '\n${arrivalText(_pos(r)!, _pos(stop), route, server: stop['arrival'] as String?)}'}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ]),
          const Gap(10),
        ],
        if (!_rider) ...[
          Btn('Call', () => callNumber(context, (r['phone'] ?? '') as String), outline: true, icon: Icons.call),
          const Gap(12),
        ],
        for (final o in orders)
          RowLink(
            '${o['n']}  ${o['name']}',
            sub: '${o['quantity']} ${o['quantity'] == 1 ? 'gallon' : 'gallons'} · ${_step(o)}',
            onTap: () {
              Navigator.pop(c);
              _openOrder((o['id'] as num).toInt());
            },
          ),
      ]),
    );
  }

  /// One rider on the map: the sidecar with "#2 · 6 min", or grey with "Last seen 7 min ago".
  Widget _sidecar(Map<String, dynamic> r) {
    final stale = ((r['minutesAgo'] ?? 99) as num) > 5;
    final stop = _nextStop(r);
    final route = _routeOf(r);
    final step = stop == null ? null : arrivalStep(_pos(r)!, _pos(stop), route, server: stop['arrival'] as String?);
    final label = stale
        ? 'Last seen ${r['minutesAgo']} min ago'
        : stop == null
            ? (r['name'] as String).split(' ').first
            : step == 'Arrived'
                ? 'Arrived at ${stop['n']}'
                : step == 'Arriving'
                    ? 'Arriving at ${stop['n']}'
                    : 'To ${stop['n']} · ${route == null ? '...' : etaShort(route)}';
    return SidecarLayer(
      key: ValueKey('rider-${r['id']}'),
      point: _pos(r)!,
      heading: _heading[r['id']] ?? 0,
      faded: stale,
      label: label,
      onTap: () => _riderCard(r),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final station = d == null ? null : d['station'] as Map<String, dynamic>;
    final start = station != null && station['lat'] != null
        ? LatLng((station['lat'] as num).toDouble(), (station['lng'] as num).toDouble())
        : qcStart;
    final riders = d == null ? const [] : d['riders'] as List;
    final orders = d == null ? const [] : d['orders'] as List;
    return Scaffold(
      appBar: widget.pushed ? AppBar(title: const Text('Live Map')) : topBar(context, 'Live Map'),
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: start,
            initialZoom: 14,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            onTap: (_, __) => setState(() => _pin = null),
          ),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.mangao.mangao_wrs'),
            for (final r in riders.cast<Map<String, dynamic>>())
              if (((r['minutesAgo'] ?? 99) as num) <= 5 && _nextStop(r) != null)
                routeLayer(_routeOf(r), travelled: _planned[r['id']]?.travelled(_pos(r)!)),
            MarkerLayer(markers: [
              if (station != null && station['lat'] != null)
                Marker(
                  point: start,
                  width: 34,
                  height: 34,
                  child: Tooltip(
                    message: 'Station${(station['address'] ?? '') == '' ? '' : ': ${station['address']}'}',
                    child: const Icon(Icons.store_mall_directory, color: Brand.ink, size: 30),
                  ),
                ),
              for (final o in orders.cast<Map<String, dynamic>>())
                if (o['lat'] != null)
                  Marker(
                    point: LatLng((o['lat'] as num).toDouble(), (o['lng'] as num).toDouble()),
                    width: 30,
                    height: 30,
                    child: GestureDetector(
                      onTap: () => setState(() => _pin = o),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _pin?['id'] == o['id'] ? Brand.blue : Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Brand.blue, width: 2),
                        ),
                        child: Text('${o['n']}',
                            style: TextStyle(fontWeight: FontWeight.w800, color: _pin?['id'] == o['id'] ? Colors.white : Brand.ink)),
                      ),
                    ),
                  ),
            ]),
            for (final r in riders.cast<Map<String, dynamic>>())
              if (r['lat'] != null) _sidecar(r),
            const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
          ],
        ),
        if (_error != null) Positioned(left: 12, right: 12, top: 12, child: MsgBanner(_error!.title, sub: _error!.message)),
        if (d != null && orders.isEmpty)
          const Center(
            child: Card(
              color: Colors.white,
              child: Padding(padding: EdgeInsets.all(16), child: Text('No deliveries running', style: TextStyle(fontWeight: FontWeight.w800))),
            ),
          ),
        if (d != null && orders.isNotEmpty && riders.cast<Map<String, dynamic>>().every((r) => r['lat'] == null))
          const Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Note("Waiting for the rider's location."),
          ),
        if (_pin != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 16,
            child: Box(
              onTap: () => _openOrder((_pin!['id'] as num).toInt()),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_pin!['name'] as String, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    Text('${_pin!['quantity']} ${_pin!['quantity'] == 1 ? 'gallon' : 'gallons'} · ${_step(_pin!)}',
                        style: const TextStyle(color: Brand.muted)),
                    Text(_pin!['address'] as String, style: const TextStyle(fontSize: 12.5)),
                  ]),
                ),
                if (!_rider) const Icon(Icons.chevron_right, color: Brand.blue),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _Points {
  final List<LatLng> list;
  const _Points(this.list);
  LatLng? get firstOrNullPoint => list.isEmpty ? null : list.first;
}
