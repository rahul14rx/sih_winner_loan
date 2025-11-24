import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:loan2/services/api.dart';
import 'package:loan2/services/database_helper.dart';

class SyncService {
  static final _syncController = StreamController<bool>.broadcast();
  static final _onlineStatusController = StreamController<bool>.broadcast();

  static Stream<bool> get onSync => _syncController.stream;
  static Stream<bool> get onOnlineStatusChanged => _onlineStatusController.stream;

  static Timer? _periodicTimer;
  static bool _isOnline = false;

  static void startListener() {
    print("🔄 Sync Listener Started...");
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      bool currentlyOnline = await realInternetCheck();

      if (currentlyOnline != _isOnline) {
        _isOnline = currentlyOnline;
        _onlineStatusController.add(_isOnline);
        print("🌐 Connection Status: ${_isOnline ? "Online" : "Offline"}");
      }

      if (_isOnline) {
        await syncImages();
      }
    });
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
    _periodicTimer?.cancel();
  }
}