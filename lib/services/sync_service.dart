import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'package:loan2/services/api.dart';
import 'package:loan2/services/database_helper.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class SyncService {
  static final _syncController = StreamController<bool>.broadcast();
  static final _onlineStatusController = StreamController<bool>.broadcast();
  static final _itemSyncedController = StreamController<Map<String, String>>.broadcast();

  static Stream<bool> get onSync => _syncController.stream;
  static Stream<bool> get onOnlineStatusChanged => _onlineStatusController.stream;
  static Stream<Map<String, String>> get onItemSynced => _itemSyncedController.stream;

  static StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  static bool _isOnline = false;

  static void startListener() {
    print("🔄 Sync Listener Started...");
    _connectivitySubscription?.cancel();

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) async {
      bool isDeviceConnected = !results.contains(ConnectivityResult.none);
      bool canReachServer = isDeviceConnected ? await realInternetCheck() : false;

      if (canReachServer != _isOnline) {
        _isOnline = canReachServer;
        _onlineStatusController.add(_isOnline);
        print("🌐 Connection Status Changed: ${_isOnline ? "Online" : "Offline"}");

        if (_isOnline) {
          print("🚀 Now online, attempting to sync...");
          await syncAll();
        }
      }
    });
    _initialCheck();
  }

  static Future<void> _initialCheck() async {
    _isOnline = await realInternetCheck();
    _onlineStatusController.add(_isOnline);
    if (_isOnline) {
      await syncAll();
    }
  }

  static Future<bool> realInternetCheck() async {
    try {
      final response = await http.get(Uri.parse(kBaseUrl)).timeout(const Duration(seconds: 3));
      return response.statusCode >= 200 && response.statusCode < 500;
    } catch (e) {
      return false;
    }
  }

  static Future<void> syncAll() async {
    await syncBeneficiaries();
    await syncImages();
    await syncOfficerActions(); // New Sync Step
  }

  static Future<void> syncImages() async {
    List<Map<String, dynamic>> data = await DatabaseHelper.instance.getQueuedForUpload();
    if (data.isEmpty) return;
    
    print("📂 Found ${data.length} verification items to sync...");
    bool wasSynced = false;

    for (var row in data) {
      final dbId = row[DatabaseHelper.colId] as int?;
      final loanId = row[DatabaseHelper.colLoanId] as String?;
      final processId = row[DatabaseHelper.colProcessId] as String?;
      final userId = row[DatabaseHelper.colUserId] as String?;
      final filePath = row[DatabaseHelper.colFilePath] as String?;

      if (dbId == null || loanId == null || processId == null || filePath == null || userId == null) continue;

      String ext = p.extension(filePath).toLowerCase();
      if (ext.isEmpty) ext = '.jpg';

      print("⬆️ Syncing Verification ($ext): Loan $loanId, Step $processId");

      var request = http.MultipartRequest("POST", Uri.parse('${kBaseUrl}upload'));
      
      try {
        // No Decryption logic as requested. Use raw file directly.
        String cleanFilename = "sync_${loanId}_$processId$ext";
        request.files.add(await http.MultipartFile.fromPath(
             'file',
             filePath,
             filename: cleanFilename
        ));

        request.fields["process_id"] = processId;
        request.fields["loan_id"] = loanId;
        request.fields["user_id"] = userId;

        var response = await request.send();
        if (response.statusCode == 200) {
          print("✅ Sync Success for Verification ID $dbId");
          await DatabaseHelper.instance.deleteImage(dbId, deleteFile: true);
          wasSynced = true;
          _itemSyncedController.add({'loanId': loanId, 'processId': processId});
        } else {
          print("❌ Server Error (${response.statusCode})");
        }
      } catch (e) {
        print("❌ Error during sync: $e");
      }
    }

    if (wasSynced) _syncController.add(true);
  }

  static Future<void> syncBeneficiaries() async {
    List<Map<String, dynamic>> data = await DatabaseHelper.instance.getPendingBeneficiaries();
    if (data.isEmpty) return;

    bool wasSynced = false;

    for (var row in data) {
      final dbId = row[DatabaseHelper.colId] as int?;

      final officerId = row[DatabaseHelper.colOfficerId] as String?;
      final name = row[DatabaseHelper.colName] as String?;
      final phone = row[DatabaseHelper.colPhone] as String?;
      final amount = row[DatabaseHelper.colAmount] as String?;
      final loanId = row[DatabaseHelper.colLoanId] as String?;
      final scheme = row[DatabaseHelper.colScheme] as String?;
      final loanType = row[DatabaseHelper.colLoanType] as String?;
      final docPath = row[DatabaseHelper.colDocPath] as String?;
      final address = row[DatabaseHelper.colAddress] as String?;
      final asset = row[DatabaseHelper.colAsset] as String?;
      final creationId = row[DatabaseHelper.colCreationId] as String?;

      // ✅ NEW: dynamic fields bundle (JSON)
      final extraJson = row[DatabaseHelper.colExtraJson] as String?;
      Map<String, dynamic> extra = {};
      if (extraJson != null && extraJson.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(extraJson);
          if (decoded is Map) {
            extra = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {}
      }

      if (dbId == null || name == null || loanId == null) continue;

      var request = http.MultipartRequest('POST', Uri.parse('${kBaseUrl}bank/beneficiary'));
      request.fields['officer_id'] = officerId ?? "";
      request.fields['name'] = name;
      request.fields['phone'] = phone ?? "";
      request.fields['amount'] = amount ?? "";
      request.fields['loan_id'] = loanId;
      request.fields['scheme'] = scheme ?? "";
      request.fields['loan_type'] = loanType ?? "";
      if (creationId != null) request.fields['creation_id'] = creationId;

      // keep old fields so current backend still accepts it
      request.fields['beneficiary_address'] = address ?? "";
      request.fields['asset_purchased'] = asset ?? "";

      // ✅ NEW: merge extra dynamic fields into request.fields
      extra.forEach((k, v) {
        if (v == null) return;
        final key = k.toString().trim();
        final val = v.toString().trim();
        if (key.isEmpty || val.isEmpty) return;
        request.fields[key] = val; // extra can override if needed
      });

      if (docPath != null && docPath.isNotEmpty) {
        try {
          request.files.add(await http.MultipartFile.fromPath('loan_agreement', docPath));
        } catch (e) {
          print("⚠️ Could not attach file for sync: $e");
        }
      }

      try {
        var response = await request.send();
        if (response.statusCode == 201) {
          await DatabaseHelper.instance.deletePendingBeneficiary(dbId);
          wasSynced = true;
        } else {
           final respStr = await response.stream.bytesToString();
          // Handle conflict (duplicate)
          if (response.statusCode == 409) {
            print("🗑️ Beneficiary already exists on server. Deleting local copy.");
            await DatabaseHelper.instance.deletePendingBeneficiary(dbId);
          } else {
            print("❌ Server Error syncing beneficiary: ${response.statusCode} - $respStr");
          }
        }
      } catch (e) {
        print("❌ Network Error syncing beneficiary: $e");
      }
    }

    if (wasSynced) _syncController.add(true);
  }


  // --- New: Sync Officer Actions ---
  static Future<void> syncOfficerActions() async {
    final actions = await DatabaseHelper.instance.getOfficerActions();
    if (actions.isEmpty) return;

    print("👮 Syncing ${actions.length} officer verification actions...");

    for (var row in actions) {
      final dbId = row[DatabaseHelper.colId] as int;
      final loanId = row[DatabaseHelper.colLoanId] as String;
      final processId = row[DatabaseHelper.colProcessId] as String;
      final actionType = row[DatabaseHelper.colActionType] as String;

      try {
        final response = await http.post(
          Uri.parse('${kBaseUrl}bank/verify'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'loan_id': loanId,
            'process_id': processId,
            'status': actionType
          }),
        );

        if (response.statusCode == 200) {
          print("✅ Officer Action Synced: Loan $loanId Step $processId -> $actionType");
          await DatabaseHelper.instance.deleteOfficerAction(dbId);
        } else {
          print("❌ Failed to sync action: Server returned ${response.statusCode}");
        }
      } catch (e) {
        print("❌ Error syncing officer action: $e");
      }
    }
  }

  static void dispose() {
    _syncController.close();
    _onlineStatusController.close();
    _itemSyncedController.close();
    _connectivitySubscription?.cancel();
  }
}
