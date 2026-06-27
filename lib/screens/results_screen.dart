import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/test_session.dart';
import '../models/question.dart';
import '../services/database_service.dart';

/// 成绩报告页面 — 展示已批阅测试历史 + 逐题详情
class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  // 当前查看详情的测试会话，null 表示在列表页
  TestSession? _detailSession;

  // 加载状态
  bool _loadingDetail = false;
  List<Question> _detailQuestions = [];
  List<TestAnswer> _detailAnswers = [];

  // 展开的题目索引集合
  final Set<int> _expandedQuestionIds = {};

  // 正在批阅中的 testId 集合
  final Set<int> _gradingIds = {};

  @override
  void dispose() {
    _expandedQuestionIds.clear();
    _gradingIds.clear();
    super.dispose();
  }

  // ==================== 加载详情 ====================

  Future<void> _loadDetail(TestSession session) async {
    setState(() {
      _loadingDetail = true;
      _detailSession = session;
      _expandedQuestionIds.clear();
    });

    try {
      final answers = await DatabaseService.getTestAnswers(session.id!);
      final questions = await DatabaseService.getAllQuestions(session.tableName);
      if (mounted) {
        setState(() {
          _detailAnswers = answers;
          _detailQuestions = questions;
          _loadingDetail = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingDetail = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载详情失败: $e')),
        );
      }
    }
  }

  void _backToList() {
    setState(() {
      _detailSession = null;
      _detailQuestions = [];
      _detailAnswers = [];
      _expandedQuestionIds.clear();
    });
  }

  // ==================== 批阅 ====================

  Future<void> _triggerGrade(TestSession session) async {
    if (session.id == null) return;
    setState(() => _gradingIds.add(session.id!));

    final app = context.read<AppState>();
    await app.gradeTest(session.id!);

    if (mounted) {
      setState(() => _gradingIds.remove(session.id));
    }
  }

  // ==================== 构建 ====================

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, app, _) {
        if (_detailSession != null) {
          return _buildDetailView(context, app);
        }
        return _buildListView(context, app);
      },
    );
  }

  // ==================== 列表视图 ====================

  Widget _buildListView(BuildContext context, AppState app) {
    // 筛选：status='completed' 的会话
    final completedSessions = app.testSessions
        .where((s) => s.status == 'completed')
        .toList();

    final gradedCount = completedSessions.where((s) => s.totalScore != null).length;
    final pendingCount = completedSessions.where((s) => s.totalScore == null).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Column(
        children: [
          _buildListHeader(context, gradedCount, pendingCount),
          Expanded(
            child: completedSessions.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    onRefresh: () => app.refreshTestSessions(),
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                      itemCount: completedSessions.length,
                      itemBuilder: (ctx, i) {
                        final session = completedSessions[i];
                        return _buildSessionCard(context, app, session);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildListHeader(BuildContext context, int gradedCount, int pendingCount) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF4A90E2), Color(0xFF6C5CE7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.assessment_outlined, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '成绩报告',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '查看测试结果与答题详情',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(51),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$gradedCount 已批阅',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (pendingCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(102),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$pendingCount 待批阅',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSessionCard(BuildContext context, AppState app, TestSession session) {
    final isGraded = session.totalScore != null;
    final isGrading = _gradingIds.contains(session.id);

    return GestureDetector(
      onTap: () {
        if (isGraded) {
          _loadDetail(session);
        } else if (!isGrading) {
          _triggerGrade(session);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(13),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // 左侧图标
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isGraded
                    ? _scoreColor(session.totalScore!, session.questionCount).withAlpha(26)
                    : Colors.orange.withAlpha(26),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isGraded ? Icons.verified : Icons.hourglass_top,
                color: isGraded
                    ? _scoreColor(session.totalScore!, session.questionCount)
                    : Colors.orange,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            // 中间信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 13, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Text(
                        _formatDate(session.createdAt),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.access_time, size: 13, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Text(
                        _formatDurationSeconds(session.timeSpentSeconds ?? session.durationSeconds),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 右侧分数 / 批阅状态
            if (isGraded) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${session.totalScore}/${session.questionCount}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _scoreColor(session.totalScore!, session.questionCount),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${((session.totalScore! / session.questionCount) * 100).round()}%',
                    style: TextStyle(
                      fontSize: 11,
                      color: _scoreColor(session.totalScore!, session.questionCount),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ] else if (isGrading) ...[
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              const Text('批阅中...', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ] else ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha(26),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withAlpha(128)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.touch_app, size: 14, color: Colors.orange),
                    SizedBox(width: 4),
                    Text(
                      '点击批阅',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bar_chart_outlined, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text(
            '暂无测试记录',
            style: TextStyle(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            '完成一次测试后，成绩将在此展示',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  // ==================== 详情视图 ====================

  Widget _buildDetailView(BuildContext context, AppState app) {
    final session = _detailSession!;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Column(
        children: [
          _buildDetailHeader(context, session),
          Expanded(
            child: _loadingDetail
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('加载答题数据...', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : _buildQuestionList(session),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailHeader(BuildContext context, TestSession session) {
    final score = session.totalScore ?? 0;
    final total = session.questionCount;
    final percent = total > 0 ? (score / total * 100).round() : 0;
    final color = _scoreColor(score, total);

    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 20,
        right: 20,
        bottom: 20,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withAlpha(204)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _backToList,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(51),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 18),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  session.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(51),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _gradeLabel(percent),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _headerStat('$score/$total', '总分', Colors.white),
              _headerDivider(),
              _headerStat('$percent%', '正确率', Colors.white),
              _headerDivider(),
              _headerStat(
                _formatDurationSeconds(session.timeSpentSeconds ?? session.durationSeconds),
                '用时',
                Colors.white,
              ),
              _headerDivider(),
              _headerStat('$total', '题数', Colors.white),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerStat(String value, String label, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: color.withAlpha(180)),
        ),
      ],
    );
  }

  Widget _headerDivider() {
    return Container(width: 1, height: 36, color: Colors.white24);
  }

  Widget _buildQuestionList(TestSession session) {
    if (_detailAnswers.isEmpty && _detailQuestions.isEmpty) {
      return const Center(
        child: Text('暂无答题数据', style: TextStyle(color: Colors.grey)),
      );
    }

    // 按 questionId 建立 Question 映射
    final questionMap = <int, Question>{};
    for (final q in _detailQuestions) {
      if (q.id != null) questionMap[q.id!] = q;
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _detailAnswers.length,
      itemBuilder: (ctx, i) {
        final answer = _detailAnswers[i];
        final question = questionMap[answer.questionId];
        final isExpanded = _expandedQuestionIds.contains(answer.questionId);

        return _buildQuestionItem(answer, question, isExpanded);
      },
    );
  }

  Widget _buildQuestionItem(TestAnswer answer, Question? question, bool isExpanded) {
    final isCorrect = answer.isCorrect == true;
    final isWrong = answer.isCorrect == false;
    final isUnanswered = !answer.isAnswered;

    Color borderColor;
    Color iconColor;
    IconData iconData;

    if (isUnanswered) {
      borderColor = Colors.grey.shade300;
      iconColor = Colors.grey;
      iconData = Icons.help_outline;
    } else if (isCorrect) {
      borderColor = const Color(0xFF4CAF50).withAlpha(128);
      iconColor = const Color(0xFF4CAF50);
      iconData = Icons.check_circle;
    } else {
      borderColor = Colors.redAccent.withAlpha(128);
      iconColor = Colors.redAccent;
      iconData = Icons.cancel;
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isExpanded) {
            _expandedQuestionIds.remove(answer.questionId);
          } else {
            _expandedQuestionIds.add(answer.questionId);
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: isExpanded ? 1.5 : 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isExpanded ? 18 : 8),
              blurRadius: isExpanded ? 12 : 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            // 标题行
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(iconData, color: iconColor, size: 22),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4A90E2).withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '第${answer.questionSeq}题',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF4A90E2),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      question?.content ?? '题目 #${answer.questionId}',
                      style: const TextStyle(fontSize: 13, color: Colors.black87),
                      maxLines: isExpanded ? null : 1,
                      overflow: isExpanded ? null : TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isCorrect
                          ? const Color(0xFF4CAF50).withAlpha(26)
                          : isWrong
                              ? Colors.redAccent.withAlpha(26)
                              : Colors.grey.withAlpha(26),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      isUnanswered ? '未答' : '${answer.score}分',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isCorrect
                            ? const Color(0xFF4CAF50)
                            : isWrong
                                ? Colors.redAccent
                                : Colors.grey,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.grey.shade400,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
            // 展开详情
            if (isExpanded && question != null)
              _buildExpandedDetail(answer, question),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedDetail(TestAnswer answer, Question question) {
    final userSelected = answer.selectedList;
    final correctAnswers = question.correctAnswers;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 12),
          // 完整题干
          Text(
            question.content,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          // 题型标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: question.type == QuestionType.multi
                  ? Colors.orange.withAlpha(26)
                  : const Color(0xFF4A90E2).withAlpha(26),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              question.type == QuestionType.multi ? '多选题' : '单选题',
              style: TextStyle(
                fontSize: 11,
                color: question.type == QuestionType.multi
                    ? Colors.orange
                    : const Color(0xFF4A90E2),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 选项列表
          ...question.options.map((opt) {
            final isCorrectOpt = correctAnswers.contains(opt.label);
            final isUserSelected = userSelected.contains(opt.label);
            final isWrongSelection = isUserSelected && !isCorrectOpt;

            Color bgColor;
            Color textColor;
            IconData? trailingIcon;
            Color? trailingColor;

            if (isCorrectOpt) {
              bgColor = const Color(0xFF4CAF50).withAlpha(20);
              textColor = const Color(0xFF4CAF50);
              trailingIcon = Icons.check;
              trailingColor = const Color(0xFF4CAF50);
            } else if (isWrongSelection) {
              bgColor = Colors.redAccent.withAlpha(20);
              textColor = Colors.redAccent;
              trailingIcon = Icons.close;
              trailingColor = Colors.redAccent;
            } else {
              bgColor = Colors.grey.withAlpha(8);
              textColor = Colors.grey.shade700;
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
                border: isCorrectOpt
                    ? Border.all(color: const Color(0xFF4CAF50).withAlpha(100))
                    : isWrongSelection
                        ? Border.all(color: Colors.redAccent.withAlpha(100))
                        : null,
              ),
              child: Row(
                children: [
                  Text(
                    '${opt.label}.',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      opt.text,
                      style: TextStyle(fontSize: 13, color: textColor),
                    ),
                  ),
                  if (trailingIcon != null)
                    Icon(trailingIcon, size: 18, color: trailingColor),
                ],
              ),
            );
          }),
          const SizedBox(height: 12),
          // 用户答案 vs 正确答案
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7FA),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                    const SizedBox(width: 6),
                    const Text(
                      '我的答案: ',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    Text(
                      userSelected.isEmpty ? '未作答' : userSelected.join(', '),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: userSelected.isEmpty
                            ? Colors.grey
                            : answer.isCorrect == true
                                ? const Color(0xFF4CAF50)
                                : Colors.redAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 16,
                      color: Color(0xFF4CAF50),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      '正确答案: ',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    Text(
                      correctAnswers.join(', '),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF4CAF50),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.star_outline, size: 16, color: Colors.orange),
                    const SizedBox(width: 6),
                    const Text(
                      '得分: ',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    Text(
                      '${answer.score} 分',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: answer.score > 0
                            ? const Color(0xFF4CAF50)
                            : Colors.redAccent,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 解析
          if (question.explanation != null &&
              question.explanation!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFE082)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.lightbulb_outline,
                          size: 16, color: Color(0xFFF9A825)),
                      SizedBox(width: 6),
                      Text(
                        '解析',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFF9A825),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    question.explanation!,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade800,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==================== 工具方法 ====================

  Color _scoreColor(int score, int total) {
    if (total == 0) return Colors.grey;
    final percent = (score / total) * 100;
    if (percent >= 90) return const Color(0xFF4CAF50);
    if (percent >= 75) return const Color(0xFF2196F3);
    if (percent >= 60) return const Color(0xFFFF9800);
    return Colors.redAccent;
  }

  String _gradeLabel(int percent) {
    if (percent >= 90) return '优秀';
    if (percent >= 75) return '良好';
    if (percent >= 60) return '及格';
    return '不及格';
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatDurationSeconds(int seconds) {
    if (seconds <= 0) return '0秒';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m == 0) return '${s}秒';
    if (s == 0) return '${m}分钟';
    return '${m}分${s}秒';
  }
}
