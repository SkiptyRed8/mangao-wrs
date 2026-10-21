import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_state.dart';
import '../services/push.dart';
import '../services/realtime.dart';
import '../widgets/alert_banner.dart';
import '../widgets/common.dart';
import '../widgets/watch.dart';
import 'auth/welcome_screen.dart';
import 'shell.dart';

/// Login 4 (App opens): the logo while the saved session is checked, then the role's Home
/// (already logged in) or Welcome (not logged in).
class Root extends StatefulWidget {
  const Root({super.key});

  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> with WidgetsBindingObserver {
  bool _ready = false;
  StreamSubscription<RtEvent>? _alerts;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
    // Alerts from the server show as a card at the top of the screen while the app is open.
    _alerts = realtime.events.where((e) => e.name == 'notification').listen(_showAlert);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alerts?.cancel();
    super.dispose();
  }

  /// Session expiry: away from the app for 2 minutes = log in again (AppState.idleLimit).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      app.checkIdle();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      app.paused();
    }
  }

  void _showAlert(RtEvent e) {
    showAlertBanner(
      title: (e.data['title'] ?? '') as String,
      message: (e.data['message'] ?? '') as String,
      orderId: (e.data['orderId'] as num?)?.toInt(),
    );
  }

  Future<void> _start() async {
    final started = DateTime.now();
    try {
      await PushSetup.init().timeout(const Duration(seconds: 5)); // phone notifications (Firebase)
    } catch (_) {}
    try {
      // Never stay on the logo screen: after 10 seconds the app opens anyway.
      await app.load().timeout(const Duration(seconds: 10));
    } catch (_) {}
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
