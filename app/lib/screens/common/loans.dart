import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/order.dart';
import '../../services/api.dart';
import '../../services/app_state.dart';
import '../../services/realtime.dart';
import '../../theme/brand.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../../widgets/map_widgets.dart';

/// A gallon loan as the server sends it.
class Loan {
  final int id;
  final String name;
  final String phone;
  final int? orderId;
  final int quantity;
  final DateTime? lentAt;
  final String lentBy;
  final DateTime? returnedAt;
  final String returnedBy;
  final String note;
  final bool out;

  const Loan(this.id, this.name, this.phone, this.orderId, this.quantity, this.lentAt, this.lentBy, this.returnedAt, this.returnedBy,
      this.note, this.out);

  factory Loan.fromJson(Map<String, dynamic> j) => Loan(
        (j['id'] as num).toInt(),
        (j['name'] ?? '') as String,
        (j['phone'] ?? '') as String,
        (j['orderId'] as num?)?.toInt(),
        (j['quantity'] as num).toInt(),
        DateTime.tryParse((j['lentAt'] ?? '') as String),
        (j['lentBy'] ?? '') as String,
        DateTime.tryParse((j['returnedAt'] ?? '') as String),
        (j['returnedBy'] ?? '') as String,
        (j['note'] ?? '') as String,
        j['out'] == true,
      );

  String get gallonsText => '$quantity ${quantity == 1 ? 'gallon' : 'gallons'}';
}

/// Admin Orders 8 / Staff 8: Lend gallon form. From an order the customer is filled in.
/// Returns the message to show after saving.
class LendGallonScreen extends StatefulWidget {
  final Order? order;
  const LendGallonScreen({super.key, this.order});

  @override
  State<LendGallonScreen> createState() => _LendGallonScreenState();
}

class _LendGallonScreenState extends State<LendGallonScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  int _qty = 1;
  late DateTime _date;
  ApiException? _error;
  bool _busy = false;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  DateTime get _today {
    final p = ph(DateTime.now());
    return DateTime(p.year, p.month, p.day);
  }

  @override
  void initState() {
    super.initState();
    _date = _today;
    final o = widget.order;
    if (o != null) {
      _name.text = o.name;
      _phone.text = phoneFmt(o.phone);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2025), lastDate: _today, helpText: 'Date lent');
    if (d != null) setState(() => _date = DateTime(d.year, d.month, d.day));
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await app.api.post('/api/loans', {
        if (widget.order != null) 'orderId': widget.order!.id,
        'name': _name.text,
        'phone': _phone.text,
        'quantity': _qty,
        'date': '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
        'note': _note.text,
      });
      if (mounted) Navigator.pop(context, (r['message'] ?? 'Gallons lent.') as String);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    return Scaffold(
      appBar: AppBar(title: const Text('Lend gallon')),
      body: Body([
        if (_error != null) MsgBanner(_error!.title, sub: _error!.message),
        if (o != null) Note('For order #${o.id} · ${o.name.isEmpty ? 'Guest' : o.name}'),
        Field('Customer name', _name, hint: 'Who borrowed the gallons', kind: FieldKind.name),
        Field('Phone number', _phone, hint: 'Optional', kind: FieldKind.phone),
        const Label('Gallons lent'),
        const Gap(6),
        QtyStepper(_qty, (v) => setState(() => _qty = v < 1 ? 1 : v), max: 20),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('Taken from New Gallons stock', style: TextStyle(color: Brand.muted, fontSize: 12)),
        ),
        const Gap(12),
        const Label('Date lent'),
        const Gap(6),
        Box(
          onTap: _pick,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(children: [
            const Icon(Icons.calendar_today_outlined, color: Brand.blue, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text('${_months[_date.month - 1]} ${_date.day}, ${_date.year}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            const Icon(Icons.chevron_right, color: Brand.blue),
          ]),
        ),
        const Gap(12),
        Field('Note', _note, hint: 'Optional, e.g. their gallon is cracked'),
        const Gap(6),
        Btn('Save', _save, busy: _busy),
      ]),
    );
  }
}

/// Returned: how many came back (all by default) and Confirm. Returns true when saved.
Future<bool> returnLoan(BuildContext context, Loan l) async {
  var qty = l.quantity;
  ApiException? err;
  var busy = false;
  String? msg;
  final ok = await sheet<bool>(context, 'Gallons returned', sub: '${l.name} borrowed ${l.gallonsText}.', (c, set) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (err != null) MsgBanner(err!.title, sub: err!.message),
      const Label('How many came back?'),
      const Gap(6),
      QtyStepper(qty, (v) => set(() => qty = v < 1 ? 1 : v), max: l.quantity),
      if (qty < l.quantity)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('${l.quantity - qty} will stay borrowed.', style: const TextStyle(color: Brand.muted)),
        ),
      const Gap(16),
      Btn('Confirm', () async {
        set(() => busy = true);
        try {
          final r = await app.api.post('/api/loans/${l.id}/return', {'quantity': qty});
          msg = (r['message'] ?? 'Returned.') as String;
          if (c.mounted) Navigator.pop(c, true);
        } on ApiException catch (e) {
          set(() {
            err = e;
            busy = false;
          });
        }
      }, busy: busy),
    ]);
  });
  if (ok == true && msg != null && context.mounted) toast(context, msg!);
  return ok == true;
}

/// One loan row with Returned (when still out).
class LoanTile extends StatelessWidget {
  final Loan loan;
  final Future<void> Function() onChanged;
  final bool showOrder;
  const LoanTile(this.loan, {super.key, required this.onChanged, this.showOrder = true});

  @override
  Widget build(BuildContext context) {
    final l = loan;
    final lent = 'Lent ${dayPh(l.lentAt)}${l.lentBy.isEmpty ? '' : ' by ${l.lentBy}'}';
    final back = l.out ? '' : ' · Returned ${dayPh(l.returnedAt)}${l.returnedBy.isEmpty ? '' : ' by ${l.returnedBy}'}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Box(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(l.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                const SizedBox(width: 8),
                Tag(l.gallonsText, filled: l.out),
              ]),
              if (l.phone.isNotEmpty)
                GestureDetector(
                  onTap: () => callNumber(context, l.phone),
                  child: Text(phoneFmt(l.phone), style: const TextStyle(color: Brand.blue, fontSize: 12.5)),
                ),
              Text('$lent$back', style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
              if (showOrder && l.orderId != null) Text('Order #${l.orderId}', style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
              if (l.note.isNotEmpty) Text('Note: ${l.note}', style: const TextStyle(fontSize: 12.5)),
            ]),
          ),
          if (l.out)
            SmallBtn('Returned', () async {
              if (await returnLoan(context, l)) await onChanged();
            }),
        ]),
      ),
    );
  }
}

/// Admin Inventory 5 / Staff 8: Borrowed Gallons. Gallons still out, Out / Returned lists, search,
/// + Lend gallon.
class BorrowedGallonsScreen extends StatefulWidget {
  const BorrowedGallonsScreen({super.key});

  @override
  State<BorrowedGallonsScreen> createState() => _BorrowedGallonsScreenState();
}

class _BorrowedGallonsScreenState extends State<BorrowedGallonsScreen> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();
  final _q = TextEditingController();
  int _tab = 0; // Out, Returned
  Timer? _wait;
  StreamSubscription<RtEvent>? _live;

  @override
  void initState() {
    super.initState();
    _live = realtime.listen((_) => _loader.currentState?.reload(), names: const {'refresh'});
  }

  @override
  void dispose() {
    _wait?.cancel();
    _live?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _reload() async => _loader.currentState?.reload();

  Future<void> _lend() async {
    final msg = await go<String>(context, const LendGallonScreen());
    if (msg != null && mounted) {
      toast(context, msg);
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Borrowed Gallons')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _lend, icon: const Icon(Icons.add), label: const Text('Lend gallon')),
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () => app.api.get('/api/loans?status=${_tab == 0 ? 'out' : 'returned'}&q=${Uri.encodeQueryComponent(_q.text.trim())}'),
        builder: (context, d, reload) {
          final loans = [for (final l in d['loans'] as List) Loan.fromJson(l as Map<String, dynamic>)];
          final n = (d['gallonsOut'] as num).toInt();
          final c = (d['customersOut'] as num).toInt();
          return Body([
            Box(
              filled: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Gallons still borrowed', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                const Gap(4),
                Text('$n', style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
                Text('$c ${c == 1 ? 'customer' : 'customers'}', style: const TextStyle(color: Colors.white)),
              ]),
            ),
            const Gap(10),
            Seg(const ['Borrowed', 'Returned'], _tab, (i) {
              setState(() => _tab = i);
              _reload();
            }),
            const Gap(10),
            TextField(
              controller: _q,
              onChanged: (_) {
                setState(() {});
                _wait?.cancel();
                _wait = Timer(const Duration(milliseconds: 350), _reload);
              },
              decoration: InputDecoration(
                hintText: 'Search name or phone',
                prefixIcon: const Icon(Icons.search, color: Brand.blue),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Brand.blue)),
              ),
            ),
            const Gap(10),
            if (loans.isEmpty) Empty(_tab == 0 ? 'No gallons borrowed right now' : 'No returned gallons yet'),
            for (final l in loans) LoanTile(l, onChanged: reload),
            const Gap(60),
          ]);
        },
      ),
    );
  }
}

/// Borrowed Gallons box on owner and staff Order Details: the loans of this order, Lend gallon, Returned.
class OrderLoansBox extends StatefulWidget {
  final Order order;
  const OrderLoansBox(this.order, {super.key});

  @override
  State<OrderLoansBox> createState() => _OrderLoansBoxState();
}

class _OrderLoansBoxState extends State<OrderLoansBox> {
  List<Loan>? _loans;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(OrderLoansBox old) {
    super.didUpdateWidget(old);
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await app.api.get('/api/loans?status=all&orderId=${widget.order.id}');
      if (mounted) setState(() => _loans = [for (final l in r['loans'] as List) Loan.fromJson(l as Map<String, dynamic>)]);
    } on ApiException {
      if (mounted) setState(() => _loans = const []);
    }
  }

  Future<void> _lend() async {
    final msg = await go<String>(context, LendGallonScreen(order: widget.order));
    if (msg != null && mounted) {
      toast(context, msg);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final loans = _loans;
    final out = loans == null ? 0 : loans.where((l) => l.out).fold<int>(0, (a, l) => a + l.quantity);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Box(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Expanded(child: Label('Borrowed Gallons')),
            SmallBtn('Lend gallon', _lend),
          ]),
          const Gap(4),
          if (loans == null)
            const Text('Loading...', style: TextStyle(color: Brand.muted))
          else if (loans.isEmpty)
            const Text('None lent for this order', style: TextStyle(color: Brand.muted))
          else ...[
            Text(out > 0 ? '$out still borrowed' : 'All returned', style: const TextStyle(fontWeight: FontWeight.w800)),
            const Gap(6),
            for (final l in loans) LoanTile(l, onChanged: _load, showOrder: false),
          ],
        ]),
      ),
    );
  }
}
