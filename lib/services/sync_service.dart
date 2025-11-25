import 'dart:async';
import 'dart:io'; // For File checks if needed
import 'package:path/path.dart' as p; // Import path package for extension
import 'package:http/http.dart' as http;
import 'package:loan2/services/api.dart';
import 'package:loan2/services/database_helper.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:loan2/services/encryption_service.dart'; // Added

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
    _connectivitySubscription?.cancel(); // Cancel any previous listener

    // Listen for connectivity changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) async {
      bool isDeviceConnected = !results.contains(ConnectivityResult.none);

      // Perform a real internet check to confirm server reachability.
      bool canReachServer = isDeviceConnected ? await realInternetCheck() : false;

      // Check if the online status has actually changed to avoid redundant calls.
      if (canReachServer != _isOnline) {
        _isOnline = canReachServer;
        _onlineStatusController.add(_isOnline);
        print("🌐 Connection Status Changed: ${_isOnline ? "Online" : "Offline"}");

        // If we just came online, trigger the sync.
        if (_isOnline) {
          print("🚀 Now online, attempting to sync...");
          await syncAll();
        }
      }
    });

    // Also perform an initial check when the app starts.
    _initialCheck();
  }

  static Future<void> _initialCheck() async {
    _isOnline = await realInternetCheck();
    _onlineStatusController.add(_isOnline);
    print("🌟 Initial Connection Status: ${_isOnline ? "Online" : "Offline"}");
    if (_isOnline) {
      await syncAll();
    }
  }

  static Future<bool> realInternetCheck() async {
    try {
      final response = await http.head(Uri.parse(kBaseUrl)).timeout(const Duration(seconds: 3));
      return response.statusCode >= 200 && response.statusCode < 500;
    } catch (e) {
      return false;
    }
  }

  static Future<void> syncAll() async {
    await syncBeneficiaries();
    await syncImages();
  }

  // --- Sync Logic for Verification Images/Videos ---
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

      if (dbId == null || loanId == null || processId == null || filePath == null || userId == null) {
        print("❌ Skipping invalid row: $row");
        continue;
      }

      // Determine extension from the ENCRYPTED file path (usually ends in .jpg or .mp4)
      // But since we are decrypting, we need to know what the original extension was.
      // EncryptionService.encryptFile preserves extension but adds _enc.
      // So .mp4 becomes _enc.mp4. Path extension works.
      String ext = p.extension(filePath).toLowerCase();
      if (ext.isEmpty) ext = '.jpg'; // Default fallback

      print("⬆️ Syncing Verification ($ext): Loan $loanId, Step $processId");

      var request = http.MultipartRequest("POST", Uri.parse('${kBaseUrl}upload'));
      
      try {
        // 1. Decrypt file to bytes
        final decryptedBytes = await EncryptionService.decryptFileToBytes(File(filePath));
        
        // 2. Add decrypted bytes to request
        // Clean filename: remove '_enc' for server clarity
        String cleanFilename = "sync_${loanId}_$processId$ext"; 
        
        request.files.add(http.MultipartFile.fromBytes(
            'file', 
            decryptedBytes, 
            filename: cleanFilename
        ));

        request.fields["process_id"] = processId;
        request.fields["loan_id"] = loanId;
        request.fields["user_id"] = userId;

        var response = await request.send();
        if (response.statusCode == 200) {
          print("✅ Sync Success for Verification ID $dbId");
          // Delete DB entry (and ideally the encrypted file too)
          await DatabaseHelper.instance.deleteImage(dbId, deleteFile: true);
          wasSynced = true;
          
          _itemSyncedController.add({
            'loanId': loanId,
            'processId': processId,
          });
          
        } else {
          print("❌ Server Error (${response.statusCode})");
        }
      } catch (e) {
        print("❌ Error during sync (Decryption/Network): $e");
      }
    }

    if (wasSynced) _syncController.add(true);
  }

  // --- Sync Logic for Pending Beneficiaries ---
  static Future<void> syncBeneficiaries() async {
    List<Map<String, dynamic>> data = await DatabaseHelper.instance.getPendingBeneficiaries();

    if (data.isEmpty) return;
    print("📂 Found ${data.length} pending beneficiaries to sync...");

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

      if (dbId == null || name == null || loanId == null) {
         continue;
      }

      print("⬆️ Syncing Beneficiary: $name ($loanId)");

      var request = http.MultipartRequest('POST', Uri.parse('${kBaseUrl}bank/beneficiary'));

      request.fields['officer_id'] = officerId ?? "";
      request.fields['name'] = name;
      request.fields['phone'] = phone ?? "";
      request.fields['amount'] = amount ?? "";
      request.fields['loan_id'] = loanId;
      request.fields['scheme'] = scheme ?? "";
      request.fields['loan_type'] = loanType ?? "";

      if (docPath != null && docPath.isNotEmpty) {
        try {
          // Decrypt the document
          final decryptedBytes = await EncryptionService.decryptFileToBytes(File(docPath));
          final filename = p.basename(docPath).replaceAll('_enc', ''); // Clean filename

          request.files.add(http.MultipartFile.fromBytes(
              'loan_document', 
              decryptedBytes,
              filename: filename
          ));
        } catch (e) {
          print("⚠️ Could not decrypt/attach file for sync: $e");
        }
      }

      try {
        var response = await request.send();
        if (response.statusCode == 201) {
          print("✅ Sync Success for Beneficiary: $name");
          await DatabaseHelper.instance.deletePendingBeneficiary(dbId);
        } else {
          print("❌ Server Error (${response.statusCode}) syncing beneficiary");
        }
      } catch (e) {
        print("❌ Network Error syncing beneficiary: $e");
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
