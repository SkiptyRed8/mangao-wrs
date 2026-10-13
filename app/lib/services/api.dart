import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

/// An error from the server, with the wording shown in the app
/// (a bold [title] and one line [message] under it).
class ApiException implements Exception {
  final int status;
  final String code;
  final String title;
  final String message;
  final Map<String, dynamic> data;

  const ApiException(this.status, this.code, this.title, this.message, [this.data = const {}]);

  /// No internet, or the server is not running.
  bool get offline => status == 0;

  @override
  String toString() => '$title: $message';
}

/// Talks to the Node.js + Express server (REST API, JSON).
class Api {
  final String baseUrl;
  final http.Client _client;
  String? token;

  /// Guest Mode: the phone's guest code, so the server knows which orders are this phone's.
  String? guestToken;

  Api({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? AppConfig.apiUrl,
        _client = client ?? http.Client();

  Future<Map<String, dynamic>> get(String path) => _send('GET', path);
  Future<Map<String, dynamic>> post(String path, [Map<String, dynamic>? body]) => _send('POST', path, body);
  Future<Map<String, dynamic>> put(String path, [Map<String, dynamic>? body]) => _send('PUT', path, body);
  Future<Map<String, dynamic>> patch(String path, [Map<String, dynamic>? body]) => _send('PATCH', path, body);
  Future<Map<String, dynamic>> delete(String path) => _send('DELETE', path);

  Future<Map<String, dynamic>> _send(String method, String path, [Map<String, dynamic>? body]) async {
    final req = http.Request(method, Uri.parse('$baseUrl$path'));
    req.headers['Accept'] = 'application/json';
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (token == null && guestToken != null) req.headers['X-Guest-Token'] = guestToken!;
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }

    http.Response res;
    try {
      final streamed = await _client.send(req).timeout(const Duration(seconds: 20));
      res = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const ApiException(0, 'TIMEOUT', 'The server is taking too long', 'Check your internet connection and try again.');
    } catch (_) {
      throw const ApiException(0, 'OFFLINE', 'Cannot reach the server', 'Check your internet connection and try again.');
    }

    Map<String, dynamic> json = {};
    if (res.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is Map<String, dynamic>) json = decoded;
      } catch (_) {
        json = {};
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return json;

    final err = json['error'];
    if (err is Map<String, dynamic>) {
      throw ApiException(
        res.statusCode,
        (err['code'] ?? 'ERROR') as String,
        (err['title'] ?? 'Something went wrong') as String,
        (err['message'] ?? '') as String,
        err,
      );
    }
    throw ApiException(res.statusCode, 'ERROR', 'Something went wrong', 'Please try again.');
  }
}
