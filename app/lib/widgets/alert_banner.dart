import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/user.dart';
import '../screens/customer/order_details.dart';
import '../screens/owner/admin_order_details.dart';
import '../services/app_state.dart';
import '../services/nav.dart';
import '../theme/brand.dart';
import '../utils/format.dart';

// The alert card at the top of the screen while the app is open (new order, order accepted,
// arriving ...). The same alert can come twice (live update and phone notification); it shows once.

final Map<String, DateTime> _recent = {};
final List<OverlayEntry> _shown = [];

/// Shows [title] and [message] at the top for 6 seconds. Tap: opens the order (owner and customers).
void showAlertBanner({required String title, String message = '', int? orderId}) {
  if (title.isEmpty && message.isEmpty) return;
  final key = '$title|$message|${orderId ?? ''}';
  final now = DateTime.now();
  _recent.removeWhere((_, t) => now.difference(t) > const Duration(seconds: 20));
  if (_recent.containsKey(key)) return;
  _recent[key] = now;

  final overlay = navKey.currentState?.overlay;
  if (overlay == null) return;
  for (final e in List.of(_shown)) {
    e.remove();
  }
  _shown.clear();

  late OverlayEntry entry;
  void close() {
    if (_shown.remove(entry)) entry.remove();
  }

  final owner = app.role == Role.owner;
  final customer = app.guest || app.role == Role.customer;
  final canOpen = orderId != null && (owner || customer);
  entry = OverlayEntry(
    builder: (context) => _AlertCard(
      title: title,
      message: message,
      time: clockPh(DateTime.now()),
      onClose: close,
      onTap: canOpen
          ? () {
              close();
              navKey.currentState?.push(MaterialPageRoute(
                builder: (_) => owner ? AdminOrderDetails(orderId: orderId) : CustomerOrderDetails(orderId: orderId),
              ));
            }
          : null,
    ),
  );
  _shown.add(entry);
  overlay.insert(entry);
  HapticFeedback.mediumImpact();
  SystemSound.play(SystemSoundType.alert);
  Timer(const Duration(seconds: 6), close);
}

class _AlertCard extends StatefulWidget {
  final String title;
  final String message;
  final String time;
  final VoidCallback onClose;
  final VoidCallback? onTap;
  const _AlertCard({required this.title, required this.message, required this.time, required this.onClose, this.onTap});

  @override
  State<_AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends State<_AlertCard> {
  bool _in = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _in = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 8;
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: AnimatedSlide(
            offset: _in ? Offset.zero : const Offset(0, -1.4),
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Dismissible(
                key: UniqueKey(),
                direction: DismissDirection.up,
                onDismissed: (_) => widget.onClose(),
                child: Material(
                  color: Colors.white,
                  elevation: 8,
                  shadowColor: Colors.black38,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: widget.onTap,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Brand.blue, width: 1.2),
                      ),
                      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: const BoxDecoration(color: Brand.blue, shape: BoxShape.circle),
                          child: const Icon(Icons.notifications_active, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              const Expanded(
                                child: Text('Mangao Water Refilling Station',
                                    style: TextStyle(color: Brand.muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
                              ),
                              Text(widget.time, style: const TextStyle(color: Brand.muted, fontSize: 11.5)),
                            ]),
                            const SizedBox(height: 2),
                            Text(widget.title, style: const TextStyle(color: Brand.ink, fontWeight: FontWeight.w800, fontSize: 15)),
                            if (widget.message.isNotEmpty)
                              Text(widget.message,
                                  maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Brand.ink, fontSize: 13.5)),
                            if (widget.onTap != null)
                              const Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: Text('Tap to view', style: TextStyle(color: Brand.blue, fontWeight: FontWeight.w700, fontSize: 12.5)),
                              ),
                          ]),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Close',
                          icon: const Icon(Icons.close, color: Brand.muted, size: 20),
                          onPressed: widget.onClose,
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
