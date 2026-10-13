import 'package:flutter/material.dart';

import '../../models/user.dart';
import '../../services/app_state.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../../widgets/watch.dart';
import '../shell.dart';

/// My Account (More 5, Staff 7, Rider 7, Customer 8): profile and Log out.
/// Edit profile and Change password are added in step 11.
class AccountScreen extends StatelessWidget {
  final bool pushed;
  const AccountScreen({super.key, this.pushed = false});

  Future<void> _logout(BuildContext context) async {
    final ok = await confirm(context, 'Log out?', sub: 'Session ends on this phone.', ok: 'Log out');
    if (!ok || !context.mounted) return;
    toRoot(context);
    await app.logout();
  }

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final u = app.user;
      return Scaffold(
        appBar: topBar(context, 'My Account', back: pushed),
        body: Body([
          if (u != null)
            Box(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Expanded(child: Label('Profile')),
                  Tag(roleName(u.role), filled: true),
                ]),
                const Gap(4),
                KV('Name', u.name),
                KV('Phone number', phoneFmt(u.phone)),
                KV('Email', u.email.isEmpty ? '-' : u.email, last: true),
              ]),
            ),
          if (app.guest) const Note('Guest Mode: orders are kept on this phone only'),
          const Gap(12),
          const ComingSoonCard(step: 11, what: 'Edit profile and Change password'),
          const Gap(16),
          Btn(app.guest ? 'Exit guest mode' : 'Log out', () => _logout(context), outline: true),
        ]),
      );
    });
  }
}
