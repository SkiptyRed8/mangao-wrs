import 'package:flutter/material.dart';

import '../../services/api.dart';
import '../../services/app_state.dart';
import '../../theme/brand.dart';
import '../../widgets/common.dart';

/// Admin Home 6 / Staff 1: Tank Alert & Counter. Gallons counted since the last refill out of the
/// tank limit (60). At the limit: owner "Refill the water tank", staff "Tell the owner...".
/// Only the owner taps "Water tank refilled" (counter back to 0).
class TankCard extends StatelessWidget {
  final int count;
  final int limit;
  final bool owner;
  final Future<void> Function()? onReset;
  const TankCard({super.key, required this.count, required this.limit, this.owner = false, this.onReset});

  factory TankCard.fromJson(Map<String, dynamic> t, {bool owner = false, Future<void> Function()? onReset}) => TankCard(
        count: (t['count'] as num).toInt(),
        limit: (t['limit'] as num).toInt(),
        owner: owner,
        onReset: onReset,
      );

  Future<void> _reset(BuildContext context) async {
    final ok = await confirm(context, 'Water tank refilled?', sub: 'The counter goes back to 0 and the alert clears.');
    if (!ok || !context.mounted) return;
    try {
      final r = await app.api.post('/api/work/tank/reset');
      if (context.mounted) toast(context, (r['message'] ?? 'Counter = 0') as String);
      await onReset?.call();
    } on ApiException catch (e) {
      if (context.mounted) toast(context, '${e.title}. ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final full = count >= limit;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Box(
        tint: full,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(owner ? 'Tank Alert & Counter' : 'Tank Counter', style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('Gallons counted out of $limit', style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
              ]),
            ),
            Text('$count / $limit', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
          ]),
          const Gap(8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: limit == 0 ? 0 : (count / limit).clamp(0, 1).toDouble(), minHeight: 10),
          ),
          if (owner) ...[
            const Gap(10),
            Align(alignment: Alignment.centerRight, child: SmallBtn('Water tank refilled', () => _reset(context))),
          ],
        ]),
      ),
      if (full) ...[
        const Gap(8),
        MsgBanner(owner ? 'Refill the water tank' : 'Tell the owner: water tank needs refilling',
            sub: owner ? '$count gallons processed since the last refill. Tap Water tank refilled after.' : null),
      ],
    ]);
  }
}
