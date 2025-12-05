// lib/services/api.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

// Change this to your Flask host - REMOVED trailing slash to prevent double slashes
const String kBaseUrl = 'http://10.10.11.253:5000 /';

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
      return <String, dynamic>{};
    }
  } catch(e) {
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
      return <String, dynamic>{};
    }
  } catch(e) {
    return <String, dynamic>{};
  }
}

Future<Map<String, dynamic>> login_user(String officerId, String password) async {
  return await postJson(
    '/login',
    body: {
      'login_id': officerId,
      'password': password,
      'role': 'officer',
    },
  );
}

Future<bool> uploadProcessMedia({
  required String loanId,
  required String processId,
  required String userId,
  required File file,
  String? latitude,
  String? longitude,
}) async {
  await _checkConnectivity();
  final uri = Uri.parse('$kBaseUrl/update_process_media');

  final request = http.MultipartRequest('POST', uri);
  request.fields['loan_id'] = loanId;
  request.fields['process_id'] = processId;
  request.fields['user_id'] = userId;
  if (latitude != null) request.fields['latitude'] = latitude;
  if (longitude != null) request.fields['longitude'] = longitude;

  final stream = http.ByteStream(file.openRead());
  final length = await file.length();

  final multipartFile = http.MultipartFile(
    'file',
    stream,
    length,
    filename: path.basename(file.path),
  );

  request.files.add(multipartFile);

  try {
    final response = await request.send();
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return true;
    } else {
      return false;
    }
  } catch (e) {
    return false;
  }
}

// Added function to create a new beneficiary
Future<bool> createBeneficiary({
  required Map<String, String> data,
  File? loanAgreementFile,
}) async {
  await _checkConnectivity();
  final uri = Uri.parse('$kBaseUrl/create_beneficiary');

  final request = http.MultipartRequest('POST', uri);

  // Add all text fields from the data map
  request.fields.addAll(data);

  // Add the file if it exists
  if (loanAgreementFile != null) {
    final stream = http.ByteStream(loanAgreementFile.openRead());
    final length = await loanAgreementFile.length();
    final multipartFile = http.MultipartFile(
      'loan_agreement', // Key must match the backend expectation
      stream,
      length,
      filename: path.basename(loanAgreementFile.path),
    );
    request.files.add(multipartFile);
  }

  try {
    final response = await request.send();
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return true;
    } else {
      return false;
    }
  } catch (e) {
    print('Error in createBeneficiary: $e');
    return false;
  }
}
