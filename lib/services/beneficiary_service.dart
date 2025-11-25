import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart'; // For Caching
import 'package:loan2/services/api.dart';
import 'package:loan2/models/beneficiary_loan.dart';

class BeneficiaryService {
  
  // --- Caching Helpers ---
  Future<String> _getCachePath(String key) async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/cache_$key.json';
  }

  Future<void> _saveToCache(String key, String content) async {
    try {
      final path = await _getCachePath(key);
      await File(path).writeAsString(content);
      print("💾 Cached data for $key");
    } catch (e) {
      print("⚠️ Failed to cache data: $e");
    }
  }

  Future<String?> _loadFromCache(String key) async {
    try {
      final path = await _getCachePath(key);
      final file = File(path);
      if (await file.exists()) {
        print("📂 Loaded data from cache for $key");
        return await file.readAsString();
      }
    } catch (e) {
      print("⚠️ Failed to load cache: $e");
    }
    return null;
  }

  // Fetch all loans/processes for a specific user ID (e.g., Phone number)
  Future<List<BeneficiaryLoan>> fetchUserLoans(String userId) async {
    try {
      final response = await http.get(Uri.parse('${kBaseUrl}user?id=$userId'));

      if (response.statusCode == 200) {
        // Save to cache on success
        await _saveToCache('user_loans_$userId', response.body);
        
        final Map<String, dynamic> body = jsonDecode(response.body);
        final List<dynamic> data = body['data'];
        return data.map((e) => BeneficiaryLoan.fromJson(e)).toList();
      } else {
        throw Exception('Failed to load data');
      }
    } catch (e) {
      print("🌐 Network error fetching user loans. Trying cache...");
      // Try loading from cache
      final cachedJson = await _loadFromCache('user_loans_$userId');
      if (cachedJson != null) {
         final Map<String, dynamic> body = jsonDecode(cachedJson);
         final List<dynamic> data = body['data'];
         return data.map((e) => BeneficiaryLoan.fromJson(e)).toList();
      }
      throw Exception('Error fetching beneficiary data (Offline & No Cache): $e');
    }
  }

  // Fetch details for a specific loan ID to get dynamic fields (Name, Amount, Scheme)
  Future<BeneficiaryLoan> fetchLoanDetails(String loanId) async {
    try {
      final uri = Uri.parse('${kBaseUrl}loan_details?loan_id=$loanId');
      print("Requesting: $uri"); 
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        // Save to cache on success
        await _saveToCache('loan_details_$loanId', response.body);
        print("Response Body: ${response.body}");
        
        return _parseLoanDetails(response.body);
      } else {
        throw Exception('Failed to load loan details: ${response.statusCode}');
      }
    } catch (e) {
      print("🌐 Network error fetching loan details. Trying cache...");
      // Try loading from cache
      final cachedJson = await _loadFromCache('loan_details_$loanId');
      if (cachedJson != null) {
        return _parseLoanDetails(cachedJson);
      }
      throw Exception('Error fetching loan details (Offline & No Cache): $e');
    }
  }

  // Helper to parse the JSON logic (Shared between online and offline)
  BeneficiaryLoan _parseLoanDetails(String jsonStr) {
    final dynamic body = jsonDecode(jsonStr);
        
    if (body is Map<String, dynamic>) {
      // Handle wrapper 'loan_details' from schema
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
  }
}
