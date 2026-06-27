import 'dart:convert';

enum QuestionType { single, multi }

class QuestionOption {
  final String label; // A, B, C, D, E
  final String text;

  QuestionOption({required this.label, required this.text});

  factory QuestionOption.fromJson(Map<String, dynamic> json) =>
      QuestionOption(label: json['label'], text: json['text']);

  Map<String, dynamic> toJson() => {'label': label, 'text': text};
}

class Question {
  final int? id;
  final String tableName;
  final int seq;
  final String content;
  final List<QuestionOption> options;
  final List<String> correctAnswers; // e.g. ['A', 'C']
  final String? explanation;
  String? dim1; // 用户定义维度1标签
  String? dim2; // 用户定义维度2标签
  String? dim3; // 用户定义维度3标签

  Question({
    this.id,
    required this.tableName,
    required this.seq,
    required this.content,
    required this.options,
    required this.correctAnswers,
    this.explanation,
    this.dim1,
    this.dim2,
    this.dim3,
  });

  QuestionType get type =>
      correctAnswers.length > 1 ? QuestionType.multi : QuestionType.single;

  bool checkAnswer(List<String> userAnswers) {
    if (userAnswers.length != correctAnswers.length) return false;
    final sortedUser = List<String>.from(userAnswers)..sort();
    final sortedCorrect = List<String>.from(correctAnswers)..sort();
    for (int i = 0; i < sortedUser.length; i++) {
      if (sortedUser[i] != sortedCorrect[i]) return false;
    }
    return true;
  }

  factory Question.fromMap(Map<String, dynamic> map, List<QuestionOption> options, {String tableName = ''}) {
    return Question(
      id: map['id'],
      tableName: map['table_name'] as String? ?? tableName,
      seq: map['seq'] as int,
      content: map['content'] as String,
      options: options,
      correctAnswers: (map['correct_answers'] as String).split(','),
      explanation: map['explanation'] as String?,
      dim1: map['dim1'] as String?,
      dim2: map['dim2'] as String?,
      dim3: map['dim3'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'seq': seq,
        'content': content,
        'options': jsonEncode(options.map((o) => o.toJson()).toList()),
        'correct_answers': correctAnswers.join(','),
        'explanation': explanation,
        'dim1': dim1,
        'dim2': dim2,
        'dim3': dim3,
      };

  Question copyWith({
    int? id,
    String? tableName,
    int? seq,
    String? content,
    List<QuestionOption>? options,
    List<String>? correctAnswers,
    String? explanation,
    String? dim1,
    String? dim2,
    String? dim3,
  }) {
    return Question(
      id: id ?? this.id,
      tableName: tableName ?? this.tableName,
      seq: seq ?? this.seq,
      content: content ?? this.content,
      options: options ?? this.options,
      correctAnswers: correctAnswers ?? this.correctAnswers,
      explanation: explanation ?? this.explanation,
      dim1: dim1 ?? this.dim1,
      dim2: dim2 ?? this.dim2,
      dim3: dim3 ?? this.dim3,
    );
  }
}
