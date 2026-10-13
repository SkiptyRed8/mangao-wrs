import 'package:flutter/material.dart';

import '../../models/user.dart';
import '../../services/app_state.dart';
import '../../theme/brand.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';

/// A staff member, rider or the owner as listed in Staff & Riders.
class StaffAccount {
  final int id;
  final String name;
  final String phone;
  final String email;
  final Role role;
  final bool active;

  const StaffAccount(this.id, this.name, this.phone, this.email, this.role, this.active);

  factory StaffAccount.fromJson(Map<String, dynamic> j) => StaffAccount(
        (j['id'] as num).toInt(),
        (j['name'] ?? '') as String,
        (j['phone'] ?? '') as String,
        (j['email'] ?? '') as String,
        roleFrom(j['role'] as String?),
        j['active'] == true,
      );
}

/// Admin More 2: Staff & Riders. "+ Add account", then the list; the Owner (all roles) has no arrow.
class StaffListScreen extends StatefulWidget {
  const StaffListScreen({super.key});

  @override
  State<StaffListScreen> createState() => _StaffListScreenState();
}

class _StaffListScreenState extends State<StaffListScreen> {
  final _loader = GlobalKey<LoaderState<List<StaffAccount>>>();

  Future<List<StaffAccount>> _load() async {
    final r = await app.api.get('/api/staff');
    return [for (final a in r['accounts'] as List) StaffAccount.fromJson(a as Map<String, dynamic>)];
  }

  Future<void> _reload() async => _loader.currentState?.reload();

  Future<void> _add() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final email = TextEditingController();
    final password = TextEditingController();
    var role = 0; // 0 Staff, 1 Rider
    final saved = await formSheet(
      context,
      'New account form',
      fields: (set) => [
        Field('Name', name, hint: 'Full name', kind: FieldKind.name),
        Field('Phone', phone, hint: '09XX XXX XXXX', kind: FieldKind.phone),
        Field('Email', email, hint: 'Used to reset the password', kind: FieldKind.email),
        const Label('Staff or Rider'),
        const Gap(6),
        Seg(const ['Staff', 'Rider'], role, (i) => set(() => role = i)),
        const Gap(12),
        Field('Temporary password', password,
            hint: 'Create a password',
            kind: FieldKind.password,
            helper: 'They can change it later, or reset it with a code sent to their email.'),
      ],
      onSave: () async {
        final r = await app.api.post('/api/staff', {
          'name': name.text,
          'phone': phone.text,
          'email': email.text,
          'role': role == 0 ? 'Staff' : 'Rider',
          'password': password.text,
        });
        return r['message'] as String?;
      },
    );
    if (saved) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Staff & Riders')),
      body: Loader<List<StaffAccount>>(
        key: _loader,
        load: _load,
        builder: (context, list, reload) => Body([
          Btn('+ Add account', _add),
          const Gap(12),
          for (final a in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Box(
                tint: a.role == Role.owner,
                onTap: a.role == Role.owner
                    ? null
                    : () async {
                        await go(context, StaffDetailsScreen(account: a));
                        await reload();
                      },
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a.role == Role.owner ? 'Owner' : a.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      Text(a.role == Role.owner ? 'Owner (all roles)' : roleName(a.role),
                          style: const TextStyle(color: Brand.muted, fontSize: 13)),
                    ]),
                  ),
                  Tag(a.active ? 'Active' : 'Inactive', filled: a.active),
                  if (a.role != Role.owner) const Icon(Icons.chevron_right, color: Brand.blue) else const SizedBox(width: 24),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Account details: Name, Phone, Email, Role. Edit, Deactivate (or Activate), Reset password.
class StaffDetailsScreen extends StatefulWidget {
  final StaffAccount account;
  const StaffDetailsScreen({super.key, required this.account});

  @override
  State<StaffDetailsScreen> createState() => _StaffDetailsScreenState();
}

class _StaffDetailsScreenState extends State<StaffDetailsScreen> {
  late StaffAccount _a = widget.account;
  bool _busy = false;

  Future<void> _edit() async {
    final name = TextEditingController(text: _a.name);
    final phone = TextEditingController(text: phoneFmt(_a.phone));
    final email = TextEditingController(text: _a.email);
    await formSheet(
      context,
      'Edit form',
      fields: (set) => [
        Field('Name', name, kind: FieldKind.name),
        Field('Phone', phone, kind: FieldKind.phone),
        Field('Email', email, kind: FieldKind.email),
      ],
      onSave: () async {
        final r = await app.api.put('/api/staff/${_a.id}', {'name': name.text, 'phone': phone.text, 'email': email.text});
        if (mounted) setState(() => _a = StaffAccount.fromJson(r['account'] as Map<String, dynamic>));
        return r['message'] as String?;
      },
    );
  }

  Future<void> _toggle() async {
    final deactivate = _a.active;
    if (deactivate) {
      final ok = await confirm(context, 'Deactivate this account?',
          sub: '${_a.name} cannot log in until activated again.', ok: 'Confirm');
      if (!ok) return;
    }
    await _run(() async {
      final r = await app.api.post('/api/staff/${_a.id}/${deactivate ? 'deactivate' : 'activate'}');
      setState(() => _a = StaffAccount.fromJson(r['account'] as Map<String, dynamic>));
      return r['message'] as String?;
    });
  }

  Future<void> _resetPassword() async {
    final ok = await confirm(context, 'Reset password?', sub: 'Use this only if they cannot get the code from their email.');
    if (!ok || !mounted) return;
    String? temp;
    await _run(() async {
      final r = await app.api.post('/api/staff/${_a.id}/reset-password');
      temp = r['tempPassword'] as String?;
      return null;
    });
    if (temp == null || !mounted) return;
    await sheet<void>(
      context,
      'Temporary password',
      sub: 'Give this to ${_a.name}. They can change it after logging in.',
      (c, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Box(
          child: SelectableText(
            temp!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, fontFamily: 'monospace', letterSpacing: 1.5),
          ),
        ),
        const Gap(24),
        Btn('Done', () => Navigator.pop(c)),
      ]),
    );
  }

  /// Runs a server call with the spinner; shows its message, or the error.
  Future<void> _run(Future<String?> Function() call) async {
    setState(() => _busy = true);
    try {
      final msg = await call();
      if (mounted && msg != null) toast(context, msg);
    } on Exception catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account details')),
      body: Body([
        if (!_a.active) const Align(alignment: Alignment.centerLeft, child: Tag('Inactive')),
        if (!_a.active) const Gap(8),
        Box(
          child: Column(children: [
            KV('Name', _a.name),
            KV('Phone', phoneFmt(_a.phone)),
            KV('Email', _a.email.isEmpty ? '-' : _a.email),
            KV('Role', roleName(_a.role), last: true),
          ]),
        ),
        const Gap(12),
        Btn('Edit', _busy ? null : _edit, outline: true),
        const Gap(),
        Btn(_a.active ? 'Deactivate' : 'Activate', _busy ? null : _toggle, outline: true),
        const Gap(),
        Btn('Reset password', _busy ? null : _resetPassword, outline: true),
        if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
      ]),
    );
  }
}
