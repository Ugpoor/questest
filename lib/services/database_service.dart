import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:crypto/crypto.dart';
import '../models/question.dart';
import '../models/test_session.dart';

class DatabaseService {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final dbDir = await getDatabasesPath();
    final path = join(dbDir, 'questest.db');

    if (!await databaseExists(path)) {
      await _copyAssetDb(path, dbDir);
    }

    final db = await openDatabase(path, version: 2, onCreate: _onCreate, onUpgrade: _onUpgrade);

    // Check if the database has data — if empty, re-copy from assets
    try {
      final tables = await db.query('question_tables');
      if (tables.isEmpty) {
        await db.close();
        await deleteDatabase(path);
        await _copyAssetDb(path, dbDir);
        return await openDatabase(path, version: 2, onCreate: _onCreate, onUpgrade: _onUpgrade);
      }
    } catch (_) {}

    return db;
  }

  static Future<void> _copyAssetDb(String path, String dbDir) async {
    try {
      await Directory(dbDir).create(recursive: true);
      final data = await rootBundle.load('assets/questest.db');
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await File(path).writeAsBytes(bytes, flush: true);
    } catch (_) {}
  }

  static Future<void> _onCreate(Database db, int version) async {
    await _createCoreTables(db);
    await _createTestTables(db);
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createTestTables(db);
    }
  }

  static Future<void> _createCoreTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS question_tables (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT UNIQUE NOT NULL,
        display_name TEXT NOT NULL,
        file_path TEXT,
        created_at TEXT NOT NULL,
        question_count INTEGER DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS dimensions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        dim_index INTEGER NOT NULL,
        dim_name TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createTestTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS file_hashes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        hash TEXT UNIQUE NOT NULL,
        file_name TEXT NOT NULL,
        table_name TEXT NOT NULL,
        imported_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS test_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        table_name TEXT NOT NULL,
        question_count INTEGER NOT NULL,
        duration_seconds INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending_selection',
        started_at TEXT,
        ended_at TEXT,
        time_spent_seconds INTEGER,
        total_score INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS test_answers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        test_id INTEGER NOT NULL,
        question_id INTEGER NOT NULL,
        question_seq INTEGER NOT NULL,
        user_answer TEXT DEFAULT '',
        score INTEGER DEFAULT 0,
        is_correct INTEGER,
        FOREIGN KEY (test_id) REFERENCES test_sessions(id)
      )
    ''');
  }

  // ==================== 题库表操作 ====================

  static Future<String> createQuestionTable(String displayName) async {
    final database = await db;
    final safeName = displayName.replaceAll(RegExp(r'[^a-zA-Z0-9_\u4e00-\u9fa5]'), '_');
    final fullName = 'q_$safeName';
    // 确保表名唯一
    String finalName = fullName;
    int suffix = 1;
    while (true) {
      final existing = await database.query('question_tables', where: 'table_name = ?', whereArgs: [finalName]);
      if (existing.isEmpty) break;
      finalName = '${fullName}_$suffix';
      suffix++;
    }
    await database.execute('''
      CREATE TABLE IF NOT EXISTS $finalName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        seq INTEGER NOT NULL,
        content TEXT NOT NULL,
        options TEXT NOT NULL,
        correct_answers TEXT NOT NULL,
        explanation TEXT,
        dim1 TEXT, dim2 TEXT, dim3 TEXT
      )
    ''');
    return finalName;
  }

  static Future<void> insertQuestions(String tableName, List<Question> questions) async {
    final database = await db;
    final batch = database.batch();
    for (final q in questions) {
      batch.insert(tableName, q.toMap());
    }
    await batch.commit(noResult: true);
  }

  static Future<void> recordTableMeta({
    required String tableName,
    required String displayName,
    String? filePath,
    required int questionCount,
  }) async {
    final database = await db;
    await database.insert('question_tables', {
      'table_name': tableName,
      'display_name': displayName,
      'file_path': filePath,
      'created_at': DateTime.now().toIso8601String(),
      'question_count': questionCount,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<Map<String, dynamic>>> getAllTables() async {
    final database = await db;
    return await database.query('question_tables', orderBy: 'created_at DESC');
  }

  static Future<void> deleteTable(String tableName) async {
    final database = await db;
    await database.execute('DROP TABLE IF EXISTS $tableName');
    await database.delete('question_tables', where: 'table_name = ?', whereArgs: [tableName]);
  }

  static Future<List<Question>> getAllQuestions(String tableName) async {
    final database = await db;
    final rows = await database.query(tableName, orderBy: 'seq ASC');
    return rows.map((row) {
      final opts = (jsonDecode(row['options'] as String) as List)
          .map((o) => QuestionOption.fromJson(o)).toList();
      return Question.fromMap(row, opts, tableName: tableName);
    }).toList();
  }

  /// 分页查询题目
  static Future<List<Question>> getQuestionsPaged(String tableName, {int page = 0, int pageSize = 20, String? keyword}) async {
    final database = await db;
    String where = '';
    List<dynamic> args = [];
    if (keyword != null && keyword.isNotEmpty) {
      where = 'content LIKE ? OR options LIKE ?';
      args = ['%$keyword%', '%$keyword%'];
    }
    final rows = await database.query(
      tableName,
      where: where.isEmpty ? null : where,
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'seq ASC',
      limit: pageSize,
      offset: page * pageSize,
    );
    return rows.map((row) {
      final opts = (jsonDecode(row['options'] as String) as List)
          .map((o) => QuestionOption.fromJson(o)).toList();
      return Question.fromMap(row, opts, tableName: tableName);
    }).toList();
  }

  /// 统计题目数（含关键词过滤）
  static Future<int> countQuestions(String tableName, {String? keyword}) async {
    final database = await db;
    String where = '';
    List<dynamic> args = [];
    if (keyword != null && keyword.isNotEmpty) {
      where = 'content LIKE ? OR options LIKE ?';
      args = ['%$keyword%', '%$keyword%'];
    }
    final result = await database.rawQuery(
      'SELECT COUNT(*) as cnt FROM $tableName ${where.isNotEmpty ? "WHERE $where" : ""}',
      args.isEmpty ? null : args,
    );
    return result.first['cnt'] as int;
  }

  // ==================== 文件排重 ====================

  static Future<String> computeFileHash(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  static Future<bool> isFileHashDuplicate(String hash) async {
    final database = await db;
    final rows = await database.query('file_hashes', where: 'hash = ?', whereArgs: [hash]);
    return rows.isNotEmpty;
  }

  static Future<void> recordFileHash({
    required String hash,
    required String fileName,
    required String tableName,
  }) async {
    final database = await db;
    await database.insert('file_hashes', {
      'hash': hash,
      'file_name': fileName,
      'table_name': tableName,
      'imported_at': DateTime.now().toIso8601String(),
    });
  }

  // ==================== 题干排重 ====================

  /// 获取已有题干集合（用于排重）
  static Future<Set<String>> getExistingContents(String tableName) async {
    final database = await db;
    final rows = await database.query(tableName, columns: ['content']);
    return rows.map((r) => (r['content'] as String).trim()).toSet();
  }

  // ==================== 维度操作 ====================

  static Future<List<String>> getDimensions() async {
    final database = await db;
    final rows = await database.query('dimensions', orderBy: 'dim_index ASC');
    return rows.map((r) => r['dim_name'] as String).toList();
  }

  static Future<void> saveDimensions(List<String> dims) async {
    final database = await db;
    await database.delete('dimensions');
    for (int i = 0; i < dims.length; i++) {
      if (dims[i].trim().isNotEmpty) {
        await database.insert('dimensions', {'dim_index': i, 'dim_name': dims[i].trim()});
      }
    }
  }

  static Future<void> batchUpdateDims(String tableName, List<Map<String, dynamic>> updates) async {
    final database = await db;
    final batch = database.batch();
    for (final u in updates) {
      batch.update(tableName, {'dim1': u['dim1'], 'dim2': u['dim2'], 'dim3': u['dim3']},
        where: 'id = ?', whereArgs: [u['id']]);
    }
    await batch.commit(noResult: true);
  }

  /// 查询指定维度的所有不同取值及其题目数量
  /// [dimColumn] 为 'dim1', 'dim2', 'dim3'
  static Future<Map<String, int>> getDimValueCounts(String tableName, String dimColumn) async {
    final database = await db;
    final rows = await database.rawQuery(
      'SELECT $dimColumn as dim_val, COUNT(*) as cnt FROM $tableName '
      'WHERE $dimColumn IS NOT NULL AND $dimColumn != \'\' '
      'GROUP BY $dimColumn ORDER BY cnt DESC',
    );
    return {for (final r in rows) r['dim_val'] as String: r['cnt'] as int};
  }

  /// 从指定维度的指定分类值中随机选取 N 道题目
  static Future<List<Question>> selectQuestionsByDim(
    String tableName,
    String dimColumn,
    String dimValue,
    int count,
  ) async {
    final database = await db;
    final rows = await database.query(
      tableName,
      where: '$dimColumn = ?',
      whereArgs: [dimValue],
      orderBy: 'RANDOM()',
      limit: count,
    );
    return rows.map((row) {
      final opts = (jsonDecode(row['options'] as String) as List)
          .map((o) => QuestionOption.fromJson(o)).toList();
      return Question.fromMap(row, opts, tableName: tableName);
    }).toList();
  }

  /// 从题库中按序号均匀散点随机选取 N 道题目（不依赖维度）
  static Future<List<Question>> selectQuestionsUniform(String tableName, int count) async {
    final database = await db;
    // 获取总题数
    final totalResult = await database.rawQuery('SELECT COUNT(*) as cnt FROM $tableName');
    final total = totalResult.first['cnt'] as int;
    if (total == 0) return [];
    if (count >= total) {
      return await getAllQuestions(tableName);
    }
    // 分段均匀采样：将总题数分成 count 段，每段随机取一题
    final segmentSize = total / count;
    final selectedIds = <int>[];
    final random = Random();
    for (int i = 0; i < count; i++) {
      final offset = ((i * segmentSize) + random.nextDouble() * segmentSize).floor().clamp(0, total - 1);
      final row = await database.query(tableName, orderBy: 'seq ASC', limit: 1, offset: offset);
      if (row.isNotEmpty) {
        selectedIds.add(row.first['id'] as int);
      }
    }
    if (selectedIds.isEmpty) return [];
    final placeholders = selectedIds.map((_) => '?').join(',');
    final rows = await database.query(
      tableName,
      where: 'id IN ($placeholders)',
      whereArgs: selectedIds,
      orderBy: 'seq ASC',
    );
    return rows.map((row) {
      final opts = (jsonDecode(row['options'] as String) as List)
          .map((o) => QuestionOption.fromJson(o)).toList();
      return Question.fromMap(row, opts, tableName: tableName);
    }).toList();
  }

  // ==================== 测试会话 ====================

  static Future<int> createTestSession(TestSession session) async {
    final database = await db;
    return await database.insert('test_sessions', session.toMap()..remove('id'));
  }

  static Future<List<TestSession>> getAllTestSessions() async {
    final database = await db;
    final rows = await database.query('test_sessions', orderBy: 'created_at DESC');
    return rows.map((r) => TestSession.fromMap(r)).toList();
  }

  static Future<TestSession?> getTestSession(int id) async {
    final database = await db;
    final rows = await database.query('test_sessions', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : TestSession.fromMap(rows.first);
  }

  static Future<void> updateTestSession(TestSession session) async {
    final database = await db;
    await database.update('test_sessions', session.toMap(), where: 'id = ?', whereArgs: [session.id]);
  }

  static Future<void> deleteTestSession(int id) async {
    final database = await db;
    await database.delete('test_answers', where: 'test_id = ?', whereArgs: [id]);
    await database.delete('test_sessions', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== 答题记录 ====================

  static Future<void> insertTestAnswers(int testId, List<Question> questions) async {
    final database = await db;
    final batch = database.batch();
    for (final q in questions) {
      batch.insert('test_answers', {
        'test_id': testId,
        'question_id': q.id ?? 0,
        'question_seq': q.seq,
        'user_answer': '',
        'score': 0,
        'is_correct': null,
      });
    }
    await batch.commit(noResult: true);
  }

  static Future<List<TestAnswer>> getTestAnswers(int testId) async {
    final database = await db;
    final rows = await database.query('test_answers', where: 'test_id = ?', whereArgs: [testId], orderBy: 'question_seq ASC');
    return rows.map((r) => TestAnswer.fromMap(r)).toList();
  }

  static Future<void> saveAnswer(TestAnswer answer) async {
    final database = await db;
    await database.update('test_answers', answer.toMap(), where: 'id = ?', whereArgs: [answer.id]);
  }

  /// 自动批阅：对比题库答案
  static Future<int> gradeTest(int testId, String tableName) async {
    final database = await db;
    final answers = await getTestAnswers(testId);
    int totalScore = 0;

    final batch = database.batch();
    for (final a in answers) {
      // 获取题目正确答案
      final qRows = await database.query(tableName, where: 'id = ?', whereArgs: [a.questionId]);
      if (qRows.isEmpty) continue;
      final correctAnswers = (qRows.first['correct_answers'] as String).split(',');

      final userAnswers = a.userAnswer.isEmpty ? <String>[] : a.userAnswer.split(',');
      final sortedUser = List<String>.from(userAnswers)..sort();
      final sortedCorrect = List<String>.from(correctAnswers)..sort();
      final isCorrect = sortedUser.length == sortedCorrect.length &&
          List.generate(sortedUser.length, (i) => sortedUser[i] == sortedCorrect[i]).every((e) => e);
      final score = isCorrect ? 1 : 0;
      totalScore += score;

      batch.update('test_answers', {'is_correct': isCorrect ? 1 : 0, 'score': score},
        where: 'id = ?', whereArgs: [a.id]);
    }
    await batch.commit(noResult: true);

    // 更新测试总分会
    await database.update('test_sessions', {'total_score': totalScore}, where: 'id = ?', whereArgs: [testId]);
    return totalScore;
  }
}
