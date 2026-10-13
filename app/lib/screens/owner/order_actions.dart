import 'package:flutter/material.dart';

import '../../models/order.dart';
import '../../services/api.dart';
import '../../services/app_state.dart';
import '../../theme/brand.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';

/// A rider the owner can choose: active riders, then "Me (Owner)".
class RiderOption {
  final int id;
  final String name;
  final bool owner;
  const RiderOption(this.id, this.name, this.owner);
}

Future<(List<RiderOption>, List<String>)> loadRiders() async {
  final r = await app.api.get('/api/admin/orders/riders');
  final riders = [
    for (final x in r['riders'] as List)
      RiderOption(((x as Map<String, dynamic>)['id'] as num).toInt(), x['name'] as String, x['owner'] == true),
  ];
  final reasons = [for (final x in r['reasons'] as List) x as String];
  return (riders, reasons);
}

/// Preview of the automatic delivery time on this computer's clock (the server sets the real one):
/// 30 minutes after accepting; 11:30 to 12:00 -> 1:00 to 1:30 PM.
String deliveryPreview() {
  final t = ph(DateTime.now());
  final m = t.hour * 60 + t.minute;
  if (m >= 11 * 60 + 30 && m < 12 * 60) return '1:00 to 1:30 PM (lunch time rule)';
  return '${timeFmt(t.add(const Duration(minutes: 30)))} (30 minutes)';
}

/// Admin Orders 3: Accept order? / Accept 3 orders?  Choose one rider (one sidecar) for all of them;
/// the delivery time is set automatically. Returns true when accepted.
Future<bool> acceptOrders(BuildContext context, List<Order> orders) async {
  if (orders.isEmpty) return false;
  List<RiderOption> riders;
  try {
    riders = (await loadRiders()).$1;
  } on ApiException catch (e) {
    if (context.mounted) toast(context, e.message);
    return false;
  }
  if (!context.mounted) return false;
  final realRiders = riders.where((r) => !r.owner).toList();
  int? chosen = realRiders.length == 1 ? realRiders.first.id : (realRiders.isEmpty ? riders.last.id : null);
  final many = orders.length > 1;
  ApiException? err;
  var busy = false;
  String? message;

  final ok = await sheet<bool>(
    context,
    many ? 'Accept ${orders.length} orders?' : 'Accept order?',
    sub: many
        ? '${orders.map((o) => o.name).join(', ')}. Choose one rider for all of them (one sidecar).'
        : 'Choose one rider. The delivery time is set automatically.',
    (c, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (err != null) MsgBanner(err!.title, sub: err!.message),
      for (final r in riders)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Box(
            tint: chosen == r.id,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            onTap: () => set(() => chosen = r.id),
            child: Row(children: [
              Icon(chosen == r.id ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: Brand.blue),
              const SizedBox(width: 10),
              Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      Note(many
          ? 'Delivery time for each: ${deliveryPreview()} after accepting.'
          : 'Estimated delivery: ${deliveryPreview()}. Orders accepted 11:30 to 12:00 get 1:00 to 1:30 PM.'),
      const Gap(8),
      Btn('Confirm', chosen == null
          ? null
          : () async {
              set(() {
                busy = true;
                err = null;
              });
              try {
                final r = await app.api.post('/api/admin/orders/accept', {'ids': [for (final o in orders) o.id], 'riderId': chosen});
                message = r['message'] as String?;
                if (c.mounted) Navigator.pop(c, true);
              } on ApiException catch (e) {
                set(() {
                  err = e;
                  busy = false;
                });
              }
            }, busy: busy),
      const Gap(),
      Btn('Cancel', () => Navigator.pop(c, false), outline: true),
    ]),
  );
  if (ok == true && message != null && context.mounted) toast(context, message!);
  return ok == true;
}

/// Admin Orders 3: Decline -> Choose reason (Other: type it). Returns true when declined.
Future<bool> declineOrder(BuildContext context, Order o) async {
  List<String> reasons;
  try {
    reasons = (await loadRiders()).$2;
  } on ApiException catch (e) {
    if (context.mounted) toast(context, e.message);
    return false;
  }
  if (!context.mounted) return false;
  final reason = await choose(context, 'Choose reason', reasons, current: reasons.first);
  if (reason == null || !context.mounted) return false;
  final other = TextEditingController();
  if (reason == 'Other') {
    return formSheet(
      context,
      'Other reason',
      button: 'Confirm',
      fields: (set) => [Field('Reason', other, hint: 'e.g. The station is closed for today.', helper: 'The customer sees this reason.')],
      onSave: () async {
        final r = await app.api.post('/api/admin/orders/${o.id}/decline', {'reason': 'Other', 'other': other.text});
        return r['message'] as String?;
      },
    );
  }
  try {
    final r = await app.api.post('/api/admin/orders/${o.id}/decline', {'reason': reason});
    if (context.mounted) toast(context, (r['message'] ?? 'Declined') as String);
    return true;
  } on ApiException catch (e) {
    if (context.mounted) toast(context, '${e.title}. ${e.message}');
    return false;
  }
}

/// Admin Orders 4: Change rider (only while the order is in Processing). Returns true when changed.
Future<bool> changeRider(BuildContext context, Order o) async {
  List<RiderOption> riders;
  try {
    riders = (await loadRiders()).$1;
  } on ApiException catch (e) {
    if (context.mounted) toast(context, e.message);
    return false;
  }
  if (!context.mounted) return false;
  String? current;
  for (final r in riders) {
    if (r.id == o.riderId) current = r.name;
  }
  final pick = await sheet<String>(
    context,
    'Change rider',
    sub: 'Only while the order is in Processing.',
    (c, set) {
      var sel = current;
      return StatefulBuilder(
        builder: (c2, set2) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final r in riders)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Box(
                tint: sel == r.name,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                onTap: () => set2(() => sel = r.name),
                child: Row(children: [
                  Icon(sel == r.name ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: Brand.blue),
                  const SizedBox(width: 10),
                  Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          const Gap(8),
          Btn('Confirm', () => Navigator.pop(c, sel)),
        ]),
      );
    },
  );
  if (pick == null || pick == current || !context.mounted) return false;
  final id = riders.firstWhere((r) => r.name == pick).id;
  try {
    final r = await app.api.post('/api/admin/orders/${o.id}/rider', {'riderId': id});
    if (context.mounted) toast(context, (r['message'] ?? 'Rider changed') as String);
    return true;
  } on ApiException catch (e) {
    if (context.mounted) toast(context, '${e.title}. ${e.message}');
    return false;
  }
}

/// Buttons for steps that come in Sprint 2.
void comingInStep(BuildContext context, int step, String what) => toast(context, '$what comes in step $step');
