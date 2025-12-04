import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static const _dbName = 'loan_app.db';
  static const _dbVersion = 9;

  static const tableImages = 'images';
  static const tableBeneficiaries = 'pending_beneficiaries';
  static const tableOfficerActions = 'officer_actions';
  static const colExtraJson = 'extra_json';

  // columns for images
  static const colId = 'id';
  static const colUserId = 'user_id';
  static const colProcessId = 'process_id';
  static const colProcessIntId = 'process_int_id';
  static const colLoanId = 'loan_id';
  static const colFilePath = 'file_path';
  static const colSubmitted = 'submitted';
  static const colCreatedAt = 'created_at';
  static const colLatitude = 'latitude';
  static const colLongitude = 'longitude';
  static const colLocationConfidence = 'location_confidence';

  // columns for beneficiaries
  static const colOfficerId = 'officer_id';
  static const colName = 'name';
  static const colPhone = 'phone';
  static const colAmount = 'amount';
  static const colScheme = 'scheme';
  static const colLoanType = 'loan_type';
  static const colDocPath = 'doc_path';
  static const colAddress = 'address';
  static const colAsset = 'asset';

  // columns for officer actions
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
        $colAsset TEXT,
        $colExtraJson TEXT
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
  Future<bool> _columnExists(Database db, String table, String column) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.any((r) => (r['name']?.toString() ?? '').toLowerCase() == column.toLowerCase());
  }

  Future<void> _addColumnIfMissing(Database db, String table, String column, String typeAndExtras) async {
    final exists = await _columnExists(db, table, column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $typeAndExtras');
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE $tableImages ADD COLUMN $colSubmitted INTEGER DEFAULT 0');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE $tableImages ADD COLUMN $colLoanId TEXT');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE $tableImages ADD COLUMN $colProcessIntId INTEGER');
    }
    if (oldVersion < 5) {
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
          $colCreatedAt INTEGER
        )
      ''');
    }
    if (oldVersion < 6) {
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
    if (oldVersion < 7) {
      await db.execute('ALTER TABLE $tableBeneficiaries ADD COLUMN $colAddress TEXT');
      await db.execute('ALTER TABLE $tableBeneficiaries ADD COLUMN $colAsset TEXT');
    }
    if (oldVersion < 8) {
      await db.execute('ALTER TABLE $tableBeneficiaries ADD COLUMN $colExtraJson TEXT');
    }
    if (oldVersion < 9) {
      await _addColumnIfMissing(db, tableImages, colLatitude, 'TEXT');
      await _addColumnIfMissing(db, tableImages, colLongitude, 'TEXT');
      await _addColumnIfMissing(db, tableImages, colLocationConfidence, 'TEXT');
    }
  }

  Future<int> insertImagePath({
    required String userId,
    required String processId,
    required int processIntId,
    required String loanId,
    required String filePath,
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
      colLatitude: latitude,
      colLongitude: longitude,
      colLocationConfidence: locationConfidence,
    };
    return await db.insert(tableImages, row);
  }

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
    final db = await instance.database;
    return await db.query(
      tableImages,
      where: '$colSubmitted = ?',
      whereArgs: [1],
    );
  }

  Future<int> getQueuedForUploadCount() async {
    final db = await instance.database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM $tableImages WHERE $colSubmitted = 1');
    final imgCount = Sqflite.firstIntValue(result) ?? 0;

    final resultBen = await db.rawQuery('SELECT COUNT(*) FROM $tableBeneficiaries');
    final benCount = Sqflite.firstIntValue(resultBen) ?? 0;

    final resultAct = await db.rawQuery('SELECT COUNT(*) FROM $tableOfficerActions');
    final actCount = Sqflite.firstIntValue(resultAct) ?? 0;

    return imgCount + benCount + actCount;
  }

  Future<int> deleteImage(int id, {bool deleteFile = true}) async {
    final db = await database;
    final rows = await db.query(
      tableImages,
      columns: [colFilePath],
      where: '$colId = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isNotEmpty && deleteFile) {
      final path = rows.first[colFilePath] as String?;
      if (path != null) {
        try {
          final f = File(path);
          if (await f.exists()) {
            await f.delete();
            debugPrint("✅ Local file deleted: $path");
          }
        } catch (e) {
          debugPrint("❌ Error deleting local file: $e");
        }
      }
    }
    final result = await db.delete(tableImages, where: '$colId = ?', whereArgs: [id]);
    debugPrint("✅ Local DB record deleted from table '$tableImages' with id: $id");
    return result;
  }

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
    String? asset,  String? extraJson,
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
      colCreatedAt: DateTime.now().millisecondsSinceEpoch,colExtraJson: extraJson,

    };
    return await db.insert(tableBeneficiaries, row);
  }

  Future<List<Map<String, dynamic>>> getPendingBeneficiaries() async {
    final db = await database;
    return await db.query(tableBeneficiaries);
  }

  Future<int> deletePendingBeneficiary(int id) async {
    final db = await database;
    final result = await db.delete(tableBeneficiaries, where: '$colId = ?', whereArgs: [id]);
    debugPrint("✅ Local DB record deleted from table '$tableBeneficiaries' with id: $id");
    return result;
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
    final result = await db.delete(tableOfficerActions, where: '$colId = ?', whereArgs: [id]);
    debugPrint("✅ Local DB record deleted from table '$tableOfficerActions' with id: $id");
    return result;
  }
}
