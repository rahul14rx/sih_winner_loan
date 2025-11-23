import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:loan2/services/api.dart'; // Import your base API config
import 'package:loan2/models/loan_application.dart';

class BankService {
  // --- DASHBOARD ANALYTICS ---

  // fetchDashboardData: Gets summary counts (Pending, Verified, Rejected)
  Future<Map<String, int>> fetchDashboardStats() async {
    try {
      final response = await http.get(Uri.parse('${kBaseUrl}bank/stats'));

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
  Future<List<LoanApplication>> fetchPendingLoans() async {
    try {
      // Status 'pending' maps to 'not verified' on the backend
      final response = await http.get(Uri.parse('${kBaseUrl}bank/loans?status=pending'));

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
  Future<bool> createBeneficiary(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('${kBaseUrl}bank/beneficiary'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );

      if (response.statusCode == 201) {
        return true; // Success
      } else {
        // Extract error message from server response if available
        String errorMsg = 'Unknown error';
        try {
          final body = jsonDecode(response.body);
          errorMsg = body['error'] ?? body['message'] ?? 'Server error';
        } catch (_) {}
        throw Exception(errorMsg);
      }
    } catch (e) {
      throw Exception('Failed to create beneficiary: $e');
    }
  }
}