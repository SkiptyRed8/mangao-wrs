import 'package:flutter/material.dart';

import '../../config.dart';
import '../../services/app_state.dart';
import '../../theme/brand.dart';
import '../../widgets/common.dart';
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
    if (app.sessionEnded) {
      app.sessionEnded = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) go(context, const LoginScreen(note: 'Session ends'));
      });
    }
  }

  Future<void> _check() async {
    final ok = await app.serverOk();
    if (mounted) setState(() => _server = ok);
  }

  Future<void> _serverSettings() async {
    final changed = await showDialog<bool>(context: context, builder: (_) => const _ServerDialog());
    if (changed == true && mounted) {
      setState(() => _server = null);
      await _check();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          child: Column(children: [
            const Spacer(flex: 3),
            // Long-press the logo: server address (backup, e.g. the laptop on the same Wi-Fi).
            GestureDetector(onLongPress: _serverSettings, child: const Logo()),
            const Gap(14),
            const Text(AppConfig.stationName,
                textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const Spacer(flex: 4),
            Btn('Log in', () => go(context, const LoginScreen())),
            const Gap(),
            Btn('Sign up', () => go(context, const SignupScreen()), outline: true),
            const Gap(14),
            LinkText('Continue as guest', () => app.startGuest()),
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

/// Small line under the buttons: shown only while connecting or when there is no connection.
class _ServerLine extends StatelessWidget {
  final bool? ok;
  final VoidCallback onRetry;
  const _ServerLine(this.ok, {required this.onRetry});

  @override
  Widget build(BuildContext context) {
    if (ok == true) return const SizedBox(height: 20);
    final waiting = ok == null;
    final color = waiting ? Brand.muted : Brand.red;
    return InkWell(
      onTap: onRetry,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(waiting ? Icons.sync : Icons.cloud_off, size: 16, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            waiting ? 'Connecting...' : 'No connection. Check the internet, then tap here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}

/// Server address (backup): type the laptop address shown by START.bat, or go back to the built-in one.
class _ServerDialog extends StatefulWidget {
  const _ServerDialog();

  @override
  State<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<_ServerDialog> {
  late final _text = TextEditingController(text: AppConfig.apiUrl);
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = AppConfig.clean(_text.text);
    if (url == null) {
      setState(() => _error = 'Type an address like http://192.168.1.5:3100');
      return;
    }
    await AppConfig.choose(url);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _reset() async {
    await AppConfig.choose(null);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Server address'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Built-in: ${AppConfig.defaultUrl}', style: const TextStyle(fontSize: 12.5, color: Brand.muted)),
        const SizedBox(height: 10),
        TextField(
          controller: _text,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'Address',
            hintText: 'http://192.168.1.5:3100',
            errorText: _error,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 8),
        const Text('For the project team only (testing).', style: TextStyle(fontSize: 12, color: Brand.muted)),
      ]),
      actions: [
        if (AppConfig.custom) TextButton(onPressed: _reset, child: const Text('Use built-in')),
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
