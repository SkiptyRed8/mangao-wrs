import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/order.dart';
import '../../services/app_state.dart';
import '../../services/realtime.dart';
import '../../theme/brand.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../../widgets/map_widgets.dart';
import '../common/damage.dart';
import '../shell.dart';
import '../station/send_out.dart';

/// Rider 1-4: Deliveries. Orders show here when the owner or staff mark them Out for Delivery
/// (no Start button). Call, Directions, Delivered (Paid / Unpaid), Not delivered, Report damaged gallon.
/// The owner sees the same list in the Delivery view (orders where the owner is the rider).
class RiderDeliveries extends StatefulWidget {
  const RiderDeliveries({super.key});

  @override
  State<RiderDeliveries> createState() => _RiderDeliveriesState();
}

class _RiderDeliveriesState extends State<RiderDeliveries> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();
  Timer? _poll;
  StreamSubscription<RtEvent>? _live;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => _loader.currentState?.reload());
    _live = realtime.listen((_) => _loader.currentState?.reload(), names: const {'order'});
  }

  @override
  void dispose() {
    _poll?.cancel();
    _live?.cancel();
    _gps?.cancel();
    super.dispose();
  }

  Future<void> _reload() async => _loader.currentState?.reload();

  // Rider 5: Location Sharing. On by itself while orders are out; sends the phone's location every
  // 15 seconds; off after the last order (the server says sharing: false).
  Timer? _gps;
  String? _gpsNote;
  bool _gpsProblem = false;

  void _sharing(bool on) {
    if (on && _gps == null) {
      _send();
      _gps = Timer.periodic(const Duration(seconds: 15), (_) => _send());
    } else if (!on && _gps != null) {
      _gps?.cancel();
      _gps = null;
    }
  }

  Future<void> _send() async {
    try {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
        throw Exception('Allow location so the owner and customers can see you.');
      }
      final pos = await Geolocator.getCurrentPosition();
      final r = await app.api.post('/api/rider/location', {'lat': pos.latitude, 'lng': pos.longitude});
      if (!mounted) return;
      if (r['sharing'] != true) _sharing(false);
      setState(() {
        _gpsProblem = false;
        _gpsNote = 'On while orders are out · sent ${timeFmt(DateTime.now())}';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _gpsProblem = true;
          _gpsNote = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: topBar(context, 'Deliveries'),
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () => app.api.get('/api/rider/deliveries'),
        builder: (context, d, reload) {
          final orders = [for (final o in d['orders'] as List) Order.fromJson(o as Map<String, dynamic>)];
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _sharing(orders.isNotEmpty);
          });
          if (orders.isEmpty) {
            return const Body([
              Padding(
                padding: EdgeInsets.only(top: 60),
                child: Column(children: [
                  Icon(Icons.local_shipping_outlined, size: 48, color: Brand.soft),
                  Gap(10),
                  Text('No orders on the road', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  Gap(4),
                  Text('Orders show here when the owner or staff mark them Out for Delivery.',
                      textAlign: TextAlign.center, style: TextStyle(color: Brand.muted)),
                ]),
              ),
            ]);
          }
          return Body([
            MsgBanner(_gpsProblem ? 'Location Sharing: turn on location' : 'Location Sharing',
                sub: _gpsNote ?? 'On while orders are out', info: !_gpsProblem),
            Row(children: [
              Expanded(child: Text('Out for Delivery (${orders.length})', style: const TextStyle(fontWeight: FontWeight.w800))),
              Text('Sent out ${(d['sentClock'] ?? '') as String}', style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
            ]),
            const Gap(8),
            for (final o in orders)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: DeliveryCard(o, onDone: _reload),
              ),
          ]);
        },
      ),
    );
  }
}

/// One order on the road (Rider 1).
class DeliveryCard extends StatelessWidget {
  final Order order;
  final Future<void> Function() onDone;
  const DeliveryCard(this.order, {super.key, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final o = order;
    final paidAlready = o.paymentStatus == 'Paid';
    final payLine = paidAlready ? '' : ' · ${o.payment == 'COD' ? 'Cash on delivery' : o.paymentText}';
    return Box(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(o.name.isEmpty ? 'Guest' : o.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
          if (paidAlready) Tag(o.payment == 'Paid at station' ? 'Paid at station' : 'Paid'),
        ]),
        const Gap(2),
        Text(o.address, style: const TextStyle(color: Brand.muted)),
        if (o.landmark.isNotEmpty) Text(o.landmark, style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
        if (o.notes.isNotEmpty) Text('Notes: ${o.notes}', style: const TextStyle(fontSize: 12.5)),
        const Gap(2),
        Text('${o.quantity} ${o.quantity == 1 ? 'gallon' : 'gallons'} · ${peso(o.total)}$payLine'),
        const Gap(10),
        Row(children: [
          Expanded(child: Btn('Call', () => callNumber(context, o.phone), outline: true, small: true)),
          const Gap(8),
          Expanded(
            child: Btn('Directions', () => openInMaps(context, lat: o.lat, lng: o.lng, address: o.address), outline: true, small: true),
          ),
        ]),
        const Gap(8),
        Row(children: [
          Expanded(
            child: Btn('Delivered', () async {
              if (await recordDelivered(context, o)) await onDone();
            }, small: true),
          ),
          const Gap(8),
          Expanded(
            child: Btn('Not delivered', () async {
              if (await recordNotDelivered(context, o)) await onDone();
            }, outline: true, small: true),
          ),
        ]),
        const Gap(4),
        Center(
          child: LinkText('Report damaged gallon', () async {
            if (await reportDamaged(context, o)) await onDone();
          }),
        ),
      ]),
    );
  }
}
