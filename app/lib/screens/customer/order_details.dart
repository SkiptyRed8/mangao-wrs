import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/order.dart';
import '../../services/api.dart';
import '../../services/app_state.dart';
import '../../services/realtime.dart';
import '../../theme/brand.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../../widgets/map_widgets.dart';
import 'order_form.dart';

/// Customer 4 and 5: Order Details. The 5 steps (Waiting for order to be accepted, Order accepted,
/// Processing, Out for Delivery, Delivered), the processing message with the estimated delivery time,
/// Call station, and Cancel order while it waits to be accepted. Declined, Cancelled and Not delivered
/// show a tag, the reason or the rider's note.
class CustomerOrderDetails extends StatefulWidget {
  final int orderId;
  const CustomerOrderDetails({super.key, required this.orderId});

  @override
  State<CustomerOrderDetails> createState() => _CustomerOrderDetailsState();
}

class _CustomerOrderDetailsState extends State<CustomerOrderDetails> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();
  Timer? _poll;
  StreamSubscription<RtEvent>? _live;
  bool _busy = false;

  static const steps = ['Waiting for order to be accepted', 'Order accepted', 'Processing', 'Out for Delivery', 'Delivered'];

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => _loader.currentState?.reload());
    _live = realtime.listen((_) => _loader.currentState?.reload(), names: const {'order', 'location'});
  }

  @override
  void dispose() {
    _poll?.cancel();
    _live?.cancel();
    super.dispose();
  }

  Future<void> _cancel(Order o) async {
    final ok = await confirm(
      context,
      'Cancel order?',
      sub: 'Are you sure you want to cancel this order? The station will be told, and this cannot be undone.',
      cancel: 'Keep order',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await app.api.post('/api/orders/${o.id}/cancel');
      if (mounted) toast(context, (r['message'] ?? 'Order cancelled') as String);
    } on ApiException catch (e) {
      if (mounted) toast(context, '${e.title}. ${e.message}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
      await _loader.currentState?.reload();
    }
  }

  /// Which of the 5 steps is current (the ones before it are done).
  static int current(Order o) => switch (o.status) {
        'New' => 0,
        'Processing' => 2,
        'Out for Delivery' => 3,
        _ => 4,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Order Details')),
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () => app.api.get('/api/orders/${widget.orderId}'),
        builder: (context, d, reload) {
          final o = Order.fromJson(d['order'] as Map<String, dynamic>);
          final phone = (d['stationPhone'] ?? '') as String;
          final tracked = ['New', 'Processing', 'Out for Delivery', 'Delivered'].contains(o.status);
          final what = o.type == 'Package' ? 'package' : 'refill';
          return Column(children: [
            Expanded(
              child: Body([
                if (tracked)
                  StatusSteps(steps, current(o),
                      done: o.status == 'Delivered',
                      lastSub: o.status == 'Delivered' ? (o.paymentStatus == 'Unpaid' ? 'Unpaid' : 'Paid') : null)
                else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Tag(o.status == 'Not Delivered' ? 'Not delivered' : o.status, filled: true, red: o.status != 'Not Delivered'),
                  ),
                const Gap(10),
                if (o.status == 'Processing')
                  Note('Your $what order is processing. Please wait for the status of your order.'),
                if (o.status == 'Out for Delivery')
                  Note((o.batchSize ?? 1) > 1 ? 'Your rider is handling multiple orders.' : 'Your rider is on the way.'),
                Box(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Label('Your order'),
                    const Gap(4),
                    Row(children: [
                      Expanded(child: Text(o.summary, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                      Text(peso(o.total), style: const TextStyle(fontWeight: FontWeight.w800, fontFamily: 'monospace')),
                    ]),
                    const Gap(2),
                    Text(o.address),
                    if (o.landmark.isNotEmpty) Text(o.landmark, style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
                    const Gap(2),
                    const Text('Cash on delivery · Pay once delivered', style: TextStyle(color: Brand.muted, fontSize: 12.5)),
                  ]),
                ),
                if ((o.status == 'Processing' || o.status == 'Out for Delivery') && o.estText.isNotEmpty) ...[
                  const Gap(10),
                  Box(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Label('Estimated Delivery'),
                      const Gap(4),
                      Text(o.estText.startsWith('by') ? 'By ${o.estText.substring(3)}' : o.estText,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    ]),
                  ),
                ],
                if (o.status == 'Out for Delivery') ...[
                  const Gap(10),
                  RiderMap(order: o, rider: d['rider'] as Map<String, dynamic>?),
                ],
                if (o.status == 'Declined') ...[
                  const Gap(10),
                  Box(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Label('Reason'),
                      const Gap(4),
                      Text(o.reason.isEmpty ? '-' : o.reason),
                    ]),
                  ),
                  const Gap(14),
                  Btn('Order again', () async {
                    final placed = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => OrderForm(again: o)));
                    if (placed == true && context.mounted) Navigator.pop(context);
                  }),
                ],
                if (o.status == 'Not Delivered') ...[
                  if (o.reason.isNotEmpty) ...[
                    const Gap(10),
                    Box(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Label("Rider's note"),
                        const Gap(4),
                        Text(o.reason),
                      ]),
                    ),
                  ],
                  const Gap(10),
                  const Note('The station will contact you to deliver again or cancel.'),
                ],
              ]),
            ),
            if (o.status != 'Declined' && o.status != 'Cancelled')
              Bottom([
                Btn('Call station', () => callNumber(context, phone), outline: true),
                if (o.status == 'New') ...[
                  const Gap(8),
                  Btn('Cancel order', _busy ? null : () => _cancel(o), outline: true, busy: _busy),
                ],
              ]),
          ]);
        },
      ),
    );
  }
}

/// The vertical status steps with check marks (Customer 4, 5).
class StatusSteps extends StatelessWidget {
  final List<String> steps;
  final int current;
  final bool done;
  final String? lastSub;
  const StatusSteps(this.steps, this.current, {super.key, this.done = false, this.lastSub});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      for (var i = 0; i < steps.length; i++)
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 26,
              child: Column(children: [
                Icon(
                  i < current || (done && i == current)
                      ? Icons.check_circle
                      : (i == current ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                  color: i <= current ? Brand.blue : Brand.muted,
                  size: 22,
                ),
                if (i < steps.length - 1)
                  Expanded(child: Container(width: 2, color: i < current ? Brand.blue : Brand.soft)),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 1, bottom: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    steps[i],
                    style: TextStyle(
                      fontWeight: i == current ? FontWeight.w800 : FontWeight.w500,
                      color: i <= current ? Brand.ink : Brand.muted,
                    ),
                  ),
                  if (i == steps.length - 1 && lastSub != null)
                    Text(lastSub!, style: const TextStyle(fontSize: 12, color: Brand.muted)),
                ]),
              ),
            ),
          ]),
        ),
    ]);
  }
}

/// Customer 5 / 11: live map with the rider (blue dot) and the delivery pin while Out for Delivery.
class RiderMap extends StatelessWidget {
  final Order order;
  final Map<String, dynamic>? rider;
  const RiderMap({super.key, required this.order, this.rider});

  @override
  Widget build(BuildContext context) {
    final home = order.lat != null ? LatLng(order.lat!, order.lng!) : null;
    final r = rider == null ? null : LatLng((rider!['lat'] as num).toDouble(), (rider!['lng'] as num).toDouble());
    final center = r ?? home ?? qcStart;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (r == null)
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Text("Waiting for the rider's location...", style: TextStyle(color: Brand.muted, fontSize: 12.5)),
        ),
      SizedBox(
        height: 210,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: FlutterMap(
            key: ValueKey('${r?.latitude},${r?.longitude}'),
            options: MapOptions(initialCenter: center, initialZoom: 15),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.mangao.mangao_wrs'),
              MarkerLayer(markers: [
                if (home != null)
                  Marker(point: home, width: 36, height: 36, alignment: Alignment.topCenter, child: const Icon(Icons.location_on, color: Brand.ink, size: 36)),
                if (r != null)
                  Marker(
                    point: r,
                    width: 26,
                    height: 26,
                    child: Container(
                      decoration: BoxDecoration(color: Brand.blue, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
                    ),
                  ),
              ]),
              const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
            ],
          ),
        ),
      ),
    ]);
  }
}
