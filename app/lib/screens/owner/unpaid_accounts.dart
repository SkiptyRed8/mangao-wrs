import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/api.dart';
import '../../services/app_state.dart';
import '../../services/realtime.dart';
import '../../theme/brand.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../../widgets/map_widgets.dart';
import 'admin_order_details.dart';
import 'export_report.dart';

String _money(num v) => peso(v);

/// Search box used by Unpaid Accounts and Customers.
class SearchBox extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  const SearchBox(this.controller, {super.key, required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search, color: Brand.blue),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Clear',
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Brand.blue)),
        ),
      );
}

/// Admin Sales 3: Unpaid Accounts. Total owed by everyone, then each customer who owes (name, phone,
/// number of unpaid orders, amount). Search by name or phone. Tap a customer for their unpaid orders.
class UnpaidAccounts extends StatefulWidget {
  const UnpaidAccounts({super.key});

  @override
  State<UnpaidAccounts> createState() => _UnpaidAccountsState();
}

class _UnpaidAccountsState extends State<UnpaidAccounts> {
  final _q = TextEditingController();
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();
  Timer? _wait;
  StreamSubscription<RtEvent>? _live;

  @override
  void initState() {
    super.initState();
    _live = realtime.listen((_) => _loader.currentState?.reload(), names: const {'order'});
  }

  @override
  void dispose() {
    _wait?.cancel();
    _live?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _search(String _) {
    setState(() {});
    _wait?.cancel();
    _wait = Timer(const Duration(milliseconds: 350), () => _loader.currentState?.reload());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Unpaid Accounts'), actions: [
        IconButton(
          tooltip: 'Export',
          icon: const Icon(Icons.file_download_outlined),
          onPressed: () => go(context, const ExportReport(report: 2)),
        ),
      ]),
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () => app.api.get('/api/sales/unpaid?q=${Uri.encodeQueryComponent(_q.text.trim())}'),
        builder: (context, d, reload) {
          final list = [for (final c in d['customers'] as List) c as Map<String, dynamic>];
          return Body([
            Box(
              filled: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Total owed', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                const Gap(4),
                Text(_money(d['total'] as num),
                    style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
                Text('${d['count']} ${d['count'] == 1 ? 'customer' : 'customers'}', style: const TextStyle(color: Colors.white)),
              ]),
            ),
            const Gap(10),
            SearchBox(_q, hint: 'Search name or phone', onChanged: _search),
            const Gap(10),
            if (list.isEmpty) Empty(_q.text.trim().isEmpty ? 'No unpaid orders. Everyone has paid.' : 'No customer found'),
            for (final c in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Box(
                  onTap: () async {
                    await go(context, UnpaidCustomer(customerKey: c['key'] as String));
                    await reload();
                  },
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c['name'] as String, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        Text(
                          '${(c['phone'] as String).isEmpty ? 'No phone' : phoneFmt(c['phone'] as String)} · ${c['orders']} unpaid ${c['orders'] == 1 ? 'order' : 'orders'}',
                          style: const TextStyle(color: Brand.muted, fontSize: 12.5),
                        ),
                      ]),
                    ),
                    Text(_money(c['owed'] as num), style: const TextStyle(fontWeight: FontWeight.w800, fontFamily: 'monospace')),
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

/// One customer's unpaid orders: total owed, Call, and Paid on each order (owner confirms).
class UnpaidCustomer extends StatefulWidget {
  final String customerKey;
  const UnpaidCustomer({super.key, required this.customerKey});

  @override
  State<UnpaidCustomer> createState() => _UnpaidCustomerState();
}

class _UnpaidCustomerState extends State<UnpaidCustomer> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();

  Future<void> _paid(Map<String, dynamic> c, Map<String, dynamic> o) async {
    final ok = await confirm(context, 'Mark as paid?', sub: '${c['name']} paid ${_money(o['total'] as num)} for order #${o['id']}.');
    if (!ok || !mounted) return;
    try {
      await app.api.post('/api/admin/orders/${o['id']}/paid');
      if (mounted) toast(context, 'Marked paid. Total owed updated.');
    } on ApiException catch (e) {
      if (mounted) toast(context, '${e.title}. ${e.message}');
    }
    await _loader.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Unpaid Orders')),
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () => app.api.get('/api/sales/unpaid/${Uri.encodeComponent(widget.customerKey)}'),
        builder: (context, d, reload) {
          final c = d['customer'] as Map<String, dynamic>;
          final orders = [for (final o in d['orders'] as List) o as Map<String, dynamic>];
          final phone = (c['phone'] ?? '') as String;
          return Body([
            Box(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(c['name'] as String, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                Text(phone.isEmpty ? 'No phone number' : phoneFmt(phone), style: const TextStyle(color: Brand.muted)),
                if (c['account'] == true) const Text('Has an account', style: TextStyle(color: Brand.muted, fontSize: 12.5)),
                const Divider(height: 20),
                Row(children: [
                  const Expanded(child: Text('Total owed', style: TextStyle(fontWeight: FontWeight.w800))),
                  Text(_money(d['owed'] as num), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
                ]),
                if (phone.isNotEmpty) ...[
                  const Gap(10),
                  Btn('Call', () => callNumber(context, phone), outline: true, icon: Icons.call),
                ],
              ]),
            ),
            const Section('Unpaid orders'),
            if (orders.isEmpty) const Empty('All paid. Nothing owed.'),
            for (final o in orders)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Box(
                  onTap: () async {
                    await go(context, AdminOrderDetails(orderId: (o['id'] as num).toInt()));
                    await reload();
                  },
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('#${o['id']} · ${dayPh(DateTime.tryParse((o['at'] ?? '') as String))}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(
                          '${o['quantity']} ${o['quantity'] == 1 ? 'gallon' : 'gallons'} · ${o['type']}${o['source'] == 'Walk-in' ? ' · Walk-in' : ''}',
                          style: const TextStyle(color: Brand.muted, fontSize: 12.5),
                        ),
                        Text(_money(o['total'] as num), style: const TextStyle(fontWeight: FontWeight.w800, fontFamily: 'monospace')),
                      ]),
                    ),
                    SmallBtn('Paid', () => _paid(c, o)),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
