
class AppSettings {
  final int totalTimeSeconds;     // 总答题时间（秒）
  final int avgTimePerQuestion;   // 每题平均答题时间（秒）

  // 用户定义的分类维度（最多3个）
  List<String> customDimensions;

  AppSettings({
    this.totalTimeSeconds = 1800,
    this.avgTimePerQuestion = 60,
    List<String>? customDimensions,
  }) : customDimensions = customDimensions ?? [];

  Map<String, dynamic> toJson() => {
        'total_time_seconds': totalTimeSeconds,
        'avg_time_per_question': avgTimePerQuestion,
        'custom_dimensions': customDimensions,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        totalTimeSeconds: json['total_time_seconds'] ?? 1800,
        avgTimePerQuestion: json['avg_time_per_question'] ?? 60,
        customDimensions: json['custom_dimensions'] != null
            ? List<String>.from(json['custom_dimensions'])
            : [],
      );

  AppSettings copyWith({
    int? totalTimeSeconds,
    int? avgTimePerQuestion,
    List<String>? customDimensions,
  }) {
    return AppSettings(
      totalTimeSeconds: totalTimeSeconds ?? this.totalTimeSeconds,
      avgTimePerQuestion: avgTimePerQuestion ?? this.avgTimePerQuestion,
      customDimensions: customDimensions ?? this.customDimensions,
    );
  }
}
