import 'package:flutter/material.dart';

import '../../models/order.dart';
import '../../services/app_state.dart';
import '../../theme/brand.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../shell.dart';
import '../staff/staff_todo.dart';

/// Staff 6: Done Today. Gallons processed today (counted today) and the orders logged and sent out
/// today, newest first (view only).
class StaffDoneToday extends StatelessWidget {
  const StaffDoneToday({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: topBar(context, 'Done Today'),
      body: Loader<Map<String, dynamic>>(
        load: () => app.api.get('/api/work/done-today'),
        builder: (context, d, reload) {
          final items = [for (final x in d['items'] as List) x as Map<String, dynamic>];
          return Body([
            Box(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Expanded(child: Label('Gallons processed today')),
                  Text('Counted today', style: TextStyle(color: Brand.muted, fontSize: 12)),
                ]),
                const Gap(6),
                Text('${d['gallons']}', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
              ]),
            ),
            const Section('Orders list'),
            const Text('Logged and sent out today, newest first', style: TextStyle(color: Brand.muted, fontSize: 12.5)),
            const Gap(8),
            if (items.isEmpty) const Empty('Nothing logged or sent out yet today'),
            for (final i in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Box(
                  onTap: () => go(context, StaffOrderDetails(orderId: (i['id'] as num).toInt())),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(i['name'] as String, style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text('${i['quantity']} ${i['quantity'] == 1 ? 'gallon' : 'gallons'} · ${i['what']}',
                            style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
                      ]),
                    ),
                    Text(i['clock'] as String, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700)),
                    const Icon(Icons.chevron_right, color: Brand.blue),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

/// Rider 6: Done Today. Delivered today, Paid and Unpaid totals, and the orders delivered today (view only).
class RiderDoneToday extends StatelessWidget {
  const RiderDoneToday({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: topBar(context, 'Done Today'),
      body: Loader<Map<String, dynamic>>(
        load: () => app.api.get('/api/rider/done-today'),
        builder: (context, d, reload) {
          final orders = [for (final o in d['orders'] as List) Order.fromJson(o as Map<String, dynamic>)];
          return Body([
            Box(
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Label('Delivered today'),
                    const Gap(6),
                    Text('${d['delivered']}', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
                  ]),
                ),
                const Text('Number of orders delivered', style: TextStyle(color: Brand.muted, fontSize: 12)),
              ]),
            ),
            const Section('Paid and Unpaid totals'),
            Row(children: [
              Expanded(
                child: Box(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Paid', style: TextStyle(color: Brand.muted)),
                    Text(peso(d['paidAmount'] as num), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
                    const Text('Amount marked Paid', style: TextStyle(color: Brand.muted, fontSize: 11.5)),
                  ]),
                ),
              ),
              const Gap(8),
              Expanded(
                child: Box(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Unpaid', style: TextStyle(color: Brand.muted)),
                    Text('${d['unpaidCount']} ${d['unpaidCount'] == 1 ? 'order' : 'orders'}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
                    const Text('Orders marked Unpaid', style: TextStyle(color: Brand.muted, fontSize: 11.5)),
                  ]),
                ),
              ),
            ]),
            const Section('Orders list'),
            const Text('Delivered today, newest first', style: TextStyle(color: Brand.muted, fontSize: 12.5)),
            const Gap(8),
            if (orders.isEmpty) const Empty('Nothing delivered yet today'),
            for (final o in orders)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Box(
                  onTap: () => go(context, RiderOrderView(o)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(o.name.isEmpty ? 'Guest' : o.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(o.address, style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(peso(o.total), style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800)),
                      const Gap(2),
                      Tag(o.paymentStatus == 'Unpaid' ? 'Unpaid' : 'Paid', filled: o.paymentStatus == 'Unpaid'),
                    ]),
                    const Icon(Icons.chevron_right, color: Brand.blue),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

/// Rider 6: Order Details (view only).
class RiderOrderView extends StatelessWidget {
  final Order o;
  const RiderOrderView(this.o, {super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Order Details')),
        body: Body([
          Box(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Label('Order info'),
              KV('Customer name', o.name.isEmpty ? 'Guest' : o.name),
              KV('Address', o.address),
              KV('Gallons', '${o.quantity}'),
              KV('Refill or Package', o.type),
              KV('Amount', peso(o.total)),
              KV('Payment', o.paymentStatus == 'Unpaid' ? 'Unpaid' : (o.payment == 'Paid at station' ? 'Paid at station' : 'Paid')),
              KV('Delivered', o.deliveredClock, last: true),
            ]),
          ),
        ]),
      );
}
