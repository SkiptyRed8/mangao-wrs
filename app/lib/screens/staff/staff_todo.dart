import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/order.dart';
import '../../services/app_state.dart';
import '../../services/realtime.dart';
import '../../theme/brand.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../owner/order_board.dart';
import '../shell.dart';
import '../station/log_forms.dart';
import '../station/send_out.dart';
import '../station/tank_card.dart';

/// Staff 1-3: To Do. Tank Counter (view only), Log Walk-in, Log Delivery, the orders in Processing
/// (refill and seal; no status to tap), and Mark Out for Delivery (one, several or all).
/// The owner sees the same page in the Staff view.
class StaffTodo extends StatefulWidget {
  const StaffTodo({super.key});

  @override
  State<StaffTodo> createState() => _StaffTodoState();
}

class _StaffTodoState extends State<StaffTodo> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();
  Timer? _poll;
  StreamSubscription<RtEvent>? _live;
  bool _select = false;
  final Set<int> _picked = {};

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => _loader.currentState?.reload());
    _live = realtime.listen((_) => _loader.currentState?.reload(), names: const {'order', 'refresh'});
  }

  @override
  void dispose() {
    _poll?.cancel();
    _live?.cancel();
    super.dispose();
  }

  Future<void> _reload() async => _loader.currentState?.reload();

  Future<void> _send(List<Order> list) async {
    if (await sendOut(context, list)) {
      setState(() {
        _select = false;
        _picked.clear();
      });
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: topBar(context, 'To Do'),
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () => app.api.get('/api/work/todo'),
        builder: (context, d, reload) {
          final list = [for (final o in d['processing'] as List) Order.fromJson(o as Map<String, dynamic>)];
          _picked.removeWhere((id) => !list.any((o) => o.id == id));
          final picked = list.where((o) => _picked.contains(o.id)).toList();
          return Column(children: [
            Expanded(
              child: Body([
                TankCard.fromJson(d['tank'] as Map<String, dynamic>),
                const Gap(10),
                StationButtons(onSaved: _reload),
                const Gap(14),
                Row(children: [
                  Expanded(child: Text('Processing (${list.length})', style: const TextStyle(fontWeight: FontWeight.w800))),
                  if (list.isNotEmpty)
                    LinkText(_select ? 'Done' : 'Select', () => setState(() {
                          _select = !_select;
                          _picked.clear();
                        })),
                ]),
                Text(_select ? 'Tick cards to select' : 'Refill and seal; no status to tap',
                    style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
                const Gap(8),
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 30),
                    child: Column(children: [
                      Text('No orders in Processing', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      Gap(4),
                      Text('Accepted and logged delivery orders show here.', style: TextStyle(color: Brand.muted)),
                    ]),
                  ),
                for (final o in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: BoardCard(
                      o,
                      picked: _select ? _picked.contains(o.id) : null,
                      onTap: () async {
                        if (_select) {
                          setState(() => _picked.contains(o.id) ? _picked.remove(o.id) : _picked.add(o.id));
                          return;
                        }
                        await go(context, StaffOrderDetails(orderId: o.id));
                        await reload();
                      },
                    ),
                  ),
              ]),
            ),
            if (list.isNotEmpty)
              Bottom([
                _select
                    ? Btn('Mark selected Out for Delivery (${picked.length})', picked.isEmpty ? null : () => _send(picked))
                    : Btn('Mark all Out for Delivery (${list.length})', () => _send(list)),
              ]),
          ]);
        },
      ),
    );
  }
}

/// Staff 5 / Staff 2: Order Details (view only) with Mark Out for Delivery and Report damaged gallon.
class StaffOrderDetails extends StatefulWidget {
  final int orderId;
  const StaffOrderDetails({super.key, required this.orderId});

  @override
  State<StaffOrderDetails> createState() => _StaffOrderDetailsState();
}

class _StaffOrderDetailsState extends State<StaffOrderDetails> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Order Details')),
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () => app.api.get('/api/work/orders/${widget.orderId}'),
        builder: (context, d, reload) {
          final o = Order.fromJson(d['order'] as Map<String, dynamic>);
          return Body([
            Align(alignment: Alignment.centerLeft, child: Tag(o.status == 'Out for Delivery' ? 'Out for delivery' : o.status)),
            const Gap(10),
            Box(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Label('Order info'),
                KV('Customer name', o.name.isEmpty ? 'Guest' : o.name),
                KV('Gallons', '${o.quantity}'),
                KV('Refill or Package', o.type),
                KV('Source', o.sourceText),
                KV('Payment', o.payment == 'COD' ? 'Cash on delivery' : o.paymentText),
                KV('Amount', peso(o.total)),
                KV('Rider', riderLabel(o)),
                if (o.estText.isNotEmpty) KV('Delivery', o.estText),
                KV('Address', o.address),
                if (o.notes.isNotEmpty) KV('Notes', o.notes),
                KV('Phone', phoneFmt(o.phone), last: true),
              ]),
            ),
            const Gap(14),
            if (o.status == 'Processing') ...[
              Btn('Mark Out for Delivery', () async {
                if (await sendOut(context, [o]) && context.mounted) Navigator.pop(context);
              }),
              const Gap(),
            ],
            Btn('Report damaged gallon', () => toast(context, 'Report damaged gallon comes in step 41'), outline: true),
          ]);
        },
      ),
    );
  }
}
