import 'package:flutter/material.dart';

import '../../config.dart';
import '../../services/app_state.dart';
import '../../theme/brand.dart';
import '../../widgets/common.dart';
import '../common/coming_soon.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

/// Login 1 / Customer 1: Welcome. Log in, Sign up, Continue as guest.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool? _server; // null = checking

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final ok = await app.serverOk();
    if (mounted) setState(() => _server = ok);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          child: Column(children: [
            const Spacer(flex: 3),
            const Logo(),
            const Gap(14),
            const Text(AppConfig.stationName,
                textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const Spacer(flex: 4),
            Btn('Log in', () => go(context, const LoginScreen())),
            const Gap(),
            Btn('Sign up', () => go(context, const SignupScreen()), outline: true),
            const Gap(14),
            LinkText('Continue as guest',
                () => go(context, const ComingSoon('Guest mode', step: 33, what: 'Order without an account', pushed: true))),
            const Gap(12),
            _ServerLine(_server, onRetry: () {
              setState(() => _server = null);
              _check();
            }),
          ]),
        ),
      ),
    );
  }
}

/// Small line under the buttons: is the server running? (helps while testing on the laptop)
class _ServerLine extends StatelessWidget {
  final bool? ok;
  final VoidCallback onRetry;
  const _ServerLine(this.ok, {required this.onRetry});

  @override
  Widget build(BuildContext context) {
    if (ok == true) return const SizedBox(height: 20);
    return InkWell(
      onTap: onRetry,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(ok == null ? Icons.sync : Icons.cloud_off, size: 16, color: ok == null ? Brand.muted : Brand.red),
        const SizedBox(width: 6),
        Text(
          ok == null ? 'Checking the server...' : 'Server not running. Start it, then tap here.',
          style: TextStyle(fontSize: 12.5, color: ok == null ? Brand.muted : Brand.red, fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}
