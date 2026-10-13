import 'package:flutter/material.dart';

import '../services/app_state.dart';
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

class _RootState extends State<Root> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _start();
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
