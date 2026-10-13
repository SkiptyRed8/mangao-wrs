import 'package:flutter/material.dart';

import '../../models/order.dart';
import '../../services/api.dart';
import '../../services/app_state.dart';
import '../../theme/brand.dart';
import '../../widgets/common.dart';

/// Rider label in the send-out popup: "Juan Dela Cruz" or "Me (Owner)" / "Owner".
String riderLabel(Order o) {
  if (o.riderRole == 'Owner' || o.riderId == null) return app.isOwner ? 'Me (Owner)' : 'Owner';
  return o.riderName ?? 'Rider';
}

/// Staff 3 / Admin Orders 5: Mark Out for Delivery for one, several or all Processing orders.
/// One rider per batch (one sidecar): orders with different riders go out as separate batches.
/// The tank counter goes up and seals go down (first time only). Returns true when sent.
Future<bool> sendOut(BuildContext context, List<Order> orders) async {
  if (orders.isEmpty) return false;
  final groups = <String, List<Order>>{};
  for (final o in orders) {
    groups.putIfAbsent(riderLabel(o), () => []).add(o);
  }
  ApiException? err;
  var busy = false;
  String? message;
  final many = groups.length > 1;
  final names = orders.map((o) => o.name.isEmpty ? 'Guest' : o.name).join(', ');
  final one = orders.length == 1 ? orders.first : null;
  final entries = groups.entries.toList();

  final ok = await sheet<bool>(
    context,
    many ? 'Different riders' : 'Send out for delivery?',
    sub: many
        ? 'The selected orders have different riders. They will go out as separate batches, one per rider.'
        : one != null
            ? '$names, ${one.quantity} ${one.quantity == 1 ? 'gallon' : 'gallons'}. Rider: ${groups.keys.first}.'
            : '$names. Rider: ${groups.keys.first}.',
    (c, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (err != null) MsgBanner(err!.title, sub: err!.message),
      if (many)
        for (var i = 0; i < entries.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Box(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Label('Batch ${i + 1} · ${entries[i].key}'),
                const Gap(4),
                for (final o in entries[i].value) Text('${o.name.isEmpty ? 'Guest' : o.name} · ${o.quantity} ${o.quantity == 1 ? 'gallon' : 'gallons'}'),
              ]),
            ),
          ),
      const Note("Tank counter goes up and seals go down. The rider's location is shared. Customers see Out for Delivery."),
      const Gap(12),
      Btn(many ? (groups.length == 2 ? 'Send both batches' : 'Send all ${groups.length} batches') : 'Confirm (${orders.length})', () async {
        set(() {
          busy = true;
          err = null;
        });
        try {
          final r = await app.api.post('/api/work/out', {'ids': [for (final o in orders) o.id]});
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

/// Rider 3 / Admin Orders 6: Delivered. Orders already paid at the station only need a confirmation;
/// others ask "Paid or Unpaid?". [path] is the server route ('/api/rider/orders' or '/api/admin/orders').
Future<bool> recordDelivered(BuildContext context, Order o, {String path = '/api/rider/orders'}) async {
  final name = o.name.isEmpty ? 'Guest' : o.name;
  bool? paid;
  if (o.paymentStatus == 'Paid') {
    final ok = await confirm(context, 'Delivered?',
        sub: '$name · ${o.quantity} ${o.quantity == 1 ? 'gallon' : 'gallons'}. Already paid at the station, so no payment question.');
    if (!ok) return false;
    paid = true;
  } else {
    paid = await sheet<bool>(
      context,
      'Paid or Unpaid?',
      sub: '$name · ₱${o.total.toStringAsFixed(2)} · ${o.paymentText}',
      (c, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Gap(6),
        Btn('Paid', () => Navigator.pop(c, true)),
        const Gap(),
        Btn('Unpaid', () => Navigator.pop(c, false), outline: true),
      ]),
    );
    if (paid == null) return false;
  }
  try {
    final r = await app.api.post('$path/${o.id}/delivered', {'paid': paid});
    if (context.mounted) toast(context, (r['message'] ?? 'Delivered.') as String);
    return true;
  } on ApiException catch (e) {
    if (context.mounted) toast(context, '${e.title}. ${e.message}', error: true);
    return false;
  }
}

/// Rider 4: Not delivered with an optional note. The owner then re-delivers or cancels.
Future<bool> recordNotDelivered(BuildContext context, Order o, {String path = '/api/rider/orders'}) {
  final note = TextEditingController();
  return formSheet(
    context,
    'Not delivered',
    button: 'Confirm',
    fields: (set) => [
      Text('${o.name.isEmpty ? 'Guest' : o.name} · ${o.address}', style: const TextStyle(color: Brand.muted)),
      const Gap(10),
      Field('Note (optional)', note, hint: 'e.g. Not home, will call later', lines: 3),
      const Note('The owner decides to re-deliver or cancel. The customer is notified.'),
    ],
    onSave: () async {
      final r = await app.api.post('$path/${o.id}/not-delivered', {'note': note.text});
      return r['message'] as String?;
    },
  );
}
