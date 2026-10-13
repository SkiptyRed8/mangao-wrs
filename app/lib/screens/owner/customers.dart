import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/app_state.dart';
import '../../theme/brand.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../../widgets/map_widgets.dart';
import '../common/loans.dart';
import 'admin_order_details.dart';
import 'unpaid_accounts.dart';

/// Admin More 1: Customers. Everyone who ordered (accounts, and logged or walk-in customers with a
/// name or phone) plus accounts with no orders yet. Search by name or phone; tap for the profile.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _q = TextEditingController();
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();
  Timer? _wait;

  @override
  void dispose() {
    _wait?.cancel();
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
      appBar: AppBar(title: const Text('Customers')),
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () => app.api.get('/api/customers?q=${Uri.encodeQueryComponent(_q.text.trim())}'),
        builder: (context, d, reload) {
          final list = [for (final c in d['customers'] as List) c as Map<String, dynamic>];
          return Body([
            SearchBox(_q, hint: 'Search name or phone', onChanged: _search),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _q.text.trim().isEmpty ? '${d['count']} customers · newest order first' : '${list.length} found',
                style: const TextStyle(color: Brand.muted, fontSize: 12.5),
              ),
            ),
            if (list.isEmpty) const Empty('No customer found'),
            for (final c in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Box(
                  onTap: () async {
                    await go(context, CustomerProfile(customerKey: c['key'] as String));
                    await reload();
                  },
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Flexible(child: Text(c['name'] as String, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                          if (c['account'] == true) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.verified_user_outlined, size: 16, color: Brand.blue),
                          ],
                        ]),
                        Text(
                          [
                            if ((c['phone'] as String).isNotEmpty) phoneFmt(c['phone'] as String),
                            '${c['orders']} ${c['orders'] == 1 ? 'order' : 'orders'}',
                            if (c['lastOrder'] != null) 'last ${dayPh(DateTime.tryParse(c['lastOrder'] as String))}',
                          ].join(' · '),
                          style: const TextStyle(color: Brand.muted, fontSize: 12.5),
                        ),
                        if ((c['owed'] as num) > 0 || (c['borrowed'] as num) > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Wrap(spacing: 6, runSpacing: 4, children: [
                              if ((c['owed'] as num) > 0) Tag('Owes ${peso(c['owed'] as num)}', filled: true),
                              if ((c['borrowed'] as num) > 0) Tag('${c['borrowed']} borrowed'),
                            ]),
                          ),
                      ]),
                    ),
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

/// Customer Profile: contact (Call), totals, unpaid orders, borrowed gallons, addresses (map pin) and
/// order history.
class CustomerProfile extends StatefulWidget {
  final String customerKey;
  const CustomerProfile({super.key, required this.customerKey});

  @override
  State<CustomerProfile> createState() => _CustomerProfileState();
}

class _CustomerProfileState extends State<CustomerProfile> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();
  bool _allOrders = false;

  static String _status(Map<String, dynamic> o) => switch (o['status'] as String) {
        'Recorded' => 'Walk-in',
        'Out for Delivery' => 'Out for delivery',
        'Not Delivered' => 'Not delivered',
        final s => s,
      };

  Widget _stat(String label, String value) => Expanded(
        child: Column(children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, fontFamily: 'monospace')),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Brand.muted, fontSize: 11.5)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Customer Profile')),
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () => app.api.get('/api/customers/${Uri.encodeComponent(widget.customerKey)}'),
        builder: (context, d, reload) {
          final c = d['customer'] as Map<String, dynamic>;
          final s = d['stats'] as Map<String, dynamic>;
          final unpaid = d['unpaid'] as Map<String, dynamic>;
          final orders = [for (final o in d['orders'] as List) o as Map<String, dynamic>];
          final addresses = [for (final a in d['addresses'] as List) a as Map<String, dynamic>];
          final loans = [for (final l in d['loans'] as List) Loan.fromJson(l as Map<String, dynamic>)];
          final phone = (c['phone'] ?? '') as String;
          final shown = _allOrders ? orders : orders.take(10).toList();
          return Body([
            Box(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(c['name'] as String, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                const Gap(4),
                KV('Phone', phone.isEmpty ? 'None' : phoneFmt(phone)),
                if ((c['email'] ?? '') != '') KV('Email', c['email'] as String),
                KV('Account', c['account'] == true ? 'Yes, since ${dayPh(DateTime.tryParse((c['since'] ?? '') as String))}' : 'No (logged or walk-in)',
                    last: true),
                if (phone.isNotEmpty) ...[
                  const Gap(10),
                  Btn('Call', () => callNumber(context, phone), outline: true, icon: Icons.call),
                ],
              ]),
            ),
            const Gap(10),
            Box(
              child: Row(children: [
                _stat('Orders', '${s['orders']}'),
                _stat('Gallons', '${s['gallons']}'),
                _stat('Paid', peso(s['spent'] as num).replaceAll('.00', '')),
                _stat('Borrowed', '${s['borrowed']}'),
              ]),
            ),
            const Section('Unpaid orders'),
            if ((unpaid['owed'] as num) == 0)
              const Text('Nothing owed', style: TextStyle(color: Brand.muted))
            else
              RowLink(
                'Owes ${peso(unpaid['owed'] as num)}',
                sub: '${(unpaid['orders'] as List).length} unpaid ${(unpaid['orders'] as List).length == 1 ? 'order' : 'orders'} · tap to mark paid',
                icon: Icons.payments_outlined,
                onTap: () async {
                  await go(context, UnpaidCustomer(customerKey: c['key'] as String));
                  await reload();
                },
              ),
            const Section('Borrowed gallons'),
            if (loans.isEmpty) const Text('None', style: TextStyle(color: Brand.muted)),
            for (final l in loans) LoanTile(l, onChanged: reload),
            const Section('Addresses'),
            if (addresses.isEmpty) const Text('None yet', style: TextStyle(color: Brand.muted)),
            for (final a in addresses)
              RowLink(
                a['saved'] == true ? (a['name'] as String) : 'Used on an order',
                sub: a['text'] as String,
                icon: a['lat'] != null ? Icons.location_on_outlined : Icons.edit_location_alt_outlined,
                onTap: () => showPinSheet(
                  context,
                  address: a['text'] as String,
                  lat: (a['lat'] as num?)?.toDouble(),
                  lng: (a['lng'] as num?)?.toDouble(),
                ),
              ),
            Section('Order history (${orders.length})'),
            if (orders.isEmpty) const Text('No orders yet', style: TextStyle(color: Brand.muted)),
            for (final o in shown)
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
                          '${o['quantity']} ${o['quantity'] == 1 ? 'gallon' : 'gallons'} · ${o['type']} · ${peso(o['total'] as num)}',
                          style: const TextStyle(color: Brand.muted, fontSize: 12.5),
                        ),
                      ]),
                    ),
                    Tag(o['paymentStatus'] == 'Unpaid' ? 'Unpaid' : _status(o),
                        filled: o['paymentStatus'] == 'Unpaid', red: ['Declined', 'Cancelled'].contains(o['status'])),
                    const Icon(Icons.chevron_right, color: Brand.blue),
                  ]),
                ),
              ),
            if (!_allOrders && orders.length > 10) Btn('Show all ${orders.length} orders', () => setState(() => _allOrders = true), outline: true, small: true),
          ]);
        },
      ),
    );
  }
}
