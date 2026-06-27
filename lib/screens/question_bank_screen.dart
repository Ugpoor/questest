import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/question.dart';
import '../services/database_service.dart';

class QuestionBankScreen extends StatefulWidget {
  const QuestionBankScreen({super.key});

  @override
  State<QuestionBankScreen> createState() => _QuestionBankScreenState();
}

class _QuestionBankScreenState extends State<QuestionBankScreen> {
  // Pagination state
  static const int _pageSize = 20;
  int _currentPage = 0; // 0-based
  int _totalCount = 0;
  List<Question> _pagedQuestions = [];
  bool _isLoadingQuestions = false;

  // Search state
  final _searchController = TextEditingController();
  String _searchKeyword = '';
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    // If a table is already selected, load its questions
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = context.read<AppState>();
      if (app.selectedTableName != null) {
        _loadQuestions();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  int get _totalPages {
    if (_totalCount == 0) return 1;
    return (_totalCount / _pageSize).ceil();
  }

  Future<void> _loadQuestions() async {
    final app = context.read<AppState>();
    final tableName = app.selectedTableName;
    if (tableName == null) return;

    setState(() => _isLoadingQuestions = true);

    try {
      final count = await DatabaseService.countQuestions(
        tableName,
        keyword: _searchKeyword.isEmpty ? null : _searchKeyword,
      );
      final questions = await DatabaseService.getQuestionsPaged(
        tableName,
        page: _currentPage,
        pageSize: _pageSize,
        keyword: _searchKeyword.isEmpty ? null : _searchKeyword,
      );

      if (mounted) {
        setState(() {
          _totalCount = count;
          _pagedQuestions = questions;
          _isLoadingQuestions = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingQuestions = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载题目失败: $e')),
        );
      }
    }
  }

  Future<void> _onTableSelected(String tableName) async {
    final app = context.read<AppState>();

    setState(() {
      _currentPage = 0;
      _searchKeyword = '';
      _searchController.clear();
      _pagedQuestions = [];
      _totalCount = 0;
    });

    await app.selectTable(tableName);

    if (mounted) {
      _loadQuestions();
    }
  }

  void _onSearchSubmitted(String keyword) {
    setState(() {
      _searchKeyword = keyword.trim();
      _currentPage = 0;
    });
    _loadQuestions();
  }

  void _onSearchChanged(String keyword) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) {
        _onSearchSubmitted(keyword);
      }
    });
  }

  void _goToPage(int page) {
    if (page < 0 || page >= _totalPages) return;
    setState(() => _currentPage = page);
    _loadQuestions();
  }

  void _showDeleteTableDialog(BuildContext context, String tableName, String displayName) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final canDelete = ctrl.text.trim() == displayName;
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
                  const SizedBox(width: 8),
                  const Text('确认删除题库'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('确定要删除题库「$displayName」吗？'),
                  const SizedBox(height: 8),
                  Text(
                    '删除后该题库下所有题目将被永久移除，无法恢复。',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '请输入题库名称以确认删除：',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: ctrl,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      hintText: displayName,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.red,
                  ),
                  onPressed: canDelete
                      ? () async {
                          Navigator.pop(ctx);
                          final app = context.read<AppState>();
                          await app.deleteTable(tableName);
                          if (mounted) {
                            setState(() {
                              _pagedQuestions = [];
                              _totalCount = 0;
                              _currentPage = 0;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('题库「$displayName」已删除'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      : null,
                  child: const Text('确认删除'),
                ),
              ],
            );
          },
        );
      },
    ).then((_) => ctrl.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('题库管理'),
        backgroundColor: const Color(0xFF4A90E2),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Row(
        children: [
          // Left panel: table list (1/5)
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.2,
            child: _buildTableListPanel(app),
          ),
          // Vertical divider
          Container(width: 1, color: Colors.grey.shade200),
          // Right panel: questions (4/5)
          Expanded(
            child: _buildQuestionsPanel(app),
          ),
        ],
      ),
    );
  }

  // ==================== Left Panel: Table List ====================

  Widget _buildTableListPanel(AppState app) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.library_books_outlined, color: Color(0xFF4A90E2), size: 18),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    '题库列表',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF333333),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A90E2).withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${app.tables.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4A90E2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1),

          // Table list
          Expanded(
            child: app.tables.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.folder_off_outlined, size: 40, color: Colors.grey.shade300),
                        const SizedBox(height: 10),
                        Text(
                          '暂无题库',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    itemCount: app.tables.length,
                    itemBuilder: (ctx, i) {
                      final table = app.tables[i];
                      final tableName = table['table_name'] as String;
                      final displayName = table['display_name'] as String? ?? tableName;
                      final questionCount = table['question_count'] as int? ?? 0;
                      final isSelected = app.selectedTableName == tableName;

                      return _buildTableListItem(
                        tableName: tableName,
                        displayName: displayName,
                        questionCount: questionCount,
                        isSelected: isSelected,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableListItem({
    required String tableName,
    required String displayName,
    required int questionCount,
    required bool isSelected,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onTableSelected(tableName),
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF4A90E2).withAlpha(18) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? const Color(0xFF4A90E2) : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isSelected ? Icons.folder : Icons.folder_outlined,
                  color: isSelected ? const Color(0xFF4A90E2) : Colors.grey.shade500,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: isSelected ? const Color(0xFF4A90E2) : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$questionCount 题',
                        style: TextStyle(
                          fontSize: 11,
                          color: isSelected ? const Color(0xFF4A90E2) : Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFF4A90E2),
                    size: 16,
                  ),
                // 删除按钮
                GestureDetector(
                  onTap: () => _showDeleteTableDialog(context, tableName, displayName),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.delete_outline,
                      color: isSelected ? Colors.red.shade300 : Colors.grey.shade300,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==================== Right Panel: Questions ====================

  Widget _buildQuestionsPanel(AppState app) {
    if (app.selectedTableName == null) {
      return _buildNoTableSelected();
    }

    return Column(
      children: [
        // Search bar + info
        _buildSearchBar(app),
        const Divider(height: 1),

        // Question list
        Expanded(
          child: _isLoadingQuestions
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF4A90E2)),
                )
              : _pagedQuestions.isEmpty
                  ? _buildNoQuestions()
                  : _buildQuestionList(),
        ),

        // Pagination
        if (_totalCount > 0) _buildPagination(),
      ],
    );
  }

  Widget _buildNoTableSelected() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.touch_app_outlined, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text(
            '请在左侧选择题库',
            style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          Text(
            '从左侧列表中选择一个题库以查看题目',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(AppState app) {
    final tableName = app.selectedTableName ?? '';
    // Find the display name from tables
    final matchingTables = app.tables.where((t) => t['table_name'] == tableName).toList();
    final tableMeta = matchingTables.isNotEmpty ? matchingTables.first : null;
    final displayName = tableMeta?['display_name'] as String? ?? tableName;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.white,
      child: Row(
        children: [
          // Table info
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A90E2).withAlpha(20),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4A90E2),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '共 $_totalCount 题',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),

          // Search field
          Expanded(
            flex: 3,
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                onSubmitted: _onSearchSubmitted,
                decoration: InputDecoration(
                  hintText: '搜索题目内容或选项...',
                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                  prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey.shade400),
                  suffixIcon: _searchKeyword.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchSubmitted('');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: Color(0xFF4A90E2), width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoQuestions() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            _searchKeyword.isNotEmpty ? '没有找到匹配的题目' : '该题库暂无题目',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          ),
          if (_searchKeyword.isNotEmpty) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                _searchController.clear();
                _onSearchSubmitted('');
              },
              child: const Text('清除搜索'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuestionList() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _pagedQuestions.length,
      itemBuilder: (ctx, i) {
        final q = _pagedQuestions[i];
        return _QuestionCard(
          question: q,
        );
      },
    );
  }

  Widget _buildPagination() {
    final displayPage = _currentPage + 1; // 1-based for display

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Previous
          _paginationButton(
            label: '上一页',
            icon: Icons.chevron_left,
            enabled: _currentPage > 0,
            onTap: () => _goToPage(_currentPage - 1),
          ),
          const SizedBox(width: 16),

          // Page info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF4A90E2).withAlpha(15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '第 $displayPage / $_totalPages 页',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4A90E2),
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Next
          _paginationButton(
            label: '下一页',
            icon: Icons.chevron_right,
            iconAtEnd: true,
            enabled: _currentPage < _totalPages - 1,
            onTap: () => _goToPage(_currentPage + 1),
          ),
        ],
      ),
    );
  }

  Widget _paginationButton({
    required String label,
    required IconData icon,
    bool iconAtEnd = false,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: iconAtEnd
                ? [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        color: enabled ? const Color(0xFF4A90E2) : Colors.grey.shade400,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Icon(
                      icon,
                      size: 18,
                      color: enabled ? const Color(0xFF4A90E2) : Colors.grey.shade400,
                    ),
                  ]
                : [
                    Icon(
                      icon,
                      size: 18,
                      color: enabled ? const Color(0xFF4A90E2) : Colors.grey.shade400,
                    ),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        color: enabled ? const Color(0xFF4A90E2) : Colors.grey.shade400,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
          ),
        ),
      ),
    );
  }
}

// ==================== Question Card Widget ====================

class _QuestionCard extends StatelessWidget {
  final Question question;

  const _QuestionCard({required this.question});

  @override
  Widget build(BuildContext context) {
    final isMulti = question.type == QuestionType.multi;
    final hasDim1 = question.dim1 != null && question.dim1!.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200, width: 0.8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showQuestionDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Seq number
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isMulti
                      ? const Color(0xFFFF9800).withAlpha(20)
                      : const Color(0xFF4A90E2).withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${question.seq}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isMulti ? const Color(0xFFFF9800) : const Color(0xFF4A90E2),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: type badge + dim1 chip
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isMulti
                                ? const Color(0xFFFF9800).withAlpha(26)
                                : const Color(0xFF4A90E2).withAlpha(26),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            isMulti ? '多选' : '单选',
                            style: TextStyle(
                              fontSize: 10,
                              color: isMulti ? const Color(0xFFFF9800) : const Color(0xFF4A90E2),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (hasDim1)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4CAF50).withAlpha(20),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              question.dim1!,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF4CAF50),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Content text (truncated)
                    Text(
                      question.content,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),

                    // Options
                    _buildOptionsRow(),
                    const SizedBox(height: 8),

                    // Answer
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4CAF50).withAlpha(20),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.check_circle_outline,
                                size: 12,
                                color: Color(0xFF4CAF50),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                question.correctAnswers.join(', '),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF4CAF50),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (question.explanation != null && question.explanation!.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              question.explanation!,
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionsRow() {
    final options = question.options;
    if (options.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: options.map((o) {
        final isCorrect = question.correctAnswers.contains(o.label);
        final truncatedText = o.text.length > 30
            ? '${o.text.substring(0, 30)}...'
            : o.text;

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isCorrect
                    ? const Color(0xFF4CAF50).withAlpha(30)
                    : Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Text(
                o.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isCorrect ? const Color(0xFF4CAF50) : Colors.grey.shade600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(
                truncatedText,
                style: TextStyle(
                  fontSize: 12,
                  color: isCorrect ? const Color(0xFF4CAF50) : Colors.grey.shade700,
                  fontWeight: isCorrect ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  void _showQuestionDetail(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 80, vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: _QuestionDetailDialog(question: question),
      ),
    );
  }
}

// ==================== Question Detail Dialog ====================

class _QuestionDetailDialog extends StatelessWidget {
  final Question question;

  const _QuestionDetailDialog({required this.question});

  @override
  Widget build(BuildContext context) {
    final isMulti = question.type == QuestionType.multi;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isMulti
                      ? const Color(0xFFFF9800).withAlpha(26)
                      : const Color(0xFF4A90E2).withAlpha(26),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '第${question.seq}题 ${isMulti ? "多选" : "单选"}',
                  style: TextStyle(
                    fontSize: 13,
                    color: isMulti ? const Color(0xFFFF9800) : const Color(0xFF4A90E2),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              if (question.dim1 != null && question.dim1!.isNotEmpty)
                _detailDimChip(question.dim1!, const Color(0xFF4CAF50)),
              if (question.dim2 != null && question.dim2!.isNotEmpty) ...[
                const SizedBox(width: 4),
                _detailDimChip(question.dim2!, const Color(0xFFFF9800)),
              ],
              if (question.dim3 != null && question.dim3!.isNotEmpty) ...[
                const SizedBox(width: 4),
                _detailDimChip(question.dim3!, const Color(0xFF9C27B0)),
              ],
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const Divider(height: 20),

          // Content
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    question.content,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, height: 1.5),
                  ),
                  const SizedBox(height: 16),

                  // Options
                  ...question.options.map((o) {
                    final isCorrect = question.correctAnswers.contains(o.label);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isCorrect
                            ? const Color(0xFF4CAF50).withAlpha(15)
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isCorrect
                              ? const Color(0xFF4CAF50).withAlpha(80)
                              : Colors.grey.shade200,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isCorrect
                                  ? const Color(0xFF4CAF50)
                                  : Colors.grey.shade300,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              o.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isCorrect ? Colors.white : Colors.grey.shade700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              o.text,
                              style: TextStyle(
                                fontSize: 14,
                                color: isCorrect ? const Color(0xFF2E7D32) : Colors.black87,
                                fontWeight: isCorrect ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (isCorrect)
                            const Icon(Icons.check, color: Color(0xFF4CAF50), size: 18),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 12),

                  // Answer
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 18),
                        const SizedBox(width: 8),
                        const Text(
                          '正确答案: ',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
                        Text(
                          question.correctAnswers.join(', '),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF4CAF50),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Explanation
                  if (question.explanation != null && question.explanation!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.lightbulb_outline, color: Color(0xFFF9A825), size: 16),
                              SizedBox(width: 6),
                              Text(
                                '解析',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFF57F17),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            question.explanation!,
                            style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailDimChip(String tag, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        tag,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }
}
