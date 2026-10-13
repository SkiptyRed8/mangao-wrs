import 'package:flutter/material.dart';

import '../../services/api.dart';
import '../../services/app_state.dart';
import '../../widgets/common.dart';
import '../common/coming_soon.dart';

/// Login 1, 2: phone number and password; messages "Details wrong" and
/// "Cannot log in until activated again". After log in the app opens the role's Home.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  ApiException? _error;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await app.login(_phone.text, _password.text);
      if (mounted) toRoot(context);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _busy = false;
          _password.clear(); // wireframe: the password is cleared after an error
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Log in')),
      body: Body([
        if (_error != null) MsgBanner(_error!.title, sub: _error!.message),
        Field('Phone number', _phone, hint: '09XX XXX XXXX', kind: FieldKind.phone, action: TextInputAction.next),
        Field('Password', _password,
            hint: 'Password', kind: FieldKind.password, action: TextInputAction.done, onSubmitted: (_) => _login()),
        const Gap(8),
        Btn('Log in', _login, busy: _busy),
        const Gap(10),
        Center(
          child: LinkText(
            'Forgot password',
            () => go(context, const ComingSoon('Forgot password', step: 8, what: '6-digit code sent to the account email', pushed: true)),
          ),
        ),
      ]),
    );
  }
}
