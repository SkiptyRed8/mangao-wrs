import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/app_state.dart';
import '../../services/realtime.dart';
import '../../theme/brand.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../owner/admin_order_details.dart';

/// Admin More 4: Notifications. Alerts (newest first): new orders, orders logged by staff, cancelled
/// and not delivered orders, tank at 60, low stock. A dot marks the unread ones; tapping an order alert
/// opens Order Details. Preferences come in step 36.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();
  StreamSubscription<RtEvent>? _live;

  @override
  void initState() {
    super.initState();
    _live = realtime.listen((_) => _loader.currentState?.reload(), names: const {'notification'});
  }

  @override
  void dispose() {
    _live?.cancel();
    super.dispose();
  }

  Future<void> _open(Map<String, dynamic> n) async {
    if (n['read'] != true) {
      try {
        await app.api.post('/api/notifications/read', {'id': n['id']});
      } catch (_) {}
    }
    if (!mounted) return;
    final orderId = (n['orderId'] as num?)?.toInt();
    final type = n['type'] as String;
    if (orderId != null && app.isOwner) {
      await go(context, AdminOrderDetails(orderId: orderId));
    } else if (type == 'Tank' && app.isOwner) {
      app.setView(AppView.admin);
      app.goTab(0);
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    } else if (type == 'Low Stock' && app.isOwner) {
      app.goTab(2);
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    await _loader.currentState?.reload();
  }

  Future<void> _readAll() async {
    try {
      await app.api.post('/api/notifications/read', {'all': true});
    } catch (_) {}
    await _loader.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () => app.api.get('/api/notifications'),
        builder: (context, d, reload) {
          final items = [for (final x in d['items'] as List) x as Map<String, dynamic>];
          final unread = (d['unread'] as num).toInt();
          return Body([
            Seg(const ['Alerts', 'Preferences'], 0, (i) {
              if (i == 1) toast(context, 'Notification preferences come in step 36');
            }),
            const Gap(10),
            Row(children: [
              Expanded(child: Text(unread == 0 ? 'All read' : '$unread unread', style: const TextStyle(color: Brand.muted))),
              if (unread > 0) LinkText('Mark all read', _readAll),
            ]),
            const Gap(6),
            if (items.isEmpty) const Empty('No alerts yet'),
            for (final n in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Box(
                  tint: n['read'] == true,
                  onTap: () => _open(n),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 8),
                      child: Icon(Icons.circle, size: 9, color: n['read'] == true ? Colors.transparent : Brand.blue),
                    ),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                            child: Text(n['title'] as String,
                                style: TextStyle(fontWeight: n['read'] == true ? FontWeight.w600 : FontWeight.w800)),
                          ),
                          Text(_when(n['at'] as String?), style: const TextStyle(color: Brand.muted, fontSize: 12)),
                        ]),
                        Text(n['message'] as String, style: const TextStyle(color: Brand.muted, fontSize: 13)),
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

  static String _when(String? iso) {
    final t = iso == null ? null : DateTime.tryParse(iso);
    final day = dayPh(t);
    return day == 'Today' ? clockPh(t) : day;
  }
}
