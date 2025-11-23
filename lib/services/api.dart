// lib/services/api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

// Change this to your Flask host (10.0.2.2 for Android emulator, or your local IP)
const String kBaseUrl = 'http://192.168.0.116:5001/'; // MAKE SURE THIS IS CORRECT

Future<Map<String, dynamic>> postJson(
    String path, {
      required Map<String, dynamic> body,
      Map<String, String>? extraHeaders,
      Duration timeout = const Duration(seconds: 15),
    }) async {
  final uri = Uri.parse('$kBaseUrl$path');
  final headers = <String, String>{
    'Content-Type': 'application/json',
    if (extraHeaders != null) ...extraHeaders,
  };

  final resp = await http.post(uri, headers: headers, body: jsonEncode(body)).timeout(timeout);

  if (resp.statusCode >= 200 && resp.statusCode < 300) {
    if (resp.body.isEmpty) return <String, dynamic>{};
    return jsonDecode(resp.body) as Map<String, dynamic>;
  } else {
    String message = 'Server error: ${resp.statusCode}';
    try {
      final data = jsonDecode(resp.body);
      if (data is Map && data['error'] != null) message = data['error'].toString();
    } catch (_) {}
    throw Exception(message);
  }
}