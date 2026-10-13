import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/order.dart';
import '../../services/app_state.dart';
import '../../theme/brand.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../../widgets/map_widgets.dart';
import '../station/send_out.dart';
import 'order_actions.dart';

/// Admin Orders 2-4: Order Details by stage. Order Info (tap the phone number to call, the address for
/// the map pin), Estimated Delivery Time (set automatically), Rider (Change rider while Processing),
/// Payment, Status Timeline; Accept / Decline for new orders.
class AdminOrderDetails extends StatefulWidget {
  final int orderId;
  const AdminOrderDetails({super.key, required this.orderId});

  @override
  State<AdminOrderDetails> createState() => _AdminOrderDetailsState();
}

class _AdminOrderDetailsState extends State<AdminOrderDetails> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _loader.currentState?.reload());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _reload() async => _loader.currentState?.reload();

  static String statusTag(Order o) => switch (o.status) {
        'Delivered' => o.payment == 'Paid at station' ? 'Delivered (Paid at station)' : 'Delivered (${o.paymentStatus})',
        'Not Delivered' => 'Not delivered',
        'Out for Delivery' => 'Out for delivery',
        _ => o.status,
      };

  Widget _box(String label, List<Widget> children, {Widget? action}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Box(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Expanded(child: Label(label)), if (action != null) action]),
            const Gap(4),
            ...children,
          ]),
        ),
      );

  Widget _underlined(String text, VoidCallback onTap, {bool mono = false}) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            text,
            style: TextStyle(
              decoration: TextDecoration.underline,
              decorationColor: Brand.blue,
              color: Brand.blue,
              fontWeight: FontWeight.w700,
              fontFamily: mono ? 'monospace' : null,
            ),
          ),
        ),
      );

  Widget? _bottom(Order o) {
    switch (o.status) {
      case 'New':
        return Bottom([
          Row(children: [
            Expanded(
              child: Btn('Decline', () async {
                if (await declineOrder(context, o)) await _reload();
              }, outline: true),
            ),
            const Gap(10),
            Expanded(
              child: Btn('Accept', () async {
                if (await acceptOrders(context, [o])) await _reload();
              }),
            ),
          ]),
        ]);
      case 'Processing':
        return Bottom([
          Btn('Mark Out for Delivery', () async {
            if (await sendOut(context, [o])) await _reload();
          }),
        ]);
      case 'Out for Delivery':
        // Admin Orders 6: the owner records the delivery when the owner is the rider.
        if (o.riderRole != 'Owner') return null;
        return Bottom([
          Row(children: [
            Expanded(
              child: Btn('Not delivered', () async {
                if (await recordNotDelivered(context, o, path: '/api/admin/orders')) await _reload();
              }, outline: true),
            ),
            const Gap(10),
            Expanded(
              child: Btn('Delivered', () async {
                if (await recordDelivered(context, o, path: '/api/admin/orders')) await _reload();
              }),
            ),
          ]),
        ]);
      case 'Not Delivered':
        return Bottom([
          Row(children: [
            Expanded(
              child: Btn('Cancel order', () async {
                if (await cancelOrder(context, o)) await _reload();
              }, outline: true),
            ),
            const Gap(10),
            Expanded(
              child: Btn('Re-deliver', () async {
                if (await redeliverOrder(context, o)) await _reload();
              }),
            ),
          ]),
        ]);
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(color: Colors.white, child: Loader<Map<String, dynamic>>(
      key: _loader,
      load: () => app.api.get('/api/admin/orders/${widget.orderId}'),
      builder: (context, d, reload) {
        final o = Order.fromJson(d['order'] as Map<String, dynamic>);
        final steps = [for (final t in d['timeline'] as List) TimelineStep.fromJson(t as Map<String, dynamic>)];
        final red = o.status == 'Declined' || o.status == 'Cancelled';
        final lunch = o.estText.contains(' to ');
        return Scaffold(
          appBar: AppBar(title: const Text('Order Details'), actions: [
            PopupMenuButton<String>(
              tooltip: 'Order actions',
              icon: const Icon(Icons.more_vert),
              color: Colors.white,
              onSelected: (v) async {
                var changed = false;
                if (v == 'damaged') comingInStep(context, 41, 'Report damaged gallon');
                if (v == 'rider') changed = await changeRider(context, o);
                if (v == 'cancel') changed = await cancelOrder(context, o);
                if (changed) await reload();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'damaged', child: Text('Report damaged gallon')),
                if (o.status == 'Processing') const PopupMenuItem(value: 'rider', child: Text('Change rider')),
                if (['New', 'Processing', 'Not Delivered'].contains(o.status))
                  const PopupMenuItem(value: 'cancel', child: Text('Cancel order')),
              ],
            ),
          ]),
          body: Body([
            Align(
              alignment: Alignment.centerLeft,
              child: Tag(statusTag(o), filled: o.status != 'New' && o.status != 'Processing', red: red),
            ),
            const Gap(10),
            _box('Order Info', [
              Row(children: [
                Expanded(child: Text(o.summary, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                Text(peso(o.total), style: const TextStyle(fontWeight: FontWeight.w800, fontFamily: 'monospace')),
              ]),
              Text(o.name.isEmpty ? 'Guest' : o.name),
              if (o.phone.isNotEmpty) _underlined(phoneFmt(o.phone), () => callNumber(context, o.phone), mono: true),
              _underlined(o.address, () => showPinSheet(context, address: o.address, lat: o.lat, lng: o.lng)),
              if (o.landmark.isNotEmpty) Text('Landmark: ${o.landmark}', style: const TextStyle(fontSize: 13)),
              if (o.notes.isNotEmpty) Text('Notes: ${o.notes}', style: const TextStyle(fontSize: 13)),
              const Gap(2),
              Text(
                ['Source: ${o.sourceText}', o.paymentText, if (o.km != null) '${o.km} km away'].join(' · '),
                style: const TextStyle(color: Brand.muted, fontSize: 12.5),
              ),
            ]),
            _box('Estimated Delivery Time', [
              if (o.estText.isEmpty)
                const Text('Set when accepted', style: TextStyle(color: Brand.muted))
              else ...[
                Text('Delivery ${o.estText}', style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(
                  lunch ? 'Accepted ${clockPh(o.acceptedAt)} (lunch time rule)' : 'Set automatically',
                  style: const TextStyle(color: Brand.muted, fontSize: 12.5),
                ),
              ],
            ]),
            if (o.riderId != null)
              _box(
                'Rider',
                [Text(o.riderRole == 'Owner' ? 'Me (Owner)' : (o.riderName ?? ''), style: const TextStyle(fontWeight: FontWeight.w800))],
                action: o.status == 'Processing'
                    ? FilledButton(
                        onPressed: () async {
                          if (await changeRider(context, o)) await reload();
                        },
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 12)),
                        child: const Text('Change rider', style: TextStyle(fontSize: 13)),
                      )
                    : null,
              ),
            if (o.status == 'Delivered')
              _box(
                'Payment',
                [
                  Text(
                    o.paymentStatus == 'Unpaid' ? 'Unpaid: owes ${peso(o.total)}' : (o.payment == 'Paid at station' ? 'Paid at station' : 'Paid'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
                action: o.paymentStatus == 'Unpaid'
                    ? SmallBtn('Mark paid', () async {
                        if (await markPaid(context, o)) await reload();
                      })
                    : null,
              ),
            const Section('Status Timeline'),
            TimelineList(steps),
          ]),
          bottomNavigationBar: _bottom(o),
        );
      },
    ));
  }
}

/// Status Timeline: every step with date, time, who did it and the note.
class TimelineList extends StatelessWidget {
  final List<TimelineStep> steps;
  const TimelineList(this.steps, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      for (var i = 0; i < steps.length; i++)
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 20,
              child: Column(children: [
                Container(
                  width: 11,
                  height: 11,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: const BoxDecoration(color: Brand.blue, shape: BoxShape.circle),
                ),
                if (i < steps.length - 1) Expanded(child: Container(width: 2, color: Brand.blue)),
              ]),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(steps[i].status, style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(
                    [dateTimePh(steps[i].at), steps[i].by, if (steps[i].note.isNotEmpty) steps[i].note].join(' · '),
                    style: const TextStyle(fontSize: 12, color: Brand.muted),
                  ),
                ]),
              ),
            ),
          ]),
        ),
    ]);
  }
}
