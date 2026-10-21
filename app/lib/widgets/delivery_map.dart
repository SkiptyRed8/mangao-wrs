import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/app_state.dart';
import '../theme/brand.dart';

// Delivery map pieces used by the customer's order tracking and the owner/staff Live Map:
// the sidecar marker (turns to the direction it moves and glides to each new place), the route
// along the streets (our server asks OSRM, OpenStreetMap roads) with a straight line when it is not
// available, the light line of the part already travelled from the station, and the
// "About 6 min away · 1.8 km" text.

const _earthMeters = 6371000.0;
double _rad(double d) => d * math.pi / 180;

/// Meters between two points (haversine formula).
double metersBetween(LatLng a, LatLng b) {
  final dLat = _rad(b.latitude - a.latitude);
  final dLng = _rad(b.longitude - a.longitude);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(a.latitude)) * math.cos(_rad(b.latitude)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthMeters * math.asin(math.min(1, math.sqrt(h)));
}

/// Compass direction from [a] to [b] in degrees: 0 north, 90 east, 180 south, 270 west.
double bearingBetween(LatLng a, LatLng b) {
  final y = math.sin(_rad(b.longitude - a.longitude)) * math.cos(_rad(b.latitude));
  final x = math.cos(_rad(a.latitude)) * math.sin(_rad(b.latitude)) -
      math.sin(_rad(a.latitude)) * math.cos(_rad(b.latitude)) * math.cos(_rad(b.longitude - a.longitude));
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// Turns the marker the short way round (350° to 10° turns 20°, not 340°).
double nextHeading(double current, double target) {
  final diff = ((target - current + 540) % 360) - 180;
  return current + diff;
}

/// A route: the points of the line, its length and the travel time.
class RouteResult {
  final List<LatLng> points;
  final double meters;
  final double seconds;

  /// True when it follows the streets; false for the straight-line fallback.
  final bool streets;
  const RouteResult(this.points, this.meters, this.seconds, this.streets);
}

/// "About 6 min away · 1.8 km" (or "Arriving now").
String etaText(RouteResult r) {
  if (r.meters < 60) return 'Arriving now';
  final minutes = math.max(1, (r.seconds / 60).ceil());
  final distance = r.meters >= 1000 ? '${(r.meters / 1000).toStringAsFixed(1)} km' : '${r.meters.round()} m';
  return 'About $minutes min away · $distance';
}

/// Within this distance of the address the rider has arrived, and within [arrivingMeters] is arriving
/// (the server sends the same two messages to the customer's phone).
const arrivedMeters = 50.0;
const arrivingMeters = 300.0;

/// Arrived, Arriving or null (on the way) from the rider's place: within [arrivedMeters] /
/// [arrivingMeters] of the pin, or of the end of the street route (a pin away from the road is
/// reached where the road ends). [server] is the order's own step (orders.arrival) when known.
String? arrivalStep(LatLng rider, LatLng? home, RouteResult? view, {String? server}) {
  if (server == 'Arrived') return 'Arrived';
  var m = home == null ? double.infinity : metersBetween(rider, home);
  if (view != null && view.streets) m = math.min(m, view.meters);
  if (m <= arrivedMeters) return 'Arrived';
  if (server == 'Arriving' || m <= arrivingMeters) return 'Arriving';
  return null;
}

/// The customer's line above the map: "Your rider has arrived. Please prepare ₱150.00",
/// "Arriving - please prepare ₱150.00", or "About 6 min away · 1.8 km".
String arrivalText(LatLng rider, LatLng? home, RouteResult? view, {String? prepare, String? server}) {
  final step = arrivalStep(rider, home, view, server: server);
  if (step == 'Arrived') return 'Your rider has arrived.${prepare == null ? '' : ' $prepare'}';
  if (step == 'Arriving') return prepare == null ? 'Arriving now' : 'Arriving - ${prepare[0].toLowerCase()}${prepare.substring(1)}';
  return view == null ? 'Finding the route...' : etaText(view);
}

/// Short form for the marker label on the Live Map: "6 min".
String etaShort(RouteResult r) => r.meters < 60 ? 'Arriving' : '${math.max(1, (r.seconds / 60).ceil())} min';

/// Routes along the streets from our server (GET /api/geo/route), which asks the free OSRM route service
/// (open-source routing on OpenStreetMap roads). If there is no answer, a straight line with about
/// 20 km/h city speed is used, so the map always works.
class RouteService {
  static const _citySpeed = 20000 / 3600; // meters per second

  static Future<RouteResult> route(LatLng from, LatLng to) async {
    try {
      final r = await app.api.get('/api/geo/route?from=${from.latitude},${from.longitude}&to=${to.latitude},${to.longitude}');
      final pts = [
        for (final p in r['points'] as List) LatLng(((p as List)[0] as num).toDouble(), (p[1] as num).toDouble()),
      ];
      if (pts.length >= 2) {
        return RouteResult(pts, (r['meters'] as num).toDouble(), (r['seconds'] as num).toDouble(), r['streets'] == true);
      }
    } catch (_) {}
    return straight(from, to);
  }

  static RouteResult straight(LatLng from, LatLng to) {
    final m = metersBetween(from, to);
    return RouteResult([from, to], m, m / _citySpeed, false);
  }
}

/// Keeps the route of one rider to one stop. It asks the route service only when needed (first time,
/// the stop changed, the rider left the route, or every 2 minutes), and in between cuts off the part
/// of the route the rider has already passed.
class RouteTracker {
  final VoidCallback onChange;
  RouteTracker(this.onChange);

  RouteResult? _route;
  LatLng? _target;
  DateTime _fetchedAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _loading = false;
  bool _disposed = false;

  void dispose() => _disposed = true;

  /// Call when the rider's place or the stop changes.
  void update(LatLng rider, LatLng target) {
    if (_loading) return;
    final r = _route;
    final age = DateTime.now().difference(_fetchedAt);
    final stopMoved = _target == null || metersBetween(_target!, target) > 30;
    final offRoute = r != null && r.streets && age > const Duration(seconds: 20) && _distanceToRoute(rider, r) > 80;
    final retryStreets = r != null && !r.streets && age > const Duration(minutes: 1);
    if (r == null || stopMoved || offRoute || retryStreets || age > const Duration(minutes: 2)) _fetch(rider, target);
  }

  Future<void> _fetch(LatLng rider, LatLng target) async {
    _loading = true;
    _target = target;
    final r = await RouteService.route(rider, target);
    _loading = false;
    if (_disposed) return;
    _route = r;
    _fetchedAt = DateTime.now();
    onChange();
  }

  static int _nearest(LatLng p, List<LatLng> pts) {
    var best = 0;
    var bestM = double.infinity;
    for (var i = 0; i < pts.length; i++) {
      final m = metersBetween(p, pts[i]);
      if (m < bestM) {
        bestM = m;
        best = i;
      }
    }
    return best;
  }

  static double _distanceToRoute(LatLng p, RouteResult r) => metersBetween(p, r.points[_nearest(p, r.points)]);

  /// What to draw from where the rider is now: the rest of the route, meters and seconds left.
  RouteResult? view(LatLng rider) {
    final r = _route;
    final target = _target;
    if (r == null || target == null) return null;
    if (!r.streets) return RouteService.straight(rider, target);
    final i = _nearest(rider, r.points);
    final rest = <LatLng>[rider, ...r.points.sublist(math.min(i + 1, r.points.length))];
    if (rest.length < 2) rest.add(target);
    var m = 0.0;
    for (var k = 0; k + 1 < rest.length; k++) {
      m += metersBetween(rest[k], rest[k + 1]);
    }
    final secs = r.meters > 0 ? r.seconds * (m / r.meters) : m / RouteService._citySpeed;
    return RouteResult(rest, m, secs, true);
  }
}

/// The planned trip from the station to the stop, fetched once. Its first part, up to where the rider
/// is now, is drawn as a light line (the way already travelled), like Grab.
class PlannedRoute {
  final VoidCallback onChange;
  PlannedRoute(this.onChange);

  RouteResult? _route;
  LatLng? _from, _to;
  bool _loading = false;
  bool _disposed = false;

  void dispose() => _disposed = true;

  void update(LatLng from, LatLng to) {
    if (_loading) return;
    if (_route != null && metersBetween(_from!, from) < 30 && metersBetween(_to!, to) < 30) return;
    _loading = true;
    _from = from;
    _to = to;
    RouteService.route(from, to).then((r) {
      _loading = false;
      if (_disposed) return;
      _route = r;
      onChange();
    });
  }

  /// From the station to the rider (null when the rider is not on the planned way).
  List<LatLng>? travelled(LatLng rider) {
    final r = _route;
    if (r == null) return null;
    if (!r.streets) return metersBetween(r.points.first, rider) < 10 ? null : [r.points.first, rider];
    final i = RouteTracker._nearest(rider, r.points);
    if (metersBetween(rider, r.points[i]) > 150) return null;
    final pts = [...r.points.sublist(0, i + 1), rider];
    return pts.length >= 2 ? pts : null;
  }
}

/// Moves a LatLng smoothly between two places (for the gliding marker).
class LatLngTween extends Tween<LatLng> {
  LatLngTween({super.begin, super.end});

  @override
  LatLng lerp(double t) {
    final a = begin!, b = end!;
    return LatLng(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t);
  }
}

/// The route lines: the way already travelled from the station (light), and the way ahead (blue with
/// a white edge; dashed when it is only a straight line).
PolylineLayer routeLayer(RouteResult? r, {List<LatLng>? travelled}) => PolylineLayer(polylines: [
      if (travelled != null && travelled.length >= 2)
        Polyline(
          points: travelled,
          strokeWidth: 5,
          color: Brand.blue.withValues(alpha: 0.35),
          borderStrokeWidth: 1.5,
          borderColor: Colors.white.withValues(alpha: 0.8),
        ),
      if (r != null && r.points.length >= 2)
        Polyline(
          points: r.points,
          strokeWidth: 6,
          color: Brand.blue,
          borderStrokeWidth: 2,
          borderColor: Colors.white,
          pattern: r.streets ? const StrokePattern.solid() : StrokePattern.dashed(segments: const [12, 10]),
        ),
    ]);

/// The rider on the map: a sidecar seen from above that glides to each new place and turns to the
/// direction it is going. [label] shows under it (e.g. "6 min" or "Last seen 7 min ago").
class SidecarLayer extends StatelessWidget {
  final LatLng point;
  final double heading;
  final bool faded;
  final String? label;
  final VoidCallback? onTap;
  const SidecarLayer({super.key, required this.point, required this.heading, this.faded = false, this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<LatLng>(
      tween: LatLngTween(end: point),
      duration: const Duration(milliseconds: 1600),
      curve: Curves.easeInOut,
      builder: (context, p, _) => TweenAnimationBuilder<double>(
        tween: Tween<double>(end: heading),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOut,
        builder: (context, h, _) => MarkerLayer(markers: [
          Marker(
            point: p,
            width: 150,
            height: 96,
            child: GestureDetector(
              onTap: onTap,
              child: Stack(alignment: Alignment.center, children: [
                Transform.rotate(angle: h * math.pi / 180, child: SidecarIcon(faded: faded)),
                if (label != null)
                  Positioned(
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: faded ? Colors.white : Brand.blue,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: faded ? Brand.muted : Colors.white, width: 1.5),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
                      ),
                      child: Text(label!,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: faded ? Brand.ink : Colors.white)),
                    ),
                  ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The station on the map: a blue circle with a water drop.
Marker stationMarker(LatLng p) => Marker(
      point: p,
      width: 34,
      height: 34,
      child: Container(
        decoration: BoxDecoration(
          color: Brand.blue,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
        ),
        child: const Icon(Icons.water_drop, color: Colors.white, size: 18),
      ),
    );

/// The customer's delivery address on the map: a white circle with a house.
Marker homeMarker(LatLng p) => Marker(
      point: p,
      width: 40,
      height: 40,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: Brand.ink, width: 2.5),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
        ),
        child: const Icon(Icons.home_rounded, color: Brand.ink, size: 22),
      ),
    );

/// Sidecar (tricycle) seen from above, pointing up: the motorcycle in the middle with the rider's
/// helmet, the sidecar on its right carrying a water gallon. Drawn by the app (original drawing).
class SidecarIcon extends StatelessWidget {
  final bool faded;
  final double size;
  const SidecarIcon({super.key, this.faded = false, this.size = 46});

  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _SidecarPainter(faded)));
}

class _SidecarPainter extends CustomPainter {
  final bool faded;
  _SidecarPainter(this.faded);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 46; // drawn on a 46 x 46 grid
    canvas.scale(s);
    final main = faded ? Brand.muted : Brand.blue;
    const dark = Brand.ink;
    final water = faded ? const Color(0xFFD5DADF) : const Color(0xFF8FD0FF);
    final fill = Paint()..style = PaintingStyle.fill;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // soft shadow under the whole vehicle
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(10, 6, 30, 36), const Radius.circular(9)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // wheels: front, back (motorcycle) and the sidecar wheel
    fill.color = dark;
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(16.5, 3, 5, 8), const Radius.circular(2)), fill);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(16.5, 35, 5, 8), const Radius.circular(2)), fill);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(38, 20, 4.5, 9), const Radius.circular(2)), fill);

    // bar joining the motorcycle and the sidecar
    line
      ..color = dark
      ..strokeWidth = 2.5;
    canvas.drawLine(const Offset(22, 17), const Offset(27, 17), line);
    canvas.drawLine(const Offset(22, 32), const Offset(27, 32), line);

    // motorcycle body
    final body = RRect.fromRectAndRadius(const Rect.fromLTWH(13.5, 8, 11, 31), const Radius.circular(5.5));
    fill.color = main;
    canvas.drawRRect(body, fill);
    line
      ..color = Colors.white
      ..strokeWidth = 2;
    canvas.drawRRect(body, line);

    // handlebar
    line
      ..color = dark
      ..strokeWidth = 2.6;
    canvas.drawLine(const Offset(11, 13), const Offset(25, 13), line);

    // rider's helmet
    fill.color = dark;
    canvas.drawCircle(const Offset(19, 22), 5.2, fill);
    fill.color = Colors.white.withValues(alpha: 0.85);
    canvas.drawCircle(const Offset(17.6, 20.4), 1.6, fill);

    // sidecar (passenger cab) with a white body and blue edge
    final cab = RRect.fromRectAndRadius(const Rect.fromLTWH(26.5, 11, 12, 27), const Radius.circular(5));
    fill.color = Colors.white;
    canvas.drawRRect(cab, fill);
    line
      ..color = main
      ..strokeWidth = 2.2;
    canvas.drawRRect(cab, line);

    // water gallon inside the sidecar, with its cap
    fill.color = water;
    canvas.drawCircle(const Offset(32.5, 25), 4.6, fill);
    line
      ..color = main
      ..strokeWidth = 1.4;
    canvas.drawCircle(const Offset(32.5, 25), 4.6, line);
    fill.color = main;
    canvas.drawCircle(const Offset(32.5, 25), 1.5, fill);

    // headlight (front of the motorcycle)
    fill.color = const Color(0xFFFFE082);
    canvas.drawCircle(const Offset(19, 8.5), 1.6, fill);
  }

  @override
  bool shouldRepaint(_SidecarPainter old) => old.faded != faded;
}

/// The customer's tracking map: the sidecar, the route to the delivery address, and the time left.
class DeliveryMap extends StatefulWidget {
  final LatLng? home;
  final LatLng? rider;

  /// The station: the trip starts here (light line of the way already travelled).
  final LatLng? start;
  final double height;

  /// "Please prepare ₱150.00" (null when the order is already paid).
  final String? prepare;

  /// The order's step from the server: Arriving, Arrived or null.
  final String? arrival;
  const DeliveryMap({super.key, required this.home, required this.rider, this.start, this.height = 260, this.prepare, this.arrival});

  @override
  State<DeliveryMap> createState() => _DeliveryMapState();
}

class _DeliveryMapState extends State<DeliveryMap> {
  final _map = MapController();
  late final RouteTracker _route = RouteTracker(() {
    if (mounted) setState(() {});
  });
  late final PlannedRoute _planned = PlannedRoute(() {
    if (mounted) setState(() {});
  });
  double _heading = 0;
  bool _fitted = false;

  /// The rider's place; before the first GPS place the sidecar waits at the station.
  LatLng? get _rider => widget.rider ?? widget.start;

  @override
  void initState() {
    super.initState();
    _follow(null);
  }

  @override
  void didUpdateWidget(DeliveryMap old) {
    super.didUpdateWidget(old);
    _follow(old.rider ?? old.start);
  }

  @override
  void dispose() {
    _route.dispose();
    _planned.dispose();
    super.dispose();
  }

  void _follow(LatLng? before) {
    final r = _rider, h = widget.home;
    if (r == null) return;
    if (before != null && metersBetween(before, r) > 4) _heading = nextHeading(_heading, bearingBetween(before, r));
    if (before == null && h != null) _heading = bearingBetween(r, h); // face the customer at first
    if (h != null) _route.update(r, h);
    if (h != null && widget.start != null) _planned.update(widget.start!, h);
    if (!_fitted) WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
  }

  /// Shows both the rider and the delivery address.
  void _fit() {
    final pts = [
      if (widget.start != null) widget.start!,
      if (_rider != null) _rider!,
      if (widget.home != null) widget.home!,
    ];
    if (pts.isEmpty || !mounted) return;
    try {
      if (pts.length == 1) {
        _map.move(pts.first, 16);
      } else {
        _map.fitCamera(CameraFit.coordinates(coordinates: pts, padding: const EdgeInsets.all(48), maxZoom: 17));
      }
      _fitted = true;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final r = _rider, h = widget.home;
    final view = r == null ? null : _route.view(r);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Icon(r == null ? Icons.hourglass_empty : Icons.two_wheeler, size: 18, color: Brand.blue),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              r == null ? "Waiting for the rider's location..." : arrivalText(r, h, view, prepare: widget.prepare, server: widget.arrival),
              style: TextStyle(fontWeight: FontWeight.w800, color: r == null ? Brand.muted : Brand.ink),
            ),
          ),
        ]),
      ),
      SizedBox(
        height: widget.height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: r ?? h ?? const LatLng(14.692823, 121.0871699),
                initialZoom: 15,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              ),
              children: [
                TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.mangao.mangao_wrs'),
                routeLayer(view, travelled: r == null ? null : _planned.travelled(r)),
                MarkerLayer(markers: [
                  if (widget.start != null) stationMarker(widget.start!),
                  if (h != null) homeMarker(h),
                ]),
                if (r != null) SidecarLayer(point: r, heading: _heading),
                const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
              ],
            ),
            Positioned(
              right: 8,
              bottom: 30,
              child: Material(
                color: Colors.white,
                shape: const CircleBorder(side: BorderSide(color: Brand.soft)),
                elevation: 2,
                child: IconButton(
                  tooltip: 'Show rider and address',
                  icon: const Icon(Icons.center_focus_strong, color: Brand.blue),
                  onPressed: _fit,
                ),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}
