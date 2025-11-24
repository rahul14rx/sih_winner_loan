import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:loan2/services/api.dart';
import 'package:loan2/models/beneficiary_loan.dart';

class BeneficiaryService {
  // Fetch all loans/processes for a specific user ID
  Future<List<BeneficiaryLoan>> fetchUserLoans(String userId) async {
    try {
      final response = await http.get(Uri.parse('${kBaseUrl}user?id=$userId'));

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(response.body);
        final List<dynamic> data = body['data'];
        return data.map((e) => BeneficiaryLoan.fromJson(e)).toList();
      } else {
        throw Exception('Failed to load user data: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching beneficiary data: $e');
    }
  }

  // Fetch details for a specific loan ID
  Future<BeneficiaryLoan> fetchLoanDetails(String loanId) async {
    try {
      final uri = Uri.parse('${kBaseUrl}loan_details?loan_id=$loanId');
      print("Requesting: $uri"); 
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        print("Response Body: ${response.body}"); // Debug log
        final dynamic body = jsonDecode(response.body);
        
        if (body is Map<String, dynamic>) {
          // Handle wrapper 'loan_details'
          if (body.containsKey('loan_details')) {
            return BeneficiaryLoan.fromJson(body['loan_details']);
          }
          
          if (body.containsKey('data')) {
            if (body['data'] is List && (body['data'] as List).isNotEmpty) {
               return BeneficiaryLoan.fromJson(body['data'][0]);
            } else if (body['data'] is Map<String, dynamic>) {
               return BeneficiaryLoan.fromJson(body['data']);
            }
          }
          return BeneficiaryLoan.fromJson(body);
        } else if (body is List && body.isNotEmpty) {
           return BeneficiaryLoan.fromJson(body[0]);
        }
        
        throw Exception('Unexpected response format');
      } else {
        // Include body in error to help debug (e.g. 404 Not Found)
        throw Exception('Failed to load loan details: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching loan details: $e');
    }
  }
}
