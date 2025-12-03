// lib/services/api.dart
import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

// Change this to your Flask host
const String kBaseUrl = 'http://192.168.0.2:5001/';

final Connectivity _connectivity = Connectivity();

Future<void> _checkConnectivity() async {
  var connectivityResult = await _connectivity.checkConnectivity();
  if (connectivityResult.contains(ConnectivityResult.none)) {
    final completer = Completer<void>();
    late StreamSubscription<List<ConnectivityResult>> subscription;

    subscription = _connectivity.onConnectivityChanged.listen((List<ConnectivityResult> result) {
      if (!result.contains(ConnectivityResult.none)) {
        subscription.cancel();
        completer.complete();
      }
    });

    await completer.future;
  }
}

Future<Map<String, dynamic>> postJson(
    String path, {
      required Map<String, dynamic> body,
      Map<String, String>? extraHeaders,
      Duration timeout = const Duration(seconds: 15),
    }) async {
  await _checkConnectivity();
  final uri = Uri.parse('$kBaseUrl$path');
  final headers = <String, String>{
    'Content-Type': 'application/json',
    if (extraHeaders != null) ...extraHeaders,
  };

  try {
    final resp = await http.post(uri, headers: headers, body: jsonEncode(body)).timeout(timeout);

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      if (resp.body.isEmpty) return <String, dynamic>{};
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } else {
      // Server returned an error, return empty map to avoid UI exception
      return <String, dynamic>{};
    }
  } catch(e) {
    // Connection failed, return empty map to avoid UI exception
    return <String, dynamic>{};
  }
}

Future<Map<String, dynamic>> getJson(
    String path, {
      Map<String, String>? extraHeaders,
      Duration timeout = const Duration(seconds: 15),
    }) async {
  await _checkConnectivity();
  final uri = Uri.parse('$kBaseUrl$path');
  final headers = <String, String>{
    'Content-Type': 'application/json',
    if (extraHeaders != null) ...extraHeaders,
  };

  try {
    final resp = await http.get(uri, headers: headers).timeout(timeout);

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      if (resp.body.isEmpty) return <String, dynamic>{};
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } else {
      // Server returned an error, return empty map to avoid UI exception
      return <String, dynamic>{};
    }
  } catch(e) {
    // Connection failed, return empty map to avoid UI exception
    return <String, dynamic>{};
  }
}

Future<Map<String, dynamic>> login_user(String officerId, String password) async {
  return await postJson(
    'login',
    body: {
      'login_id': officerId,
      'password': password,
      'role': 'officer',
    },
  );
}
