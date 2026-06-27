import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/question.dart';
import '../models/app_settings.dart';
import '../models/test_session.dart';
import '../services/database_service.dart';
import '../services/doc_parser_service.dart';
import '../services/llm_classify_service.dart';
import '../services/question_selector.dart';

/// 全局应用状态管理
/// 使用 Provider/ChangeNotifier 模式，管理题库、测试会话、答题等全部状态
class AppState extends ChangeNotifier {
  // ==================== 导航状态 ====================

  /// 当前选中的 Tab 页索引
  /// 0=导入, 1=题库, 2=选题, 3=答题, 4=结果
  int _currentTab = 0;
  int get currentTab => _currentTab;

  // ==================== 题库状态 ====================

  /// 所有题库表元信息
  List<Map<String, dynamic>> _tables = [];
  List<Map<String, dynamic>> get tables => _tables;

  /// 当前选中的题库表名
  String? _selectedTableName;
  String? get selectedTableName => _selectedTableName;

  /// 当前题库的全部题目
  List<Question> _allQuestions = [];
  List<Question> get allQuestions => _allQuestions;

  // ==================== 测试会话状态 ====================

  /// 所有测试会话列表
  List<TestSession> _testSessions = [];
  List<TestSession> get testSessions => _testSessions;

  /// 当前进行中的测试
  TestSession? _activeTest;
  TestSession? get activeTest => _activeTest;

  /// 当前测试的答题记录
  List<TestAnswer> _activeAnswers = [];
  List<TestAnswer> get activeAnswers => _activeAnswers;

  /// 当前测试的题目列表
  List<Question> _activeQuestions = [];
  List<Question> get activeQuestions => _activeQuestions;

  // ==================== 设置 ====================

  AppSettings _settings = AppSettings();
  AppSettings get settings => _settings;

  // ==================== 加载 / 错误状态 ====================

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String _loadingMessage = '';
  String get loadingMessage => _loadingMessage;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // ==================== 导入结果追踪 ====================

  int _importParsed = 0;
  int get importParsed => _importParsed;

  int _importAdded = 0;
  int get importAdded => _importAdded;

  int _importDuplicated = 0;
  int get importDuplicated => _importDuplicated;

  String? _importMessage;
  String? get importMessage => _importMessage;

  // LLM 分类结果（供分类界面使用）
  Map<int, Map<String, String?>> _classifyResults = {};
  Map<int, Map<String, String?>> get classifyResults => _classifyResults;

  // ==================== 构造器 ====================

  AppState() {
    _loadSettings();
    refreshTables();
    _loadTestSessions();
  }

  // ==================== 内部工具方法 ====================

  void _setLoading(bool loading, [String msg = '']) {
    _isLoading = loading;
    _loadingMessage = msg;
    notifyListeners();
  }

  void _setError(String? err) {
    _errorMessage = err;
    notifyListeners();
  }

  // ==================== 1. Tab 切换 ====================

  /// 切换底部 Tab 页
  void setTab(int index) {
    if (index < 0 || index > 4) return;
    _currentTab = index;
    // 切到结果页时自动刷新测试列表
    if (index == 4) {
      _loadTestSessions();
    }
    notifyListeners();
  }

  // ==================== 刷新测试会话列表 ====================

  /// 公开方法：重新加载测试会话列表（供成绩报告页面下拉刷新使用）
  Future<void> refreshTestSessions() async {
    await _loadTestSessions();
  }

  // ==================== 2. 刷新题库表列表 ====================

  Future<void> refreshTables() async {
    try {
      _tables = await DatabaseService.getAllTables();
      notifyListeners();
    } catch (e) {
      _setError('刷新题库失败: $e');
    }
  }

  // ==================== 3. 选中题库 ====================

  /// 选中指定题库表，加载其全部题目
  Future<void> selectTable(String tableName) async {
    _setLoading(true, '加载题库...');
    try {
      _selectedTableName = tableName;
      _allQuestions = await DatabaseService.getAllQuestions(tableName);
      _classifyResults = {};
      notifyListeners();
    } catch (e) {
      _setError('加载题库失败: $e');
    } finally {
      _setLoading(false);
    }
  }

  // ==================== 4. 导入文档（完整流程） ====================

  /// 导入文档完整流程：
  /// 1. 计算文件哈希 -> 2. 文件级排重 -> 3. 解析文档 ->
  /// 4. 题干级排重 -> 5. 入库 -> 6. 记录元信息与哈希
  Future<void> importDocument(String filePath, String displayName) async {
    _setLoading(true, '正在解析文档...');
    _setError(null);
    _clearImportCounters();

    try {
      // --- 步骤 1: 计算文件哈希 ---
      _loadingMessage = '计算文件指纹...';
      notifyListeners();
      final hash = await DatabaseService.computeFileHash(filePath);

      // --- 步骤 2: 文件级排重 ---
      final isDup = await DatabaseService.isFileHashDuplicate(hash);
      if (isDup) {
        _importMessage = '该文件已导入过（文件内容完全相同），跳过导入。';
        _setLoading(false);
        return;
      }

      // --- 步骤 3: 创建表并解析文档 ---
      _loadingMessage = '正在解析文档...';
      notifyListeners();
      final tableName = await DatabaseService.createQuestionTable(displayName);
      final parsedQuestions = await DocParserService.parseFile(filePath, tableName);

      if (parsedQuestions.isEmpty) {
        throw Exception('未能从文档中解析出任何题目');
      }

      _importParsed = parsedQuestions.length;

      // --- 步骤 4: 题干级排重 ---
      _loadingMessage = '检查重复题目...';
      notifyListeners();
      final existingContents = await DatabaseService.getExistingContents(tableName);

      final newQuestions = <Question>[];
      int dupCount = 0;
      for (final q in parsedQuestions) {
        if (existingContents.contains(q.content.trim())) {
          dupCount++;
        } else {
          newQuestions.add(q);
        }
      }
      _importDuplicated = dupCount;

      if (newQuestions.isEmpty) {
        _importMessage = '解析 $_importParsed 道题目，全部与已有题目重复，未新增。';
        _importAdded = 0;
        _setLoading(false);
        return;
      }

      // --- 步骤 5: 入库 ---
      _loadingMessage = '正在保存 ${newQuestions.length} 道题目...';
      notifyListeners();
      await DatabaseService.insertQuestions(tableName, newQuestions);
      _importAdded = newQuestions.length;

      // --- 步骤 6: 记录元信息与文件哈希 ---
      await DatabaseService.recordTableMeta(
        tableName: tableName,
        displayName: displayName,
        filePath: filePath,
        questionCount: newQuestions.length,
      );
      await DatabaseService.recordFileHash(
        hash: hash,
        fileName: displayName,
        tableName: tableName,
      );

      // 设置导入结果消息
      if (_importDuplicated > 0) {
        _importMessage = '解析 $_importParsed 道题，新增 $_importAdded 道，重复 $_importDuplicated 道。';
      } else {
        _importMessage = '成功导入 $_importAdded 道题目。';
      }

      await refreshTables();
      _setLoading(false);
    } catch (e) {
      _setLoading(false);
      _setError('导入失败: $e');
    }
  }

  // ==================== 5. 创建测试会话 ====================

  /// 创建新测试会话，同时插入空的 test_answers 占位行
  Future<int> createTestSession(
    String title,
    String tableName,
    int questionCount,
    int durationSeconds,
  ) async {
    _setLoading(true, '创建测试...');
    try {
      final session = TestSession(
        title: title,
        tableName: tableName,
        questionCount: questionCount,
        durationSeconds: durationSeconds,
        createdAt: DateTime.now(),
        status: 'pending_selection',
      );

      final testId = await DatabaseService.createTestSession(session);

      // 加载题库题目，用于插入空答题行（占位）
      final questions = await DatabaseService.getAllQuestions(tableName);
      if (questions.isNotEmpty) {
        final placeholders = questions.length <= questionCount
            ? questions
            : (List<Question>.from(questions)..shuffle()).take(questionCount).toList();
        await DatabaseService.insertTestAnswers(testId, placeholders);
      }

      await _loadTestSessions();
      _setLoading(false);
      return testId;
    } catch (e) {
      _setLoading(false);
      _setError('创建测试失败: $e');
      rethrow;
    }
  }

  // ==================== 6. 选题 ====================

  /// 选题进度回调
  void Function(double progress, String message)? onSelectionProgress;

  /// 为测试选取题目
  /// [testId] - 测试会话 ID
  /// [dimCounts] - 若为 null，按 dim1 标签均匀抽样（维度分散采样）；
  ///               若提供，则按 {标签名: 数量} 从 dim1 中按标签指定选题数
  /// [dimColumn] - 维度列名 (dim1/dim2/dim3)，默认 dim1
  /// [useUniform] - 是否使用均匀散点选题（不依赖维度）
  Future<void> selectQuestions(
    int testId, {
    Map<String, int>? dimCounts,
    String dimColumn = 'dim1',
    bool useUniform = false,
  }) async {
    _setLoading(true, '智能选题中...');
    onSelectionProgress?.call(0.0, '正在准备选题...');
    try {
      // 找到对应的测试会话
      final session = await DatabaseService.getTestSession(testId);
      if (session == null) throw Exception('测试会话不存在');

      final tableName = session.tableName;
      final targetCount = session.questionCount;

      onSelectionProgress?.call(0.1, '正在加载题库...');

      List<Question> selected;

      if (useUniform) {
        // --- 均匀散点选题（不依赖维度） ---
        onSelectionProgress?.call(0.3, '正在按序号均匀选题...');
        selected = await DatabaseService.selectQuestionsUniform(tableName, targetCount);
      } else if (dimCounts != null && dimCounts.isNotEmpty) {
        // --- 按指定维度数量选题 ---
        onSelectionProgress?.call(0.3, '正在按维度分类选题...');
        selected = await _selectByDimFromDB(tableName, dimColumn, dimCounts, targetCount);
      } else {
        // --- 维度均匀抽样：使用 QuestionSelector 智能选题 ---
        final allQs = await DatabaseService.getAllQuestions(tableName);
        if (allQs.isEmpty) throw Exception('题库为空，无法选题');

        onSelectionProgress?.call(0.5, '正在智能选题...');
        final dims = _settings.customDimensions.isNotEmpty
            ? _settings.customDimensions
            : null;
        selected = QuestionSelector.selectQuestions(
          questions: allQs,
          targetCount: targetCount,
          dimensions: dims,
        );
      }

      onSelectionProgress?.call(0.8, '正在保存选题结果...');

      if (selected.isEmpty) throw Exception('选题失败：无可用题目');

      // 删除旧的答题记录，重新插入选中题目
      final db = await DatabaseService.db;
      await db.delete('test_answers', where: 'test_id = ?', whereArgs: [testId]);
      await DatabaseService.insertTestAnswers(testId, selected);

      // 更新测试状态为 pending_submit
      final updatedSession = session.copyWith(status: 'pending_submit');
      await DatabaseService.updateTestSession(updatedSession);

      await _loadTestSessions();

      // 加载已选题目到 activeQuestions 供界面展示
      _activeAnswers = await DatabaseService.getTestAnswers(testId);
      final qIds = _activeAnswers.map((a) => a.questionId).toSet();
      final allQs = await DatabaseService.getAllQuestions(tableName);
      _activeQuestions = allQs.where((q) => qIds.contains(q.id)).toList();

      onSelectionProgress?.call(1.0, '选题完成！共选 ${selected.length} 道题');
      _setLoading(false);
    } catch (e) {
      _setLoading(false);
      _setError('选题失败: $e');
      rethrow;
    }
  }

  /// 按维度从数据库直接选题
  Future<List<Question>> _selectByDimFromDB(
    String tableName,
    String dimColumn,
    Map<String, int> dimCounts,
    int fallbackCount,
  ) async {
    final selected = <Question>[];
    final selectedIds = <int>{};
    final totalSteps = dimCounts.length;
    int step = 0;

    for (final entry in dimCounts.entries) {
      step++;
      final tag = entry.key;
      final count = entry.value;
      if (count <= 0) continue;

      onSelectionProgress?.call(
        0.3 + (0.5 * step / totalSteps),
        '正在从「$tag」中选取 $count 道题...',
      );

      final qs = await DatabaseService.selectQuestionsByDim(
        tableName, dimColumn, tag, count,
      );
      for (final q in qs) {
        if (q.id != null && !selectedIds.contains(q.id)) {
          selected.add(q);
          selectedIds.add(q.id!);
        }
      }
    }

    // 如果不足目标数量，从剩余题目补充
    if (selected.length < fallbackCount) {
      onSelectionProgress?.call(0.75, '正在补充剩余题目...');
      final allQs = await DatabaseService.getAllQuestions(tableName);
      final remaining = allQs.where((q) => q.id != null && !selectedIds.contains(q.id)).toList()
        ..shuffle();
      for (final q in remaining) {
        if (selected.length >= fallbackCount) break;
        selected.add(q);
        if (q.id != null) selectedIds.add(q.id!);
      }
    }

    return selected;
  }

  /// 获取指定维度的所有取值及其题目数
  Future<Map<String, int>> getDimValueCounts(String tableName, String dimColumn) async {
    return await DatabaseService.getDimValueCounts(tableName, dimColumn);
  }

  // ==================== 7. 提交测试 ====================

  /// 将测试状态设为 completed
  Future<void> submitTest(int testId) async {
    try {
      final session = await DatabaseService.getTestSession(testId);
      if (session == null) return;

      final updated = session.copyWith(status: 'completed');
      await DatabaseService.updateTestSession(updated);
      await _loadTestSessions();

      // 如果当前活跃测试就是该会话，同步更新
      if (_activeTest?.id == testId) {
        _activeTest = updated;
        notifyListeners();
      }
    } catch (e) {
      _setError('提交失败: $e');
    }
  }

  // ==================== 8. 开始答题 ====================

  /// 加载测试的题目和答题记录，设置 startedAt，进入答题模式
  Future<void> startTest(int testId) async {
    _setLoading(true, '加载答题...');
    try {
      final session = await DatabaseService.getTestSession(testId);
      if (session == null) throw Exception('测试会话不存在');

      // 加载答题记录
      _activeAnswers = await DatabaseService.getTestAnswers(testId);

      // 加载对应题目（按答题记录中的 questionId 匹配）
      final allQs = await DatabaseService.getAllQuestions(session.tableName);
      final answerQuestionIds = _activeAnswers.map((a) => a.questionId).toSet();
      _activeQuestions = allQs.where((q) => answerQuestionIds.contains(q.id)).toList();

      // 按答题记录的 question_seq 排序题目
      final seqOrder = {for (final a in _activeAnswers) a.questionId: a.questionSeq};
      _activeQuestions.sort((a, b) =>
          (seqOrder[a.id] ?? 0).compareTo(seqOrder[b.id] ?? 0));

      // 更新 startedAt 和 status
      final now = DateTime.now();
      final updated = session.copyWith(
        startedAt: session.startedAt ?? now,
        status: 'pending_submit',
      );
      await DatabaseService.updateTestSession(updated);
      _activeTest = updated;

      await _loadTestSessions();
      _setLoading(false);
    } catch (e) {
      _setLoading(false);
      _setError('开始答题失败: $e');
    }
  }

  // ==================== 9. 保存单题答案 ====================

  /// 保存单道题的用户答案到数据库，并更新内存列表
  Future<void> saveAnswer(TestAnswer answer) async {
    try {
      await DatabaseService.saveAnswer(answer);

      // 更新内存中的答题记录
      final idx = _activeAnswers.indexWhere((a) => a.id == answer.id);
      if (idx >= 0) {
        _activeAnswers[idx] = answer;
      }
      notifyListeners();
    } catch (e) {
      _setError('保存答案失败: $e');
    }
  }

  // ==================== 10. 结束答题 ====================

  /// 结束答题：设置 endedAt，计算用时，触发自动批阅
  Future<void> endTest(int testId) async {
    _setLoading(true, '正在提交...');
    try {
      final session = await DatabaseService.getTestSession(testId);
      if (session == null) throw Exception('测试会话不存在');

      final now = DateTime.now();
      final startedAt = session.startedAt ?? now;
      final timeSpent = now.difference(startedAt).inSeconds;

      final updated = session.copyWith(
        endedAt: now,
        timeSpentSeconds: timeSpent,
        status: 'completed',
      );
      await DatabaseService.updateTestSession(updated);

      // 自动触发批阅
      await gradeTest(testId);

      // 清除活跃测试状态
      _activeTest = null;
      _activeAnswers = [];
      _activeQuestions = [];

      await _loadTestSessions();
      _setLoading(false);
    } catch (e) {
      _setLoading(false);
      _setError('结束答题失败: $e');
    }
  }

  // ==================== 10b. 中止测试 ====================

  /// 中止当前测试，状态设为 aborted，不触发批阅
  Future<void> abortTest(int testId) async {
    try {
      final session = await DatabaseService.getTestSession(testId);
      if (session == null) return;

      final now = DateTime.now();
      final startedAt = session.startedAt ?? now;
      final timeSpent = now.difference(startedAt).inSeconds;

      final updated = session.copyWith(
        endedAt: now,
        timeSpentSeconds: timeSpent,
        status: 'aborted',
      );
      await DatabaseService.updateTestSession(updated);

      // 清除活跃测试状态
      _activeTest = null;
      _activeAnswers = [];
      _activeQuestions = [];

      await _loadTestSessions();
      notifyListeners();
    } catch (e) {
      _setError('中止测试失败: $e');
    }
  }

  // ==================== 11. 批阅测试 ====================

  /// 调用数据库服务进行自动批阅，刷新会话列表
  Future<void> gradeTest(int testId) async {
    try {
      // 优先从内存查找，其次从数据库加载
      TestSession? session;
      try {
        session = _testSessions.firstWhere((s) => s.id == testId);
      } catch (_) {
        session = await DatabaseService.getTestSession(testId);
      }
      if (session == null) return;

      await DatabaseService.gradeTest(testId, session.tableName);
      await _loadTestSessions();
      notifyListeners();
    } catch (e) {
      _setError('批阅失败: $e');
    }
  }

  // ==================== 11b. 退出答题视图 ====================

  /// 退出当前答题视图（不改变测试状态），返回可做试题一览
  /// 已保存的答案不丢失，下次可继续作答
  void exitTestView() {
    _activeTest = null;
    _activeAnswers = [];
    _activeQuestions = [];
    notifyListeners();
  }

  // ==================== 12. 删除测试 ====================

  /// 删除测试会话及其所有答题记录
  Future<void> deleteTest(int testId) async {
    try {
      await DatabaseService.deleteTestSession(testId);

      // 如果删除的是当前活跃测试，清空状态
      if (_activeTest?.id == testId) {
        _activeTest = null;
        _activeAnswers = [];
        _activeQuestions = [];
      }

      await _loadTestSessions();
    } catch (e) {
      _setError('删除测试失败: $e');
    }
  }

  // ==================== 13. 保存设置 ====================

  /// 保存应用设置到 SharedPreferences
  Future<void> saveSettings(AppSettings newSettings) async {
    _settings = newSettings;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_settings', jsonEncode(newSettings.toJson()));
    notifyListeners();
  }

  /// 保存维度定义到数据库（同时更新设置）
  Future<void> saveDimensions(List<String> dims) async {
    await DatabaseService.saveDimensions(dims);
    _settings = _settings.copyWith(customDimensions: dims);
    await saveSettings(_settings);
  }

  // ==================== 14. 清除导入结果 ====================

  /// 重置导入相关计数器与消息
  void clearImportResult() {
    _clearImportCounters();
    notifyListeners();
  }

  void _clearImportCounters() {
    _importParsed = 0;
    _importAdded = 0;
    _importDuplicated = 0;
    _importMessage = null;
  }

  // ==================== 15. LLM 分类题目 ====================

  /// 使用 LLM 对当前题库题目进行维度分类
  Future<void> classifyQuestions(List<String> dimensions) async {
    if (_allQuestions.isEmpty || dimensions.isEmpty) return;
    _setLoading(true, 'AI 正在归类题目...');
    try {
      _classifyResults = await LlmClassifyService.classifyQuestions(
        questions: _allQuestions,
        dimensions: dimensions,
      );

      // 批量更新数据库中的维度标签
      final updates = <Map<String, dynamic>>[];
      for (final q in _allQuestions) {
        final r = _classifyResults[q.seq];
        if (r != null) {
          updates.add({
            'id': q.id,
            'dim1': r[dimensions.length > 0 ? dimensions[0] : 'dim1'],
            'dim2': r[dimensions.length > 1 ? dimensions[1] : 'dim2'],
            'dim3': r[dimensions.length > 2 ? dimensions[2] : 'dim3'],
          });
        }
      }

      if (updates.isNotEmpty && _selectedTableName != null) {
        await DatabaseService.batchUpdateDims(_selectedTableName!, updates);
        // 重新加载题目（含更新后的维度标签）
        _allQuestions = await DatabaseService.getAllQuestions(_selectedTableName!);
      }

      notifyListeners();
    } catch (e) {
      _setError('分类失败: $e');
    } finally {
      _setLoading(false);
    }
  }

  // ==================== 删除题库表 ====================

  /// 删除题库表及其题目数据
  Future<void> deleteTable(String tableName) async {
    try {
      await DatabaseService.deleteTable(tableName);
      if (_selectedTableName == tableName) {
        _selectedTableName = null;
        _allQuestions = [];
        _classifyResults = {};
      }
      await refreshTables();
    } catch (e) {
      _setError('删除失败: $e');
    }
  }

  // ==================== 清除错误 ====================

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // ==================== 内部：加载设置 ====================

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString('app_settings');
      if (settingsJson != null) {
        _settings = AppSettings.fromJson(jsonDecode(settingsJson));
        notifyListeners();
      }

      // 从数据库加载维度定义（优先使用数据库中的值）
      final dims = await DatabaseService.getDimensions();
      if (dims.isNotEmpty && _settings.customDimensions.isEmpty) {
        _settings = _settings.copyWith(customDimensions: dims);
      }
    } catch (e) {
      _setError('加载设置失败: $e');
    }
  }

  // ==================== 内部：加载测试会话列表 ====================

  Future<void> _loadTestSessions() async {
    try {
      _testSessions = await DatabaseService.getAllTestSessions();
      notifyListeners();
    } catch (e) {
      // 静默失败，不影响主流程
      debugPrint('加载测试会话失败: $e');
    }
  }
}
