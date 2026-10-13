import 'dart:async';

import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/app_state.dart';
import '../services/nav.dart';
import '../services/realtime.dart';
import '../theme/brand.dart';
import '../widgets/common.dart';
import '../widgets/watch.dart';
import 'auth/welcome_screen.dart';
import 'customer/order_details.dart';
import 'owner/admin_order_details.dart';
import 'shell.dart';

/// Login 4 (App opens): the logo while the saved session is checked, then the role's Home
/// (already logged in) or Welcome (not logged in).
class Root extends StatefulWidget {
  const Root({super.key});

  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  bool _ready = false;
  StreamSubscription<RtEvent>? _alerts;

  @override
  void initState() {
    super.initState();
    _start();
    // Alerts from the server show as a banner at the bottom (on a phone they also come as push).
    _alerts = realtime.events.where((e) => e.name == 'notification').listen(_showAlert);
  }

  @override
  void dispose() {
    _alerts?.cancel();
    super.dispose();
  }

  void _showAlert(RtEvent e) {
    final title = (e.data['title'] ?? '') as String;
    final message = (e.data['message'] ?? '') as String;
    final orderId = (e.data['orderId'] as num?)?.toInt();
    final owner = app.role == Role.owner;
    final customer = app.guest || app.role == Role.customer;
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        backgroundColor: Brand.ink,
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Mangao Water Refilling Station', style: TextStyle(color: Colors.white70, fontSize: 11.5)),
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          if (message.isNotEmpty) Text(message, style: const TextStyle(color: Colors.white)),
        ]),
        action: orderId != null && (owner || customer)
            ? SnackBarAction(
                label: 'View',
                textColor: Brand.soft,
                onPressed: () => navKey.currentState?.push(MaterialPageRoute(
                  builder: (_) => owner ? AdminOrderDetails(orderId: orderId) : CustomerOrderDetails(orderId: orderId),
                )),
              )
            : null,
      ),
    );
  }

  Future<void> _start() async {
    final started = DateTime.now();
    await app.load();
    final wait = const Duration(milliseconds: 700) - DateTime.now().difference(started);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Logo(),
            Gap(14),
            Text('Mangao Water Refilling Station', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ]),
        ),
      );
    }
    return Watch((context) => (app.loggedIn || app.guest) ? const Shell() : const WelcomeScreen());
  }
}
