import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api.dart';
import '../../services/app_state.dart';
import '../../theme/brand.dart';
import '../../widgets/common.dart';

/// Login 2 / 2A: Forgot password -> Enter code -> New password, for every role.
/// Each screen returns true to the one before it when the password was changed,
/// so the Log in screen can show "Password changed. Log in with your new password."
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  ApiException? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final sent = await app.api.post('/api/auth/forgot', {'email': _email.text.trim()});
      if (!mounted) return;
      setState(() => _busy = false);
      final changed = await go<bool>(context, EnterCodeScreen(email: _email.text.trim(), sent: sent));
      if (changed == true && mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot password')),
      body: Body([
        if (_error != null) MsgBanner(_error!.title, sub: _error!.message),
        const Text('Reset your password', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const Gap(4),
        const Text(
          'Type the email on your account. We will send a 6-digit code to reset your password. '
          'Works for all accounts: owner, staff, rider and customer.',
          style: TextStyle(color: Brand.muted),
        ),
        const Gap(14),
        Field('Email', _email,
            hint: 'name@gmail.com', kind: FieldKind.email, action: TextInputAction.done, onSubmitted: (_) => _send()),
        const Gap(4),
        Btn('Send code', _send, busy: _busy),
      ]),
    );
  }
}

/// Enter code: six boxes, Verify, and "Resend code" after 60 seconds.
class EnterCodeScreen extends StatefulWidget {
  final String email;
  final Map<String, dynamic> sent;
  const EnterCodeScreen({super.key, required this.email, required this.sent});

  @override
  State<EnterCodeScreen> createState() => _EnterCodeScreenState();
}

class _EnterCodeScreenState extends State<EnterCodeScreen> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  late Map<String, dynamic> _sent;
  ApiException? _error;
  bool _busy = false;
  bool _resending = false;
  int _wait = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _sent = widget.sent;
    _startWait((_sent['resendIn'] as num?)?.toInt() ?? 60);
    _code.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startWait(int seconds) {
    _timer?.cancel();
    _wait = seconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _wait = _wait > 0 ? _wait - 1 : 0);
      if (_wait == 0) t.cancel();
    });
  }

  Future<void> _verify() async {
    if (_code.text.length != 6) {
      setState(() => _error = const ApiException(400, 'CODE_SHORT', 'Code not complete', 'Type all 6 digits from the email.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await app.api.post('/api/auth/forgot/verify', {'email': widget.email, 'code': _code.text});
      if (!mounted) return;
      setState(() => _busy = false);
      final changed = await go<bool>(context, NewPasswordScreen(resetToken: r['resetToken'] as String));
      if (changed == true && mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _busy = false;
        });
      }
    }
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      final r = await app.api.post('/api/auth/forgot', {'email': widget.email});
      if (!mounted) return;
      setState(() {
        _sent = r;
        _resending = false;
        _code.clear();
      });
      _startWait((r['resendIn'] as num?)?.toInt() ?? 60);
      _focus.requestFocus();
      toast(context, 'New code sent. The old code no longer works.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _resending = false;
        _error = e;
      });
      final wait = e.data['resendIn'];
      if (wait is num) _startWait(wait.toInt());
    }
  }

  @override
  Widget build(BuildContext context) {
    final masked = (_sent['email'] ?? widget.email) as String;
    final mm = _wait ~/ 60;
    final ss = (_wait % 60).toString().padLeft(2, '0');
    return Scaffold(
      appBar: AppBar(title: const Text('Enter code')),
      body: Body([
        if (_error != null) MsgBanner(_error!.title, sub: _error!.message),
        const Text('Check your email', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const Gap(4),
        Text('We sent a 6-digit code to $masked. The code works for 10 minutes.', style: const TextStyle(color: Brand.muted)),
        const Gap(14),
        const Label('6-digit code'),
        const Gap(6),
        _CodeBoxes(controller: _code, focus: _focus, onDone: _verify),
        const Gap(16),
        Btn('Verify', _verify, busy: _busy),
        const Gap(12),
        Center(
          child: _wait > 0
              ? Text('Resend code in $mm:$ss', style: const TextStyle(color: Brand.muted, fontWeight: FontWeight.w600))
              : _resending
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
                  : LinkText('Resend code', _resend),
        ),
      ]),
    );
  }
}

/// Six boxes that show the digits typed into one hidden field (typing, deleting and pasting all work).
class _CodeBoxes extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onDone;
  const _CodeBoxes({required this.controller, required this.focus, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final digits = controller.text;
    return GestureDetector(
      onTap: focus.requestFocus,
      child: Stack(children: [
        Row(children: [
          for (var i = 0; i < 6; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: AspectRatio(
                aspectRatio: 0.85,
                child: AnimatedBuilder(
                  animation: focus,
                  builder: (context, _) {
                    final active = focus.hasFocus && (i == digits.length || (i == 5 && digits.length == 6));
                    return Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: i < digits.length ? Brand.light : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Brand.blue, width: active ? 2.2 : 1.2),
                      ),
                      child: Text(
                        i < digits.length ? digits[i] : '',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Brand.ink),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ]),
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: controller,
              focusNode: focus,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              showCursor: false,
              enableInteractiveSelection: false,
              decoration: const InputDecoration(border: InputBorder.none, filled: false, counterText: ''),
              onChanged: (v) {
                if (v.length == 6) onDone();
              },
            ),
          ),
        ),
      ]),
    );
  }
}

/// New password: at least 6 characters, typed twice.
class NewPasswordScreen extends StatefulWidget {
  final String resetToken;
  const NewPasswordScreen({super.key, required this.resetToken});

  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  ApiException? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await app.api.post('/api/auth/forgot/reset', {
        'resetToken': widget.resetToken,
        'password': _password.text,
        'confirm': _confirm.text,
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New password')),
      body: Body([
        if (_error != null) MsgBanner(_error!.title, sub: _error!.message),
        const Text('Set a new password', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const Gap(4),
        const Text('At least 6 characters.', style: TextStyle(color: Brand.muted)),
        const Gap(14),
        Field('New password', _password, kind: FieldKind.password, action: TextInputAction.next),
        Field('Confirm new password', _confirm,
            kind: FieldKind.password, action: TextInputAction.done, onSubmitted: (_) => _save()),
        const Gap(4),
        Btn('Save', _save, busy: _busy),
      ]),
    );
  }
}
