import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:loan2/services/api.dart';
import 'package:loan2/services/database_helper.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class SyncService {
  static final _syncController = StreamController<bool>.broadcast();
  static final _onlineStatusController = StreamController<bool>.broadcast();

  static Stream<bool> get onSync => _syncController.stream;
  static Stream<bool> get onOnlineStatusChanged => _onlineStatusController.stream;

  static StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  static bool _isOnline = false;

  static void startListener() {
    print("🔄 Sync Listener Started...");
    _connectivitySubscription?.cancel(); // Cancel any previous listener

    // Listen for connectivity changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((ConnectivityResult result) async {
      bool isDeviceConnected = result != ConnectivityResult.none;

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
          await syncImages();
        }
      }
    });

    // Also perform an initial check when the app starts.
    _initialCheck();
  }

  // New method for the initial check
  static Future<void> _initialCheck() async {
    _isOnline = await realInternetCheck();
    _onlineStatusController.add(_isOnline);
    print("🌟 Initial Connection Status: ${_isOnline ? "Online" : "Offline"}");
    if (_isOnline) {
      await syncImages();
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

  static Future<void> syncImages() async {
    // Get all items queued for upload
    List<Map<String, dynamic>> data = await DatabaseHelper.instance.getQueuedForUpload();

    if (data.isEmpty) return;
    print("📂 Found ${data.length} items to sync...");

    bool wasSynced = false;

    for (var row in data) {
      final dbId = row[DatabaseHelper.colId] as int?;
      final loanId = row[DatabaseHelper.colLoanId] as String?;
      final processId = row[DatabaseHelper.colProcessId] as String?; // "P1"
      final userId = row[DatabaseHelper.colUserId] as String?; // CRITICAL: Fetch user_id
      final filePath = row[DatabaseHelper.colFilePath] as String?;

      if (dbId == null || loanId == null || processId == null || filePath == null || userId == null) {
        print("❌ Skipping invalid row (missing data): $row");
        continue;
      }

      print("⬆️ Syncing: Loan $loanId, Step $processId");

      var request = http.MultipartRequest(
        "POST",
        Uri.parse('${kBaseUrl}upload'),
      );

      // Add the file
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          filePath,
          filename: "sync_${loanId}_$processId.jpg",
        ),
      );

      // Add fields exactly as api.py expects them
      request.fields["process_id"] = processId;
      request.fields["loan_id"] = loanId;
      request.fields["user_id"] = userId; // Added this field

      try {
        var response = await request.send();
        final respStr = await response.stream.bytesToString();

        if (response.statusCode == 200) {
          print("✅ Sync Success for ID $dbId");
          // Remove from local DB or mark as synced
          await DatabaseHelper.instance.deleteImage(dbId, deleteFile: true);
          wasSynced = true;
        } else {
          print("❌ Server Error (${response.statusCode}): $respStr");
        }
      } catch (e) {
        print("❌ Network Error during sync: $e");
      }
    }

    if (wasSynced) {
      _syncController.add(true); // Notify UI to refresh
    }
  }

  static void dispose() {
    _syncController.close();
    _onlineStatusController.close();
    _connectivitySubscription?.cancel();
  }
}
