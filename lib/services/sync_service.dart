import 'dart:async';
import 'dart:io'; // Import for SocketException
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
    // Check every 5 seconds
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
      // Try to lookup a reliable domain (e.g., google.com) or your server IP
      // Using lookup is faster and more reliable for "internet" check than connecting to your specific server API
      final result = await InternetAddress.lookup('google.com');
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        return true;
      }
      return false;
    } on SocketException catch (_) {
      return false;
    }
  }

  static Future<void> syncImages() async {
    List<Map<String, dynamic>> data = await DatabaseHelper.instance.getQueuedForUpload();

    if (data.isEmpty) return;
    print("📂 Found ${data.length} items to sync...");

    bool wasSynced = false;

    for (var row in data) {
      final dbId = row[DatabaseHelper.colId] as int?;
      final loanId = row[DatabaseHelper.colLoanId] as String?;
      final processId = row[DatabaseHelper.colProcessId] as String?;
      final userId = row[DatabaseHelper.colUserId] as String?;
      final filePath = row[DatabaseHelper.colFilePath] as String?;

      if (dbId == null || loanId == null || processId == null || filePath == null || userId == null) {
        continue;
      }

      // Check if file exists locally before trying to upload
      final file = File(filePath);
      if (!await file.exists()) {
        print("⚠️ File not found at $filePath, deleting record.");
        await DatabaseHelper.instance.deleteImage(dbId, deleteFile: false);
        continue;
      }

      print("⬆️ Syncing: Loan $loanId, Step $processId");

      var request = http.MultipartRequest(
        "POST",
        Uri.parse('${kBaseUrl}upload'),
      );

      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          filePath,
          filename: "sync_${loanId}_$processId.jpg",
        ),
      );

      request.fields["process_id"] = processId;
      request.fields["loan_id"] = loanId;
      request.fields["user_id"] = userId;

      try {
        var response = await request.send();

        if (response.statusCode == 200) {
          print("✅ Sync Success for ID $dbId");
          await DatabaseHelper.instance.deleteImage(dbId, deleteFile: true);
          wasSynced = true;
        } else {
          print("❌ Server Error: ${response.statusCode}");
          // Don't delete, retry later
        }
      } on SocketException catch (e) {
        print("⚠️ Network Unreachable during sync (Will retry later): $e");
        // Stop the loop for this pass if network is dead
        break;
      } catch (e) {
        print("❌ Sync Error: $e");
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