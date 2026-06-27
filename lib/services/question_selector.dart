import '../models/question.dart';

/// 智能选题服务
/// 支持：分散序号、类别内随机、尽量覆盖类别
class QuestionSelector {

  /// 从题库中智能选题
  /// [questions] - 全部题目
  /// [targetCount] - 目标题目数量
  /// [dimensions] - 需要覆盖的维度（最多3个）
  /// [coverageRatio] - 每个维度的覆盖率（0.0-1.0）
  static List<Question> selectQuestions({
    required List<Question> questions,
    required int targetCount,
    List<String>? dimensions,
    double coverageRatio = 0.8,
  }) {
    if (questions.isEmpty) return [];
    if (targetCount >= questions.length) {
      // 全量题目，打散序号
      final shuffled = List<Question>.from(questions)..shuffle();
      return _spreadBySeq(shuffled);
    }

    final dims = dimensions ?? [];
    if (dims.isEmpty) {
      // 无维度要求：均匀分散序号
      return _spreadBySeq(List<Question>.from(questions)..shuffle())
          .take(targetCount)
          .toList();
    }

    // 有维度要求：分层抽样
    return _stratifiedSelect(
      questions: questions,
      targetCount: targetCount,
      dimensions: dims,
      coverageRatio: coverageRatio,
    );
  }

  /// 按序号均匀分散
  static List<Question> _spreadBySeq(List<Question> questions) {
    // 按序号排序后交叉分散
    final sorted = List<Question>.from(questions)..sort((a, b) => a.seq.compareTo(b.seq));
    final result = <Question>[];
    int left = 0, right = sorted.length - 1;
    bool leftTurn = true;

    while (left <= right && result.length < sorted.length) {
      if (leftTurn && left <= right) {
        result.add(sorted[left++]);
      } else if (!leftTurn && left <= right) {
        result.add(sorted[right--]);
      }
      leftTurn = !leftTurn;
    }
    return result;
  }

  /// 分层抽样：尽量覆盖各维度
  static List<Question> _stratifiedSelect({
    required List<Question> questions,
    required int targetCount,
    required List<String> dimensions,
    required double coverageRatio,
  }) {
    // 收集各维度标签分布
    final dimGroups = <String, Map<String, List<Question>>>{};
    for (final dim in dimensions) {
      dimGroups[dim] = {};
    }

    for (final q in questions) {
      final tags = [q.dim1, q.dim2, q.dim3];
      for (int i = 0; i < dimensions.length && i < tags.length; i++) {
        final tag = tags[i];
        if (tag != null && tag.isNotEmpty) {
          dimGroups[dimensions[i]]![tag] ??= [];
          dimGroups[dimensions[i]]![tag]!.add(q);
        }
      }
    }

    final selected = <Question>{};
    final tagQuota = <String, int>{};

    // 计算每个维度的配额（按覆盖率分配）
    for (final dim in dimensions) {
      final allTags = dimGroups[dim]!.keys.toList();
      final coveredCount = (allTags.length * coverageRatio).ceil();
      tagQuota[dim] = (targetCount / dimensions.length * coveredCount / allTags.length).ceil().clamp(1, targetCount);
    }

    // 第一轮：每个维度每个标签至少选1题（如果可能）
    for (final dim in dimensions) {
      for (final tag in dimGroups[dim]!.keys) {
        final qs = dimGroups[dim]![tag]!;
        if (qs.isNotEmpty && selected.length < targetCount) {
          // 尽量选序号不同的
          final sortedQs = List<Question>.from(qs)..sort((a, b) => a.seq.compareTo(b.seq));
          selected.add(sortedQs.first);
        }
      }
    }

    // 第二轮：补充到目标数量（序号尽量分散）
    if (selected.length < targetCount) {
      final remaining = questions.where((q) => !selected.contains(q)).toList();
      remaining.shuffle();
      for (final q in remaining) {
        if (selected.length >= targetCount) break;
        selected.add(q);
      }
    }

    // 最终按序号分散排序
    return _spreadBySeq(selected.toList());
  }

  /// 根据用户定义的标签过滤题目
  static List<Question> filterByTags({
    required List<Question> questions,
    String? dim1Tag,
    String? dim2Tag,
    String? dim3Tag,
  }) {
    return questions.where((q) {
      if (dim1Tag != null && dim1Tag.isNotEmpty && q.dim1 != dim1Tag) return false;
      if (dim2Tag != null && dim2Tag.isNotEmpty && q.dim2 != dim2Tag) return false;
      if (dim3Tag != null && dim3Tag.isNotEmpty && q.dim3 != dim3Tag) return false;
      return true;
    }).toList();
  }

  /// 获取维度分布概览
  static Map<String, Map<String, int>> getDimOverview(List<Question> questions) {
    final overview = <String, Map<String, int>>{};
    for (final q in questions) {
      final tags = [q.dim1, q.dim2, q.dim3];
      for (int i = 0; i < 3; i++) {
        final dimKey = 'dim${i + 1}';
        if (tags[i] != null && tags[i]!.isNotEmpty) {
          overview[dimKey] ??= {};
          overview[dimKey]![tags[i]!] = (overview[dimKey]![tags[i]!] ?? 0) + 1;
        }
      }
    }
    return overview;
  }
}
