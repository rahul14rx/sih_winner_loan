// lib/services/database_helper.dart
//
// Database helper (updated)
// - added uploadQueuedItem
// - safer onUpgrade (try/catch around ALTERs)
// - updateStepUtilization accepts dynamic processId
//
// Author: ChatGPT (fixes for Wizard integration)

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:http/http.dart' as http;
import 'package:loan2/services/api.dart'; // for kBaseUrl

class DatabaseHelper {
  static const _dbName = 'loan_app.db';
  static const _dbVersion = 8; // UPDATED to 8 (new geotag + utilization fields)

  // ---------- TABLE NAMES ----------
  static const tableImages = 'images';
  static const tableBeneficiaries = 'pending_beneficiaries';
  static const tableOfficerActions = 'officer_actions';

  // ---------- COMMON COLUMNS ----------
  static const colId = 'id';

  // ---------- IMAGES TABLE ----------
  static const colUserId = 'user_id';
  static const colProcessId = 'process_id';
  static const colProcessIntId = 'process_int_id';
  static const colLoanId = 'loan_id';
  static const colFilePath = 'file_path';
  static const colSubmitted = 'submitted';
  static const colCreatedAt = 'created_at';

  // NEW (v8) — Utilization + Geotag
  static const colUtilizationAmount = 'utilization_amount';
  static const colLatitude = 'latitude';
  static const colLongitude = 'longitude';
  static const colLocationConfidence = 'location_confidence';

  // ---------- BENEFICIARY TABLE ----------
  static const colOfficerId = 'officer_id';
  static const colName = 'name';
  static const colPhone = 'phone';
  static const colAmount = 'amount';
  static const colScheme = 'scheme';
  static const colLoanType = 'loan_type';
  static const colDocPath = 'doc_path';
  static const colAddress = 'address';
  static const colAsset = 'asset';

  // ---------- OFFICER ACTIONS ----------
  static const colActionType = 'action_type';
  static const colStatus = 'status';

  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;
  Future<Database> get database async => _database ??= await _initDatabase();

  Future<Database> _initDatabase() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(docsDir.path, _dbName);
    return await openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  // -------------------------------------------------------
  //                   ON CREATE
  // -------------------------------------------------------
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableImages (
        $colId INTEGER PRIMARY KEY AUTOINCREMENT,
        $colUserId TEXT,
        $colProcessId TEXT,
        $colProcessIntId INTEGER,
        $colLoanId TEXT,
        $colFilePath TEXT,
        $colSubmitted INTEGER DEFAULT 0,
        $colCreatedAt INTEGER,
        $colUtilizationAmount TEXT,
        $colLatitude TEXT,
        $colLongitude TEXT,
        $colLocationConfidence TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableBeneficiaries (
        $colId INTEGER PRIMARY KEY AUTOINCREMENT,
        $colOfficerId TEXT,
        $colName TEXT,
        $colPhone TEXT,
        $colAmount TEXT,
        $colLoanId TEXT,
        $colScheme TEXT,
        $colLoanType TEXT,
        $colDocPath TEXT,
        $colCreatedAt INTEGER,
        $colAddress TEXT,
        $colAsset TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableOfficerActions (
        $colId INTEGER PRIMARY KEY AUTOINCREMENT,
        $colLoanId TEXT,
        $colProcessId TEXT,
        $colActionType TEXT,
        $colCreatedAt INTEGER
      )
    ''');
  }

  // -------------------------------------------------------
  //                   ON UPGRADE
  // -------------------------------------------------------
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Wrap each DDL in try/catch to avoid crash when column/table already exists
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE $tableImages ADD COLUMN $colSubmitted INTEGER DEFAULT 0;');
      } catch (_) {}
    }
    if (oldVersion < 3) {
      try {
        await db.execute('ALTER TABLE $tableImages ADD COLUMN $colLoanId TEXT;');
      } catch (_) {}
    }
    if (oldVersion < 4) {
      try {
        await db.execute('ALTER TABLE $tableImages ADD COLUMN $colProcessIntId INTEGER;');
      } catch (_) {}
    }
    if (oldVersion < 5) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS $tableBeneficiaries (
            $colId INTEGER PRIMARY KEY AUTOINCREMENT,
            $colOfficerId TEXT,
            $colName TEXT,
            $colPhone TEXT,
            $colAmount TEXT,
            $colLoanId TEXT,
            $colScheme TEXT,
            $colLoanType TEXT,
            $colDocPath TEXT,
            $colCreatedAt INTEGER
          )
        ''');
      } catch (_) {}
    }
    if (oldVersion < 6) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS $tableOfficerActions (
            $colId INTEGER PRIMARY KEY AUTOINCREMENT,
            $colLoanId TEXT,
            $colProcessId TEXT,
            $colActionType TEXT,
            $colCreatedAt INTEGER
          )
        ''');
      } catch (_) {}
    }
    if (oldVersion < 7) {
      try {
        await db.execute('ALTER TABLE $tableBeneficiaries ADD COLUMN $colAddress TEXT;');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE $tableBeneficiaries ADD COLUMN $colAsset TEXT;');
      } catch (_) {}
    }

    // NEW VERSION 8 — UTILIZATION + GEO-TAG SUPPORT
    if (oldVersion < 8) {
      try {
        await db.execute('ALTER TABLE $tableImages ADD COLUMN $colUtilizationAmount TEXT;');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE $tableImages ADD COLUMN $colLatitude TEXT;');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE $tableImages ADD COLUMN $colLongitude TEXT;');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE $tableImages ADD COLUMN $colLocationConfidence TEXT;');
      } catch (_) {}
    }
  }

  // -------------------------------------------------------
  //                   INSERT IMAGE (UPDATED)
  // -------------------------------------------------------
  Future<int> insertImagePath({
    required String userId,
    required String processId,
    required int processIntId,
    required String loanId,
    required String filePath,
    String? utilizationAmount,
    String? latitude,
    String? longitude,
    String? locationConfidence,
  }) async {
    final db = await database;

    final row = {
      colUserId: userId,
      colProcessId: processId,
      colProcessIntId: processIntId,
      colLoanId: loanId,
      colFilePath: filePath,
      colSubmitted: 0,
      colCreatedAt: DateTime.now().millisecondsSinceEpoch,

      // NEW FIELDS
      colUtilizationAmount: utilizationAmount,
      colLatitude: latitude,
      colLongitude: longitude,
      colLocationConfidence: locationConfidence,
    };

    return await db.insert(tableImages, row);
  }

  // -------------------------------------------------------
  //                   IMAGE QUERIES
  // -------------------------------------------------------
  Future<List<Map<String, dynamic>>> getImagesForUser(String userId) async {
    final db = await database;
    return await db.query(
      tableImages,
      where: '$colUserId = ?',
      whereArgs: [userId],
      orderBy: '$colCreatedAt DESC',
    );
  }

  Future<int> queueForUpload(int id) async {
    final db = await database;
    return await db.update(
      tableImages,
      {colSubmitted: 1},
      where: '$colId = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getQueuedForUpload() async {
    final db = await database;
    return await db.query(tableImages, where: '$colSubmitted = 1');
  }

  Future<int> getQueuedForUploadCount() async {
    final db = await database;

    final imgCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $tableImages WHERE $colSubmitted = 1')) ?? 0;

    final benCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $tableBeneficiaries')) ?? 0;

    final actCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $tableOfficerActions')) ?? 0;

    return imgCount + benCount + actCount;
  }

  Future<int> deleteImage(int id, {bool deleteFile = true}) async {
    final db = await database;

    // delete file
    final rows = await db.query(
      tableImages,
      columns: [colFilePath],
      where: '$colId = ?',
      whereArgs: [id],
    );

    if (rows.isNotEmpty && deleteFile) {
      final filePath = rows.first[colFilePath] as String?;
      if (filePath != null) {
        try {
          final f = File(filePath);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }

    return await db.delete(tableImages, where: '$colId = ?', whereArgs: [id]);
  }

  // -------------------------------------------------------
  //      Beneficiary & Officer Actions — unchanged
  // -------------------------------------------------------

  Future<int> insertPendingBeneficiary({
    required String officerId,
    required String name,
    required String phone,
    required String amount,
    required String loanId,
    required String scheme,
    required String loanType,
    String? docPath,
    String? address,
    String? asset,
  }) async {
    final db = await database;
    final row = {
      colOfficerId: officerId,
      colName: name,
      colPhone: phone,
      colAmount: amount,
      colLoanId: loanId,
      colScheme: scheme,
      colLoanType: loanType,
      colDocPath: docPath,
      colAddress: address,
      colAsset: asset,
      colCreatedAt: DateTime.now().millisecondsSinceEpoch,
    };
    return await db.insert(tableBeneficiaries, row);
  }

  Future<List<Map<String, dynamic>>> getPendingBeneficiaries() async {
    final db = await database;
    return await db.query(tableBeneficiaries);
  }

  // Accept dynamic processId to support both string-id and numeric processId usage
  Future<int> updateStepUtilization({
    required String loanId,
    required dynamic processId,
    required double utilizationAmount,
  }) async {
    final db = await database;

    return await db.update(
      tableImages,
      {colUtilizationAmount: utilizationAmount.toString()},
      where: '$colLoanId = ? AND $colProcessId = ?',
      whereArgs: [loanId, processId.toString()],
    );
  }

  Future<int> deletePendingBeneficiary(int id) async {
    final db = await database;
    return await db.delete(tableBeneficiaries, where: '$colId = ?', whereArgs: [id]);
  }

  Future<int> insertOfficerAction({
    required String loanId,
    required String processId,
    required String actionType,
  }) async {
    final db = await database;

    final row = {
      colLoanId: loanId,
      colProcessId: processId,
      colActionType: actionType,
      colCreatedAt: DateTime.now().millisecondsSinceEpoch,
    };

    return await db.insert(tableOfficerActions, row);
  }

  Future<List<Map<String, dynamic>>> getOfficerActions() async {
    final db = await database;
    return await db.query(tableOfficerActions);
  }

  Future<int> deleteOfficerAction(int id) async {
    final db = await database;
    return await db.delete(tableOfficerActions, where: '$colId = ?', whereArgs: [id]);
  }

  // -------------------------------------------------------
  //  Attempt immediate upload for a queued image row
  //  Returns true on success (and deletes DB row), false otherwise.
  //  This is a best-effort helper — you can customize fields per backend.
  // -------------------------------------------------------
  Future<bool> uploadQueuedItem(int id) async {
    try {
      final db = await database;
      final rows = await db.query(tableImages, where: '$colId = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) return false;

      final row = rows.first;
      final filePath = (row[colFilePath] as String?) ?? '';
      if (filePath.isEmpty) return false;

      final uri = Uri.parse('${kBaseUrl}upload');
      final req = http.MultipartRequest('POST', uri);

      // standard fields
      if (row[colLoanId] != null) req.fields['loan_id'] = row[colLoanId].toString();
      if (row[colProcessIntId] != null) req.fields['process_int_id'] = row[colProcessIntId].toString();
      if (row[colProcessId] != null) req.fields['process_id'] = row[colProcessId].toString();
      if (row[colUserId] != null) req.fields['user_id'] = row[colUserId].toString();

      // geo & utilization if available
      if (row[colLatitude] != null) req.fields['latitude'] = row[colLatitude].toString();
      if (row[colLongitude] != null) req.fields['longitude'] = row[colLongitude].toString();
      if (row[colLocationConfidence] != null) req.fields['location_confidence'] = row[colLocationConfidence].toString();
      if (row[colUtilizationAmount] != null) req.fields['utilization_amount'] = row[colUtilizationAmount].toString();

      // attach file
      try {
        final multipart = await http.MultipartFile.fromPath('file', filePath);
        req.files.add(multipart);
      } catch (e) {
        // file missing or unreadable
        return false;
      }

      // send with timeout
      final streamed = await req.send().timeout(const Duration(seconds: 40));
      if (streamed.statusCode == 200) {
        // delete DB row but keep file (deleteFile=false). Change if you want to remove file.
        await deleteImage(id, deleteFile: false);
        return true;
      } else {
        // server error -> keep queued
        return false;
      }
    } catch (e) {
      if (kDebugMode) print('uploadQueuedItem error: $e');
      return false;
    }
  }
}
