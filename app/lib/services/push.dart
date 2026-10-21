import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../models/user.dart';
import '../screens/customer/order_details.dart';
import '../screens/owner/admin_order_details.dart';
import '../widgets/alert_banner.dart';
import 'app_state.dart';
import 'nav.dart';

/// Phone notifications (Android) with Firebase Cloud Messaging: alerts show in the phone's
/// notification bar even when the app is closed. The Firebase settings come from the GitHub build
/// (secret FIREBASE_ANDROID_JSON); without them the app still shows every alert inside the app.
class PushSetup {
  static const _apiKey = String.fromEnvironment('FB_API_KEY');
  static const _appId = String.fromEnvironment('FB_APP_ID');
  static const _senderId = String.fromEnvironment('FB_SENDER_ID');
  static const _projectId = String.fromEnvironment('FB_PROJECT_ID');

  static bool get configured => !kIsWeb && _apiKey.isNotEmpty && _appId.isNotEmpty;
  static bool _ready = false;
  static StreamSubscription<String>? _refresh;

  /// When the app opens.
  static Future<void> init() async {
    if (!configured || _ready) return;
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(apiKey: _apiKey, appId: _appId, messagingSenderId: _senderId, projectId: _projectId),
      );
      _ready = true;
      // Tapping a notification opens the order.
      FirebaseMessaging.onMessageOpenedApp.listen(_open);
      // While the app is open Android does not show the notification itself: show the alert card.
      FirebaseMessaging.onMessage.listen((m) {
        final id = int.tryParse('${m.data['orderId'] ?? ''}');
        showAlertBanner(title: m.notification?.title ?? '', message: m.notification?.body ?? '', orderId: id);
      });
      final first = await FirebaseMessaging.instance.getInitialMessage();
      if (first != null) Future.delayed(const Duration(seconds: 2), () => _open(first));
    } catch (_) {
      _ready = false;
    }
  }

  /// After log in, sign up, guest start or opening with a saved session: asks the user once to allow
  /// notifications and tells the server this phone's address for notifications.
  static Future<void> register() async {
    if (!_ready) return;
    try {
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _send(token);
      _refresh ??= FirebaseMessaging.instance.onTokenRefresh.listen(_send);
    } catch (_) {}
  }

  static Future<void> _send(String token) async {
    try {
      await app.api.post('/api/notifications/device', {'token': token, 'platform': 'android'});
    } catch (_) {}
  }

  /// Log out: this phone stops getting the account's notifications.
  static Future<void> unregister() async {
    if (!_ready) return;
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  static void _open(RemoteMessage m) {
    final id = int.tryParse('${m.data['orderId'] ?? ''}');
    if (id == null) return;
    final owner = app.role == Role.owner;
    final customer = app.guest || app.role == Role.customer;
    if (!owner && !customer) return;
    navKey.currentState?.push(MaterialPageRoute(
      builder: (_) => owner ? AdminOrderDetails(orderId: id) : CustomerOrderDetails(orderId: id),
    ));
  }
}
