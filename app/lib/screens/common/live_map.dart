import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/api.dart';
import '../../services/app_state.dart';
import '../../services/realtime.dart';
import '../../theme/brand.dart';
import '../../widgets/common.dart';
import '../../widgets/map_widgets.dart';
import '../owner/admin_order_details.dart';
import '../shell.dart';
import '../staff/staff_todo.dart';

/// Admin Orders 7 / Staff 9: Live Map. The rider marker (grey with "Last seen" when it has not moved for
/// 5 minutes) and numbered pins for the orders on the road. Tap the rider for the rider card (Call, the
/// orders on board); tap a pin for the order. Staff see and call only.
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
              r['lat'] = e.data['lat'];
              r['lng'] = e.data['lng'];
              r['minutesAgo'] = 0;
            }
          }
        });
      } else {
        _load();
      }
    }, names: const {'order', 'location'});
  }

  @override
  void dispose() {
    _poll?.cancel();
    _live?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await app.api.get('/api/map');
      if (!mounted) return;
      setState(() {
        _data = r;
        _error = null;
      });
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

  void _openOrder(int id) {
    if (app.isOwner && app.view == AppView.admin) {
      go(context, AdminOrderDetails(orderId: id));
    } else {
      go(context, StaffOrderDetails(orderId: id));
    }
  }

  void _riderCard(Map<String, dynamic> r) {
    final orders = [for (final o in _data!['orders'] as List) o as Map<String, dynamic>].where((o) => o['riderId'] == r['id']).toList();
    final ago = r['minutesAgo'] == null ? 'No location yet' : (r['minutesAgo'] == 0 ? 'Updated just now' : 'Updated ${r['minutesAgo']} min ago');
    sheet<void>(
      context,
      r['name'] as String,
      sub: '${orders.length} ${orders.length == 1 ? 'order' : 'orders'} on board · $ago',
      (c, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Btn('Call', () => callNumber(context, (r['phone'] ?? '') as String), outline: true, icon: Icons.call),
        const Gap(12),
        for (final o in orders)
          RowLink(
            '${o['n']}  ${o['name']}',
            sub: '${o['quantity']} ${o['quantity'] == 1 ? 'gallon' : 'gallons'} · Out for delivery',
            onTap: () {
              Navigator.pop(c);
              _openOrder((o['id'] as num).toInt());
            },
          ),
      ]),
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
              for (final r in riders.cast<Map<String, dynamic>>())
                if (r['lat'] != null)
                  Marker(
                    point: LatLng((r['lat'] as num).toDouble(), (r['lng'] as num).toDouble()),
                    width: 120,
                    height: 64,
                    child: GestureDetector(
                      onTap: () => _riderCard(r),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        CircleAvatar(
                          radius: 17,
                          backgroundColor: ((r['minutesAgo'] ?? 99) as num) > 5 ? Brand.muted : Brand.blue,
                          child: Text((r['name'] as String).substring(0, 1),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                        ),
                        if (((r['minutesAgo'] ?? 99) as num) > 5)
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4), border: Border.all(color: Brand.muted)),
                            child: Text('Last seen ${r['minutesAgo']} min ago', style: const TextStyle(fontSize: 10)),
                          ),
                      ]),
                    ),
                  ),
            ]),
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
            child: Note("Waiting for the rider's location. It shows when the rider opens Deliveries with location on."),
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
                    Text('${_pin!['quantity']} ${_pin!['quantity'] == 1 ? 'gallon' : 'gallons'} · Out for delivery',
                        style: const TextStyle(color: Brand.muted)),
                    Text(_pin!['address'] as String, style: const TextStyle(fontSize: 12.5)),
                  ]),
                ),
                const Icon(Icons.chevron_right, color: Brand.blue),
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
