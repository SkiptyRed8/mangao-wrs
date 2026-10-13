import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/order.dart';
import '../../services/api.dart';
import '../../services/app_state.dart';
import '../../theme/brand.dart';
import '../../widgets/common.dart';
import '../../widgets/map_widgets.dart';

/// Customer 3A (Delivery address) and Customer 7 (Add / Edit address).
/// Pin on map (like a ride or shopping app) or Type address: house / unit no., block / lot, street and
/// barangay; the city is always Quezon City.
///  - For the Order Form ([forOrder]): saved addresses on top; "Use this address" returns an [Address].
///  - For My Account: a Name field; Save (and Delete when editing) talk to the server and return the message.
class AddressScreen extends StatefulWidget {
  final bool forOrder;
  final Address? initial;
  final List<Address> saved;
  const AddressScreen({super.key, this.forOrder = false, this.initial, this.saved = const []});

  @override
  State<AddressScreen> createState() => _AddressScreenState();
}

class _AddressScreenState extends State<AddressScreen> {
  final _map = MapController();
  final _name = TextEditingController();
  final _search = TextEditingController();
  final _house = TextEditingController();
  final _blockLot = TextEditingController();
  final _street = TextEditingController();
  final _landmark = TextEditingController();
  String _barangay = '';

  int _tab = 0; // 0 Pin on map, 1 Type address
  late LatLng _pin;
  bool _moved = false;
  String _pinStreet = '';
  String _pinBarangay = '';
  String _pinLabel = '';
  bool _looking = false;
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;
  bool _holdScroll = false;

  ApiException? _error;
  Set<String> _missing = {};
  bool _busy = false;

  bool get _editing => !widget.forOrder && widget.initial?.id != null;

  @override
  void initState() {
    super.initState();
    final a = widget.initial;
    _pin = a?.lat != null && a?.lng != null ? LatLng(a!.lat!, a.lng!) : qcStart;
    if (a != null) {
      _name.text = a.name;
      _landmark.text = a.landmark;
      if (a.pinned) {
        _moved = a.lat != null;
        _pinStreet = a.street;
        _pinBarangay = a.barangay;
        _pinLabel = [a.street, a.barangay].where((s) => s.isNotEmpty).join(', ');
      } else {
        _tab = 1;
        _house.text = a.house;
        _blockLot.text = a.blockLot;
        _street.text = a.street;
        _barangay = a.barangay;
      }
    }
    if (!_moved) _lookUp(_pin);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_name, _search, _house, _blockLot, _street, _landmark]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onMoved(LatLng p) {
    setState(() {
      _pin = p;
      _moved = true;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () => _lookUp(p));
  }

  /// "Pinned: near 12 Malaya St., Commonwealth" for the pin (OpenStreetMap, through the server).
  Future<void> _lookUp(LatLng p) async {
    setState(() => _looking = true);
    try {
      final r = await app.api.get('/api/geo/reverse?lat=${p.latitude}&lng=${p.longitude}');
      if (!mounted || p != _pin) return;
      setState(() {
        _pinStreet = [r['house'] ?? '', r['street'] ?? ''].where((s) => (s as String).isNotEmpty).join(' ');
        _pinBarangay = (r['barangay'] ?? '') as String;
        _pinLabel = (r['label'] ?? '') as String;
      });
    } on ApiException {
      if (mounted) setState(() => _pinLabel = '');
    } finally {
      if (mounted) setState(() => _looking = false);
    }
  }

  Future<void> _find() async {
    final q = _search.text.trim();
    if (q.length < 3) return;
    setState(() => _searching = true);
    try {
      final r = await app.api.get('/api/geo/search?q=${Uri.encodeQueryComponent(q)}');
      if (!mounted) return;
      final list = [for (final x in r['results'] as List) x as Map<String, dynamic>];
      setState(() => _results = list);
      if (list.isEmpty) toast(context, 'No place found in Quezon City. Move the map instead.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _pick(Map<String, dynamic> r) {
    final p = LatLng((r['lat'] as num).toDouble(), (r['lng'] as num).toDouble());
    _map.move(p, 18);
    _onMoved(p);
    setState(() => _results = []);
    FocusScope.of(context).unfocus();
  }

  Future<void> _chooseBarangay() async {
    final b = await go<String>(context, BarangayPicker(current: _barangay));
    if (b != null && mounted) {
      setState(() {
        _barangay = b;
        _missing.remove('barangay');
      });
    }
  }

  /// The address on screen, or null after showing what is missing.
  Address? _read() {
    if (_tab == 0) {
      if (!_moved) {
        setState(() => _error = const ApiException(400, 'PIN', 'Pin missing', 'Move the map to place the pin.'));
        return null;
      }
      return Address(
        id: null,
        name: _name.text.trim(),
        mode: 'pin',
        street: _pinStreet,
        barangay: _pinBarangay,
        landmark: _landmark.text.trim(),
        lat: _pin.latitude,
        lng: _pin.longitude,
        text: Address.line(pinned: true, street: _pinStreet, barangay: _pinBarangay),
      );
    }
    final missing = <String>{
      if (_house.text.trim().isEmpty) 'house',
      if (_street.text.trim().isEmpty) 'street',
      if (_barangay.isEmpty) 'barangay',
    };
    if (missing.isNotEmpty) {
      setState(() {
        _missing = missing;
        _error = const ApiException(400, 'MISSING', 'Fill in the missing fields', 'House / unit no., Street and Barangay are needed');
      });
      return null;
    }
    return Address(
      name: _name.text.trim(),
      mode: 'typed',
      house: _house.text.trim(),
      blockLot: _blockLot.text.trim(),
      street: _street.text.trim(),
      barangay: _barangay,
      landmark: _landmark.text.trim(),
      text: Address.line(pinned: false, house: _house.text.trim(), blockLot: _blockLot.text.trim(), street: _street.text.trim(), barangay: _barangay),
    );
  }

  Future<void> _done() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _missing = {};
    });
    final a = _read();
    if (a == null) return;
    if (widget.forOrder) {
      Navigator.pop(context, a);
      return;
    }
    setState(() => _busy = true);
    try {
      final r = _editing
          ? await app.api.put('/api/addresses/${widget.initial!.id}', a.toJson())
          : await app.api.post('/api/addresses', a.toJson());
      if (mounted) Navigator.pop(context, r['message'] as String?);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e;
        final f = e.data['fields'];
        if (f is List) _missing = {for (final x in f) x as String};
      });
    }
  }

  Future<void> _delete() async {
    final a = widget.initial!;
    final ok = await confirm(context, 'Delete this address?', sub: '${a.name}: ${a.text} will be removed from your saved addresses.');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await app.api.delete('/api/addresses/${a.id}');
      if (mounted) Navigator.pop(context, r['message'] as String?);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e;
        });
      }
    }
  }

  Widget _tabs() => Container(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Brand.soft))),
        child: Row(children: [
          for (final (i, label) in [(0, 'Pin on map'), (1, 'Type address')])
            Expanded(
              child: InkWell(
                onTap: () => setState(() {
                  _tab = i;
                  _error = null;
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: _tab == i ? Brand.blue : Colors.transparent, width: 3)),
                  ),
                  child: Text(label,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w700, color: _tab == i ? Brand.blue : Brand.muted)),
                ),
              ),
            ),
        ]),
      );

  Widget _top() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_error != null) MsgBanner(_error!.title, sub: _error!.message),
        if (!widget.forOrder) Field('Name', _name, hint: 'e.g. Home, Work', kind: FieldKind.name),
        if (widget.forOrder && widget.saved.isNotEmpty) ...[
          const Label('Saved addresses'),
          const Gap(6),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final s in widget.saved)
              ActionChip(
                label: Text(s.name),
                onPressed: () => Navigator.pop(context, s),
                side: const BorderSide(color: Brand.blue),
                backgroundColor: Colors.white,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700, color: Brand.ink),
                shape: const StadiumBorder(),
              ),
          ]),
          const Gap(8),
        ],
        _tabs(),
        const Gap(10),
      ]);

  Widget _pinTab() {
    final label = _looking ? 'finding the street...' : (_pinLabel.isEmpty ? 'the map pin' : _pinLabel);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _search,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _find(),
        decoration: InputDecoration(
          hintText: 'Search a street or place',
          prefixIcon: const Icon(Icons.search, color: Brand.muted),
          suffixIcon: _searching
              ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(icon: const Icon(Icons.arrow_forward, color: Brand.blue), onPressed: _find, tooltip: 'Search'),
        ),
      ),
      if (_results.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(border: Border.all(color: Brand.blue), borderRadius: BorderRadius.circular(10), color: Colors.white),
          child: Column(children: [
            for (final r in _results)
              ListTile(
                dense: true,
                leading: const Icon(Icons.place_outlined, color: Brand.blue),
                title: Text(r['label'] as String),
                onTap: () => _pick(r),
              ),
          ]),
        ),
      const Gap(8),
      // While a finger or the mouse is on the map, the page does not scroll, so the map can be moved.
      Listener(
        onPointerDown: (_) => setState(() => _holdScroll = true),
        onPointerUp: (_) => setState(() => _holdScroll = false),
        onPointerCancel: (_) => setState(() => _holdScroll = false),
        child: PinMap(start: _pin, controller: _map, onMoved: _onMoved, height: 260),
      ),
      const Gap(8),
      Text.rich(TextSpan(children: [
        const TextSpan(text: 'Pinned: ', style: TextStyle(fontWeight: FontWeight.w800)),
        TextSpan(text: _moved || _pinLabel.isNotEmpty ? 'near $label, Quezon City' : 'move the map to place the pin'),
      ])),
      const Gap(10),
      Field('Landmark (optional)', _landmark, hint: 'e.g. Blue gate beside the sari-sari store'),
    ]);
  }


  Widget _typedTab() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Field('House / unit no.', _house, hint: 'e.g. 12', error: _missing.contains('house'))),
          const Gap(10),
          Expanded(child: Field('Block / Lot (optional)', _blockLot, hint: 'e.g. Blk 2 Lot 5')),
        ]),
        Field('Street', _street, hint: 'e.g. Sampaguita St.', error: _missing.contains('street')),
        const Label('Barangay'),
        const Gap(5),
        InkWell(
          onTap: _chooseBarangay,
          borderRadius: BorderRadius.circular(10),
          child: InputDecorator(
            decoration: InputDecoration(
              suffixIcon: const Icon(Icons.expand_more, color: Brand.blue),
              fillColor: _missing.contains('barangay') ? Brand.redLight : Colors.white,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _missing.contains('barangay') ? Brand.red : Brand.blue, width: _missing.contains('barangay') ? 2 : 1.2),
              ),
            ),
            child: Text(_barangay.isEmpty ? 'Choose barangay' : _barangay,
                style: TextStyle(color: _barangay.isEmpty ? Brand.muted : Brand.ink)),
          ),
        ),
        const Gap(12),
        const Label('City'),
        const Gap(5),
        const InputDecorator(
          decoration: InputDecoration(fillColor: Brand.light),
          child: Text('Quezon City', style: TextStyle(color: Brand.muted)),
        ),
        const Gap(12),
        Field('Landmark (optional)', _landmark, hint: 'e.g. Near the chapel'),
      ]);

  @override
  Widget build(BuildContext context) {
    final title = widget.forOrder ? 'Delivery address' : (_editing ? 'Edit address' : 'Add address');
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        physics: _holdScroll ? const NeverScrollableScrollPhysics() : null,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [_top(), _tab == 0 ? _pinTab() : _typedTab()],
      ),
      bottomNavigationBar: Bottom([
        Btn(widget.forOrder ? 'Use this address' : 'Save', _done, busy: _busy),
        if (_editing) ...[const Gap(8), Btn('Delete', _busy ? null : _delete, outline: true)],
      ]),
    );
  }
}

/// Choose barangay: the Quezon City list (A to Z) with a search box.
class BarangayPicker extends StatefulWidget {
  final String current;
  const BarangayPicker({super.key, this.current = ''});

  static List<String>? _cache;

  @override
  State<BarangayPicker> createState() => _BarangayPickerState();
}

class _BarangayPickerState extends State<BarangayPicker> {
  final _q = TextEditingController();

  Future<List<String>> _load() async {
    if (BarangayPicker._cache != null) return BarangayPicker._cache!;
    final r = await app.api.get('/api/geo/barangays');
    return BarangayPicker._cache = [for (final b in r['barangays'] as List) b as String];
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose barangay')),
      body: Loader<List<String>>(
        load: _load,
        builder: (context, all, reload) {
          final q = _q.text.trim().toLowerCase();
          final list = q.isEmpty ? all : all.where((b) => b.toLowerCase().contains(q)).toList();
          return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
            TextField(
              controller: _q,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: 'Search barangay', prefixIcon: Icon(Icons.search, color: Brand.muted)),
            ),
            const Gap(6),
            Text('Quezon City barangays (A to Z) · ${list.length}', style: const TextStyle(color: Brand.muted, fontSize: 12)),
            const Gap(4),
            for (final b in list)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(b, style: TextStyle(fontWeight: b == widget.current ? FontWeight.w800 : FontWeight.w500)),
                trailing: b == widget.current ? const Icon(Icons.check, color: Brand.blue) : null,
                shape: const Border(bottom: BorderSide(color: Brand.soft)),
                onTap: () => Navigator.pop(context, b),
              ),
            if (list.isEmpty) const Empty('No barangay with that name in Quezon City'),
          ]);
        },
      ),
    );
  }
}
