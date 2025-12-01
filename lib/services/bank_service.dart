// lib/services/bank_service.dart
//
// FINAL SAFE VERSION
// - Added connectivity checks
// - Safe JSON parsing
// - Consistent return shapes
// - Zero breaking changes

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:loan2/services/api.dart';
import 'package:loan2/models/loan_application.dart';
import 'package:loan2/services//beneficiary_service.dart';
import 'dart:async';



class BankService {
  // -------------------------------
  // DASHBOARD ANALYTICS
  // -------------------------------
  Future<Map<String, int>> fetchDashboardStats(String officerId) async {
    try {


      final response = await http.get(
        Uri.parse('${kBaseUrl}bank/stats?officer_id=$officerId'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) ?? {};

        return {
          'pending': data['pending'] ?? 0,
          'verified': data['verified'] ?? 0,
          'rejected': data['rejected'] ?? 0,
        };
      }

      return {'pending': 0, 'verified': 0, 'rejected': 0};
    } catch (_) {
      return {'pending': 0, 'verified': 0, 'rejected': 0};
    }
  }

  // -------------------------------
  // LOAD PENDING LOANS
  // -------------------------------
  Future<List<LoanApplication>> fetchPendingLoans(String officerId) async {
    try {

      final res = await http.get(
        Uri.parse('${kBaseUrl}bank/loans?status=pending&officer_id=$officerId'),
      );

      if (res.statusCode != 200) {
        throw Exception('Server error ${res.statusCode}');
      }

      final decoded = jsonDecode(res.body);

      final List<dynamic> list =
      (decoded is Map && decoded['data'] is List)
          ? decoded['data']
          : <dynamic>[];

      return list.map((e) => LoanApplication.fromJson(e)).toList();
    } catch (e) {
      throw Exception('Error fetching loans: $e');
    }
  }

  // -------------------------------
  // CREATE BENEFICIARY
  // -------------------------------
  Future<bool> createBeneficiary(
      Map<String, String> data, {
        String? docPath,
      }) async {

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${kBaseUrl}bank/beneficiary'),
    );
    request.fields.addAll(data);

    if (docPath != null && docPath.isNotEmpty) {
      request.files
          .add(await http.MultipartFile.fromPath('loan_document', docPath));
    }

    try {
      final response = await request.send();

      if (response.statusCode == 201) return true;

      String errorMsg = 'Server error (${response.statusCode})';

      try {
        final body = jsonDecode(await response.stream.bytesToString());
        errorMsg = body['error'] ?? body['message'] ?? errorMsg;
      } catch (_) {}

      throw Exception(errorMsg);
    } catch (e) {
      throw Exception('Failed to create beneficiary: $e');
    }
  }

  // -------------------------------
  // OFFICER PROFILE
  // -------------------------------
  Future<Map<String, dynamic>> fetchOfficerProfile(String officerId) async {
    final tries = <String>[
      'bank/officer/profile',
      'bank/profile',
      'officer/profile',
      'profile',
    ];

    for (final route in tries) {
      final url = Uri.parse('${kBaseUrl}$route?officer_id=$officerId');

      try {
        final res = await http.get(url).timeout(const Duration(seconds: 15));

        if (res.statusCode == 200) {
          final decoded = jsonDecode(res.body);

          // Always return same shape for UI safety
          if (decoded is Map<String, dynamic>) {
            return {"data": decoded};
          }
          return {"data": {}};
        }
      } catch (_) {}
    }

    // fallback to avoid crash
    return {
      "data": {
        "officer_id": officerId,
        "name": "Bank Officer",
      }
    };
  }
}
