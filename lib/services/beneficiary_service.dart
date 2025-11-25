import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:loan2/models/beneficiary_loan.dart';
import 'package:loan2/services/api.dart';

class BeneficiaryService {
  // Fetch all loans/processes for a specific user ID (e.g., Phone number)
  Future<List<BeneficiaryLoan>> fetchUserLoans(String userId) async {
    try {
      final response = await http.get(Uri.parse('${kBaseUrl}user?id=$userId'));

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(response.body);
        final List<dynamic> data = body['data'];
        return data.map((e) => BeneficiaryLoan.fromJson(e)).toList();
      } else {
        throw Exception('Failed to load data');
      }
    } catch (e) {
      // In a real app, you'd return cached data here if offline
      throw Exception('Error fetching beneficiary data: $e');
    }
  }

  // Fetch the latest details for a single loan
  Future<BeneficiaryLoan> fetchLoanDetails(String loanId) async {
    try {
      final data = await getJson('loan_details?loan_id=$loanId');
      // The API returns a list with one item, so we take the first.
      return BeneficiaryLoan.fromJson(data['data'][0]);
    } catch (e) {
      throw Exception('Error fetching loan details: $e');
    }
  }
}
