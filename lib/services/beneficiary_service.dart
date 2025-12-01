// lib/services/beneficiary_service.dart
//
// Merged & Safe Version
// - Keeps offline cache for BOTH user loans and loan details
// - Robust connectivity handling (works across connectivity_plus versions)
// - Defensive JSON parsing (no Map[0] bug)
// - Includes new APIs: saveStageUtilization, finalizeVerification
//
// Author: ChatGPT (2025)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'package:loan2/models/beneficiary_loan.dart';
import 'package:loan2/services/api.dart';

class BeneficiaryService {
  // Single connectivity instance
  static final Connectivity _connectivity = Connectivity();

  // -------------------------------------------------------------
  // CACHE HELPERS
  // -------------------------------------------------------------
  Future<String> _getCachePath(String key) async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/cache_$key.json';
  }

  Future<void> _saveToCache(String key, String content) async {
    try {
      final path = await _getCachePath(key);
      await File(path).writeAsString(content);
      // debug
      // print("💾 Cached data for $key");
    } catch (e) {
      // print("⚠️ Failed to cache data: $e");
    }
  }

  Future<String?> _loadFromCache(String key) async {
    try {
      final path = await _getCachePath(key);
      final file = File(path);
      if (await file.exists()) {
        // print("📂 Loaded data from cache for $key");
        return await file.readAsString();
      }
    } catch (e) {
      // print("⚠️ Failed to load cache: $e");
    }
    return null;
  }

  // -------------------------------------------------------------
  // CONNECTIVITY (robust across connectivity_plus versions)
  // -------------------------------------------------------------
  Future<void> _checkConnectivity() async {
    final initial = await _connectivity.checkConnectivity();

    // Support both: ConnectivityResult and List<ConnectivityResult>
    bool offline = false;
    if (initial is ConnectivityResult) {
      offline = initial == ConnectivityResult.none;
    } else if (initial is List<ConnectivityResult>) {
      offline = initial.every((e) => e == ConnectivityResult.none);
    }

    if (!offline) return;

    final completer = Completer<void>();

    // Cast to dynamic Stream so we can accept either type at runtime.
    final Stream<dynamic> stream =
    (_connectivity.onConnectivityChanged as Stream);

    late StreamSubscription sub;
    sub = stream.listen((event) {
      bool online = false;
      if (event is ConnectivityResult) {
        online = event != ConnectivityResult.none;
      } else if (event is List<ConnectivityResult>) {
        online = event.any((e) => e != ConnectivityResult.none);
      } else {
        online = true;
      }
      if (online && !completer.isCompleted) {
        sub.cancel();
        completer.complete();
      }
    });

    await completer.future;
  }

  // -------------------------------------------------------------
  // FETCH USER LOANS (with cache fallback)
  // -------------------------------------------------------------
  Future<List<BeneficiaryLoan>> fetchUserLoans(String userId) async {
    try {
      await _checkConnectivity();
      final uri = Uri.parse('${kBaseUrl}user?id=$userId');
      final res = await http.get(uri).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        // Save to cache on success
        await _saveToCache('user_loans_$userId', res.body);

        final decoded = jsonDecode(res.body);
        final list = (decoded is Map && decoded['data'] is List)
            ? decoded['data'] as List
            : <dynamic>[];

        return list.map((e) => BeneficiaryLoan.fromJson(e)).toList();
      } else {
        // Server error → fall back to cache
        final cached = await _loadFromCache('user_loans_$userId');
        if (cached != null) {
          final decoded = jsonDecode(cached);
          final list = (decoded is Map && decoded['data'] is List)
              ? decoded['data'] as List
              : <dynamic>[];
          return list.map((e) => BeneficiaryLoan.fromJson(e)).toList();
        }
        throw Exception('Failed to load data: ${res.statusCode}');
      }
    } catch (_) {
      // Network error → try cache
      final cached = await _loadFromCache('user_loans_$userId');
      if (cached != null) {
        final decoded = jsonDecode(cached);
        final list = (decoded is Map && decoded['data'] is List)
            ? decoded['data'] as List
            : <dynamic>[];
        return list.map((e) => BeneficiaryLoan.fromJson(e)).toList();
      }
      // No cache
      rethrow;
    }
  }

  // -------------------------------------------------------------
  // FETCH SINGLE LOAN (with cache fallback)
  // -------------------------------------------------------------
  Future<BeneficiaryLoan> fetchLoanDetails(String loanId) async {
    try {
      await _checkConnectivity();

      final uri = Uri.parse('${kBaseUrl}loan_details?loan_id=$loanId');
      final res = await http.get(uri).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        await _saveToCache('loan_details_$loanId', res.body);
        return _parseLoanDetails(res.body);
      } else {
        // Server error → fall back to cache
        final cached = await _loadFromCache('loan_details_$loanId');
        if (cached != null) return _parseLoanDetails(cached);
        throw Exception('Failed to load loan details: ${res.statusCode}');
      }
    } catch (_) {
      // Network error → try cache
      final cached = await _loadFromCache('loan_details_$loanId');
      if (cached != null) return _parseLoanDetails(cached);
      throw Exception('Error fetching loan details (Offline & No Cache)');
    }
  }

  BeneficiaryLoan _parseLoanDetails(String jsonStr) {
    final dynamic body = jsonDecode(jsonStr);

    if (body is Map<String, dynamic>) {
      // schema: { "loan_details": {...} }
      if (body['loan_details'] is Map<String, dynamic>) {
        return BeneficiaryLoan.fromJson(body['loan_details']);
      }

      // schema: { "data": [ {...} ] }
      if (body['data'] is List && (body['data'] as List).isNotEmpty) {
        return BeneficiaryLoan.fromJson((body['data'] as List).first);
      }

      // schema: { "data": {...} }
      if (body['data'] is Map<String, dynamic>) {
        return BeneficiaryLoan.fromJson(body['data'] as Map<String, dynamic>);
      }

      // schema: direct object
      return BeneficiaryLoan.fromJson(body);
    }

    if (body is List && body.isNotEmpty) {
      return BeneficiaryLoan.fromJson(body.first);
    }

    throw Exception('Unexpected response format for loan details');
  }

  // Backward-compatible alias
  Future<BeneficiaryLoan> getLoanDetails(String loanId) => fetchLoanDetails(loanId);

  // -------------------------------------------------------------
  // SAVE UTILIZATION
  // -------------------------------------------------------------
  Future<bool> saveStageUtilization(
      String loanId,
      String userId,
      int processIntId,
      double amount,
      ) async {
    await _checkConnectivity();

    try {
      final uri = Uri.parse('${kBaseUrl}save_utilization');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'loan_id': loanId,
          'user_id': userId,
          'process_int_id': processIntId,
          'utilization_amount': amount,
        }),
      );
      return res.statusCode == 200;
    } catch (e) {
      // print("❌ Utilization API error: $e");
      return false;
    }
  }

  // -------------------------------------------------------------
  // FINALIZE
  // -------------------------------------------------------------
  Future<bool> finalizeVerification(String loanId) async {
    await _checkConnectivity();

    try {
      final uri = Uri.parse('${kBaseUrl}finalize_verification');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'loan_id': loanId}),
      );
      return res.statusCode == 200;
    } catch (e) {
      // print("❌ Finalize API error: $e");
      return false;
    }
  }
}
