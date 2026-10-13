import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/app_state.dart';
import '../../services/realtime.dart';
import '../../theme/brand.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../shell.dart';
import '../station/log_forms.dart';
import '../station/tank_card.dart';
import 'inventory.dart';

/// Admin Home 1-7: Log Walk-in and Log Delivery, Switch View, Tank Alert & Counter, Needs Your Action
/// (new orders, ready to send out), Today's Summary tiles (each opens its screen) and Stock Alerts.
class OwnerHome extends StatefulWidget {
  const OwnerHome({super.key});

  @override
  State<OwnerHome> createState() => _OwnerHomeState();
}

class _OwnerHomeState extends State<OwnerHome> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();
  Timer? _poll;
  StreamSubscription<RtEvent>? _live;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => _loader.currentState?.reload());
    _live = realtime.listen((_) => _loader.currentState?.reload(), names: const {'order', 'refresh', 'notification'});
  }

  @override
  void dispose() {
    _poll?.cancel();
    _live?.cancel();
    super.dispose();
  }

  Future<void> _reload() async => _loader.currentState?.reload();

  Widget _view(String title, String sub, VoidCallback onTap) => Expanded(
        child: Box(
          onTap: onTap,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(sub, style: const TextStyle(color: Brand.muted, fontSize: 12)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Brand.blue, size: 20),
          ]),
        ),
      );

  Widget _action(String title, int n, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Box(
          onTap: onTap,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            CountBadge(n),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: Brand.blue),
          ]),
        ),
      );

  Widget _tile(String label, String value, VoidCallback onTap, {bool tint = false}) => Box(
        onTap: onTap,
        tint: tint,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Brand.muted, fontSize: 11.5)),
          const Gap(2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, fontFamily: 'monospace')),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: topBar(context, 'Home'),
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () => app.api.get('/api/admin/home'),
        builder: (context, d, reload) {
          int n(Map<String, dynamic> m, String k) => ((m[k] ?? 0) as num).toInt();
          final c = d['counts'] as Map<String, dynamic>;
          final t = d['today'] as Map<String, dynamic>;
          final stock = [for (final s in d['stock'] as List) s as Map<String, dynamic>];
          final low = stock.where((s) => s['low'] == true).toList();
          final ok = stock.where((s) => s['low'] != true).map((s) => '${s['label']} OK').join(' · ');
          final tiles = [
            _tile('New', '${n(c, 'new')}', () => app.openBoard('new')),
            _tile('Processing', '${n(c, 'processing')}', () => app.openBoard('processing')),
            _tile('Out for Delivery', '${n(c, 'out')}', () => app.openBoard('out')),
            _tile('Delivered', '${n(t, 'delivered')}', () => app.openBoard('delivered')),
            _tile('Walk-in', '${n(t, 'walkIns')}', () => app.goTab(3)),
            _tile('Not delivered', '${n(c, 'notDelivered')}', () => app.openBoard('not-delivered')),
            _tile('Gallons processed', '${n(t, 'gallons')}', () => app.goTab(3), tint: true),
            _tile('Sales', peso((t['moneyEarned'] ?? 0) as num).replaceAll('.00', ''), () => app.goTab(3), tint: true),
            _tile('Unpaid', peso((t['unpaid'] ?? 0) as num).replaceAll('.00', ''), () => app.goTab(3), tint: true),
          ];
          return Body([
            StationButtons(onSaved: _reload),
            const Section('Switch View'),
            Row(children: [
              _view('Staff view', '${n(c, 'processing')} orders processing', () => app.setView(AppView.staff)),
              const Gap(8),
              _view('Delivery view', '${n(c, 'out')} orders out', () => app.setView(AppView.delivery)),
            ]),
            const Gap(10),
            TankCard.fromJson(d['tank'] as Map<String, dynamic>, owner: true, onReset: _reload),
            const Section('Needs Your Action'),
            _action('New orders', n(c, 'new'), () => app.openBoard('new')),
            _action('Ready to send out', n(c, 'processing'), () => app.openBoard('processing')),
            if (n(c, 'notDelivered') > 0) _action('Not delivered', n(c, 'notDelivered'), () => app.openBoard('not-delivered')),
            const Section("Today's Summary"),
            for (var i = 0; i < tiles.length; i += 3)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  for (var j = i; j < i + 3; j++) ...[
                    if (j > i) const Gap(8),
                    Expanded(child: tiles[j]),
                  ],
                ]),
              ),
            const Section('Stock Alerts'),
            if (low.isEmpty) Note('Stock OK: ${stock.map((s) => '${s['label']} ${s['quantity']}').join(' · ')}'),
            for (final s in low)
              LowStockBanner(
                '${s['label'] == 'Seals' ? 'Seals' : 'New gallons'} at or below ${s['level']}${ok.isEmpty ? '' : ' · $ok'}',
                title: 'Low ${(s['label'] as String).toLowerCase()}: ${s['quantity']} left',
                onTap: () => app.goTab(2),
              ),
          ]);
        },
      ),
    );
  }
}
