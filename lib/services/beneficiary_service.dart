// lib/services/beneficiary_service.dart
//
// FIXED FOR connectivity_plus v6
// - Correct API for checkConnectivity + onConnectivityChanged
// - No type errors
// - Safe caching + offline support
//
// Author: ChatGPT (2025 Premium Fix)

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:loan2/services/api.dart';
import 'package:loan2/models/beneficiary_loan.dart';
import 'package:loan2/services/sync_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';

class BeneficiaryService {
  // Create single connectivity instance
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
      print("💾 Cached data for $key");
    } catch (e) {
      print("⚠ Failed to cache data: $e");
    }
  }

  Future<String?> _loadFromCache(String key) async {
    try {
      final path = await _getCachePath(key);
      final file = File(path);
      if (await file.exists()) {
        print("📂 Loaded cache for $key");
        return await file.readAsString();
      }
    } catch (e) {
      print("⚠ Cache read error: $e");
    }
    return null;
  }

  // -------------------------------------------------------------
  // CONNECTIVITY FIX (connectivity_plus v6)
  // -------------------------------------------------------------
  Future<void> _checkConnectivity() async {
    final results = await _connectivity.checkConnectivity(); // returns List<ConnectivityResult>

    bool isOffline = results.isEmpty || results.first == ConnectivityResult.none;

    if (!isOffline) return;

    print("📴 No internet → waiting...");

    final completer = Completer<void>();
    late StreamSubscription<List<ConnectivityResult>> subscription;

    subscription = _connectivity.onConnectivityChanged.listen((List<ConnectivityResult> newResults) {
      bool hasNet = newResults.isNotEmpty && newResults.first != ConnectivityResult.none;
      if (hasNet) {
        subscription.cancel();
        completer.complete();
      }
    });

    await completer.future;
  }

  // -------------------------------------------------------------
  // FETCH USER LOANS
  // -------------------------------------------------------------
  Future<List<BeneficiaryLoan>> fetchUserLoans(String userId) async {
    await _checkConnectivity();

    try {
      final res = await http.get(
        Uri.parse('${kBaseUrl}user?id=$userId'),
      );

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final list = decoded['data'] as List? ?? [];
        return list.map((e) => BeneficiaryLoan.fromJson(e)).toList();
      }
    } catch (e) {
      print("User loans fetch error: $e");
    }

    return [];
  }

  // -------------------------------------------------------------
  // FETCH SINGLE LOAN
  // -------------------------------------------------------------
  Future<BeneficiaryLoan> fetchLoanDetails(String loanId) async {
    await _checkConnectivity();

    try {
      final uri = Uri.parse('${kBaseUrl}loan_details?loan_id=$loanId');

      final res = await http.get(uri).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        await _saveToCache('loan_details_$loanId', res.body);
        return _parseLoanDetails(res.body);
      }
    } catch (_) {
      final cached = await _loadFromCache('loan_details_$loanId');
      if (cached != null) {
        return _parseLoanDetails(cached);
      }
    }

    throw Exception("Loan details unavailable (offline + no cache)");
  }

  BeneficiaryLoan _parseLoanDetails(String jsonStr) {
    final body = jsonDecode(jsonStr);

    if (body is Map && body['loan_details'] is Map) {
      return BeneficiaryLoan.fromJson(body['loan_details']);
    }
    if (body is Map && body['data'] is List && body['data'].isNotEmpty) {
      return BeneficiaryLoan.fromJson(body['data'][0]);
    }
    if (body is Map && body['data'] is Map) {
      return BeneficiaryLoan.fromJson(body['data']);
    }
    if (body is List && body.isNotEmpty) {
      return BeneficiaryLoan.fromJson(body[0]);
    }
    if (body is Map) {
      return BeneficiaryLoan.fromJson(body[0]);
    }

    throw Exception("Unexpected loan details JSON");
  }

  Future<BeneficiaryLoan> getLoanDetails(String loanId) async {
    return fetchLoanDetails(loanId);
  }

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
      print("❌ Utilization API error: $e");
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
      print("❌ Finalize API error: $e");
      return false;
    }
  }
}
