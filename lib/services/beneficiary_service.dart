import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:loan2/services/api.dart';
import 'package:loan2/models/beneficiary_loan.dart';

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
}