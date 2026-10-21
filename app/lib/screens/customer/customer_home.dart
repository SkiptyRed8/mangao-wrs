import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/order.dart';
import '../../services/app_state.dart';
import '../../services/realtime.dart';
import '../../theme/brand.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../shell.dart';
import 'order_details.dart';
import 'order_form.dart';

/// Customer 2: Home. Your current order (status and estimated delivery time), Order Now, Price List.
class CustomerHome extends StatefulWidget {
  const CustomerHome({super.key});

  @override
  State<CustomerHome> createState() => _CustomerHomeState();
}

class _CustomerHomeState extends State<CustomerHome> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();
  Timer? _poll;
  StreamSubscription<RtEvent>? _live;

  @override
  void initState() {
    super.initState();
    // Status changes show up without pulling down (live updates come in step 35).
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => _loader.currentState?.reload());
    _live = realtime.listen((_) => _loader.currentState?.reload(), names: const {'order', 'refresh'});
  }

  @override
  void dispose() {
    _poll?.cancel();
    _live?.cancel();
    super.dispose();
  }

  Future<void> _order() async {
    final placed = await go<bool>(context, const OrderForm());
    if (placed == true) await _loader.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: topBar(context, 'Home'),
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () => app.api.get('/api/orders/home'),
        builder: (context, d, reload) {
          final active = [for (final o in d['active'] as List) Order.fromJson(o as Map<String, dynamic>)];
          final prices = d['prices'] as Map<String, dynamic>;
          return Body([
            if (app.guest) const Note('Orders kept on this phone only'),
            for (final o in active)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ActiveOrderCard(o, onTap: () async {
                  await go(context, CustomerOrderDetails(orderId: o.id));
                  await reload();
                }),
              ),
            Btn('Order Now', _order),
            const Gap(12),
            Box(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Label('Price List'),
                const Gap(6),
                _price('Refill (delivery)', '${peso(prices['delivery'] as num)} per gallon'),
                const Divider(height: 14),
                _price('Package', peso(prices['package'] as num)),
                const Gap(4),
                const Text('Same price for round and slim gallons. Pay once delivered.',
                    style: TextStyle(color: Brand.muted, fontSize: 12)),
              ]),
            ),
          ]);
        },
      ),
    );
  }

  Widget _price(String k, String v) => Row(children: [
        Expanded(child: Text(k, style: const TextStyle(fontWeight: FontWeight.w700))),
        Text(v, style: const TextStyle(fontWeight: FontWeight.w800, fontFamily: 'monospace')),
      ]);
}

/// The status a customer sees (Customer 5).
String customerStatus(Order o) => switch (o.status) {
      'New' => 'Waiting to be accepted',
      'Delivered' => o.paymentStatus == 'Unpaid' ? 'Delivered · Unpaid' : 'Delivered',
      _ => o.shownStatus,
    };

/// Your current order on Customer Home (wireframe: Active Order Card).
class ActiveOrderCard extends StatelessWidget {
  final Order order;
  final VoidCallback onTap;
  const ActiveOrderCard(this.order, {super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final o = order;
    final line = o.status == 'New'
        ? 'Waiting for the station to accept'
        : (o.estText.isEmpty ? '' : 'Estimated delivery: ${o.estText}');
    return Box(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Label('Your current order')),
          Tag(customerStatus(o), filled: o.status != 'New'),
        ]),
        const Gap(6),
        Row(children: [
          Expanded(child: Text(o.summary, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          const Icon(Icons.chevron_right, color: Brand.blue),
        ]),
        if (line.isNotEmpty) ...[
          const Divider(height: 16),
          Text(line, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ]),
    );
  }
}
