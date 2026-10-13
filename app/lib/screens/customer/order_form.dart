import 'package:flutter/material.dart';

import '../../models/order.dart';
import '../../services/api.dart';
import '../../services/app_state.dart';
import '../../theme/brand.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import 'address_screen.dart';

/// Customer 3: Order Form. Order type (Refill my gallons / Buy a package), gallons with the live total
/// (3 x P35.00 = P105.00), delivery address (Customer 3A), phone number, notes, and the only payment:
/// Cash on delivery (COD), pay once delivered. Place order -> Confirm order? -> thank-you message.
/// Returns true when an order was placed.
class OrderForm extends StatefulWidget {
  /// "Order again" from a declined (or past) order: same type, gallons and address.
  final Order? again;
  const OrderForm({super.key, this.again});

  @override
  State<OrderForm> createState() => _OrderFormState();
}

class _OrderFormState extends State<OrderForm> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _notes = TextEditingController();
  int _type = 0; // 0 Refill my gallons, 1 Buy a package
  int _qty = 1;
  Address? _address;
  int? _fromOrder;
  ApiException? _error;
  bool _busy = false;

  Map<String, dynamic> _prices = const {'delivery': 35, 'package': 150};
  double _unpaid = 0;
  List<Address> _saved = [];
  bool _loaded = false;

  static const maxGallons = 50;

  @override
  void initState() {
    super.initState();
    _phone.text = phoneFmt(app.user?.phone ?? '');
    final a = widget.again;
    if (a != null) {
      _type = a.type == 'Package' ? 1 : 0;
      _qty = a.quantity;
      _fromOrder = a.id;
      _phone.text = phoneFmt(a.phone);
      if (app.guest) _name.text = a.name;
    }
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final home = await app.api.get('/api/orders/home');
      List<Address> saved = [];
      if (app.user != null) {
        final r = await app.api.get('/api/addresses');
        saved = [for (final x in r['addresses'] as List) Address.fromJson(x as Map<String, dynamic>)];
      }
      if (!mounted) return;
      setState(() {
        _prices = home['prices'] as Map<String, dynamic>;
        _unpaid = (home['unpaid'] as num).toDouble();
        _saved = saved;
        _loaded = true;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  double get _unit => ((_type == 1 ? _prices['package'] : _prices['delivery']) as num).toDouble();
  double get _total => _unit * _qty;
  String get _each => '$_qty x ${peso(_unit)} ${_type == 1 ? 'per package' : 'per gallon (delivery)'}';
  String get _addressText => _address?.text ?? (widget.again != null && _fromOrder != null ? widget.again!.address : '');

  Future<void> _pickAddress() async {
    final a = await go<Address>(context, AddressScreen(forOrder: true, initial: _address?.id == null ? _address : null, saved: _saved));
    if (a != null && mounted) {
      setState(() {
        _address = a;
        _fromOrder = null;
        if (_error?.code == 'ADDRESS_MISSING') _error = null;
      });
    }
  }

  Future<void> _place() async {
    FocusScope.of(context).unfocus();
    if (app.guest && _name.text.trim().isEmpty) {
      setState(() => _error = const ApiException(400, 'NAME_MISSING', 'Name missing', 'Type your name so the rider knows who to look for.'));
      return;
    }
    if (_addressText.isEmpty) {
      setState(() => _error = const ApiException(400, 'ADDRESS_MISSING', 'Delivery address missing', 'Pin on map or type the address.'));
      return;
    }
    setState(() => _error = null);
    final type = _type == 1 ? 'Package' : 'Refill';
    final ok = await sheet<bool>(
      context,
      'Confirm order?',
      close: false,
      (c, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        KV('$_qty ${_qty == 1 ? 'gallon' : 'gallons'} · $type', '$_qty x ${peso(_unit)}'),
        KV('Deliver to', _addressText),
        const KV('Payment', 'Cash on delivery'),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(children: [
            const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.w800))),
            Text(peso(_total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, fontFamily: 'monospace')),
          ]),
        ),
        const Gap(20),
        Btn('Confirm', () => Navigator.pop(c, true)),
        const Gap(),
        Btn('Edit order', () => Navigator.pop(c, false), outline: true),
      ]),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final body = <String, dynamic>{
        'type': type,
        'quantity': _qty,
        'phone': _phone.text,
        'notes': _notes.text,
        if (app.guest) 'name': _name.text,
        if (_address?.id != null) 'addressId': _address!.id,
        if (_address != null && _address!.id == null) 'address': _address!.toJson(),
        if (_address == null && _fromOrder != null) 'fromOrderId': _fromOrder,
      };
      final r = await app.api.post('/api/orders', body);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Brand.blue, width: 1.2)),
          title: Text((r['title'] ?? 'Thank you for your order!') as String, style: const TextStyle(fontWeight: FontWeight.w800)),
          content: Text((r['message'] ?? '') as String),
          actions: [SizedBox(width: double.infinity, child: Btn('OK', () => Navigator.pop(c)))],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e;
        });
      }
    }
  }

  Future<void> _cancel() async {
    final ok = await confirm(
      context,
      'Cancel this order?',
      sub: 'What you entered will be cleared. Nothing is sent to the station.',
      ok: 'Yes, cancel',
      cancel: 'Keep editing',
    );
    if (!ok || !mounted) return;
    toast(context, 'Order cancelled. Nothing was sent.');
    Navigator.pop(context, false);
  }

  Widget _stepBtn(IconData icon, VoidCallback? onTap, {bool filled = false}) => SizedBox(
        width: 40,
        height: 40,
        child: Material(
          color: filled ? Brand.blue : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Brand.blue, width: 1.2)),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Icon(icon, color: filled ? Colors.white : Brand.blue, size: 20),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Order Form')),
      body: !_loaded && _error == null
          ? const Center(child: CircularProgressIndicator())
          : Body([
              if (_error != null) MsgBanner(_error!.title, sub: _error!.message),
              if (_unpaid > 0) Note('Unpaid balance: ${peso(_unpaid)}'),
              if (app.guest) Field('Name', _name, hint: 'Your name', kind: FieldKind.name),
              const Label('Order type'),
              const Gap(6),
              Seg(const ['Refill my gallons', 'Buy a package'], _type, (i) => setState(() => _type = i)),
              const Gap(12),
              const Label('Gallons'),
              const Gap(6),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(border: Border.all(color: Brand.blue, width: 1.2), borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  _stepBtn(Icons.remove, _qty > 1 ? () => setState(() => _qty--) : null),
                  Expanded(
                    child: Text('$_qty', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                  _stepBtn(Icons.add, _qty < maxGallons ? () => setState(() => _qty++) : null, filled: true),
                ]),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Same price for round and slim', style: TextStyle(color: Brand.muted, fontSize: 12)),
              ),
              const Gap(8),
              Box(
                tint: true,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Total', style: TextStyle(fontWeight: FontWeight.w800)),
                      Text(_each, style: const TextStyle(color: Brand.muted, fontSize: 12)),
                    ]),
                  ),
                  Text(peso(_total), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
                ]),
              ),
              const Gap(14),
              const Label('Delivery address'),
              const Gap(6),
              Material(
                color: _error?.code == 'ADDRESS_MISSING' ? Brand.light : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Brand.blue, width: _error?.code == 'ADDRESS_MISSING' ? 2.2 : 1.2),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _pickAddress,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    child: Row(children: [
                      Expanded(
                        child: Text(
                          _addressText.isEmpty ? 'Pin on map or type address' : _addressText,
                          style: TextStyle(color: _addressText.isEmpty ? Brand.muted : Brand.ink),
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Brand.blue),
                    ]),
                  ),
                ),
              ),
              const Gap(12),
              Field('Phone number', _phone, kind: FieldKind.phone),
              Field('Notes', _notes, hint: 'Optional'),
              const Label('Payment'),
              const Gap(6),
              const Box(
                tint: true,
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(children: [
                  Icon(Icons.radio_button_checked, color: Brand.blue),
                  SizedBox(width: 10),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Cash on delivery (COD)', style: TextStyle(fontWeight: FontWeight.w800)),
                    Text('Pay once delivered', style: TextStyle(color: Brand.muted, fontSize: 12.5)),
                  ]),
                ]),
              ),
              const Gap(16),
              Btn('Place order', _place, busy: _busy),
              const Gap(),
              Btn('Cancel', _busy ? null : _cancel, outline: true),
            ]),
    );
  }
}
