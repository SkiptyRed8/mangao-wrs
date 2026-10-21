import 'package:flutter/material.dart';

import '../../services/app_state.dart';
import '../../theme/brand.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../common/loans.dart';
import '../shell.dart';

/// One line of the stock Entries list / Movement History.
class Movement {
  final int change;
  final String itemLabel;
  final String label;
  final String note;
  final int? orderId;
  final bool automatic;
  final String by;
  final DateTime? at;
  const Movement(this.change, this.itemLabel, this.label, this.note, this.orderId, this.automatic, this.by, this.at);

  factory Movement.fromJson(Map<String, dynamic> j) => Movement(
        (j['change'] as num).toInt(),
        (j['itemLabel'] ?? '') as String,
        (j['label'] ?? '') as String,
        (j['note'] ?? '') as String,
        (j['orderId'] as num?)?.toInt(),
        j['automatic'] == true,
        (j['by'] ?? '') as String,
        DateTime.tryParse((j['at'] ?? '') as String),
      );
}

String _day(DateTime? t) {
  if (t == null) return '';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final p = ph(t);
  return '${m[p.month - 1]} ${p.day}';
}

String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// One entry row: "+20  Stock added  Sep 27 · Owner" / "-3  Gallon sealed  Sep 28 · Order #1042 · Automatic".
class MovementRow extends StatelessWidget {
  final Movement m;
  final bool showItem;
  const MovementRow(this.m, {super.key, this.showItem = false});

  @override
  Widget build(BuildContext context) {
    final sub = [
      if (showItem) m.label,
      _day(m.at),
      if (m.orderId != null) 'Order #${m.orderId}',
      if (!m.automatic && m.by.isNotEmpty) m.by,
      if (m.automatic) 'Automatic',
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Brand.soft))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 64,
          child: Text(m.change > 0 ? '+${m.change}' : '${m.change}',
              style: TextStyle(fontWeight: FontWeight.w800, fontFamily: 'monospace', fontSize: 16, color: m.change > 0 ? Brand.blue : Brand.ink)),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(showItem ? m.itemLabel : m.label, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(sub, style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
            if (m.note.isNotEmpty) Text(m.note, style: const TextStyle(fontSize: 12.5)),
          ]),
        ),
      ]),
    );
  }
}

/// Admin Inventory 1: Stock Overview. Low-stock warning at the level set in Settings, New Gallons and
/// Seals counts, Movement History, Borrowed Gallons (Admin Inventory 5).
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();

  Widget _count(String label, Map<String, dynamic> item, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Box(
          onTap: onTap,
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Label(label),
                const Gap(8),
                Text('${item['quantity']}', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
                Text('Low-stock level: ${item['level']}', style: const TextStyle(color: Brand.muted, fontSize: 12)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Brand.blue),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: topBar(context, 'Stock Overview'),
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () => app.api.get('/api/inventory'),
        builder: (context, d, reload) {
          final g = d['gallons'] as Map<String, dynamic>;
          final s = d['seals'] as Map<String, dynamic>;
          Future<void> open(String item) async {
            await go(context, StockItemScreen(item: item, sealsPerGallon: (d['sealsPerGallon'] as num).toInt()));
            await reload();
          }

          return Body([
            if (g['low'] == true) LowStockBanner('New Gallons: ${g['quantity']} left', onTap: () => open('gallons')),
            if (s['low'] == true) LowStockBanner('Seals: ${s['quantity']} left', onTap: () => open('seals')),
            _count('New Gallons', g, () => open('gallons')),
            _count('Seals', s, () => open('seals')),
            Btn('Movement History', () => go(context, const MovementHistoryScreen()), outline: true),
            const Gap(),
            Btn('Borrowed Gallons', () => go(context, const BorrowedGallonsScreen()), outline: true),
          ]);
        },
      ),
    );
  }
}

/// Grey box with a blue bar: "Low-stock warning · New Gallons: 24 left".
class LowStockBanner extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final String title;
  const LowStockBanner(this.text, {super.key, this.onTap, this.title = 'Low-stock warning'});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: Brand.light,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              decoration: const BoxDecoration(border: Border(left: BorderSide(color: Brand.blue, width: 5))),
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(text, style: const TextStyle(color: Brand.muted, fontSize: 13)),
                  ]),
                ),
                if (onTap != null) const Icon(Icons.chevron_right, color: Brand.blue),
              ]),
            ),
          ),
        ),
      );
}

/// Admin Inventory 2, 3: New Gallons / Seals. Current stock, Add stock, Damaged or Lost (seals: Lost),
/// and the Entries list (newest first) with the automatic entries.
class StockItemScreen extends StatefulWidget {
  final String item; // gallons, seals
  final int sealsPerGallon;
  const StockItemScreen({super.key, required this.item, this.sealsPerGallon = 3});

  @override
  State<StockItemScreen> createState() => _StockItemScreenState();
}

class _StockItemScreenState extends State<StockItemScreen> {
  final _loader = GlobalKey<LoaderState<(int, List<Movement>)>>();

  bool get _seals => widget.item == 'seals';

  Future<(int, List<Movement>)> _load() async {
    final inv = await app.api.get('/api/inventory');
    final m = await app.api.get('/api/inventory/movements?item=${widget.item}');
    final qty = ((inv[widget.item] as Map<String, dynamic>)['quantity'] as num).toInt();
    return (qty, [for (final x in m['movements'] as List) Movement.fromJson(x as Map<String, dynamic>)]);
  }

  Future<void> _add() async {
    var qty = 0;
    var date = DateTime.now();
    final note = TextEditingController();
    final saved = await formSheet(
      context,
      'Add stock form',
      fields: (set) => [
        const Label('Quantity'),
        const Gap(6),
        QtyStepper(qty, (v) => set(() => qty = v), max: 100000),
        const Gap(12),
        const Label('Date'),
        const Gap(6),
        OutlinedButton.icon(
          onPressed: () async {
            final d = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2025), lastDate: DateTime.now());
            if (d != null) set(() => date = d);
          },
          icon: const Icon(Icons.calendar_today, size: 18),
          label: Text(_ymdLabel(date)),
        ),
        const Gap(12),
        Field('Note', note, hint: 'Add a note'),
      ],
      onSave: () async {
        final r = await app.api.post('/api/inventory/${widget.item}/add', {'quantity': qty, 'date': _ymd(date), 'note': note.text});
        return r['message'] as String?;
      },
    );
    if (saved) await _loader.currentState?.reload();
  }

  Future<void> _remove() async {
    var qty = 0;
    var kind = _seals ? 1 : 0; // 0 Damaged, 1 Lost
    final note = TextEditingController();
    final saved = await formSheet(
      context,
      _seals ? 'Lost seals' : 'Damaged or Lost',
      fields: (set) => [
        const Label('Quantity'),
        const Gap(6),
        QtyStepper(qty, (v) => set(() => qty = v), max: 100000),
        const Gap(12),
        if (!_seals) ...[
          Seg(const ['Damaged', 'Lost'], kind, (i) => set(() => kind = i)),
          const Gap(12),
        ],
        Field('Note', note, hint: _seals ? 'e.g. Torn seals' : 'e.g. Cracked while stacking'),
      ],
      onSave: () async {
        final r = await app.api.post('/api/inventory/${widget.item}/remove', {'quantity': qty, 'kind': kind == 1 ? 'Lost' : 'Damaged', 'note': note.text});
        return r['message'] as String?;
      },
    );
    if (saved) await _loader.currentState?.reload();
  }

  static String _ymdLabel(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_seals ? 'Seals' : 'New Gallons')),
      body: Loader<(int, List<Movement>)>(
        key: _loader,
        load: _load,
        builder: (context, d, reload) => Body([
          Box(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(child: Label('Current stock')),
                if (_seals) Text('${widget.sealsPerGallon} seals used per gallon processed', style: const TextStyle(color: Brand.muted, fontSize: 12)),
              ]),
              const Gap(6),
              Text('${d.$1}', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
            ]),
          ),
          const Gap(10),
          Row(children: [
            Expanded(child: Btn('Add stock', _add)),
            const Gap(10),
            Expanded(child: Btn(_seals ? 'Lost' : 'Damaged or Lost', _remove, outline: true)),
          ]),
          const Gap(14),
          const Row(children: [
            Expanded(child: Label('Stock added and removed')),
            Text('Newest first', style: TextStyle(color: Brand.muted, fontSize: 12)),
          ]),
          if (d.$2.isEmpty) const Empty('No entries yet'),
          for (final m in d.$2) MovementRow(m),
        ]),
      ),
    );
  }
}

/// Admin Inventory 4: Movement History. Gallons and seals together, newest first, with a Filter
/// (gallons or seals, type, date).
class MovementHistoryScreen extends StatefulWidget {
  const MovementHistoryScreen({super.key});

  @override
  State<MovementHistoryScreen> createState() => _MovementHistoryScreenState();
}

class _MovementHistoryScreenState extends State<MovementHistoryScreen> {
  int _item = 0; // All, New Gallons, Seals
  String? _type; // Added, Damaged, Lost, Automatic
  DateTime? _date;
  List<Movement>? _list;
  String? _error;

  static const items = ['All', 'New Gallons', 'Seals'];
  static const itemKeys = ['all', 'gallons', 'seals'];
  static const types = ['Added', 'Damaged', 'Lost', 'Automatic'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final q = [
      'item=${itemKeys[_item]}',
      if (_type != null) 'type=$_type',
      if (_date != null) 'from=${_ymd(_date!)}&to=${_ymd(_date!)}',
    ].join('&');
    try {
      final r = await app.api.get('/api/inventory/movements?$q');
      if (mounted) {
        setState(() {
          _list = [for (final x in r['movements'] as List) Movement.fromJson(x as Map<String, dynamic>)];
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _filter() async {
    var item = _item;
    var type = _type;
    var date = _date;
    final ok = await sheet<bool>(context, 'Filter', (c, set) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Label('Gallons or seals'),
        const Gap(6),
        Seg(items, item, (i) => set(() => item = i)),
        const Gap(12),
        const Label('Type'),
        const Gap(6),
        Wrap(spacing: 8, children: [
          for (final t in types)
            ChoiceChip(
              label: Text(t),
              selected: type == t,
              showCheckmark: false,
              selectedColor: Brand.blue,
              backgroundColor: Colors.white,
              side: const BorderSide(color: Brand.blue),
              labelStyle: TextStyle(color: type == t ? Colors.white : Brand.ink, fontWeight: FontWeight.w700),
              onSelected: (_) => set(() => type = type == t ? null : t),
            ),
        ]),
        const Gap(12),
        const Label('Date'),
        const Gap(6),
        RowLink(date == null ? 'Any date' : _StockItemScreenState._ymdLabel(date!), onTap: () async {
          final d = await showDatePicker(context: c, initialDate: date ?? DateTime.now(), firstDate: DateTime(2025), lastDate: DateTime.now());
          if (d != null) set(() => date = d);
        }),
        const Gap(8),
        Btn('Show', () => Navigator.pop(c, true)),
        const Gap(),
        Btn('Clear filter', () {
          set(() {
            item = 0;
            type = null;
            date = null;
          });
        }, outline: true),
      ]);
    });
    if (ok == true) {
      setState(() {
        _item = item;
        _type = type;
        _date = date;
        _list = null;
      });
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (_item > 0) items[_item],
      if (_type != null) _type!,
      if (_date != null) _StockItemScreenState._ymdLabel(_date!),
    ];
    final list = _list;
    return Scaffold(
      appBar: AppBar(title: const Text('Movement History')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Body([
          Btn('Filter', _filter, outline: parts.isEmpty),
          if (parts.isNotEmpty) ...[const Gap(8), Note('Filter: ${parts.join(' · ')}')],
          const Gap(8),
          const Label('Stock added and removed'),
          if (_error != null) MsgBanner('Could not load', sub: _error),
          if (list == null && _error == null) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
          if (list != null && list.isEmpty) const Empty('No entries for this filter'),
          if (list != null) for (final m in list) MovementRow(m, showItem: true),
        ]),
      ),
    );
  }
}
