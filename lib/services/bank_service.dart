import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:loan2/services/api.dart';
import 'package:loan2/models/loan_application.dart';

class BankService {
  // --- DASHBOARD ANALYTICS ---
  Future<Map<String, int>> fetchDashboardStats(String officerId) async {
    try {
      final response = await http.get(
        Uri.parse('${kBaseUrl}bank/stats?officer_id=$officerId'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'pending': data['pending'] ?? 0,
          'verified': data['verified'] ?? 0,
          'rejected': data['rejected'] ?? 0,
        };
      } else {
        throw Exception('Failed to load stats');
      }
    } catch (_) {
      return {'pending': 0, 'verified': 0, 'rejected': 0};
    }
  }

  // --- LOAN MANAGEMENT ---
  Future<List<LoanApplication>> fetchPendingLoans(String officerId) async {
    try {
      final response = await http.get(
        Uri.parse('${kBaseUrl}bank/loans?status=pending&officer_id=$officerId'),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final List<dynamic> body = (decoded is Map && decoded['data'] is List)
            ? decoded['data']
            : <dynamic>[];
        return body.map((e) => LoanApplication.fromJson(e)).toList();
      } else {
        throw Exception('Failed to load loans: Server error ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching loans: $e');
    }
  }

  // --- BENEFICIARY CREATION ---
  Future<bool> createBeneficiary(Map<String, String> data, {String? docPath}) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${kBaseUrl}bank/beneficiary'),
    );
    request.fields.addAll(data);

    if (docPath != null && docPath.isNotEmpty) {
      request.files.add(await http.MultipartFile.fromPath('loan_document', docPath));
    }

    try {
      final response = await request.send();

      if (response.statusCode == 201) return true;

      String errorMsg = 'Server error (${response.statusCode})';
      try {
        final responseBody = await response.stream.bytesToString();
        final body = jsonDecode(responseBody);
        errorMsg = body['error'] ?? body['message'] ?? errorMsg;
      } catch (_) {}
      throw Exception(errorMsg);
    } catch (e) {
      throw Exception('Failed to create beneficiary: $e');
    }
  }

  // --- OFFICER PROFILE (for ProfileSettingsPage) ---
  Future<Map<String, dynamic>> fetchOfficerProfile(String officerId) async {
    final candidates = <Uri>[
      Uri.parse('${kBaseUrl}bank/officer/profile?officer_id=$officerId'),
      Uri.parse('${kBaseUrl}bank/profile?officer_id=$officerId'),
      Uri.parse('${kBaseUrl}officer/profile?officer_id=$officerId'),
      Uri.parse('${kBaseUrl}profile?officer_id=$officerId'),
    ];

    for (final u in candidates) {
      try {
        final res = await http.get(u).timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body);
          if (body is Map<String, dynamic>) return body;
          return {"data": body};
        }
      } catch (_) {}
    }

    // Fallback to prevent UI crash if backend route differs
    return {
      "data": {
        "officer_id": officerId,
        "name": "Bank Officer",
      }
    };
  }
}
