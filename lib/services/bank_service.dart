import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:loan2/services/api.dart'; // Import your base API config
import 'package:loan2/models/loan_application.dart';

class BankService {
  // --- DASHBOARD ANALYTICS ---

  // fetchDashboardData: Gets summary counts (Pending, Verified, Rejected)
  Future<Map<String, int>> fetchDashboardStats(String officerId) async {
    try {
      final response = await http.get(Uri.parse('${kBaseUrl}bank/stats?officer_id=$officerId'));

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
    } catch (e) {
      // Return zeros on error/offline for now to prevent crash
      return {'pending': 0, 'verified': 0, 'rejected': 0};
    }
  }

  // --- LOAN MANAGEMENT ---

  // fetchPendingLoans: Gets the list of loans needing verification
  Future<List<LoanApplication>> fetchPendingLoans(String officerId) async {
    try {
      // Status 'pending' maps to 'not verified' on the backend
      final response = await http.get(Uri.parse('${kBaseUrl}bank/loans?status=pending&officer_id=$officerId'));

      if (response.statusCode == 200) {
        final List<dynamic> body = jsonDecode(response.body)['data'];
        return body.map((dynamic item) => LoanApplication.fromJson(item)).toList();
      } else {
        throw Exception('Failed to load loans: Server error ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching loans: $e');
    }
  }

  // --- BENEFICIARY CREATION ---

  // createBeneficiary: Sends new beneficiary data to the server
  Future<bool> createBeneficiary(Map<String, String> data, {String? docPath}) async {
    var request = http.MultipartRequest('POST', Uri.parse('${kBaseUrl}bank/beneficiary'));
    request.fields.addAll(data);

    if (docPath != null && docPath.isNotEmpty) {
      try {
        request.files.add(await http.MultipartFile.fromPath('loan_document', docPath));
      } catch (e) {
        throw Exception('Error attaching document: $e');
      }
    }

    try {
      final response = await request.send();

      if (response.statusCode == 201) {
        return true; // Success
      } else {
        String errorMsg = 'Unknown error';
        try {
          final responseBody = await response.stream.bytesToString();
          final body = jsonDecode(responseBody);
          errorMsg = body['error'] ?? body['message'] ?? 'Server error (${response.statusCode})';
        } catch (_) {
          errorMsg = 'Server error (${response.statusCode})';
        }
        throw Exception(errorMsg);
      }
    } catch (e) {
      throw Exception('Failed to create beneficiary: $e');
    }
  }
}