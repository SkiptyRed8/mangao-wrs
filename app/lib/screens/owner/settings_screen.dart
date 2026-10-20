import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/api.dart';
import '../../services/app_state.dart';
import '../../theme/brand.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';

/// Admin More 3: Prices & Settings. Prices (walk-in P30, delivery P35, package P150), tank limit,
/// low-stock levels and station location, each with its own form and a message after saving.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();

  Future<void> _reload() async => _loader.currentState?.reload();

  static String _num(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  Future<void> _editPrices(Map<String, dynamic> p) async {
    final walkIn = TextEditingController(text: (p['walkIn'] as num).toStringAsFixed(2));
    final delivery = TextEditingController(text: (p['delivery'] as num).toStringAsFixed(2));
    final package = TextEditingController(text: (p['package'] as num).toStringAsFixed(2));
    final saved = await formSheet(
      context,
      'Price form',
      fields: (set) => [
        Field('Refill (walk-in), per gallon', walkIn, kind: FieldKind.money),
        Field('Refill (delivery), per gallon', delivery, kind: FieldKind.money),
        Field('Package (walk-in or delivery)', package,
            kind: FieldKind.money, helper: 'Same price for round and slim. New prices apply to new orders only.'),
      ],
      onSave: () async {
        final r = await app.api.put('/api/settings/prices', {
          'walkIn': double.tryParse(walkIn.text) ?? 0,
          'delivery': double.tryParse(delivery.text) ?? 0,
          'package': double.tryParse(package.text) ?? 0,
        });
        return r['message'] as String?;
      },
    );
    if (saved) await _reload();
  }

  Future<void> _editTank(int limit) async {
    final c = TextEditingController(text: '$limit');
    final saved = await formSheet(
      context,
      'Tank limit form',
      fields: (set) => [Field('Gallons before the alert', c, kind: FieldKind.number)],
      onSave: () async {
        final r = await app.api.put('/api/settings/tank-limit', {'tankLimit': int.tryParse(c.text) ?? 0});
        return r['message'] as String?;
      },
    );
    if (saved) await _reload();
  }

  Future<void> _editLowStock(Map<String, dynamic> low) async {
    final g = TextEditingController(text: '${low['gallons']}');
    final s = TextEditingController(text: '${low['seals']}');
    final saved = await formSheet(
      context,
      'Low-stock form',
      fields: (set) => [
        Field('Gallon level', g, kind: FieldKind.number),
        Field('Seal level', s, kind: FieldKind.number),
      ],
      onSave: () async {
        final r = await app.api.put('/api/settings/low-stock', {'gallons': int.tryParse(g.text) ?? -1, 'seals': int.tryParse(s.text) ?? -1});
        return r['message'] as String?;
      },
    );
    if (saved) await _reload();
  }

  Future<void> _editLocation(Map<String, dynamic> station) async {
    final msg = await go<String>(
      context,
      StationLocationScreen(
        lat: (station['lat'] as num?)?.toDouble(),
        lng: (station['lng'] as num?)?.toDouble(),
        address: (station['address'] ?? '') as String,
      ),
    );
    if (msg != null && mounted) {
      toast(context, msg);
      await _reload();
    }
  }

  /// Demo ride on/off (testing and presentations).
  Future<void> _setDemoRide(bool on) async {
    try {
      final r = await app.api.put('/api/settings/demo-ride', {'on': on});
      if (mounted) toast(context, (r['message'] ?? 'Saved') as String);
    } on ApiException catch (e) {
      if (mounted) toast(context, '${e.title}. ${e.message}', error: true);
    }
    await _reload();
  }

  Widget _card(String title, String button, VoidCallback onTap, List<Widget> rows) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Box(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              SmallBtn(button, onTap),
            ]),
            const Gap(4),
            ...rows,
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Prices & Settings')),
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () => app.api.get('/api/settings'),
        builder: (context, s, reload) {
          final p = s['prices'] as Map<String, dynamic>;
          final low = s['lowStock'] as Map<String, dynamic>;
          final station = s['station'] as Map<String, dynamic>;
          final hasPin = station['lat'] != null;
          return Body([
            _card('Prices', 'Edit prices', () => _editPrices(p), [
              KV('Refill (walk-in), per gallon', peso(p['walkIn'] as num)),
              KV('Refill (delivery), per gallon', peso(p['delivery'] as num)),
              KV('Package (walk-in or delivery)', peso(p['package'] as num), last: true),
              const Text('Same price for round and slim gallons.', style: TextStyle(color: Brand.muted, fontSize: 12)),
            ]),
            _card('Tank limit', 'Edit', () => _editTank((s['tankLimit'] as num).toInt()), [
              KV('Gallons before the alert', _num(s['tankLimit'] as num), last: true),
            ]),
            _card('Low-stock levels', 'Edit', () => _editLowStock(low), [
              KV('Gallons', _num(low['gallons'] as num)),
              KV('Seals', _num(low['seals'] as num), last: true),
            ]),
            _card('Station location', 'Change', () => _editLocation(station), [
              if ((station['address'] ?? '') != '')
                Text(station['address'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
              const Text('Used for customer distance, maps and reports', style: TextStyle(color: Brand.muted)),
              if (hasPin)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Pin: ${(station['lat'] as num).toStringAsFixed(5)}, ${(station['lng'] as num).toStringAsFixed(5)}',
                    style: const TextStyle(fontSize: 12.5, color: Brand.muted),
                  ),
                ),
            ]),
            Box(
              child: Row(children: [
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Demo ride', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    Gap(2),
                    Text(
                      'For testing and presentations: the sidecar drives by itself from the station along the streets to '
                      'each stop (about 2 minutes per trip) and waits there until the rider marks the order. '
                      'Turn it off for real deliveries, so the rider\'s phone moves the sidecar.',
                      style: TextStyle(color: Brand.muted, fontSize: 12.5),
                    ),
                  ]),
                ),
                const SizedBox(width: 8),
                Switch(value: s['demoRide'] == true, onChanged: _setDemoRide),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}

/// Map with pin: move the map so the pin is on the station, then Save.
class StationLocationScreen extends StatefulWidget {
  final double? lat;
  final double? lng;
  final String address;
  const StationLocationScreen({super.key, this.lat, this.lng, this.address = ''});

  /// 98 Riverside Street, Barangay Commonwealth, Quezon City (used until the owner sets the pin).
  static const fallback = LatLng(14.692823, 121.0871699);

  @override
  State<StationLocationScreen> createState() => _StationLocationScreenState();
}

class _StationLocationScreenState extends State<StationLocationScreen> {
  final _map = MapController();
  late final _address = TextEditingController(text: widget.address);
  bool _busy = false;
  ApiException? _error;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final c = _map.camera.center;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await app.api.put('/api/settings/location', {'lat': c.latitude, 'lng': c.longitude, 'address': _address.text});
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

  @override
  Widget build(BuildContext context) {
    final start = widget.lat != null && widget.lng != null ? LatLng(widget.lat!, widget.lng!) : StationLocationScreen.fallback;
    return Scaffold(
      appBar: AppBar(title: const Text('Station location')),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_error != null) MsgBanner(_error!.title, sub: _error!.message),
            Field('Station address', _address,
                hint: 'e.g. 98 Riverside Street, Barangay Commonwealth, Quezon City', error: _error?.code == 'ADDRESS_MISSING'),
            const Text('Move the pin to the station', style: TextStyle(fontWeight: FontWeight.w700)),
            const Text('Drag the map; the pin stays in the middle.', style: TextStyle(color: Brand.muted, fontSize: 12.5)),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: DecoratedBox(
                decoration: BoxDecoration(border: Border.all(color: Brand.blue, width: 1.2), borderRadius: BorderRadius.circular(12)),
                child: Stack(children: [
                  FlutterMap(
                    mapController: _map,
                    options: MapOptions(
                      initialCenter: start,
                      initialZoom: 17,
                      interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.mangao.mangao_wrs',
                      ),
                      const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
                    ],
                  ),
                  const IgnorePointer(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 40),
                        child: Icon(Icons.location_on, size: 44, color: Brand.blue),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
      bottomNavigationBar: Bottom([Btn('Save', _save, busy: _busy)]),
    );
  }
}
