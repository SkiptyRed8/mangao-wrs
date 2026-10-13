import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../services/api.dart';
import '../../services/app_state.dart';
import '../../theme/brand.dart';
import '../../widgets/common.dart';

/// Login 3 / 3A: Sign up (customers only). Name, phone number, email, password, confirm password
/// and the consent box. After "Account created" -> Continue opens Customer Home.
/// A guest who signs up here keeps the orders made on this phone (Customer 10).
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _consent = false;
  bool _wasGuest = false;
  ApiException? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  String? get _errorField => _error?.data['field'] as String?;

  /// Customer 10: a guest who creates an account gets the name and phone from the last order on this phone.
  @override
  void initState() {
    super.initState();
    if (app.guest) {
      app.api.get('/api/orders').then((r) {
        final list = r['orders'] as List;
        if (list.isEmpty || !mounted) return;
        final o = list.first as Map<String, dynamic>;
        setState(() {
          if (_name.text.isEmpty) _name.text = (o['name'] ?? '') as String;
          if (_phone.text.isEmpty) _phone.text = (o['phone'] ?? '') as String;
        });
      }).catchError((_) {});
    }
  }

  Future<void> _openTerms() async {
    final agreed = await go<bool>(context, const TermsScreen());
    if (agreed == true && mounted) {
      setState(() {
        _consent = true;
        if (_errorField == 'consent') _error = null;
      });
    }
  }

  Future<void> _create() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    _wasGuest = app.guest;
    try {
      await app.signup(
        name: _name.text,
        phone: _phone.text,
        email: _email.text,
        password: _password.text,
        confirm: _confirm.text,
        consent: _consent,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      await _created();
      if (mounted) toRoot(context);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _busy = false;
        });
      }
    }
  }

  /// "Account created" message (Login 3, Result: Account created).
  Future<void> _created() {
    final first = (app.user?.name ?? '').split(' ').first;
    final wasGuest = _wasGuest;
    return sheet<void>(
      context,
      '',
      close: false,
      dismissible: false,
      (c, set) => Column(children: [
        Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(color: Brand.blue, shape: BoxShape.circle),
          child: const Icon(Icons.check, color: Colors.white, size: 32),
        ),
        const Gap(12),
        const Text('Account created', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const Gap(6),
        Text(
          wasGuest
              ? 'Welcome${first.isEmpty ? '' : ', $first'}! The orders on this phone are now in your account.'
              : 'Welcome${first.isEmpty ? '' : ', $first'}! Your account is ready. You can now order and track your gallons.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Brand.muted),
        ),
        const Gap(24),
        Btn('Continue', () => Navigator.pop(c)),
      ]),
    );
  }

  /// Red border on the field the message is about (wireframe 3A).
  Widget _mark(String field, Widget child) => ErrorWrap(_errorField == field, child);

  @override
  Widget build(BuildContext context) {
    const linkStyle = TextStyle(
      fontWeight: FontWeight.w800,
      color: Brand.blue,
      decoration: TextDecoration.underline,
      decorationColor: Brand.blue,
    );
    final consentWrong = _errorField == 'consent';
    return Scaffold(
      appBar: AppBar(title: const Text('Sign up')),
      body: Body([
        if (_error != null) MsgBanner(_error!.title, sub: _error!.message),
        _mark('name', Field('Name', _name, hint: 'Full name', kind: FieldKind.name, action: TextInputAction.next)),
        _mark('phone', Field('Phone number', _phone, hint: '09XX XXX XXXX', kind: FieldKind.phone, action: TextInputAction.next)),
        _mark(
          'email',
          Field('Email', _email,
              hint: 'Used to reset your password',
              helper: 'Phone number and email are both required.',
              kind: FieldKind.email,
              action: TextInputAction.next),
        ),
        _mark('password',
            Field('Password', _password, hint: 'Create a password', kind: FieldKind.password, action: TextInputAction.next)),
        _mark('confirm',
            Field('Confirm password', _confirm, hint: 'Type it again', kind: FieldKind.password, action: TextInputAction.done)),
        Container(
          padding: consentWrong ? const EdgeInsets.all(6) : EdgeInsets.zero,
          decoration: consentWrong
              ? BoxDecoration(borderRadius: BorderRadius.circular(10), color: Brand.redLight, border: Border.all(color: Brand.red, width: 1.6))
              : null,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Checkbox(
              value: _consent,
              onChanged: (v) => setState(() {
                _consent = v ?? false;
                if (_consent && consentWrong) _error = null;
              }),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text.rich(TextSpan(style: const TextStyle(color: Brand.ink, height: 1.35), children: [
                  const TextSpan(text: 'I have read and agree to the '),
                  TextSpan(text: 'Terms and Conditions', style: linkStyle, recognizer: TapGestureRecognizer()..onTap = _openTerms),
                  const TextSpan(text: ' and '),
                  TextSpan(text: 'Data Privacy Notice', style: linkStyle, recognizer: TapGestureRecognizer()..onTap = _openTerms),
                  const TextSpan(text: ' of Mangao Water Refilling Station.'),
                ])),
              ),
            ),
          ]),
        ),
        const Gap(16),
        Btn('Create account', _create, busy: _busy),
        if (_error?.code == 'PHONE_USED') ...[
          const Gap(10),
          Center(child: LinkText('Log in instead', () => Navigator.pop(context))),
        ],
      ]),
    );
  }
}

/// Terms and Data Privacy Notice (Login 3). "I agree" ticks the consent box.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  static const _parts = [
    ('Who we are', 'Mangao Water Refilling Station, 98 Riverside St., Barangay Commonwealth, Quezon City. Phone 0917 000 0000.'),
    ('What we collect', 'Your name, phone number, email, delivery addresses and map pins, and your orders and payments (Paid or Unpaid).'),
    (
      'Why we collect it',
      'To take, refill, deliver and track your orders, to contact you about an order, to keep a record of unpaid orders, '
          'and to send a code when you reset your password.'
    ),
    (
      'Who can see it',
      'Only the owner, staff and riders of the station, for your orders. Riders see your location only while delivering. '
          'We do not sell or share your data.'
    ),
    ('How long we keep it', 'While your account is active. You can ask the station to delete your account and data.'),
    (
      'Your rights',
      'Under the Data Privacy Act of 2012 (RA 10173), you can ask to see, correct or delete your data. Contact the station to do this.'
    ),
    (
      'Terms of ordering',
      'Prices apply to new orders only. You can cancel an order only before it is accepted. Unpaid orders are recorded on your account.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terms and Data Privacy Notice')),
      body: Body([
        const Text('Last updated: Oct 2026', style: TextStyle(color: Brand.muted, fontSize: 12.5)),
        const Gap(6),
        for (final (title, body) in _parts) ...[
          const Gap(10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const Gap(3),
          Text(body, style: const TextStyle(height: 1.4)),
        ],
      ]),
      bottomNavigationBar: Bottom([Btn('I agree', () => Navigator.pop(context, true))]),
    );
  }
}
