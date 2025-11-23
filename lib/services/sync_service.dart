// lib/services/sync_service.dart
import 'dart:async';
import 'package:http/http.dart' as http;
// Ensure these imports point to your new files
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
    _periodicTimer?.cancel(); // Cancel any existing timer
    _periodicTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      bool currentlyOnline = await realInternetCheck();

      if (currentlyOnline != _isOnline) {
        _isOnline = currentlyOnline;
        _onlineStatusController.add(_isOnline);
      }

      if (_isOnline) {
        await syncImages();
      }
    });
  }

  static Future<bool> realInternetCheck() async {
    try {
      // Use the base URL from api.dart for the check
      final response = await http.head(Uri.parse(kBaseUrl)).timeout(const Duration(seconds: 3));
      return response.statusCode >= 200 && response.statusCode < 500;
    } catch (e) {
      return false;
    }
  }

  static Future<void> syncImages() async {
    List<Map<String, dynamic>> data = await DatabaseHelper.instance.getQueuedForUpload();

    if (data.isEmpty) return;
    print("📂 Unsynced items found: ${data.length}");

    bool wasSynced = false;

    for (var row in data) {
      final dbId = row[DatabaseHelper.colId] as int?;
      final loanId = row[DatabaseHelper.colLoanId] as String?;
      final processId = row[DatabaseHelper.colProcessId] as String?;
      final processIntId = row[DatabaseHelper.colProcessIntId] as int?;
      final filePath = row[DatabaseHelper.colFilePath] as String?;

      // Simple validation to prevent crash on null data
      if (dbId == null || loanId == null || processId == null || processIntId == null || filePath == null) {
        print("❌ Skipping invalid row in database: $row");
        continue; // Skip to the next item
      }

      print("⬆️ Uploading offline item → id=$dbId loan=$loanId");

      // Use the base URL from api.dart
      var request = http.MultipartRequest(
        "POST",
        Uri.parse('${kBaseUrl}upload'),
      );

      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          filePath,
          filename: "sync_$dbId.jpg",
        ),
      );

      request.fields["id"] = processIntId.toString();
      request.fields["loan_id"] = loanId;
      request.fields["process_id"] = processId;

      try {
        var response = await request.send();

        if (response.statusCode == 200) {
          print("✅ Uploaded id=$dbId");
          await DatabaseHelper.instance.deleteImage(dbId, deleteFile: true);
          wasSynced = true;
        } else {
          print("❌ Failed to upload id=$dbId → server error: ${response.statusCode}");
        }
      } catch (e) {
        print("❌ Failed to upload id=$dbId → network error: $e");
      }
    }

    if (wasSynced) {
      _syncController.add(true);
    }
  }

  static void dispose() {
    _syncController.close();
    _onlineStatusController.close();
    _periodicTimer?.cancel();
  }
}