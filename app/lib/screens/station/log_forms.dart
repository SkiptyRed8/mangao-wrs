import 'package:flutter/material.dart';

import '../../services/api.dart';
import '../../services/app_state.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';

/// Current prices for the forms (walk-in P30, delivery P35, package P150 by default).
Future<Map<String, dynamic>> loadPrices() async => (await app.api.get('/api/settings/prices'))['prices'] as Map<String, dynamic>;

/// Admin Home 5 / Staff 10: Log Walk-in. Quantity, Refill or Package, Paid or Unpaid, Name (optional),
/// live total (P30 per gallon walk-in, P150 package). A record only: no status steps.
/// Returns the message to show ("Walk-in saved: 2 gallons, Paid") after saving.
class LogWalkInScreen extends StatefulWidget {
  const LogWalkInScreen({super.key});

  @override
  State<LogWalkInScreen> createState() => _LogWalkInScreenState();
}

class _LogWalkInScreenState extends State<LogWalkInScreen> {
  final _name = TextEditingController();
  int _qty = 0;
  int _type = 0; // Refill, Package
  int _paid = 0; // Paid, Unpaid
  Map<String, dynamic> _prices = const {'walkIn': 30, 'package': 150};
  ApiException? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    loadPrices().then((p) {
      if (mounted) setState(() => _prices = p);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  double get _unit => ((_type == 1 ? _prices['package'] : _prices['walkIn']) as num).toDouble();

  Future<void> _save() async {
    if (_qty == 0) {
      setState(() => _error = const ApiException(400, 'QUANTITY_MISSING', 'Quantity missing', 'Tap + to add the gallons.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await app.api.post('/api/work/walk-in', {
        'quantity': _qty,
        'type': _type == 1 ? 'Package' : 'Refill',
        'paid': _paid == 0,
        'name': _name.text,
      });
      if (mounted) Navigator.pop(context, r['message'] as String?);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _busy = false;
        });
      }
    }
  }

  Future<void> _cancel() async {
    final ok = await confirm(context, 'Cancel walk-in order?',
        sub: 'What you entered will be cleared. No order is created.', cancel: 'Keep editing');
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Log Walk-in')),
      body: Body([
        if (_error != null) MsgBanner(_error!.title, sub: _error!.message),
        const Label('Quantity'),
        const Gap(6),
        QtyStepper(_qty, (v) => setState(() {
              _qty = v;
              if (v > 0 && _error?.code == 'QUANTITY_MISSING') _error = null;
            }), highlight: _error?.code == 'QUANTITY_MISSING'),
        const Gap(12),
        const Label('Refill or package'),
        const Gap(6),
        Seg(const ['Refill', 'Package'], _type, (i) => setState(() => _type = i)),
        const Gap(12),
        const Label('Paid or unpaid'),
        const Gap(6),
        Seg(const ['Paid', 'Unpaid'], _paid, (i) => setState(() => _paid = i)),
        const Gap(12),
        Field('Name (optional)', _name, hint: 'e.g. Aling Rosa', kind: FieldKind.name),
        TotalBox('$_qty x ${peso(_unit)} ${_type == 1 ? 'per package' : 'per gallon (walk-in)'}', peso(_unit * _qty)),
      ]),
      bottomNavigationBar: Bottom([
        Btn('Save', _save, busy: _busy),
        const Gap(8),
        Btn('Cancel', _busy ? null : _cancel, outline: true),
      ]),
    );
  }
}

/// Admin Home 5A / Staff 4: Log Delivery Order, for customers without the app (call, text, Messenger,
/// or walk-in for delivery). Goes straight to Processing with the owner as rider.
/// Returns the message to show ("Order saved").
class LogDeliveryScreen extends StatefulWidget {
  const LogDeliveryScreen({super.key});

  @override
  State<LogDeliveryScreen> createState() => _LogDeliveryScreenState();
}

class _LogDeliveryScreenState extends State<LogDeliveryScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  int _qty = 1;
  int _type = 0;
  int _channel = 0; // Call, Text, Messenger, Walk-in
  int _payment = 0; // Pay on delivery, Paid at station
  Map<String, dynamic> _prices = const {'delivery': 35, 'package': 150};
  ApiException? _error;
  Set<String> _missing = {};
  bool _busy = false;

  static const channels = ['Call', 'Text', 'Messenger', 'Walk-in'];
  static const payments = ['Pay on delivery', 'Paid at station'];

  @override
  void initState() {
    super.initState();
    loadPrices().then((p) {
      if (mounted) setState(() => _prices = p);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _unit => ((_type == 1 ? _prices['package'] : _prices['delivery']) as num).toDouble();

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final missing = <String>{
      if (_name.text.trim().isEmpty) 'name',
      if (_phone.text.trim().isEmpty) 'phone',
      if (_address.text.trim().isEmpty) 'address',
      if (_qty == 0) 'quantity',
    };
    if (missing.isNotEmpty) {
      setState(() {
        _missing = missing;
        _error = const ApiException(400, 'FIELDS_MISSING', 'Name, phone, address or quantity missing', 'Fill in the highlighted fields.');
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _missing = {};
    });
    try {
      final r = await app.api.post('/api/work/delivery', {
        'name': _name.text,
        'phone': _phone.text,
        'address': _address.text,
        'quantity': _qty,
        'type': _type == 1 ? 'Package' : 'Refill',
        'channel': channels[_channel],
        'payment': payments[_payment],
      });
      if (mounted) Navigator.pop(context, r['message'] as String?);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _busy = false;
        final f = e.data['fields'];
        if (f is List) _missing = {for (final x in f) x as String};
      });
    }
  }

  Future<void> _cancel() async {
    final ok = await confirm(context, 'Cancel delivery order?',
        sub: 'What you entered will be cleared. No order is created.', cancel: 'Keep editing');
    if (ok && mounted) Navigator.pop(context);
  }

  Widget _mark(String f, Widget child) => ErrorWrap(_missing.contains(f), child);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Log Delivery Order')),
      body: Body([
        if (_error != null) MsgBanner(_error!.title, sub: _error!.message),
        _mark('name', Field('Customer name', _name, hint: 'e.g. Ben Cruz', kind: FieldKind.name)),
        _mark('phone', Field('Phone number', _phone, hint: '09XX XXX XXXX', kind: FieldKind.phone)),
        _mark('address', Field('Delivery address', _address, hint: 'House no., street, barangay')),
        const Label('Quantity'),
        const Gap(6),
        QtyStepper(_qty, (v) => setState(() => _qty = v), highlight: _missing.contains('quantity')),
        const Gap(12),
        const Label('Refill or package'),
        const Gap(6),
        Seg(const ['Refill', 'Package'], _type, (i) => setState(() => _type = i)),
        const Gap(12),
        const Label('Order received by'),
        const Gap(6),
        Seg(channels, _channel, (i) => setState(() => _channel = i)),
        const Gap(12),
        const Label('Payment'),
        const Gap(6),
        Seg(payments, _payment, (i) => setState(() => _payment = i)),
        const Gap(12),
        TotalBox('$_qty x ${peso(_unit)} ${_type == 1 ? 'per package' : 'per gallon (delivery)'}', peso(_unit * _qty)),
      ]),
      bottomNavigationBar: Bottom([
        Btn('Save', _save, busy: _busy),
        const Gap(8),
        Btn('Cancel', _busy ? null : _cancel, outline: true),
      ]),
    );
  }
}

/// The two buttons at the top of the owner's Home and the staff To Do: Log Walk-in and Log Delivery.
/// [onSaved] runs after an order is saved (to refresh the page).
class StationButtons extends StatelessWidget {
  final VoidCallback? onSaved;
  const StationButtons({super.key, this.onSaved});

  Future<void> _open(BuildContext context, Widget page) async {
    final msg = await go<String>(context, page);
    if (msg != null && context.mounted) {
      toast(context, msg);
      onSaved?.call();
    }
  }

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Btn('Log Walk-in', () => _open(context, const LogWalkInScreen()))),
        const Gap(10),
        Expanded(child: Btn('Log Delivery', () => _open(context, const LogDeliveryScreen()))),
      ]);
}
