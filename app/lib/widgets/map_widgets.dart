import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/brand.dart';
import 'common.dart';

/// Commonwealth, Quezon City: where the map starts when nothing is pinned yet.
const qcStart = LatLng(14.6976, 121.0886);

const _tiles = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _agent = 'com.mangao.mangao_wrs';

/// Map with a pin fixed in the middle (Customer 3A, Customer 7): the customer moves the map to place
/// the pin, or taps "Use my location". [onMoved] gets the pin position after each move.
class PinMap extends StatefulWidget {
  final LatLng start;
  final MapController controller;
  final ValueChanged<LatLng> onMoved;
  final double height;
  const PinMap({super.key, required this.start, required this.controller, required this.onMoved, this.height = 230});

  @override
  State<PinMap> createState() => _PinMapState();
}

class _PinMapState extends State<PinMap> {
  bool _locating = false;

  Future<void> _myLocation() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw Exception('Turn on location first.');
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
        throw Exception('Allow location for this app, or move the map by hand.');
      }
      final pos = await Geolocator.getCurrentPosition();
      final here = LatLng(pos.latitude, pos.longitude);
      widget.controller.move(here, 18);
      widget.onMoved(here);
    } catch (e) {
      if (mounted) toast(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border.all(color: Brand.blue, width: 1.2), borderRadius: BorderRadius.circular(12)),
          child: Stack(children: [
            FlutterMap(
              mapController: widget.controller,
              options: MapOptions(
                initialCenter: widget.start,
                initialZoom: 17,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                onMapEvent: (e) {
                  if (e is MapEventMoveEnd || e is MapEventFlingAnimationEnd || e is MapEventDoubleTapZoomEnd || e is MapEventScrollWheelZoom) {
                    widget.onMoved(e.camera.center);
                  }
                },
              ),
              children: [
                TileLayer(urlTemplate: _tiles, userAgentPackageName: _agent),
                const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
              ],
            ),
            const IgnorePointer(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.location_on, size: 42, color: Brand.blue),
                  SizedBox(height: 42),
                ]),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 34),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Brand.ink, borderRadius: BorderRadius.circular(6)),
                    child: const Text('Move the map to place the pin',
                        style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: Material(
                color: Colors.white,
                shape: const StadiumBorder(side: BorderSide(color: Brand.blue)),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: _locating ? null : _myLocation,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      _locating
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.my_location, size: 16, color: Brand.blue),
                      const SizedBox(width: 6),
                      const Text('Use my location', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Brand.blue)),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A small map showing one pin (Admin Orders 4: Tap address -> Map pin).
class PinView extends StatelessWidget {
  final LatLng point;
  final double height;
  const PinView(this.point, {super.key, this.height = 240});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: FlutterMap(
            options: MapOptions(initialCenter: point, initialZoom: 17),
            children: [
              TileLayer(urlTemplate: _tiles, userAgentPackageName: _agent),
              MarkerLayer(markers: [
                Marker(
                  point: point,
                  width: 44,
                  height: 44,
                  alignment: Alignment.topCenter,
                  child: const Icon(Icons.location_on, size: 44, color: Brand.blue),
                ),
              ]),
              const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
            ],
          ),
        ),
      );
}

/// Opens Google Maps at a point (or searches the address text when there is no pin).
Future<void> openInMaps(BuildContext context, {double? lat, double? lng, String address = ''}) async {
  final q = lat != null && lng != null ? '$lat,$lng' : Uri.encodeComponent('$address, Quezon City');
  final ok = await launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$q'), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) toast(context, 'Could not open Google Maps', error: true);
}

/// Opens the phone dialer (Call station, tap a phone number).
Future<void> callNumber(BuildContext context, String phone) async {
  final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (digits.isEmpty) {
    toast(context, 'No phone number saved', error: true);
    return;
  }
  final ok = await launchUrl(Uri.parse('tel:$digits'));
  if (!ok && context.mounted) toast(context, 'Call $phone from your phone');
}

/// Map pin sheet: the address on the map and "Open in Google Maps".
Future<void> showPinSheet(BuildContext context, {required String address, double? lat, double? lng}) {
  return sheet<void>(
    context,
    'Map pin',
    sub: address,
    (c, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (lat != null && lng != null) PinView(LatLng(lat, lng)) else const Note('This address was typed, not pinned on the map.'),
      const Gap(16),
      Btn('Open in Google Maps', () => openInMaps(context, lat: lat, lng: lng, address: address), outline: true),
    ]),
  );
}
