// lib/services/database_helper.dart
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static const _dbName = 'loan_app.db';
  static const _dbVersion = 4;
  static const tableImages = 'images';

  // columns & statuses
  static const colId = 'id';
  static const colUserId = 'user_id';
  static const colProcessId = 'process_id';
  static const colProcessIntId = 'process_int_id';
  static const colLoanId = 'loan_id';
  static const colFilePath = 'file_path';
  static const colSubmitted = 'submitted'; // 0 = captured, 1 = queued for upload
  static const colCreatedAt = 'created_at';

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
        $colCreatedAt INTEGER
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE $tableImages ADD COLUMN $colSubmitted INTEGER DEFAULT 0;');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE $tableImages ADD COLUMN $colLoanId TEXT;');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE $tableImages ADD COLUMN $colProcessIntId INTEGER;');
    }
  }

  Future<int> insertImagePath({
    required String userId,
    required String processId,
    required int processIntId,
    required String loanId,
    required String filePath,
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
      {colSubmitted: 1}, // 1 = Queued for Sync
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
    return Sqflite.firstIntValue(result) ?? 0;
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
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
    return await db.delete(tableImages, where: '$colId = ?', whereArgs: [id]);
  }
}