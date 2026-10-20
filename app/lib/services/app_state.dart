import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/user.dart';
import 'api.dart';
import 'realtime.dart';

/// Which screens the owner is looking at (top-bar switcher, Admin Home 2).
enum AppView { admin, staff, delivery }

/// Who is using the app. Kept on the phone so the app opens to the right Home (Login 4).
class AppState extends ChangeNotifier {
  final Api api;
  AppState(this.api);

  AppUser? user;
  bool guest = false;
  String? guestToken;
  AppView view = AppView.admin;
  int tab = 0;

  bool get loggedIn => user != null;
  Role? get role => user?.role;
  bool get isOwner => user?.role == Role.owner;

  /// The role whose screens are shown (the owner can switch to Staff or Delivery).
  Role? get shownRole {
    if (!isOwner) return guest ? Role.customer : role;
    return switch (view) { AppView.staff => Role.staff, AppView.delivery => Role.rider, _ => Role.owner };
  }

  static const _kToken = 'token';
  static const _kUser = 'user';
  static const _kGuest = 'guest';
  static const _kGuestToken = 'guestToken';

  /// Called when the app opens: already logged in -> that role's Home; otherwise Welcome.
  /// It never waits for the internet: the saved session opens at once and is checked in the background,
  /// so a sleeping or slow server can not keep the app on the logo screen.
  Future<void> load() async {
    try {
      await AppConfig.load();
    } catch (_) {}
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      notifyListeners();
      return;
    }
    try {
      guestToken = prefs.getString(_kGuestToken);
      guest = prefs.getBool(_kGuest) ?? false;
    } catch (_) {
      guestToken = null;
      guest = false;
    }
    api.guestToken = guest ? guestToken : null;
    String? token;
    try {
      token = prefs.getString(_kToken);
    } catch (_) {
      token = null;
    }
    if (token == null) {
      if (guest && guestToken != null) realtime.connect(guest: guestToken);
      notifyListeners();
      return;
    }
    api.token = token;
    try {
      final saved = prefs.getString(_kUser);
      if (saved != null) user = AppUser.fromJson(jsonDecode(saved) as Map<String, dynamic>);
    } catch (_) {
      user = null;
    }
    if (user != null) {
      realtime.connect(token: token);
      notifyListeners();
      _verify(prefs, token); // in the background
      return;
    }
    // No usable saved user: ask the server once, but do not wait for it forever.
    await _verify(prefs, token).timeout(const Duration(seconds: 8), onTimeout: () {});
    if (user == null) await _clear(prefs);
    notifyListeners();
  }

  /// Checks the saved session with the server. Session ended or account deactivated: back to Welcome.
  /// Server off, slow or answering something unexpected: keep what is saved.
  Future<void> _verify(SharedPreferences prefs, String token) async {
    try {
      final r = await api.get('/api/auth/me');
      final u = r['user'];
      if (u is Map<String, dynamic>) {
        user = AppUser.fromJson(u);
        await prefs.setString(_kUser, jsonEncode(user!.toJson()));
        if (!realtime.connected) realtime.connect(token: token);
      }
    } on ApiException catch (e) {
      if (!e.offline && (e.status == 401 || e.status == 403)) {
        await _clear(prefs);
        sessionEnded = false;
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _saveSession(String token, AppUser u) async {
    final prefs = await SharedPreferences.getInstance();
    api.token = token;
    api.guestToken = null;
    user = u;
    guest = false;
    view = AppView.admin;
    tab = 0;
    await prefs.setString(_kToken, token);
    await prefs.setString(_kUser, jsonEncode(u.toJson()));
    await prefs.setBool(_kGuest, false);
    realtime.connect(token: token);
    notifyListeners();
  }

  Future<void> _clear(SharedPreferences prefs) async {
    api.token = null;
    user = null;
    realtime.disconnect();
    await prefs.remove(_kToken);
    await prefs.remove(_kUser);
  }

  /// Log in with phone number and password (all roles).
  Future<void> login(String phone, String password) async {
    final body = {'phone': phone, 'password': password};
    Map<String, dynamic> r;
    try {
      r = await api.post('/api/auth/login', body);
    } on ApiException catch (e) {
      // The server was still waking up: wait for it once, then try again.
      if (!e.offline || !await serverOk()) rethrow;
      r = await api.post('/api/auth/login', body);
    }
    await _saveSession(r['token'] as String, AppUser.fromJson(r['user'] as Map<String, dynamic>));
  }

  /// Sign up (customers only). A guest's orders move to the new account (the server reads
  /// the guest code that is still sent with this request).
  Future<void> signup({
    required String name,
    required String phone,
    required String email,
    required String password,
    required String confirm,
    required bool consent,
  }) async {
    final r = await api.post('/api/auth/signup', {
      'name': name,
      'phone': phone,
      'email': email,
      'password': password,
      'confirm': confirm,
      'consent': consent,
    });
    if (guest) {
      final prefs = await SharedPreferences.getInstance();
      guestToken = null;
      await prefs.remove(_kGuestToken);
    }
    await _saveSession(r['token'] as String, AppUser.fromJson(r['user'] as Map<String, dynamic>));
  }

  /// Continue as guest: orders are kept on this phone only.
  Future<void> startGuest() async {
    final prefs = await SharedPreferences.getInstance();
    guestToken ??= _randomToken();
    guest = true;
    user = null;
    api.token = null;
    api.guestToken = guestToken;
    tab = 0;
    await prefs.setString(_kGuestToken, guestToken!);
    await prefs.setBool(_kGuest, true);
    realtime.connect(guest: guestToken);
    notifyListeners();
  }

  /// Set by Log out for the owner, staff and riders: Welcome then opens Log in with "Session ends"
  /// (Admin More 5). Customers go back to Welcome (Customer 8).
  bool sessionEnded = false;

  /// After My Account > Edit: keeps the new name, phone and email.
  Future<void> setUser(AppUser u) async {
    final prefs = await SharedPreferences.getInstance();
    user = u;
    await prefs.setString(_kUser, jsonEncode(u.toJson()));
    notifyListeners();
  }

  /// Log out (or Exit guest mode, which also forgets the guest's orders on this phone).
  Future<void> logout() async {
    sessionEnded = !guest && user != null && user!.role != Role.customer;
    final prefs = await SharedPreferences.getInstance();
    await _clear(prefs);
    if (guest) {
      guestToken = null;
      await prefs.remove(_kGuestToken);
    }
    guest = false;
    api.guestToken = null;
    realtime.disconnect();
    await prefs.setBool(_kGuest, false);
    view = AppView.admin;
    tab = 0;
    notifyListeners();
  }

  void setView(AppView v) {
    view = v;
    tab = 0;
    notifyListeners();
  }

  void goTab(int i) {
    tab = i;
    notifyListeners();
  }

  /// Which Order Board tab to open next (Home tiles and Needs Your Action set it).
  String? boardView;

  /// Owner: open the Orders tab at one view (new, processing, out, delivered, not-delivered ...).
  void openBoard(String view) {
    boardView = view;
    goTab(1);
  }

  /// Server check shown on the Welcome screen while setting up.
  /// True when the server answers. The free online server sleeps when nobody uses it and needs
  /// about a minute to wake up, so this keeps trying for up to [wait] before it says "no connection".
  Future<bool> serverOk({Duration wait = const Duration(seconds: 90)}) async {
    final until = DateTime.now().add(wait);
    while (true) {
      try {
        final r = await api.get('/health');
        if (r['ok'] == true) return true;
      } catch (_) {}
      if (DateTime.now().isAfter(until)) return false;
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  static String _randomToken() {
    final rnd = Random.secure();
    return List.generate(32, (_) => rnd.nextInt(16).toRadixString(16)).join();
  }
}

/// The one app state used by every screen.
final app = AppState(Api());
