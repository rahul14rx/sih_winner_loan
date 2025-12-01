// lib/services/api.dart

import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

/// Change this to your Flask backend
const String kBaseUrl = 'http://10.10.3.219:5001/';

final Connectivity _connectivity = Connectivity();

/// ---------------------------------------------------------------------------
/// FIXED CONNECTIVITY HANDLER (Connectivity Plus v6 API)
/// ---------------------------------------------------------------------------
/// New API:
///   - checkConnectivity() → Future<List<ConnectivityResult>>
///   - onConnectivityChanged → Stream<List<ConnectivityResult>>
///
/// We always check the FIRST item in the list.
/// ---------------------------------------------------------------------------

Future<void> _checkConnectivity() async {
  List<ConnectivityResult> results = await _connectivity.checkConnectivity();

  bool hasNet = results.isNotEmpty && results.first != ConnectivityResult.none;

  if (!hasNet) {
    final Completer<void> completer = Completer<void>();

    late StreamSubscription<List<ConnectivityResult>> sub;

    sub = _connectivity.onConnectivityChanged.listen((List<ConnectivityResult> res) {
      bool nowOnline = res.isNotEmpty && res.first != ConnectivityResult.none;

      if (nowOnline) {
        sub.cancel();
        completer.complete();
      }
    });

    await completer.future;
  }
}

/// ---------------------------------------------------------------------------
/// HTTP POST JSON
/// ---------------------------------------------------------------------------
Future<Map<String, dynamic>> postJson(
    String path, {
      required Map<String, dynamic> body,
      Map<String, String>? extraHeaders,
      Duration timeout = const Duration(seconds: 15),
    }) async {
  await _checkConnectivity();

  final uri = Uri.parse('$kBaseUrl$path');
  final headers = {
    'Content-Type': 'application/json',
    if (extraHeaders != null) ...extraHeaders,
  };

  try {
    final resp =
    await http.post(uri, headers: headers, body: jsonEncode(body)).timeout(timeout);

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      if (resp.body.isEmpty) return {};
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
  } catch (_) {}

  return {}; // fallback
}

/// ---------------------------------------------------------------------------
/// HTTP GET JSON
/// ---------------------------------------------------------------------------
Future<Map<String, dynamic>> getJson(
    String path, {
      Map<String, String>? extraHeaders,
      Duration timeout = const Duration(seconds: 15),
    }) async {
  await _checkConnectivity();

  final uri = Uri.parse('$kBaseUrl$path');
  final headers = {
    'Content-Type': 'application/json',
    if (extraHeaders != null) ...extraHeaders,
  };

  try {
    final resp = await http.get(uri, headers: headers).timeout(timeout);

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      if (resp.body.isEmpty) return {};
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
  } catch (_) {}

  return {};
}

/// ---------------------------------------------------------------------------
/// LOGIN API
/// ---------------------------------------------------------------------------
Future<Map<String, dynamic>> login_user(
    String officerId,
    String password,
    ) async {
  return await postJson(
    'login',
    body: {
      'login_id': officerId,
      'password': password,
      'role': 'officer',
    },
  );
}
