import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/test_session.dart';
import '../models/question.dart';

class SelectionScreen extends StatefulWidget {
  const SelectionScreen({super.key});

  @override
  State<SelectionScreen> createState() => _SelectionScreenState();
}

class _SelectionScreenState extends State<SelectionScreen> {
  int? _selectedSessionId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().refreshTestSessions();
    });
  }

  // ======================== Dialog: Create New Test ========================

  void _showCreateTestDialog() {
    final app = context.read<AppState>();
    if (app.tables.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先导入题库')),
      );
      return;
    }

    final titleCtrl = TextEditingController();
    String? selectedTable = app.tables.first['table_name'] as String?;
    final countCtrl = TextEditingController(text: '10');
    final durationCtrl = TextEditingController(text: '30');

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final count = int.tryParse(countCtrl.text) ?? 0;
            final duration = int.tryParse(durationCtrl.text) ?? 0;
            final perQuestion = count > 0 && duration > 0
                ? (duration * 60 / count).toStringAsFixed(1)
                : '--';

            return AlertDialog(
              title: const Text('新建测试'),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: '测试标题',
                        hintText: '例如：第一次模拟考试',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: selectedTable,
                      decoration: const InputDecoration(
                        labelText: '选择题库',
                        border: OutlineInputBorder(),
                      ),
                      items: app.tables.map<DropdownMenuItem<String>>((t) {
                        return DropdownMenuItem(
                          value: t['table_name'] as String,
                          child: Text(
                            '${t['display_name']} (${t['question_count']}题)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (v) => setDialogState(() => selectedTable = v),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: countCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(
                              labelText: '题目数量',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setDialogState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: durationCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(
                              labelText: '时长（分钟）',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setDialogState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A90E2).withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.timer_outlined, size: 16, color: Color(0xFF4A90E2)),
                          const SizedBox(width: 6),
                          Text(
                            '每题时长: $perQuestion 秒',
                            style: const TextStyle(
                              color: Color(0xFF4A90E2),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4A90E2),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final title = titleCtrl.text.trim();
                    if (title.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('请输入测试标题')),
                      );
                      return;
                    }
                    if (selectedTable == null) return;
                    final qCount = int.tryParse(countCtrl.text) ?? 0;
                    final dur = int.tryParse(durationCtrl.text) ?? 0;
                    if (qCount <= 0 || dur <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('题目数量和时长必须大于0')),
                      );
                      return;
                    }
                    Navigator.pop(ctx);
                    final id = await app.createTestSession(
                      title,
                      selectedTable!,
                      qCount,
                      dur * 60,
                    );
                    setState(() => _selectedSessionId = id);
                  },
                  child: const Text('创建'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ======================== Dialog: Delete Confirmation ========================

  void _showDeleteDialog(TestSession session) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('确认删除'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('请输入测试标题「${session.title}」以确认删除：'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ctrl,
                    decoration: const InputDecoration(
                      hintText: '输入测试标题',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: ctrl.text.trim() == session.title
                      ? () async {
                          Navigator.pop(ctx);
                          await context.read<AppState>().deleteTest(session.id!);
                          if (_selectedSessionId == session.id) {
                            setState(() => _selectedSessionId = null);
                          }
                        }
                      : null,
                  child: const Text('删除'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ======================== Helpers ========================

  Color _statusColor(TestSession s) {
    if (s.isAborted) return Colors.red;
    if (s.isPendingSelection) return Colors.orange;
    if (s.isPendingSubmit) return const Color(0xFF4A90E2);
    if (s.isGraded) return const Color(0xFF4CAF50);
    return Colors.grey;
  }

  IconData _statusIcon(TestSession s) {
    if (s.isAborted) return Icons.cancel_outlined;
    if (s.isPendingSelection) return Icons.edit_note;
    if (s.isPendingSubmit) return Icons.pending_actions;
    if (s.isGraded) return Icons.verified;
    return Icons.article_outlined;
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0 && s > 0) return '${m}分${s}秒';
    if (m > 0) return '${m}分钟';
    return '${s}秒';
  }

  // ======================== Build ========================

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final sessions = app.testSessions;
    final selectedSession = sessions.where((s) => s.id == _selectedSessionId).firstOrNull;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Row(
          children: [
            // Left Panel
            SizedBox(
              width: MediaQuery.of(context).size.width * 0.2,
              child: _buildLeftPanel(app, sessions),
            ),
            // Divider
            Container(width: 1, color: Colors.grey.shade300),
            // Right Panel
            Expanded(
              child: _buildRightPanel(app, selectedSession),
            ),
          ],
        ),
      ),
    );
  }

  // ======================== Left Panel ========================

  Widget _buildLeftPanel(AppState app, List<TestSession> sessions) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF4A90E2), Color(0xFF6C5CE7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.assignment_outlined, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '测试管理',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // New test button
          Padding(
            padding: const EdgeInsets.all(10),
            child: SizedBox(
              width: double.infinity,
              height: 40,
              child: ElevatedButton.icon(
                onPressed: _showCreateTestDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建测试', style: TextStyle(fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A90E2),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 2,
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          // Session list
          Expanded(
            child: sessions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inbox_outlined, size: 40, color: Colors.grey.shade300),
                        const SizedBox(height: 8),
                        const Text('暂无测试', style: TextStyle(color: Colors.grey, fontSize: 13)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    itemCount: sessions.length,
                    itemBuilder: (ctx, i) {
                      final s = sessions[i];
                      final isSelected = s.id == _selectedSessionId;
                      return _SessionListItem(
                        session: s,
                        isSelected: isSelected,
                        statusColor: _statusColor(s),
                        statusIcon: _statusIcon(s),
                        onTap: () => setState(() => _selectedSessionId = s.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ======================== Right Panel ========================

  Widget _buildRightPanel(AppState app, TestSession? session) {
    if (session == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              '从左侧选择一个测试查看详情',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 8),
            Text(
              '或点击「新建测试」创建',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade300),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildSessionHeader(session),
        const Divider(height: 1),
        if (session.isPendingSelection)
          Expanded(
            flex: 0,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.55,
              ),
              child: SingleChildScrollView(
                child: _buildSessionActions(app, session),
              ),
            ),
          )
        else
          _buildSessionActions(app, session),
        const Divider(height: 1),
        Expanded(child: _buildQuestionList(app, session)),
      ],
    );
  }

  Widget _buildSessionHeader(TestSession session) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      session.title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _statusColor(session).withAlpha(26),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        session.statusLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: _statusColor(session),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _headerInfo(Icons.quiz_outlined, '${session.questionCount} 题'),
                    const SizedBox(width: 16),
                    _headerInfo(Icons.timer_outlined, _formatDuration(session.durationSeconds)),
                    const SizedBox(width: 16),
                    _headerInfo(Icons.table_chart_outlined, session.tableName),
                    if (session.isGraded) ...[
                      const SizedBox(width: 16),
                      _headerInfo(
                        Icons.star_outline,
                        '${session.totalScore}/${session.questionCount}',
                        color: const Color(0xFF4CAF50),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // 删除按钮（所有状态均显示）
          IconButton(
            icon: Icon(Icons.delete_outline, size: 20, color: Colors.grey.shade400),
            tooltip: '删除测试',
            onPressed: () => _showDeleteDialog(session),
          ),
        ],
      ),
    );
  }

  Widget _headerInfo(IconData icon, String text, {Color? color}) {
    final c = color ?? Colors.grey;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: c),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, color: c)),
      ],
    );
  }

  // ======================== Status-Specific Actions ========================

  Widget _buildSessionActions(AppState app, TestSession session) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: Colors.white,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (session.isPendingSelection)
            Expanded(
              child: _PendingSelectionActions(
                session: session,
                app: app,
                onSelected: () => setState(() {}),
              ),
            ),
          if (session.isPendingSubmit)
            _PendingSubmitActions(
              session: session,
              app: app,
              onSubmitted: () => setState(() {}),
            ),
          if (session.isCompleted && !session.isGraded)
            Expanded(
              child: _CompletedActions(
                session: session,
                onDelete: () => _showDeleteDialog(session),
              ),
            ),
          if (session.isGraded)
            Expanded(
              child: _GradedInfo(
                session: session,
                onDelete: () => _showDeleteDialog(session),
              ),
            ),
          if (session.isAborted)
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.red.withAlpha(15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.withAlpha(60)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.cancel_outlined, size: 16, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '该测试已中止，未进行批阅',
                              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () => _showDeleteDialog(session),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('删除'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ======================== Question List for Session ========================

  Widget _buildQuestionList(AppState app, TestSession session) {
    // For pending_submit and completed, show the active questions
    if (!session.isPendingSelection) {
      final questions = app.activeQuestions;
      final answers = app.activeAnswers;

      if (questions.isEmpty) {
        return _buildEmptyQuestionState(session);
      }

      return ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: questions.length,
        itemBuilder: (ctx, i) {
          final q = questions[i];
          final answer = answers.where((a) => a.questionId == q.id).firstOrNull;
          return _QuestionEntryCard(
            question: q,
            index: i + 1,
            answer: answer,
            showResult: session.isGraded,
          );
        },
      );
    }

    // For pending_selection, show a placeholder
    return _buildEmptyQuestionState(session);
  }

  Widget _buildEmptyQuestionState(TestSession session) {
    String message;
    IconData icon;
    if (session.isPendingSelection) {
      message = '点击上方「选题」按钮为该测试选择题目';
      icon = Icons.library_add_outlined;
    } else {
      message = '暂无题目数据';
      icon = Icons.quiz_outlined;
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
        ],
      ),
    );
  }
}

// ======================== Session List Item ========================

class _SessionListItem extends StatelessWidget {
  final TestSession session;
  final bool isSelected;
  final Color statusColor;
  final IconData statusIcon;
  final VoidCallback onTap;

  const _SessionListItem({
    required this.session,
    required this.isSelected,
    required this.statusColor,
    required this.statusIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF4A90E2).withAlpha(20) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(color: const Color(0xFF4A90E2).withAlpha(80))
              : null,
        ),
        child: Row(
          children: [
            Icon(statusIcon, size: 16, color: statusColor),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? const Color(0xFF4A90E2) : Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${session.questionCount}题 · ${session.statusLabel}',
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected ? const Color(0xFF4A90E2).withAlpha(180) : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================== Pending Selection Actions ========================

class _PendingSelectionActions extends StatefulWidget {
  final TestSession session;
  final AppState app;
  final VoidCallback onSelected;

  const _PendingSelectionActions({
    required this.session,
    required this.app,
    required this.onSelected,
  });

  @override
  State<_PendingSelectionActions> createState() => _PendingSelectionActionsState();
}

class _PendingSelectionActionsState extends State<_PendingSelectionActions> {
  // 选题模式: 0=自动随机, 1=按维度选题(指定数量)
  int _mode = 0;
  // 选中的维度列: dim1/dim2/dim3
  String _selectedDim = 'dim1';
  // 维度取值及其题目数
  Map<String, int> _dimValueCounts = {};
  // 用户为每个分类设定的选题数
  final Map<String, int> _userCounts = {};
  // 是否正在加载维度数据
  bool _isLoadingDims = false;
  // 是否正在选题
  bool _isSelecting = false;
  // 选题进度
  double _progress = 0.0;
  String _progressMessage = '';

  @override
  void initState() {
    super.initState();
    _loadDimCounts();
  }

  Future<void> _loadDimCounts() async {
    setState(() => _isLoadingDims = true);
    try {
      // 确保题库表已加载
      final app = widget.app;
      if (app.selectedTableName != widget.session.tableName) {
        await app.selectTable(widget.session.tableName);
      }
      final counts = await widget.app.getDimValueCounts(
        widget.session.tableName, _selectedDim,
      );
      if (mounted) {
        setState(() {
          _dimValueCounts = counts;
          _isLoadingDims = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingDims = false);
    }
  }

  Future<void> _onDimChanged(String dim) async {
    setState(() {
      _selectedDim = dim;
      _userCounts.clear();
    });
    await _loadDimCounts();
  }

  int get _targetCount => widget.session.questionCount;

  /// 所有非末尾项的用户分配总量
  int get _userTotalEditable {
    final entries = _dimValueCounts.entries.toList();
    if (entries.isEmpty) return 0;
    final lastLabel = entries.last.key;
    int sum = 0;
    for (final entry in _userCounts.entries) {
      if (entry.key != lastLabel) sum += entry.value;
    }
    return sum;
  }

  /// 末尾项的自动计算值 = 目标数 - 用户已分配数，再 clamp 到 [0, 末尾项可用数]
  int get _autoCalcCount {
    final entries = _dimValueCounts.entries.toList();
    if (entries.isEmpty) return 0;
    final lastAvailable = entries.last.value;
    final remaining = _targetCount - _userTotalEditable;
    return remaining.clamp(0, lastAvailable);
  }

  /// 所有项（含末尾自动项）的总分配数
  int get _totalAll => _userTotalEditable + _autoCalcCount;

  Future<void> _doSelect() async {
    setState(() {
      _isSelecting = true;
      _progress = 0.0;
      _progressMessage = '正在准备选题...';
    });

    // 设置进度回调
    widget.app.onSelectionProgress = (progress, message) {
      if (mounted) {
        setState(() {
          _progress = progress;
          _progressMessage = message;
        });
      }
    };

    try {
      if (_mode == 0) {
        // 自动随机选题（均匀散点）
        await widget.app.selectQuestions(
          widget.session.id!,
          useUniform: true,
        );
      } else {
        // 按维度指定数量选题
        final dimCounts = <String, int>{};
        // 加入用户手动设定的非末尾项
        for (final entry in _userCounts.entries) {
          if (entry.value > 0) dimCounts[entry.key] = entry.value;
        }
        // 加入末尾自动计算项
        final entries = _dimValueCounts.entries.toList();
        if (entries.isNotEmpty && _autoCalcCount > 0) {
          dimCounts[entries.last.key] = _autoCalcCount;
        }
        await widget.app.selectQuestions(
          widget.session.id!,
          dimCounts: dimCounts,
          dimColumn: _selectedDim,
        );
      }
      widget.onSelected();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选题失败: $e')),
        );
      }
    } finally {
      widget.app.onSelectionProgress = null;
      if (mounted) setState(() => _isSelecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasDims = _dimValueCounts.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 选题模式选择
        _buildModeSelector(),
        const SizedBox(height: 12),

        // 维度选题配置
        if (_mode == 1 && hasDims) ...[
          _buildDimConfig(),
          const SizedBox(height: 12),
        ],

        // 选题按钮和进度条
        _buildSelectButton(),

        // 进度条
        if (_isSelecting) ...[
          const SizedBox(height: 12),
          _buildProgressBar(),
        ],
      ],
    );
  }

  Widget _buildModeSelector() {
    return Row(
      children: [
        _modeChip(Icons.shuffle, '自动随机选题', _mode == 0),
        const SizedBox(width: 8),
        _modeChip(Icons.category, '按维度选题', _mode == 1),
      ],
    );
  }

  Widget _modeChip(IconData icon, String label, bool selected) {
    return GestureDetector(
      onTap: _isSelecting ? null : () => setState(() => _mode = selected ? _mode : (label == '自动随机选题' ? 0 : 1)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF4A90E2) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFF4A90E2) : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? Colors.white : Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: selected ? Colors.white : Colors.grey.shade700,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDimConfig() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 维度选择下拉（固定）
          Row(
            children: [
              Text(
                '选择维度: ',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey.shade700),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<String>(
                  value: _selectedDim,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'dim1', child: Text('维度1 (dim1)')),
                    DropdownMenuItem(value: 'dim2', child: Text('维度2 (dim2)')),
                    DropdownMenuItem(value: 'dim3', child: Text('维度3 (dim3)')),
                  ],
                  onChanged: _isSelecting ? null : (v) => _onDimChanged(v!),
                ),
              ),
              if (_isLoadingDims)
                const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // 已分配统计（固定，不随分类列表滚动）
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.pie_chart_outline,
                  size: 16,
                  color: _totalAll == _targetCount ? const Color(0xFF4CAF50) : Colors.orange,
                ),
                const SizedBox(width: 8),
                Text(
                  '题目分配',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _totalAll == _targetCount
                        ? const Color(0xFF4CAF50).withAlpha(26)
                        : Colors.orange.withAlpha(26),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '已分配 $_totalAll / $_targetCount',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _totalAll == _targetCount
                          ? const Color(0xFF4CAF50) : Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // 分类列表（可滚动区域）
          if (_dimValueCounts.isEmpty && !_isLoadingDims)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '该维度暂无分类数据',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.25,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _buildDimCategoryRows(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildDimCategoryRows() {
    final entries = _dimValueCounts.entries.toList();
    final rows = <Widget>[];
    // 是否还有余量允许用户增加（非末尾项）
    final canIncrease = _userTotalEditable < _targetCount;

    for (int i = 0; i < entries.length; i++) {
      final label = entries[i].key;
      final available = entries[i].value;
      final isLast = i == entries.length - 1;
      final currentCount = _userCounts[label] ?? 0;

      // 末尾项：纯展示自动计算值，不存入 _userCounts
      final isAutoCalc = isLast;
      final displayCount = isAutoCalc ? _autoCalcCount : currentCount;

      rows.add(
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isAutoCalc ? Colors.grey.shade300 : Colors.grey.shade200,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isAutoCalc ? Colors.grey.shade600 : Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '(共$available题)',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isAutoCalc) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$displayCount',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: displayCount > 0 ? const Color(0xFF4A90E2) : Colors.grey.shade400,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '(自动)',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ] else ...[
                _miniButton(Icons.remove, currentCount > 0 ? () {
                  setState(() {
                    _userCounts[label] = currentCount - 1;
                    if (_userCounts[label] == 0) _userCounts.remove(label);
                  });
                } : null),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '$currentCount',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
                _miniButton(Icons.add, currentCount < available && canIncrease ? () {
                  setState(() => _userCounts[label] = currentCount + 1);
                } : null),
              ],
            ],
          ),
        ),
      );
    }
    return rows;
  }

  Widget _miniButton(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: onTap != null ? const Color(0xFF4A90E2).withAlpha(30) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 16, color: onTap != null ? const Color(0xFF4A90E2) : Colors.grey.shade300),
      ),
    );
  }

  Widget _buildSelectButton() {
    return ElevatedButton.icon(
      onPressed: _isSelecting ? null : _doSelect,
      icon: _isSelecting
          ? const SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.auto_fix_high, size: 18),
      label: Text(_isSelecting ? '选题中...' : '开始选题'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF4A90E2),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    );
  }

  Widget _buildProgressBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: _progress,
            minHeight: 8,
            backgroundColor: Colors.grey.shade200,
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4A90E2)),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              '${(_progress * 100).toInt()}%',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4A90E2),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _progressMessage,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ======================== Pending Submit Actions ========================

class _PendingSubmitActions extends StatelessWidget {
  final TestSession session;
  final AppState app;
  final VoidCallback onSubmitted;

  const _PendingSubmitActions({
    required this.session,
    required this.app,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final questions = app.activeQuestions;
    return Expanded(
      child: Row(
        children: [
          ElevatedButton.icon(
            onPressed: () async {
              await app.submitTest(session.id!);
              onSubmitted();
            },
            icon: const Icon(Icons.send, size: 18),
            label: const Text('提交测试'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF4A90E2).withAlpha(20),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '已选 ${questions.length} 道题',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF4A90E2),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (questions.isNotEmpty)
            Expanded(
              child: Text(
                '题号: ${questions.map((q) => q.seq).join(", ")}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

// ======================== Completed Actions ========================

class _CompletedActions extends StatelessWidget {
  final TestSession session;
  final VoidCallback onDelete;

  const _CompletedActions({
    required this.session,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('删除测试'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red,
            side: const BorderSide(color: Colors.red),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
        ),
      ],
    );
  }
}

// ======================== Graded Info ========================

class _GradedInfo extends StatelessWidget {
  final TestSession session;
  final VoidCallback onDelete;

  const _GradedInfo({required this.session, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final score = session.totalScore ?? 0;
    final total = session.questionCount;
    final pct = total > 0 ? (score / total * 100).round() : 0;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: pct >= 60 ? const Color(0xFF4CAF50).withAlpha(26) : Colors.red.withAlpha(26),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                pct >= 60 ? Icons.emoji_events_outlined : Icons.sentiment_dissatisfied_outlined,
                size: 16,
                color: pct >= 60 ? const Color(0xFF4CAF50) : Colors.red,
              ),
              const SizedBox(width: 6),
              Text(
                '得分: $score/$total ($pct%)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: pct >= 60 ? const Color(0xFF4CAF50) : Colors.red,
                ),
              ),
            ],
          ),
        ),
        if (session.timeSpentSeconds != null) ...[
          const SizedBox(width: 12),
          Text(
            '用时: ${_fmtDur(session.timeSpentSeconds!)}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
        const Spacer(),
        OutlinedButton.icon(
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline, size: 16),
          label: const Text('删除'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.grey,
            side: BorderSide(color: Colors.grey.shade300),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            textStyle: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }

  String _fmtDur(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return m > 0 ? '${m}分${sec}秒' : '${sec}秒';
  }
}

// ======================== Question Entry Card ========================

class _QuestionEntryCard extends StatelessWidget {
  final Question question;
  final int index;
  final TestAnswer? answer;
  final bool showResult;

  const _QuestionEntryCard({
    required this.question,
    required this.index,
    this.answer,
    this.showResult = false,
  });

  @override
  Widget build(BuildContext context) {
    final isMulti = question.type == QuestionType.multi;
    final isCorrect = showResult && answer?.isCorrect == true;
    final isWrong = showResult && answer?.isCorrect == false;

    Color borderColor = Colors.grey.shade200;
    Color? leftBarColor;
    if (isCorrect) {
      borderColor = const Color(0xFF4CAF50).withAlpha(80);
      leftBarColor = const Color(0xFF4CAF50);
    } else if (isWrong) {
      borderColor = Colors.red.withAlpha(80);
      leftBarColor = Colors.red;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: borderColor),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Left color bar
            if (leftBarColor != null)
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: leftBarColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(10),
                    bottomLeft: Radius.circular(10),
                  ),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // Seq number
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isMulti
                            ? Colors.orange.withAlpha(26)
                            : const Color(0xFF4A90E2).withAlpha(26),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          '${question.seq}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isMulti ? Colors.orange : const Color(0xFF4A90E2),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Dim1 tag
                    if (question.dim1 != null && question.dim1!.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50).withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          question.dim1!,
                          style: const TextStyle(fontSize: 10, color: Color(0xFF4CAF50)),
                        ),
                      ),
                    // Content
                    Expanded(
                      child: Text(
                        question.content,
                        style: const TextStyle(fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Result icon
                    if (showResult && answer != null) ...[
                      const SizedBox(width: 8),
                      if (isCorrect)
                        const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 18)
                      else if (isWrong)
                        const Icon(Icons.cancel, color: Colors.red, size: 18)
                      else
                        const Icon(Icons.help_outline, color: Colors.grey, size: 18),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
