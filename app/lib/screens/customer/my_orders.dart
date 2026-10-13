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

/// Customer 6: My Orders. Unpaid Balance (only when something is owed), Active orders and History
/// (delivered, declined, cancelled) with Reorder.
class MyOrders extends StatefulWidget {
  const MyOrders({super.key});

  @override
  State<MyOrders> createState() => _MyOrdersState();
}

class _MyOrdersState extends State<MyOrders> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();
  int _tab = 0; // Active, History
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
    super.dispose();
  }

  static String historyTag(Order o) => switch (o.status) {
        'Delivered' => o.paymentStatus == 'Unpaid' ? 'Delivered (Unpaid)' : 'Delivered (Paid)',
        'Not Delivered' => 'Not delivered',
        _ => o.status,
      };

  static String activeTag(Order o) => switch (o.status) {
        'New' => 'Waiting to be accepted',
        'Out for Delivery' => 'Out for delivery',
        _ => o.status,
      };

  Future<void> _reorder(Order o) async {
    final placed = await go<bool>(context, OrderForm(again: o));
    if (placed == true) {
      setState(() => _tab = 0);
      await _loader.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: topBar(context, 'My Orders'),
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () => app.api.get('/api/orders'),
        builder: (context, d, reload) {
          final all = [for (final o in d['orders'] as List) Order.fromJson(o as Map<String, dynamic>)];
          final owed = ((d['unpaid'] ?? 0) as num).toDouble();
          final active = all.where((o) => o.active).toList();
          final history = all.where((o) => !o.active).toList();
          final list = _tab == 0 ? active : history;
          return Body([
            if (app.guest) const Note('This phone only; lost if the app is deleted'),
            if (owed > 0) ...[
              Box(
                filled: true,
                child: Row(children: [
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Unpaid Balance', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                      Text('Amount owed', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ]),
                  ),
                  Text(peso(owed), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
                ]),
              ),
              const Gap(10),
            ],
            Seg(['Active (${active.length})', 'History'], _tab, (i) => setState(() => _tab = i)),
            const Gap(10),
            if (list.isEmpty) Empty(_tab == 0 ? 'No orders in progress. Tap Home > Order Now.' : 'No past orders yet'),
            for (final o in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Box(
                  onTap: () async {
                    await go(context, CustomerOrderDetails(orderId: o.id));
                    await reload();
                  },
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: _tab == 0
                      ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(o.summary, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                              Text(
                                [
                                  '${dayPh(o.createdAt)} ${clockPh(o.createdAt)}',
                                  if (o.estText.isNotEmpty) o.estText.startsWith('by') ? 'By ${o.estText.substring(3)}' : o.estText,
                                ].join(' · '),
                                style: const TextStyle(color: Brand.muted, fontSize: 12.5),
                              ),
                            ]),
                          ),
                          Tag(activeTag(o), filled: o.status == 'Out for Delivery'),
                        ])
                      : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Row(children: [
                            Expanded(child: Text(dayPh(o.createdAt), style: const TextStyle(color: Brand.muted, fontSize: 12.5))),
                            Tag(historyTag(o), filled: o.status != 'Delivered' || o.paymentStatus == 'Unpaid',
                                red: o.status == 'Declined' || o.status == 'Cancelled'),
                          ]),
                          Row(children: [
                            Expanded(child: Text(o.summary, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                            SmallBtn('Reorder', () => _reorder(o)),
                          ]),
                        ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
