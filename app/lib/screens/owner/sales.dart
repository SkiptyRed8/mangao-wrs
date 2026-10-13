import 'package:flutter/material.dart';

import '../../services/api.dart';
import '../../services/app_state.dart';
import '../../theme/brand.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../shell.dart';
import 'admin_order_details.dart';
import 'unpaid_accounts.dart';
import 'weekly_sales.dart';

/// Admin Sales 1: Daily Sales Report. Money earned, Unpaid, Gallons processed, Packages sold,
/// Delivery vs walk-in, Rider paid, and the orders of the day. The Weekly switch opens Admin Sales 2;
/// the Unpaid tile opens Admin Sales 3.
class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  DateTime _day = ph(DateTime.now());
  Map<String, dynamic>? _data;
  ApiException? _error;
  bool _loading = true;
  int _mode = 0; // 0 Daily, 1 Weekly

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static String _label(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

  DateTime get _today {
    final p = ph(DateTime.now());
    return DateTime(p.year, p.month, p.day);
  }

  @override
  void initState() {
    super.initState();
    _day = _today;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await app.api.get('/api/sales/daily?date=${_ymd(_day)}');
      if (mounted) {
        setState(() {
          _data = r;
          _error = null;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  void _move(int days) {
    final next = _day.add(Duration(days: days));
    if (next.isAfter(_today)) return;
    setState(() => _day = next);
    _load();
  }

  Future<void> _pick() async {
    final d = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime(2025), lastDate: _today, helpText: 'Choose date');
    if (d != null) {
      setState(() => _day = DateTime(d.year, d.month, d.day));
      await _load();
    }
  }

  Widget _tile(String label, String value, {VoidCallback? onTap}) => Box(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: Brand.muted, fontSize: 12)),
              const Gap(2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19, fontFamily: 'monospace')),
              ),
            ]),
          ),
          if (onTap != null) const Icon(Icons.chevron_right, color: Brand.blue, size: 20),
        ]),
      );

  String _money(num v) => peso(v).replaceAll('.00', '');

  Widget _switch() => Seg(const ['Daily', 'Weekly'], _mode, (i) => setState(() => _mode = i));

  @override
  Widget build(BuildContext context) {
    if (_mode == 1) {
      return Scaffold(
        appBar: topBar(context, 'Weekly Sales Report'),
        body: WeeklySales(
          header: _switch(),
          onOpenDay: (day) {
            setState(() {
              _mode = 0;
              _day = day;
            });
            _load();
          },
        ),
      );
    }
    final d = _data;
    final s = d == null ? null : d['summary'] as Map<String, dynamic>;
    final orders = d == null ? const [] : d['orders'] as List;
    final isToday = !_day.isBefore(_today);
    return Scaffold(
      appBar: topBar(context, 'Daily Sales Report'),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Body([
          _switch(),
          const Gap(10),
          Box(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(children: [
              IconButton(onPressed: () => _move(-1), icon: const Icon(Icons.chevron_left, color: Brand.blue), tooltip: 'Day before'),
              Expanded(
                child: InkWell(
                  onTap: _pick,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(_label(_day), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
              IconButton(
                onPressed: isToday ? null : () => _move(1),
                icon: Icon(Icons.chevron_right, color: isToday ? Brand.soft : Brand.blue),
                tooltip: 'Next day',
              ),
            ]),
          ),
          const Gap(10),
          if (_error != null) MsgBanner(_error!.title, sub: _error!.message),
          if (_loading && d == null) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())),
          if (s != null) ...[
            Box(
              filled: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Money earned', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                const Gap(4),
                Text(_money(s['moneyEarned'] as num),
                    style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
              ]),
            ),
            const Gap(8),
            Row(children: [
              Expanded(child: _tile('Unpaid', _money(s['unpaid'] as num), onTap: () => go(context, const UnpaidAccounts()))),
              const Gap(8),
              Expanded(child: _tile('Gallons processed', '${s['gallons']}')),
            ]),
            const Gap(8),
            Row(children: [
              Expanded(child: _tile('Packages sold', '${s['packages']}')),
              const Gap(8),
              Expanded(child: _tile('Delivery vs walk-in', '${s['deliveryGallons']} / ${s['walkInGallons']}')),
            ]),
            const Gap(8),
            Row(children: [
              Expanded(child: _tile('Rider paid', _money(s['riderPaid'] as num))),
              const Gap(8),
              Expanded(child: _tile('Orders completed', '${(s['delivered'] as num) + (s['walkIns'] as num)}')),
            ]),
            const Section('Orders list'),
            if (orders.isEmpty) const Empty('No completed orders on this day'),
            for (final o in orders.cast<Map<String, dynamic>>())
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Box(
                  onTap: () => go(context, AdminOrderDetails(orderId: (o['id'] as num).toInt())),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(o['name'] as String, style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(
                          '${o['quantity']} ${o['quantity'] == 1 ? 'gallon' : 'gallons'}${o['type'] == 'Package' ? ' · Package' : ''} · ${_money(o['total'] as num)}',
                          style: const TextStyle(color: Brand.muted, fontSize: 12.5),
                        ),
                      ]),
                    ),
                    Tag(o['tag'] as String, filled: o['tag'] == 'Unpaid'),
                    const Icon(Icons.chevron_right, color: Brand.blue),
                  ]),
                ),
              ),
            const Gap(8),
            Btn('Export', () => toast(context, 'Export comes in step 39'), outline: true),
          ],
        ]),
      ),
    );
  }
}
