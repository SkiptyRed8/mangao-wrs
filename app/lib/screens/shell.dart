import 'dart:async';

import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/app_state.dart';
import '../services/realtime.dart';
import '../theme/brand.dart';
import '../widgets/common.dart';
import '../widgets/watch.dart';
import 'common/account_screen.dart';
import 'common/coming_soon.dart';
import 'common/done_today.dart';
import 'common/live_map.dart';
import 'common/notifications.dart';
import 'customer/customer_home.dart';
import 'customer/my_orders.dart';
import 'owner/inventory.dart';
import 'owner/order_board.dart';
import 'owner/owner_home.dart';
import 'owner/sales.dart';
import 'owner/settings_screen.dart';
import 'owner/staff_screens.dart';
import 'rider/deliveries.dart';
import 'staff/staff_todo.dart';

class TabDef {
  final String label;
  final IconData icon;
  final IconData selected;
  final Widget page;
  const TabDef(this.label, this.icon, this.selected, this.page);
}

/// Tab bar of each role (sitemaps 8.10, 8.16, 8.18, 8.20).
/// The owner can switch to the Staff or Delivery view from the top bar (Admin Home 2).
class Shell extends StatelessWidget {
  const Shell({super.key});

  static List<TabDef> tabsFor(Role? r) {
    switch (r) {
      case Role.owner:
        return const [
          TabDef('Home', Icons.home_outlined, Icons.home, OwnerHome()),
          TabDef('Orders', Icons.receipt_long_outlined, Icons.receipt_long, OrderBoard()),
          TabDef('Inventory', Icons.inventory_2_outlined, Icons.inventory_2, InventoryScreen()),
          TabDef('Sales', Icons.bar_chart_outlined, Icons.bar_chart, SalesScreen()),
          TabDef('More', Icons.more_horiz, Icons.more_horiz, OwnerMore()),
        ];
      case Role.staff:
        return const [
          TabDef('To Do', Icons.assignment_outlined, Icons.assignment, StaffTodo()),
          TabDef('Live Map', Icons.location_on_outlined, Icons.location_on, LiveMapScreen()),
          TabDef('Done Today', Icons.check_circle_outline, Icons.check_circle, StaffDoneToday()),
          TabDef('My Account', Icons.person_outline, Icons.person, AccountScreen()),
        ];
      case Role.rider:
        return const [
          TabDef('Deliveries', Icons.local_shipping_outlined, Icons.local_shipping, RiderDeliveries()),
          TabDef('Done Today', Icons.check_circle_outline, Icons.check_circle, RiderDoneToday()),
          TabDef('My Account', Icons.person_outline, Icons.person, AccountScreen()),
        ];
      default:
        return const [
          TabDef('Home', Icons.home_outlined, Icons.home, CustomerHome()),
          TabDef('My Orders', Icons.list_alt_outlined, Icons.list_alt, MyOrders()),
          TabDef('My Account', Icons.person_outline, Icons.person, AccountScreen()),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final t = tabsFor(app.shownRole);
      final i = app.tab < t.length ? app.tab : 0;
      return Scaffold(
        body: t[i].page,
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Brand.blue, width: 1.2))),
          child: NavigationBar(
            selectedIndex: i,
            onDestinationSelected: app.goTab,
            destinations: [
              for (final d in t) NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selected), label: d.label),
            ],
          ),
        ),
      );
    });
  }
}

/// Top bar of every tab page. The owner also sees the view switcher and the bell.
PreferredSizeWidget topBar(BuildContext context, String title, {List<Widget> actions = const [], bool back = false}) {
  final owner = app.isOwner;
  return AppBar(
    automaticallyImplyLeading: back,
    title: Text(title),
    actions: [
      ...actions,
      if (owner) const ViewSwitch(),
      if (owner) const Bell(),
      const SizedBox(width: 8),
    ],
  );
}

/// Admin / Staff / Delivery view switcher (owner only).
class ViewSwitch extends StatelessWidget {
  const ViewSwitch({super.key});

  static const _names = {AppView.admin: 'Admin', AppView.staff: 'Staff', AppView.delivery: 'Delivery'};

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 10)),
        onPressed: () async {
          final r = await choose(context, 'Switch view', _names.values.toList(), current: _names[app.view], ok: 'Open view');
          if (r == null) return;
          app.setView(_names.entries.firstWhere((e) => e.value == r).key);
          if (context.mounted) toRoot(context);
        },
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(_names[app.view]!, style: const TextStyle(fontSize: 13)),
          const Icon(Icons.expand_more, size: 18),
        ]),
      ),
    );
  }
}

/// Notification bell (owner) with the number of unread alerts; checks every 30 seconds.
class Bell extends StatefulWidget {
  const Bell({super.key});

  @override
  State<Bell> createState() => _BellState();
}

class _BellState extends State<Bell> {
  int _unread = 0;
  Timer? _timer;
  StreamSubscription<RtEvent>? _live;

  @override
  void initState() {
    super.initState();
    _check();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _check());
    _live = realtime.listen((_) => _check(), names: const {'notification'});
  }

  @override
  void dispose() {
    _timer?.cancel();
    _live?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    try {
      final r = await app.api.get('/api/notifications/unread');
      if (mounted) setState(() => _unread = (r['unread'] as num).toInt());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Notifications',
        onPressed: () async {
          await go(context, const NotificationsScreen());
          await _check();
        },
        icon: Badge(
          isLabelVisible: _unread > 0,
          label: Text('$_unread'),
          backgroundColor: Brand.blue,
          child: const Icon(Icons.notifications_none, color: Brand.ink),
        ),
      );
}

/// Owner's More tab (Admin More 1): Customers, Staff & Riders, Prices & Settings, Notifications, My Account.
class OwnerMore extends StatelessWidget {
  const OwnerMore({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: topBar(context, 'More'),
      body: Body([
        RowLink('Customers', sub: 'Contacts, addresses, order history', icon: Icons.people_outline,
            onTap: () => go(context, const ComingSoon('Customers', step: 42, what: 'Customer list and records', pushed: true))),
        RowLink('Staff & Riders', sub: 'Add, edit, deactivate', icon: Icons.badge_outlined,
            onTap: () => go(context, const StaffListScreen())),
        RowLink('Prices & Settings', sub: 'Prices, tank limit, low-stock levels, station location', icon: Icons.tune,
            onTap: () => go(context, const SettingsScreen())),
        RowLink('Notifications', sub: 'Alerts and preferences', icon: Icons.notifications_none,
            onTap: () => go(context, const NotificationsScreen())),
        RowLink('My Account', sub: 'Profile, password, log out', icon: Icons.person_outline,
            onTap: () => go(context, const AccountScreen(pushed: true))),
      ]),
    );
  }
}
