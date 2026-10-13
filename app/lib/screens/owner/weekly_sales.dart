import 'package:flutter/material.dart';

import '../../services/api.dart';
import '../../services/app_state.dart';
import '../../theme/brand.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';

/// Admin Sales 2: Weekly Sales Report. Choose a week (Monday to Sunday); money earned for each day as
/// bars (this week dark, last week light), totals, and the change from last week. Tap a day to open
/// its Daily Sales Report.
class WeeklySales extends StatefulWidget {
  /// Shown at the top of the list (the Daily / Weekly switch).
  final Widget header;
  final void Function(DateTime day) onOpenDay;
  const WeeklySales({super.key, required this.header, required this.onOpenDay});

  @override
  State<WeeklySales> createState() => _WeeklySalesState();
}

class _WeeklySalesState extends State<WeeklySales> {
  late DateTime _monday;
  Map<String, dynamic>? _data;
  ApiException? _error;
  bool _loading = true;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static DateTime _parse(String s) {
    final p = s.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  static DateTime _mondayOf(DateTime d) => DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  DateTime get _thisMonday {
    final p = ph(DateTime.now());
    return _mondayOf(DateTime(p.year, p.month, p.day));
  }

  String get _range {
    final s = _monday;
    final e = _monday.add(const Duration(days: 6));
    final left = '${_months[s.month - 1]} ${s.day}';
    final right = s.month == e.month ? '${e.day}' : '${_months[e.month - 1]} ${e.day}';
    return '$left - $right, ${e.year}';
  }

  @override
  void initState() {
    super.initState();
    _monday = _thisMonday;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await app.api.get('/api/sales/weekly?start=${_ymd(_monday)}');
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

  void _move(int weeks) {
    final next = _monday.add(Duration(days: 7 * weeks));
    if (next.isAfter(_thisMonday)) return;
    setState(() => _monday = next);
    _load();
  }

  Future<void> _pick() async {
    final p = ph(DateTime.now());
    final d = await showDatePicker(
      context: context,
      initialDate: _monday,
      firstDate: DateTime(2025),
      lastDate: DateTime(p.year, p.month, p.day),
      helpText: 'Choose any day of the week',
    );
    if (d != null) {
      setState(() => _monday = _mondayOf(d));
      await _load();
    }
  }

  String _money(num v) => peso(v).replaceAll('.00', '');

  Widget _changeLine(String label, num? pct) {
    final String text;
    if (pct == null) {
      text = 'No sales last week to compare';
    } else if (pct == 0) {
      text = 'Same as last week';
    } else {
      text = '${pct > 0 ? 'Up' : 'Down'} ${pct.abs()}% from last week';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [
        Icon(pct == null || pct == 0 ? Icons.remove : (pct > 0 ? Icons.trending_up : Icons.trending_down),
            size: 18, color: pct != null && pct < 0 ? Brand.red : Brand.blue),
        const SizedBox(width: 6),
        Expanded(child: Text('$label: $text', style: const TextStyle(fontSize: 13))),
      ]),
    );
  }

  Widget _chart(List<Map<String, dynamic>> days, List<Map<String, dynamic>> last) {
    num top = 1;
    for (final d in [...days, ...last]) {
      if ((d['moneyEarned'] as num) > top) top = d['moneyEarned'] as num;
    }
    const h = 130.0;
    return Box(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Label('Money earned per day'),
        const Gap(10),
        SizedBox(
          height: h + 44,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < days.length; i++)
              Expanded(
                child: InkWell(
                  onTap: days[i]['future'] == true ? null : () => widget.onOpenDay(_parse(days[i]['date'] as String)),
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    FittedBox(
                      child: Text(
                        days[i]['future'] == true ? '' : _money(days[i]['moneyEarned'] as num),
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Container(
                        width: 7,
                        height: i < last.length ? h * ((last[i]['moneyEarned'] as num) / top) + 1 : 1,
                        decoration: BoxDecoration(color: Brand.soft, borderRadius: BorderRadius.circular(3)),
                      ),
                      const SizedBox(width: 2),
                      Container(
                        width: 14,
                        height: h * ((days[i]['moneyEarned'] as num) / top) + 1,
                        decoration: BoxDecoration(color: Brand.blue, borderRadius: BorderRadius.circular(3)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text(days[i]['day'] as String,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: days[i]['future'] == true ? Brand.soft : Brand.ink)),
                  ]),
                ),
              ),
          ]),
        ),
        const Gap(8),
        Row(children: [
          Container(width: 12, height: 12, color: Brand.blue),
          const SizedBox(width: 6),
          const Text('This week', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 14),
          Container(width: 12, height: 12, color: Brand.soft),
          const SizedBox(width: 6),
          const Text('Last week', style: TextStyle(fontSize: 12)),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final t = d == null ? null : d['totals'] as Map<String, dynamic>;
    final lw = d == null ? null : d['lastWeek'] as Map<String, dynamic>;
    final ch = d == null ? null : d['change'] as Map<String, dynamic>;
    final days = d == null ? const <Map<String, dynamic>>[] : [for (final x in d['days'] as List) x as Map<String, dynamic>];
    final last = d == null ? const <Map<String, dynamic>>[] : [for (final x in d['lastWeekDays'] as List) x as Map<String, dynamic>];
    final isThisWeek = !_monday.isBefore(_thisMonday);
    return RefreshIndicator(
      onRefresh: _load,
      child: Body([
        widget.header,
        const Gap(10),
        Box(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(children: [
            IconButton(onPressed: () => _move(-1), icon: const Icon(Icons.chevron_left, color: Brand.blue), tooltip: 'Week before'),
            Expanded(
              child: InkWell(
                onTap: _pick,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(_range, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ),
            IconButton(
              onPressed: isThisWeek ? null : () => _move(1),
              icon: Icon(Icons.chevron_right, color: isThisWeek ? Brand.soft : Brand.blue),
              tooltip: 'Next week',
            ),
          ]),
        ),
        const Gap(10),
        if (_error != null) MsgBanner(_error!.title, sub: _error!.message),
        if (_loading && d == null) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())),
        if (t != null && lw != null && ch != null) ...[
          Box(
            filled: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Money earned this week', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              const Gap(4),
              Text(_money(t['moneyEarned'] as num),
                  style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
              Text('Last week: ${_money(lw['moneyEarned'] as num)}', style: const TextStyle(color: Colors.white)),
            ]),
          ),
          const Gap(8),
          _chart(days, last),
          const Gap(8),
          Box(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Label('Compared with last week'),
              _changeLine('Money earned', ch['moneyEarned'] as num?),
              _changeLine('Gallons processed', ch['gallons'] as num?),
              _changeLine('Orders completed', ch['orders'] as num?),
            ]),
          ),
          const Gap(8),
          Box(
            child: Column(children: [
              KV('Gallons processed', '${t['gallons']}  (last week ${lw['gallons']})'),
              KV('Packages sold', '${t['packages']}'),
              KV('Delivery vs walk-in', '${t['deliveryGallons']} / ${t['walkInGallons']}'),
              KV('Orders completed', '${t['orders']}'),
              KV('Unpaid', _money(t['unpaid'] as num)),
              KV('Rider paid', _money(t['riderPaid'] as num), last: true),
            ]),
          ),
          const Section('Day by day'),
          for (final x in days)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Box(
                onTap: x['future'] == true ? null : () => widget.onOpenDay(_parse(x['date'] as String)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(children: [
                  SizedBox(width: 44, child: Text(x['day'] as String, style: const TextStyle(fontWeight: FontWeight.w800))),
                  Expanded(
                    child: Text(
                      x['future'] == true
                          ? 'Not yet'
                          : '${x['gallons']} ${x['gallons'] == 1 ? 'gallon' : 'gallons'} · ${x['orders']} ${x['orders'] == 1 ? 'order' : 'orders'}',
                      style: const TextStyle(color: Brand.muted, fontSize: 12.5),
                    ),
                  ),
                  Text(x['future'] == true ? '' : _money(x['moneyEarned'] as num),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontFamily: 'monospace')),
                  if (x['future'] != true) const Icon(Icons.chevron_right, color: Brand.blue),
                ]),
              ),
            ),
        ],
      ]),
    );
  }
}
