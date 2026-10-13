import 'package:flutter/material.dart';

import '../../models/user.dart';
import '../../services/app_state.dart';
import '../../theme/brand.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../../widgets/watch.dart';
import '../auth/signup_screen.dart';
import '../shell.dart';

/// My Account (Admin More 5, Staff 7, Rider 7, Customer 8): profile, Change password, Log out.
/// The owner and customers edit their profile; staff and riders see it only (the owner edits them).
class AccountScreen extends StatelessWidget {
  final bool pushed;
  const AccountScreen({super.key, this.pushed = false});

  Future<void> _logout(BuildContext context) async {
    final ok = await confirm(
      context,
      app.guest ? 'Exit guest mode?' : 'Log out?',
      sub: app.guest ? 'Orders kept on this phone will no longer be shown.' : null,
    );
    if (!ok || !context.mounted) return;
    toRoot(context);
    await app.logout();
  }

  Future<void> _edit(BuildContext context, AppUser u) async {
    final name = TextEditingController(text: u.name);
    final phone = TextEditingController(text: phoneFmt(u.phone));
    final email = TextEditingController(text: u.email);
    await formSheet(
      context,
      u.role == Role.customer ? 'Edit profile form' : 'Edit form',
      fields: (set) => [
        Field('Name', name, kind: FieldKind.name),
        Field('Phone', phone, kind: FieldKind.phone),
        Field('Email', email,
            kind: FieldKind.email,
            helper: 'Phone number and email are both required. The email is where the code goes when you reset your password.'),
      ],
      onSave: () async {
        final r = await app.api.put('/api/account/profile', {'name': name.text, 'phone': phone.text, 'email': email.text});
        await app.setUser(AppUser.fromJson(r['user'] as Map<String, dynamic>));
        return r['message'] as String?;
      },
    );
  }

  Future<void> _password(BuildContext context) async {
    final old = TextEditingController();
    final next = TextEditingController();
    await formSheet(
      context,
      'Password form',
      fields: (set) => [
        Field('Old password', old, hint: 'Enter old password', kind: FieldKind.password),
        Field('New password', next, hint: 'Enter new password', kind: FieldKind.password, helper: 'At least 6 characters.'),
      ],
      onSave: () async {
        final r = await app.api.post('/api/account/password', {'oldPassword': old.text, 'newPassword': next.text});
        return r['message'] as String?;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final u = app.user;
      final canEdit = u != null && (u.role == Role.owner || u.role == Role.customer);
      final customer = u?.role == Role.customer;
      return Scaffold(
        appBar: topBar(context, 'My Account', back: pushed),
        body: Body([
          if (u != null)
            Box(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Expanded(child: Label('Profile')),
                  if (canEdit) SmallBtn('Edit', () => _edit(context, u)),
                ]),
                const Gap(4),
                Text(u.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const Gap(2),
                Text(phoneFmt(u.phone), style: const TextStyle(fontFamily: 'monospace', color: Brand.ink, letterSpacing: 0.5)),
                Text(u.email.isEmpty ? '-' : u.email, style: const TextStyle(color: Brand.muted)),
              ]),
            ),
          if (customer) ...[
            const Section('Saved Addresses'),
            const ComingSoonCard(step: 15, what: 'Saved addresses: Home, Work and more, pinned on the map'),
          ],
          if (app.guest) ...[
            const Note('Guest Mode: orders are kept on this phone only'),
            Btn('Create account', () => go(context, const SignupScreen())),
          ],
          const Gap(12),
          if (u != null) ...[
            Btn('Change password', () => _password(context), outline: true),
            const Gap(),
          ],
          Btn(app.guest ? 'Exit guest mode' : 'Log out', () => _logout(context), outline: true),
        ]),
      );
    });
  }
}
