import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/order.dart';
import '../../services/api.dart';
import '../../services/app_state.dart';
import '../../theme/brand.dart';
import '../../widgets/common.dart';
import '../common/coming_soon.dart';
import '../shell.dart';
import 'admin_order_details.dart';
import '../station/send_out.dart';
import 'order_actions.dart';

/// Admin Orders 1: Order Board. Tabs New, Processing, Out for Delivery, Delivered (today), the Filter for
/// Not delivered, Declined and Cancelled, Live Map, Select, Accept all / Accept selected.
class OrderBoard extends StatefulWidget {
  const OrderBoard({super.key});

  @override
  State<OrderBoard> createState() => _OrderBoardState();
}

class _OrderBoardState extends State<OrderBoard> {
  static const tabs = [('new', 'New'), ('processing', 'Processing'), ('out', 'Out for Delivery'), ('delivered', 'Delivered')];
  static const filters = {
    'All orders': 'all',
    'Not delivered': 'not-delivered',
    'Declined': 'declined',
    'Cancelled': 'cancelled',
  };

  String _view = 'new';
  List<Order> _orders = [];
  Map<String, dynamic> _counts = {};
  bool _loading = true;
  ApiException? _error;
  bool _select = false;
  final Set<int> _picked = {};
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    try {
      final r = await app.api.get('/api/admin/orders?view=$_view');
      if (!mounted) return;
      setState(() {
        _orders = [for (final o in r['orders'] as List) Order.fromJson(o as Map<String, dynamic>)];
        _counts = r['counts'] as Map<String, dynamic>;
        _picked.removeWhere((id) => !_orders.any((o) => o.id == id));
        _error = null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  void _open(String view) {
    setState(() {
      _view = view;
      _select = false;
      _picked.clear();
      _orders = [];
    });
    _load();
  }

  Future<void> _filter() async {
    final current = filters.entries.where((e) => e.value == _view).map((e) => e.key);
    final r = await choose(context, 'Filter', filters.keys.toList(), current: current.isEmpty ? null : current.first, ok: 'Show');
    if (r != null) _open(filters[r]!);
  }

  Future<void> _accept(List<Order> list) async {
    if (await acceptOrders(context, list)) {
      setState(() {
        _select = false;
        _picked.clear();
      });
      await _load();
    }
  }

  Future<void> _send(List<Order> list) async {
    if (await sendOut(context, list)) {
      setState(() {
        _select = false;
        _picked.clear();
      });
      await _load();
    }
  }

  int _count(String key) => ((_counts[key] ?? 0) as num).toInt();

  Widget _chip(String view, String label) {
    final on = _view == view;
    final n = _count(view);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text('$label $n'),
        selected: on,
        showCheckmark: false,
        onSelected: (_) => _open(view),
        selectedColor: Brand.blue,
        backgroundColor: Colors.white,
        side: const BorderSide(color: Brand.blue),
        labelStyle: TextStyle(fontWeight: FontWeight.w700, color: on ? Colors.white : Brand.ink),
        shape: const StadiumBorder(),
      ),
    );
  }

  Widget? _bottom() {
    if (_view == 'new' && _orders.isNotEmpty) {
      if (_select) {
        final list = _orders.where((o) => _picked.contains(o.id)).toList();
        return Bottom([Btn('Accept selected (${list.length})', list.isEmpty ? null : () => _accept(list))]);
      }
      return Bottom([Btn('Accept all (${_orders.length})', () => _accept(_orders))]);
    }
    if (_view == 'processing' && _orders.isNotEmpty) {
      if (_select) {
        final list = _orders.where((o) => _picked.contains(o.id)).toList();
        return Bottom([Btn('Mark selected Out for Delivery (${list.length})', list.isEmpty ? null : () => _send(list))]);
      }
      return Bottom([Btn('Mark all Out for Delivery (${_orders.length})', () => _send(_orders))]);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final filterName = filters.entries.where((e) => e.value == _view).map((e) => e.key);
    return Scaffold(
      appBar: topBar(context, 'Order Board'),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 24), children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [for (final (v, l) in tabs) _chip(v, l)]),
          ),
          const Gap(8),
          Row(children: [
            Expanded(
              child: Btn('Live Map', () => go(context, const ComingSoon('Live Map', step: 34, what: 'Rider location and order pins', pushed: true)),
                  outline: true, small: true),
            ),
            const Gap(8),
            if (_view == 'new' || _view == 'processing') ...[
              Expanded(
                child: Btn(_select ? 'Done' : 'Select', () => setState(() {
                      _select = !_select;
                      _picked.clear();
                    }), outline: !_select, small: true),
              ),
              const Gap(8),
            ],
            Expanded(child: Btn('Filter', _filter, outline: filterName.isEmpty, small: true)),
          ]),
          if (filterName.isNotEmpty) ...[
            const Gap(10),
            Row(children: [
              Expanded(child: Text('Filter: ${filterName.first}', style: const TextStyle(fontWeight: FontWeight.w800))),
              LinkText('Back to New', () => _open('new')),
            ]),
          ],
          if (_count('notDelivered') > 0 && _view != 'not-delivered') ...[
            const Gap(10),
            MsgBanner(
              '${_count('notDelivered')} not delivered',
              sub: 'Re-deliver or cancel them. Open Filter > Not delivered.',
              action: TextButton(
                onPressed: () => _open('not-delivered'),
                child: const Text('Open', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
          const Gap(10),
          if (_error != null) MsgBanner(_error!.title, sub: _error!.message),
          if (_loading && _orders.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())),
          if (!_loading && _orders.isEmpty && _error == null) Empty(_emptyText()),
          for (final o in _orders)
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
                  await go(context, AdminOrderDetails(orderId: o.id));
                  await _load(quiet: true);
                },
              ),
            ),
        ]),
      ),
      bottomNavigationBar: _bottom(),
    );
  }

  String _emptyText() => switch (_view) {
        'new' => 'No new orders right now',
        'processing' => 'Nothing in Processing',
        'out' => 'No orders out for delivery',
        'delivered' => 'Nothing delivered yet today',
        'not-delivered' => 'No not-delivered orders',
        'declined' => 'No declined orders today',
        'cancelled' => 'No cancelled orders today',
        _ => 'No orders today',
      };
}

/// One order card on the board (Admin Orders 1).
class BoardCard extends StatelessWidget {
  final Order order;
  final bool? picked; // null = not selecting
  final VoidCallback onTap;
  const BoardCard(this.order, {super.key, this.picked, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final o = order;
    final line2 = [if (o.km != null) '${o.km} km away', o.sourceText].join(' · ');
    final footer = switch (o.status) {
      'New' => 'Delivery time: set when accepted',
      'Processing' || 'Out for Delivery' => 'Rider: ${o.riderShort} · Delivery ${o.estText}',
      'Delivered' => 'Delivered ${o.deliveredClock} · ${o.riderShort}',
      'Not Delivered' => [if (o.reason.isNotEmpty) o.reason, o.riderShort].join(' · '),
      'Declined' => 'Reason: ${o.reason}',
      _ => o.status,
    };
    final Widget? tag = switch (o.status) {
      'New' => null,
      'Delivered' => Tag(o.payment == 'Paid at station' ? 'Paid at station' : o.paymentStatus, filled: o.paymentStatus == 'Unpaid'),
      'Not Delivered' => const Tag('Not delivered', filled: true),
      'Declined' || 'Cancelled' => Tag(o.status, filled: true, red: true),
      _ => Tag(o.status == 'Out for Delivery' ? 'Out for delivery' : o.status, filled: o.status == 'Out for Delivery'),
    };
    return Box(
      onTap: onTap,
      tint: picked == true,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (picked != null)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Icon(picked! ? Icons.check_box : Icons.check_box_outline_blank, color: Brand.blue),
          ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(o.name.isEmpty ? 'Guest' : o.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              if (tag != null) tag,
            ]),
            const Gap(2),
            Text(o.summary),
            Text(line2, style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
            const Divider(height: 14),
            Row(children: [
              Expanded(child: Text(footer, style: const TextStyle(fontSize: 12.5, color: Brand.muted))),
              const Icon(Icons.chevron_right, color: Brand.blue, size: 20),
            ]),
          ]),
        ),
      ]),
    );
  }
}
