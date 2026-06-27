/// 测试会话模型 — 对应 test_sessions 表
class TestSession {
  final int? id;
  final String title;
  final String tableName; // 所属题库表
  final int questionCount;
  final int durationSeconds; // 总时长
  final DateTime createdAt;
  final String status; // pending_selection / pending_submit / completed / aborted
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int? timeSpentSeconds;
  final int? totalScore;

  TestSession({
    this.id,
    required this.title,
    required this.tableName,
    required this.questionCount,
    required this.durationSeconds,
    required this.createdAt,
    this.status = 'pending_selection',
    this.startedAt,
    this.endedAt,
    this.timeSpentSeconds,
    this.totalScore,
  });

  bool get isPendingSelection => status == 'pending_selection';
  bool get isPendingSubmit => status == 'pending_submit';
  bool get isCompleted => status == 'completed';
  bool get isAborted => status == 'aborted';
  bool get isGraded => totalScore != null;
  bool get isInProgress => startedAt != null && endedAt == null;
  bool get isTimeUp {
    if (startedAt == null) return false;
    return DateTime.now().difference(startedAt!) >= Duration(seconds: durationSeconds);
  }

  int get remainingSeconds {
    if (startedAt == null) return durationSeconds;
    final elapsed = DateTime.now().difference(startedAt!).inSeconds;
    return (durationSeconds - elapsed).clamp(0, durationSeconds);
  }

  String get statusLabel {
    switch (status) {
      case 'pending_selection': return '待选题';
      case 'pending_submit': return '待提交';
      case 'completed': return totalScore != null ? '已批阅' : '批阅中';
      case 'aborted': return '已中止';
      default: return status;
    }
  }

  factory TestSession.fromMap(Map<String, dynamic> map) => TestSession(
    id: map['id'],
    title: map['title'],
    tableName: map['table_name'],
    questionCount: map['question_count'],
    durationSeconds: map['duration_seconds'],
    createdAt: DateTime.parse(map['created_at']),
    status: map['status'],
    startedAt: map['started_at'] != null ? DateTime.parse(map['started_at']) : null,
    endedAt: map['ended_at'] != null ? DateTime.parse(map['ended_at']) : null,
    timeSpentSeconds: map['time_spent_seconds'],
    totalScore: map['total_score'],
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'title': title,
    'table_name': tableName,
    'question_count': questionCount,
    'duration_seconds': durationSeconds,
    'created_at': createdAt.toIso8601String(),
    'status': status,
    'started_at': startedAt?.toIso8601String(),
    'ended_at': endedAt?.toIso8601String(),
    'time_spent_seconds': timeSpentSeconds,
    'total_score': totalScore,
  };

  TestSession copyWith({
    int? id,
    String? title,
    String? tableName,
    int? questionCount,
    int? durationSeconds,
    DateTime? createdAt,
    String? status,
    DateTime? startedAt,
    DateTime? endedAt,
    int? timeSpentSeconds,
    int? totalScore,
  }) => TestSession(
    id: id ?? this.id,
    title: title ?? this.title,
    tableName: tableName ?? this.tableName,
    questionCount: questionCount ?? this.questionCount,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    createdAt: createdAt ?? this.createdAt,
    status: status ?? this.status,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt ?? this.endedAt,
    timeSpentSeconds: timeSpentSeconds ?? this.timeSpentSeconds,
    totalScore: totalScore ?? this.totalScore,
  );
}

/// 测试答题记录 — 对应 test_answers 表
class TestAnswer {
  final int? id;
  final int testId;
  final int questionId;
  final int questionSeq;
  final String userAnswer; // "A,C" 或 ""
  final int score; // 1 或 0
  final bool? isCorrect; // null=未批阅

  TestAnswer({
    this.id,
    required this.testId,
    required this.questionId,
    required this.questionSeq,
    this.userAnswer = '',
    this.score = 0,
    this.isCorrect,
  });

  bool get isAnswered => userAnswer.isNotEmpty;
  List<String> get selectedList => userAnswer.isEmpty ? [] : userAnswer.split(',');

  factory TestAnswer.fromMap(Map<String, dynamic> map) => TestAnswer(
    id: map['id'],
    testId: map['test_id'],
    questionId: map['question_id'],
    questionSeq: map['question_seq'],
    userAnswer: map['user_answer'] ?? '',
    score: map['score'] ?? 0,
    isCorrect: map['is_correct'] == null ? null : map['is_correct'] == 1,
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'test_id': testId,
    'question_id': questionId,
    'question_seq': questionSeq,
    'user_answer': userAnswer,
    'score': score,
    'is_correct': isCorrect == null ? null : (isCorrect! ? 1 : 0),
  };

  TestAnswer copyWith({String? userAnswer, int? score, bool? isCorrect}) => TestAnswer(
    id: id,
    testId: testId,
    questionId: questionId,
    questionSeq: questionSeq,
    userAnswer: userAnswer ?? this.userAnswer,
    score: score ?? this.score,
    isCorrect: isCorrect ?? this.isCorrect,
  );
}
