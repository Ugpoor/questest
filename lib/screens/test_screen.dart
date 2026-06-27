import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/test_session.dart';
import '../models/question.dart';

class TestScreen extends StatefulWidget {
  const TestScreen({super.key});

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  Timer? _countdownTimer;
  int _remainingSeconds = 0;
  int _currentQuestionIndex = 0;
  final _jumpCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryResume();
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _jumpCtrl.dispose();
    super.dispose();
  }

  // ======================== Resume Support ========================

  void _tryResume() {
    final app = context.read<AppState>();
    final active = app.activeTest;
    if (active != null && active.isInProgress && !active.isTimeUp) {
      _enterTestingMode(active);
    }
  }

  void _enterTestingMode(TestSession session) {
    _remainingSeconds = session.remainingSeconds;
    _currentQuestionIndex = 0;

    // Find first unanswered question to resume position
    final answers = context.read<AppState>().activeAnswers;
    if (answers.isNotEmpty) {
      for (int i = 0; i < answers.length; i++) {
        if (!answers[i].isAnswered) {
          _currentQuestionIndex = i;
          break;
        }
      }
    }

    _startCountdown();
    setState(() {});
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _remainingSeconds--;
      });

      if (_remainingSeconds <= 0) {
        timer.cancel();
        _onTimeUp();
      }
    });
  }

  Future<void> _onTimeUp() async {
    final app = context.read<AppState>();
    final active = app.activeTest;
    if (active == null) return;

    await app.endTest(active.id!);
    if (mounted) {
      _showTimeUpDialog();
      setState(() {});
    }
  }

  void _showTimeUpDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.timer_off, color: Colors.red, size: 24),
            const SizedBox(width: 8),
            const Text('时间到'),
          ],
        ),
        content: const Text('考试时间已结束，系统已自动交卷。'),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {});
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A90E2),
              foregroundColor: Colors.white,
            ),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // ======================== Format Helpers ========================

  String _formatTime(int seconds) {
    if (seconds < 0) seconds = 0;
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
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
    final activeTest = app.activeTest;
    final isTesting = activeTest != null && activeTest.isInProgress && !activeTest.isTimeUp;

    if (isTesting) {
      return _buildTestingView(app, activeTest);
    } else {
      return _buildNonTestingView(app);
    }
  }

  // ======================== Non-Testing View ========================

  Widget _buildNonTestingView(AppState app) {
    final sessions = app.testSessions;

    // Tests ready to take: completed status, never started
    final availableTests = sessions
        .where((s) => s.isCompleted && s.startedAt == null && !s.isGraded)
        .toList();

    // Tests in progress or finished
    final activeTests = sessions.where((s) => s.startedAt != null).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: app.isLoading
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFF4A90E2)),
                    const SizedBox(height: 12),
                    Text(
                      app.loadingMessage,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              )
            : availableTests.isEmpty && activeTests.isEmpty
                ? _buildEmptyTestState()
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (availableTests.isNotEmpty) ...[
                          _sectionHeader('可参加的测试', Icons.play_circle_outline,
                              const Color(0xFF4A90E2)),
                          const SizedBox(height: 12),
                          ...availableTests.map((s) => _buildAvailableTestCard(app, s)),
                          const SizedBox(height: 24),
                        ],
                        if (activeTests.isNotEmpty) ...[
                          _sectionHeader('测试记录', Icons.history, Colors.grey),
                          const SizedBox(height: 12),
                          ...activeTests.map((s) => _buildTestRecordCard(app, s)),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildEmptyTestState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.school_outlined, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            '暂无可参加的测试',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 8),
          Text(
            '请先在「选题管理」中创建并提交测试',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade300),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  Widget _buildAvailableTestCard(AppState app, TestSession session) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4A90E2).withAlpha(15),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: const Color(0xFF4A90E2).withAlpha(40)),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4A90E2), Color(0xFF6C5CE7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.quiz, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _cardInfo(Icons.format_list_numbered, '${session.questionCount} 题'),
                    const SizedBox(width: 12),
                    _cardInfo(Icons.timer_outlined, _formatDuration(session.durationSeconds)),
                  ],
                ),
              ],
            ),
          ),
          // Start button
          ElevatedButton.icon(
            onPressed: () async {
              await app.startTest(session.id!);
              if (mounted && app.activeTest != null) {
                _enterTestingMode(app.activeTest!);
              }
            },
            icon: const Icon(Icons.play_arrow, size: 20),
            label: const Text('开始测试'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A90E2),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              elevation: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardInfo(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.grey),
        const SizedBox(width: 3),
        Text(text, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildTestRecordCard(AppState app, TestSession session) {
    final isFinished = session.endedAt != null;
    final isGraded = session.isGraded;
    final isInProgress = session.isInProgress;

    Color statusColor;
    String statusText;
    IconData statusIcon;
    if (isGraded) {
      statusColor = const Color(0xFF4CAF50);
      statusText = '已批阅 ${session.totalScore}/${session.questionCount}';
      statusIcon = Icons.verified;
    } else if (isFinished) {
      statusColor = Colors.orange;
      statusText = '批阅中';
      statusIcon = Icons.hourglass_top;
    } else if (isInProgress) {
      statusColor = const Color(0xFF4A90E2);
      statusText = '进行中';
      statusIcon = Icons.play_arrow;
    } else {
      statusColor = Colors.grey;
      statusText = session.statusLabel;
      statusIcon = Icons.article_outlined;
    }

    final canResume = isInProgress && !session.isTimeUp;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: canResume
            ? () async {
                if (app.activeTest?.id != session.id) {
                  await app.startTest(session.id!);
                }
                if (mounted && app.activeTest != null) {
                  _enterTestingMode(app.activeTest!);
                }
              }
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: canResume
                ? Border.all(color: const Color(0xFF4A90E2).withAlpha(80), width: 1.5)
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(8),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(statusIcon, color: statusColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          '${session.questionCount}题 · ${_formatDuration(session.durationSeconds)}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                        if (session.timeSpentSeconds != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            '用时 ${_formatDuration(session.timeSpentSeconds!)}',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 11,
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (canResume) ...[
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    if (app.activeTest?.id != session.id) {
                      await app.startTest(session.id!);
                    }
                    if (mounted && app.activeTest != null) {
                      _enterTestingMode(app.activeTest!);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4A90E2),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: const Text('继续'),
                ),
              ],
          if (isGraded) ...[
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () {
                // Results navigation handled by parent tab switch
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF4CAF50),
                side: const BorderSide(color: Color(0xFF4CAF50)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: const Text('查看结果'),
            ),
          ],
        ],
      ),
    ),
  ),
);
  }

  // ======================== Testing View ========================

  Widget _buildTestingView(AppState app, TestSession session) {
    final questions = app.activeQuestions;
    final answers = app.activeAnswers;

    if (questions.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFF4A90E2)),
              const SizedBox(height: 12),
              Text('加载题目中...', style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
        ),
      );
    }

    final idx = _currentQuestionIndex.clamp(0, questions.length - 1);
    final question = questions[idx];
    final answer = answers.where((a) => a.questionId == question.id).firstOrNull;
    final selectedLabels = answer?.selectedList ?? <String>[];
    final isLastQuestion = idx == questions.length - 1;
    final isLowTime = _remainingSeconds < 60;
    final answeredCount = answers.where((a) => a.isAnswered).length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _showExitConfirmDialog(session);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        body: Column(
          children: [
            // Timer bar
            _buildTimerBar(session, answeredCount, questions.length, isLowTime),
            // Main content
            Expanded(
              child: Row(
                children: [
                  // Question area
                  Expanded(
                    flex: 3,
                    child: _buildQuestionArea(
                      question,
                      selectedLabels,
                      session,
                      idx,
                      questions.length,
                    ),
                  ),
                  // Right sidebar: navigation
                  Container(
                    width: 220,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(left: BorderSide(color: Colors.grey.shade200)),
                    ),
                    child: _buildNavigationSidebar(
                      questions,
                      answers,
                      idx,
                      session,
                    ),
                  ),
                ],
              ),
            ),
            // Bottom bar
            _buildTestingBottomBar(session, idx, questions.length, isLastQuestion),
          ],
        ),
      ),
    );
  }

  // ======================== Timer Bar ========================

  Widget _buildTimerBar(TestSession session, int answeredCount, int totalCount, bool isLowTime) {
    final progress = totalCount > 0 ? answeredCount / totalCount : 0.0;
    final timeProgress = session.durationSeconds > 0
        ? (_remainingSeconds / session.durationSeconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 6,
        left: 16,
        right: 16,
        bottom: 8,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Exit button
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => _showExitConfirmDialog(session),
                tooltip: '退出测试',
              ),
              const SizedBox(width: 8),
              // Title
              Expanded(
                child: Text(
                  session.title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Progress
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF4A90E2).withAlpha(20),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '$answeredCount/$totalCount',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4A90E2),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Timer
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isLowTime ? Colors.red.withAlpha(20) : const Color(0xFF4A90E2).withAlpha(20),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.timer,
                      size: 16,
                      color: isLowTime ? Colors.red : const Color(0xFF4A90E2),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatTime(_remainingSeconds),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isLowTime ? Colors.red : const Color(0xFF4A90E2),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Progress bars
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF4A90E2)),
                    minHeight: 4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: timeProgress,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation(
                      isLowTime ? Colors.red : const Color(0xFF4CAF50),
                    ),
                    minHeight: 4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ======================== Question Area ========================

  Widget _buildQuestionArea(
    Question question,
    List<String> selectedLabels,
    TestSession session,
    int currentIndex,
    int totalCount,
  ) {
    final isMulti = question.type == QuestionType.multi;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question type badge + number
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isMulti ? Colors.orange.withAlpha(26) : const Color(0xFF4A90E2).withAlpha(26),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isMulti ? Icons.check_box : Icons.radio_button_checked,
                      size: 14,
                      color: isMulti ? Colors.orange : const Color(0xFF4A90E2),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '第${currentIndex + 1}题 ${isMulti ? "多选" : "单选"}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isMulti ? Colors.orange : const Color(0xFF4A90E2),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (question.dim1 != null && question.dim1!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    question.dim1!,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF4CAF50)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // Question content
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(10),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              question.content,
              style: const TextStyle(fontSize: 16, height: 1.6, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(height: 20),
          // Options
          ...question.options.map((opt) {
            final isSelected = selectedLabels.contains(opt.label);
            return _buildOptionTile(opt, isMulti, isSelected, question, session);
          }),
          const SizedBox(height: 16),
          // Hint for multi-choice
          if (isMulti)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withAlpha(50)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: Colors.orange),
                  const SizedBox(width: 6),
                  Text(
                    '本题为多选题，正确答案: ${question.correctAnswers.length} 个选项',
                    style: const TextStyle(fontSize: 12, color: Colors.orange),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOptionTile(
    QuestionOption opt,
    bool isMulti,
    bool isSelected,
    Question question,
    TestSession session,
  ) {
    final borderColor = isSelected ? const Color(0xFF4A90E2) : Colors.grey.shade200;
    final bgColor = isSelected ? const Color(0xFF4A90E2).withAlpha(15) : Colors.white;

    return GestureDetector(
      onTap: () => _toggleOption(opt.label, isMulti, question, session),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
        ),
        child: Row(
          children: [
            // Selection indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF4A90E2) : Colors.transparent,
                borderRadius: isMulti ? BorderRadius.circular(6) : BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? const Color(0xFF4A90E2) : Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : Center(
                      child: Text(
                        opt.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                opt.text,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: isSelected ? const Color(0xFF4A90E2) : Colors.black87,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ======================== Toggle Option & Save ========================

  void _toggleOption(String label, bool isMulti, Question question, TestSession session) {
    final app = context.read<AppState>();
    final answers = app.activeAnswers;
    final answer = answers.where((a) => a.questionId == question.id).firstOrNull;
    if (answer == null) return;

    List<String> selected = List<String>.from(answer.selectedList);

    if (isMulti) {
      if (selected.contains(label)) {
        selected.remove(label);
      } else {
        selected.add(label);
      }
    } else {
      // Single choice: tap to select, tap again to deselect
      if (selected.contains(label)) {
        selected.clear();
      } else {
        selected.clear();
        selected.add(label);
      }
    }

    selected.sort();
    final updatedAnswer = answer.copyWith(userAnswer: selected.join(','));
    app.saveAnswer(updatedAnswer);
  }

  // ======================== Navigation Sidebar ========================

  Widget _buildNavigationSidebar(
    List<Question> questions,
    List<TestAnswer> answers,
    int currentIndex,
    TestSession session,
  ) {
    return Column(
      children: [
        // Jump to question
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _jumpCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    hintText: '跳转题号',
                    hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    isDense: true,
                  ),
                  onSubmitted: (v) => _jumpToQuestion(v, questions.length),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.arrow_forward, size: 18),
                onPressed: () => _jumpToQuestion(_jumpCtrl.text, questions.length),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF4A90E2).withAlpha(20),
                ),
              ),
            ],
          ),
        ),
        // Question grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(10),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: questions.length,
            itemBuilder: (ctx, i) {
              final q = questions[i];
              final answer = answers.where((a) => a.questionId == q.id).firstOrNull;
              final isAnswered = answer?.isAnswered ?? false;
              final isCurrent = i == currentIndex;

              Color bgColor;
              Color textColor;
              if (isCurrent) {
                bgColor = const Color(0xFF4A90E2);
                textColor = Colors.white;
              } else if (isAnswered) {
                bgColor = const Color(0xFF4CAF50);
                textColor = Colors.white;
              } else {
                bgColor = Colors.grey.shade100;
                textColor = Colors.grey.shade700;
              }

              return GestureDetector(
                onTap: () => setState(() => _currentQuestionIndex = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(8),
                    border: isCurrent
                        ? Border.all(color: const Color(0xFF4A90E2), width: 2)
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isCurrent || isAnswered ? FontWeight.bold : FontWeight.normal,
                        color: textColor,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // Legend
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _legendItem(const Color(0xFF4A90E2), '当前'),
              _legendItem(const Color(0xFF4CAF50), '已答'),
              _legendItem(Colors.grey.shade300, '未答'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ],
    );
  }

  void _jumpToQuestion(String input, int totalQuestions) {
    final num = int.tryParse(input);
    if (num == null || num < 1 || num > totalQuestions) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('请输入 1-$totalQuestions 之间的题号'),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }
    setState(() {
      _currentQuestionIndex = num - 1;
      _jumpCtrl.clear();
    });
  }

  // ======================== Bottom Bar ========================

  Widget _buildTestingBottomBar(
    TestSession session,
    int currentIndex,
    int totalCount,
    bool isLastQuestion,
  ) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 6, offset: const Offset(0, -2)),
        ],
      ),
      child: Row(
        children: [
          // 终止按钮（红色）
          SizedBox(
            width: 80,
            child: OutlinedButton.icon(
              onPressed: () => _showAbortDialog(session),
              icon: const Icon(Icons.stop_circle_outlined, size: 16),
              label: const Text('终止'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Previous
          if (currentIndex > 0)
            SizedBox(
              width: 100,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _currentQuestionIndex--),
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('上一题'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontSize: 13),
                ),
              ),
            )
          else
            const SizedBox(width: 100),
          const Spacer(),
          // Question position indicator
          Text(
            '${currentIndex + 1} / $totalCount',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const Spacer(),
          // Next or Submit
          if (!isLastQuestion)
            SizedBox(
              width: 100,
              child: ElevatedButton.icon(
                onPressed: () => setState(() => _currentQuestionIndex++),
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: const Text('下一题'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A90E2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontSize: 13),
                ),
              ),
            )
          else
            SizedBox(
              width: 120,
              child: ElevatedButton.icon(
                onPressed: () => _showEarlySubmitDialog(session),
                icon: const Icon(Icons.send, size: 16),
                label: const Text('提前交卷'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  elevation: 2,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ======================== Dialogs ========================

  void _showEarlySubmitDialog(TestSession session) {
    final app = context.read<AppState>();
    final answers = app.activeAnswers;
    final unanswered = answers.where((a) => !a.isAnswered).length;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
            const SizedBox(width: 8),
            const Text('确认交卷'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (unanswered > 0) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 18, color: Colors.orange),
                    const SizedBox(width: 8),
                    Text(
                      '还有 $unanswered 道题未作答',
                      style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            const Text('确定要提前交卷吗？交卷后将自动批阅。'),
            const SizedBox(height: 8),
            Text(
              '剩余时间: ${_formatTime(_remainingSeconds)}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('继续答题'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              _countdownTimer?.cancel();
              await app.endTest(session.id!);
              if (mounted) {
                _showSubmitCompleteDialog(session);
                setState(() {});
              }
            },
            child: const Text('确认交卷'),
          ),
        ],
      ),
    );
  }

  void _showSubmitCompleteDialog(TestSession session) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: const Color(0xFF4CAF50), size: 24),
            const SizedBox(width: 8),
            const Text('交卷成功'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('测试「${session.title}」已成功提交。'),
            const SizedBox(height: 8),
            if (session.totalScore != null) ...[
              Text(
                '得分: ${session.totalScore}/${session.questionCount}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF4CAF50)),
              ),
            ] else
              const Text('系统正在批阅中...', style: TextStyle(color: Colors.grey)),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {});
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A90E2),
              foregroundColor: Colors.white,
            ),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showExitConfirmDialog(TestSession session) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认退出'),
        content: const Text('退出后答题进度将自动保存，下次可继续作答。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('继续答题'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _countdownTimer?.cancel();
              setState(() {
                _currentQuestionIndex = 0;
              });
              context.read<AppState>().exitTestView();
            },
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }

  void _showAbortDialog(TestSession session) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 24),
            const SizedBox(width: 8),
            const Text('确认终止测试'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('确定要终止测试「${session.title}」吗？'),
            const SizedBox(height: 8),
            Text(
              '终止后测试状态将标记为「已中止」，不会进行批阅。已中止的测试可以删除。',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('继续答题'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.red,
            ),
            onPressed: () async {
              Navigator.pop(ctx); // close dialog
              _countdownTimer?.cancel();
              final app = context.read<AppState>();
              await app.abortTest(session.id!);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('测试「${session.title}」已中止'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('确认终止'),
          ),
        ],
      ),
    );
  }
}
