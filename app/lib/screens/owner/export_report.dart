import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../services/api.dart';
import '../../services/app_state.dart';
import '../../theme/brand.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';

/// Admin Sales 4: Export Report. Choose the report (Daily, Weekly, Unpaid accounts), the date or week,
/// and the format (PDF or Spreadsheet), then Create file. Chrome: the file goes to the Downloads folder.
/// Phone: the app downloads the file and opens the phone's Save screen (Downloads), so it does not
/// depend on the phone's browser.
class ExportReport extends StatefulWidget {
  /// 0 Daily, 1 Weekly, 2 Unpaid accounts.
  final int report;
  final DateTime? date;
  const ExportReport({super.key, this.report = 0, this.date});

  @override
  State<ExportReport> createState() => _ExportReportState();
}

class _ExportReportState extends State<ExportReport> {
  late int _report = widget.report;
  late DateTime _date;
  int _format = 0; // 0 PDF, 1 Spreadsheet
  bool _busy = false;
  ApiException? _error;
  String? _fileName;
  String? _url;
  Uint8List? _bytes; // phone: the downloaded file, kept so "Save again" works
  bool? _saved; // phone: true saved, false the Save screen was closed without saving

  static const _reports = ['Daily', 'Weekly', 'Unpaid accounts'];
  static const _keys = ['daily', 'weekly', 'unpaid'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static String _label(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

  DateTime get _today {
    final p = ph(DateTime.now());
    return DateTime(p.year, p.month, p.day);
  }

  DateTime get _monday => _date.subtract(Duration(days: _date.weekday - 1));

  String get _dateText {
    if (_report == 2) return 'As of today, ${_label(_today)}';
    if (_report == 1) return 'Week of ${_label(_monday)} to ${_label(_monday.add(const Duration(days: 6)))}';
    return _label(_date);
  }

  @override
  void initState() {
    super.initState();
    final d = widget.date ?? _today;
    _date = DateTime(d.year, d.month, d.day);
  }

  void _changed(VoidCallback f) => setState(() {
        f();
        _fileName = null;
        _url = null;
        _bytes = null;
        _saved = null;
        _error = null;
      });

  Future<void> _pick() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2025),
      lastDate: _today,
      helpText: _report == 1 ? 'Choose any day of the week' : 'Choose date',
    );
    if (d != null) _changed(() => _date = DateTime(d.year, d.month, d.day));
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await app.api.post('/api/export', {
        'report': _keys[_report],
        if (_report != 2) 'date': _ymd(_date),
        'format': _format == 0 ? 'pdf' : 'xlsx',
      });
      if (!mounted) return;
      _fileName = r['fileName'] as String;
      _url = r['url'] as String;
      _bytes = null;
      _saved = null;
      if (kIsWeb) {
        _madeAt = DateTime.now();
        setState(() => _busy = false);
        await _download();
      } else {
        _bytes = await _fetch();
        if (!mounted) return;
        setState(() => _busy = false);
        await _saveOnPhone();
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e;
        });
      }
    }
  }

  DateTime? _madeAt; // the download link works for 5 minutes

  /// Web version (Chrome, Safari on iPhone): the file downloads in the same tab. A new window is
  /// blocked by Safari on iPhone, but the same tab is not, and the page stays (the server sends the
  /// file as a download).
  Future<void> _download() async {
    final made = _madeAt;
    if (made == null || DateTime.now().difference(made) > const Duration(minutes: 4)) {
      await _create(); // link too old: make a new one (it downloads again)
      return;
    }
    final ok = await launchUrl(Uri.parse('${AppConfig.apiUrl}$_url'), webOnlyWindowName: '_self');
    if (!ok && mounted) toast(context, 'Could not download the file', error: true);
  }

  static const _notSaved = ApiException(0, 'DOWNLOAD', 'File not saved', 'Check the internet, then tap Create file again.');

  /// Phone: downloads the file into the app (the link works for 5 minutes).
  Future<Uint8List> _fetch() async {
    try {
      final res = await http.get(Uri.parse('${AppConfig.apiUrl}$_url')).timeout(const Duration(seconds: 60));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) throw _notSaved;
      return res.bodyBytes;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw _notSaved;
    }
  }

  /// Phone: the phone's Save screen opens (usually at Downloads); the user taps Save.
  Future<void> _saveOnPhone() async {
    final bytes = _bytes;
    final name = _fileName;
    if (bytes == null || name == null) return;
    try {
      final uri = await FilePicker.saveFile(
        fileName: name,
        bytes: bytes,
        mimeType: name.endsWith('.pdf')
            ? 'application/pdf'
            : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        dialogTitle: 'Save report',
      );
      if (mounted) setState(() => _saved = uri != null);
    } catch (_) {
      if (mounted) setState(() => _error = _notSaved);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export Report')),
      body: Body([
        if (_error != null) MsgBanner(_error!.title, sub: _error!.message),
        const Label('Report'),
        const Gap(6),
        Seg(_reports, _report, (i) => _changed(() => _report = i)),
        const Gap(14),
        Label(_report == 1 ? 'Week' : 'Date'),
        const Gap(6),
        Box(
          onTap: _report == 2 ? null : _pick,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(children: [
            const Icon(Icons.calendar_today_outlined, color: Brand.blue, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(_dateText, style: const TextStyle(fontWeight: FontWeight.w700))),
            if (_report != 2) const Icon(Icons.chevron_right, color: Brand.blue),
          ]),
        ),
        const Gap(14),
        const Label('Format'),
        const Gap(6),
        Seg(const ['PDF', 'Spreadsheet'], _format, (i) => _changed(() => _format = i)),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('Spreadsheet opens in Excel or Google Sheets.', style: TextStyle(color: Brand.muted, fontSize: 12)),
        ),
        const Gap(18),
        Btn('Create file', _create, busy: _busy, icon: Icons.file_download_outlined),
        if (_fileName != null && kIsWeb) ...[
          const Gap(14),
          Box(
            tint: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Row(children: [
                Icon(Icons.check_circle, color: Brand.blue),
                SizedBox(width: 8),
                Text('File ready', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ]),
              const Gap(4),
              Text(_fileName!, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
              const Gap(2),
              const Text(
                'If it did not download, tap Download. iPhone: tap Download when Safari asks; the file goes to the Files app > Downloads. Computer: the Downloads folder.',
                style: TextStyle(color: Brand.muted, fontSize: 12.5),
              ),
              const Gap(10),
              Btn('Download', _download, small: true, icon: Icons.file_download_outlined),
            ]),
          ),
        ],
        if (_fileName != null && !kIsWeb && _saved != null) ...[
          const Gap(14),
          Box(
            tint: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Icon(_saved! ? Icons.check_circle : Icons.info_outline, color: Brand.blue),
                const SizedBox(width: 8),
                Text(_saved! ? 'File saved' : 'File not saved yet', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ]),
              const Gap(4),
              Text(_fileName!, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
              const Gap(2),
              Text(
                _saved!
                    ? 'Open it from the Files app (Downloads or the folder you chose). From there you can open or share it.'
                    : 'Tap Save to phone, then tap Save on the next screen.',
                style: const TextStyle(color: Brand.muted, fontSize: 12.5),
              ),
              const Gap(10),
              Btn(_saved! ? 'Save again' : 'Save to phone', _saveOnPhone, outline: _saved!, small: true),
            ]),
          ),
        ],
      ]),
    );
  }
}
