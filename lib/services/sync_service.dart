// lib/services/sync_service.dart — FIXED for connectivity_plus v6

import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';

import 'package:loan2/services/api.dart';
import 'package:loan2/services/database_helper.dart';
import 'package:loan2/services/location_security_service.dart';

class SyncService {
  // ---------------- Singleton ----------------
  SyncService._internal() {
    _locSec = LocationSecurityService();
  }
  static final SyncService instance = SyncService._internal();

  // ---------------- Streams ----------------
  static final _syncController = StreamController<bool>.broadcast();
  static final _onlineStatusController = StreamController<bool>.broadcast();
  static final _itemSyncedController = StreamController<Map<String, String>>.broadcast();

  static Stream<bool> get onSync => _syncController.stream;
  static Stream<bool> get onOnlineStatusChanged => _onlineStatusController.stream;
  static Stream<Map<String, String>> get onItemSynced => _itemSyncedController.stream;

  // ---------------- Connectivity (FIXED) ----------------
  static StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  static bool _isOnline = false;

  // ---------------- Locations ----------------
  late LocationSecurityService _locSec;

  // =============================================================
  // Instance API — Used by Wizard
  // =============================================================

  Future<bool> syncNow() async {
    try {
      await SyncService.syncAll();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// CURRENT LOCATION (Confidence-based)
  Future<Map<String, dynamic>?> getCurrentLocation({Duration timeout = const Duration(seconds: 5)}) async {
    try {
      await _locSec.start();
    } catch (_) {}

    bool enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return null;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return null;
    }

    try {
      final pos =
      await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best)
          .timeout(timeout);

      final eval = await _locSec.evaluate(pos);

      if (eval.isMocked) return null;

      return {
        "latitude": pos.latitude,
        "longitude": pos.longitude,
        "confidence": eval.confidence,
      };
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> realLocation() async => await getCurrentLocation();

  // =============================================================
  // Static Sync Engine
  // =============================================================

  /// LISTENER — FIXED FOR NEW CONNECTIVITY API
  static void startListener() {
    print("🔄 Sync Listener Started...");

    _connectivitySubscription?.cancel();

    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) async {
          bool hasNet = results.isNotEmpty && results.first != ConnectivityResult.none;

          bool serverOk = hasNet ? await realInternetCheck() : false;

          if (serverOk != _isOnline) {
            _isOnline = serverOk;
            _onlineStatusController.add(_isOnline);

            print("🌐 Connection Status: ${_isOnline ? "ONLINE" : "OFFLINE"}");

            if (_isOnline) {
              print("🚀 Auto-sync triggered...");
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

  // ---------------- Server Check ----------------
  static Future<bool> realInternetCheck() async {
    try {
      final r = await http.get(Uri.parse('${kBaseUrl}health'))
          .timeout(const Duration(seconds: 3));

      return r.statusCode >= 200 && r.statusCode < 300;
    } catch (_) {
      try {
        final r2 = await http.head(Uri.parse(kBaseUrl))
            .timeout(const Duration(seconds: 3));
        return r2.statusCode >= 200 && r2.statusCode < 300;
      } catch (_) {
        return false;
      }
    }
  }

  // =============================================================
  // FULL SYNC
  // =============================================================

  static Future<void> syncAll() async {
    await syncBeneficiaries();
    await syncImages();
    await syncOfficerActions();

    try {
      _syncController.add(true);
    } catch (_) {}
  }

  // =============================================================
  // SYNC: Verification Images
  // =============================================================

  static Future<void> syncImages() async {
    final data = await DatabaseHelper.instance.getQueuedForUpload();
    if (data.isEmpty) return;

    print("📂 Found ${data.length} files to sync...");

    for (var row in data) {
      final dbId = row[DatabaseHelper.colId];
      final loanId = row[DatabaseHelper.colLoanId];
      final processId = row[DatabaseHelper.colProcessId];
      final userId = row[DatabaseHelper.colUserId];
      final filePath = row[DatabaseHelper.colFilePath];

      if (dbId == null || loanId == null || processId == null || userId == null || filePath == null) {
        continue;
      }

      final req = http.MultipartRequest("POST", Uri.parse('${kBaseUrl}upload'));

      final util = row[DatabaseHelper.colUtilizationAmount];
      final lat = row[DatabaseHelper.colLatitude];
      final lng = row[DatabaseHelper.colLongitude];
      final conf = row[DatabaseHelper.colLocationConfidence];

      if (util != null) req.fields["utilization_amount"] = util;
      if (lat != null) req.fields["latitude"] = lat;
      if (lng != null) req.fields["longitude"] = lng;
      if (conf != null) req.fields["location_confidence"] = conf;

      req.fields["loan_id"] = loanId;
      req.fields["process_id"] = processId;
      req.fields["user_id"] = userId;

      try {
        req.files.add(await http.MultipartFile.fromPath(
          'file',
          filePath,
          filename: "sync_${loanId}_${processId}${p.extension(filePath)}",
        ));
      } catch (_) {
        continue;
      }

      try {
        final resp = await req.send().timeout(const Duration(seconds: 40));

        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          print("✅ Synced image: $dbId");
          await DatabaseHelper.instance.deleteImage(dbId, deleteFile: true);

          try {
            _itemSyncedController.add({"loanId": loanId, "processId": processId});
          } catch (_) {}
        } else {
          print("❌ Server Error while syncing $dbId");
        }
      } catch (e) {
        print("❌ Sync error for $dbId: $e");
      }
    }

    try {
      _syncController.add(true);
    } catch (_) {}
  }

  // =============================================================
  // SYNC: Beneficiaries
  // =============================================================

  static Future<void> syncBeneficiaries() async {
    final rows = await DatabaseHelper.instance.getPendingBeneficiaries();
    if (rows.isEmpty) return;

    for (var row in rows) {
      final dbId = row[DatabaseHelper.colId];

      final req = http.MultipartRequest('POST', Uri.parse('${kBaseUrl}bank/beneficiary'));

      row.forEach((key, value) {
        if (value != null && key != DatabaseHelper.colDocPath && key != DatabaseHelper.colId) {
          req.fields[key] = value.toString();
        }
      });

      if (row[DatabaseHelper.colDocPath] != null) {
        try {
          req.files.add(await http.MultipartFile.fromPath(
            'loan_document',
            row[DatabaseHelper.colDocPath],
          ));
        } catch (e) {
          print("⚠️ Could not attach doc: $e");
        }
      }

      try {
        final resp = await req.send().timeout(const Duration(seconds: 30));

        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          await DatabaseHelper.instance.deletePendingBeneficiary(dbId);
          print("✅ Beneficiary synced: $dbId");
        } else {
          print("❌ Server error on beneficiary sync: $dbId");
        }
      } catch (e) {
        print("❌ Error syncing beneficiary: $e");
      }
    }
  }

  // =============================================================
  // SYNC: Officer Actions
  // =============================================================

  static Future<void> syncOfficerActions() async {
    final rows = await DatabaseHelper.instance.getOfficerActions();
    if (rows.isEmpty) return;

    for (var row in rows) {
      final dbId = row[DatabaseHelper.colId];
      final loanId = row[DatabaseHelper.colLoanId];
      final processId = row[DatabaseHelper.colProcessId];
      final actionType = row[DatabaseHelper.colActionType];

      try {
        final resp = await http.post(
          Uri.parse('${kBaseUrl}bank/verify'),
          headers: {"Content-Type": "application/json"},
          body: '{"loan_id":"$loanId","process_id":"$processId","status":"$actionType"}',
        );

        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          await DatabaseHelper.instance.deleteOfficerAction(dbId);
          print("✔ Officer Action Synced ");
        } else {
          print("❌ Server error syncing officer action: $dbId");
        }
      } catch (e) {
        print("❌ Error syncing officer action: $e");
      }
    }
  }

  // =============================================================
  // Dispose
  // =============================================================
  void dispose() {
    try {
      _connectivitySubscription?.cancel();
      _syncController.close();
      _onlineStatusController.close();
      _itemSyncedController.close();
    } catch (_) {}
  }
}
