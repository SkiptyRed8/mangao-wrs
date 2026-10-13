import 'package:flutter/material.dart';

import '../../services/api.dart';
import '../../services/app_state.dart';
import '../../widgets/common.dart';
import 'forgot_screens.dart';

/// Login 1, 2: phone number and password; messages "Details wrong" and
/// "Cannot log in until activated again", and Forgot password. After log in the app opens the role's Home.
class LoginScreen extends StatefulWidget {
  /// Grey note at the top, e.g. "Session ends" after Log out.
  final String? note;
  const LoginScreen({super.key, this.note});

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

  /// Wrong phone number or password, or a field left empty (not for server or network problems).
  bool get _wrongDetails => _error != null && _error!.status >= 400 && _error!.status < 500;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Log in')),
      body: Body([
        if (_error != null) MsgBanner(_error!.title, sub: _error!.message),
        if (_error == null && widget.note != null) Note(widget.note!),
        Field('Phone number', _phone,
            hint: '09XX XXX XXXX', kind: FieldKind.phone, action: TextInputAction.next, error: _wrongDetails),
        Field('Password', _password,
            hint: 'Password',
            kind: FieldKind.password,
            action: TextInputAction.done,
            onSubmitted: (_) => _login(),
            error: _wrongDetails),
        const Gap(8),
        Btn('Log in', _login, busy: _busy),
        const Gap(10),
        Center(
          child: LinkText('Forgot password', () async {
            final changed = await go<bool>(context, const ForgotPasswordScreen());
            if (changed == true && context.mounted) {
              setState(() => _error = null);
              _password.clear();
              toast(context, 'Password changed. Log in with your new password.');
            }
          }),
        ),
      ]),
    );
  }
}
