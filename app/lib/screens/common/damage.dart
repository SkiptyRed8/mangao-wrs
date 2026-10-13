import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../config.dart';
import '../../models/order.dart';
import '../../services/api.dart';
import '../../services/app_state.dart';
import '../../theme/brand.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';

/// Opens Report damaged gallon for an order. Returns true when sent (the caller reloads).
Future<bool> reportDamaged(BuildContext context, Order o) async {
  final msg = await go<String>(context, DamageReportScreen(order: o));
  if (msg != null && context.mounted) toast(context, msg);
  return msg != null;
}

/// Rider 4 / Staff 2 / Admin Orders 5: Report damaged gallon. Take a photo (or choose one), write a
/// note, Send (Confirm for the owner). One new gallon from stock replaces it and the owner is alerted.
class DamageReportScreen extends StatefulWidget {
  final Order order;
  const DamageReportScreen({super.key, required this.order});

  @override
  State<DamageReportScreen> createState() => _DamageReportScreenState();
}

class _DamageReportScreenState extends State<DamageReportScreen> {
  final _note = TextEditingController();
  Uint8List? _photo;
  ApiException? _error;
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final f = await ImagePicker().pickImage(source: source, maxWidth: 1280, maxHeight: 1280, imageQuality: 70);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photo = bytes;
        if (_error?.code == 'PHOTO_MISSING') _error = null;
      });
    } catch (_) {
      if (mounted) toast(context, 'Could not open the camera. Choose a photo instead.', error: true);
    }
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    if (_photo == null) {
      setState(() => _error = const ApiException(400, 'PHOTO_MISSING', 'Photo missing', 'Take a photo of the damaged gallon.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await app.api.post('/api/damage', {
        'orderId': widget.order.id,
        'photo': base64Encode(_photo!),
        'note': _note.text,
      });
      if (mounted) Navigator.pop(context, (r['message'] ?? 'Sent.') as String);
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
    final owner = app.isOwner;
    return Scaffold(
      appBar: AppBar(title: const Text('Report damaged gallon')),
      body: Body([
        if (_error != null) MsgBanner(_error!.title, sub: _error!.message),
        Note('Order #${o.id} · ${o.name.isEmpty ? 'Guest' : o.name} · ${o.quantity} ${o.quantity == 1 ? 'gallon' : 'gallons'}'),
        const Label('Photo'),
        const Gap(6),
        Material(
          color: _error?.code == 'PHOTO_MISSING' ? Brand.redLight : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: _error?.code == 'PHOTO_MISSING' ? Brand.red : Brand.blue,
              width: _error?.code == 'PHOTO_MISSING' ? 2 : 1.2,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _pick(ImageSource.camera),
            child: SizedBox(
              height: 200,
              child: _photo == null
                  ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.photo_camera_outlined, size: 44, color: Brand.blue),
                      Gap(6),
                      Text('Take photo', style: TextStyle(fontWeight: FontWeight.w800)),
                    ])
                  : Image.memory(_photo!, fit: BoxFit.cover, width: double.infinity),
            ),
          ),
        ),
        const Gap(8),
        Row(children: [
          Expanded(child: Btn(_photo == null ? 'Take photo' : 'Retake', () => _pick(ImageSource.camera), outline: true, small: true, icon: Icons.photo_camera_outlined)),
          const Gap(8),
          Expanded(child: Btn('Choose photo', () => _pick(ImageSource.gallery), outline: true, small: true, icon: Icons.image_outlined)),
        ]),
        const Gap(14),
        Field('Note', _note, hint: 'What is damaged, e.g. cracked at the handle', lines: 2),
        const Text('One new gallon from stock replaces it. The order continues.', style: TextStyle(color: Brand.muted, fontSize: 12.5)),
        const Gap(16),
        Btn(owner ? 'Confirm' : 'Send', _send, busy: _busy),
        const Gap(),
        Btn('Close', _busy ? null : () => Navigator.pop(context), outline: true),
      ]),
    );
  }
}

/// Damaged gallons reported for an order (photo, note, who and when). Hidden when there are none.
class DamageBox extends StatefulWidget {
  final int orderId;

  /// Changes when the order reloads so the box reloads too.
  final Object? version;
  const DamageBox(this.orderId, {super.key, this.version});

  @override
  State<DamageBox> createState() => _DamageBoxState();
}

class _DamageBoxState extends State<DamageBox> {
  List<Map<String, dynamic>> _reports = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DamageBox old) {
    super.didUpdateWidget(old);
    if (old.version != widget.version) _load();
  }

  Future<void> _load() async {
    try {
      final r = await app.api.get('/api/damage?orderId=${widget.orderId}');
      if (mounted) setState(() => _reports = [for (final x in r['reports'] as List) x as Map<String, dynamic>]);
    } on ApiException {
      // The box just stays hidden.
    }
  }

  void _view(String url) => showDialog<void>(
        context: context,
        builder: (c) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(12),
          child: GestureDetector(onTap: () => Navigator.pop(c), child: InteractiveViewer(child: Image.network(url))),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_reports.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Box(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Label('Damaged gallon (${_reports.length})'),
          const Gap(6),
          for (final r in _reports)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (r['photo'] != null)
                  GestureDetector(
                    onTap: () => _view('${AppConfig.apiUrl}${r['photo']}'),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        '${AppConfig.apiUrl}${r['photo']}',
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(width: 64, height: 64, child: Icon(Icons.broken_image_outlined)),
                      ),
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r['note'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${r['by']} · ${dateTimePh(DateTime.tryParse((r['at'] ?? '') as String))}',
                        style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
                  ]),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}
